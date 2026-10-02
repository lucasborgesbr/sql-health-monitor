/*
    SQL Health Monitor - Weekly Report HTML Builder
    Pure HTML renderer — no queries to permanent tables.
    All data comes from parameters (scalars) and temp tables (tabular sections).

    Caller must create and populate these temp tables before calling:

        CREATE TABLE #WeeklyWoW (
            MetricName  NVARCHAR(50),
            ThisWeek    DECIMAL(18,2),
            LastWeek    DECIMAL(18,2)
        );
        CREATE TABLE #WeeklyDiskCapacity (
            DriveLetter   NVARCHAR(10),
            TotalGB       DECIMAL(10,1),
            UsedGB        DECIMAL(10,1),
            FreeGB        DECIMAL(10,1),
            UsedPct       DECIMAL(5,1),
            WeeklyGrowthGB DECIMAL(10,2),
            DaysUntil95   INT,           -- 9999 = no growth
            CapStatus     NVARCHAR(10)   -- 'ok' | 'warning' | 'critical'
        );
        CREATE TABLE #WeeklyChanges (
            ChangeType  NVARCHAR(50),
            ChangeDate  DATETIME2,
            Description NVARCHAR(500),
            Impact      NVARCHAR(10)   -- 'HIGH' | 'MEDIUM' | 'LOW'
        );
        CREATE TABLE #WeeklyTopQueries (
            DatabaseName NVARCHAR(128),
            CpuMsThis    BIGINT,
            CpuMsLast    BIGINT,
            ChangePct    DECIMAL(10,1),  -- NULL = new query
            Executions   BIGINT,
            QueryText    NVARCHAR(200)
        );
        CREATE TABLE #WeeklyRecommendations (
            Priority   INT,
            Category   NVARCHAR(50),
            Message    NVARCHAR(500),
            ActionItem NVARCHAR(500)
        );
        CREATE TABLE #WeeklyTopWaits (
            WaitType    NVARCHAR(100),
            DeltaMsThis BIGINT,
            DeltaMsLast BIGINT
        );

    Output:
        @HtmlBody VARCHAR(MAX) OUTPUT  -- Complete HTML email body

    Schema: [monitor]
    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

IF OBJECT_ID('[monitor].[usp_BuildWeeklyHtml]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_BuildWeeklyHtml] @ServerName NVARCHAR(128) = NULL, @WeekStr NVARCHAR(50) = NULL, @CpuAvgThis INT = NULL, @CpuAvgLast INT = NULL, @PleAvgThis INT = NULL, @BlockingThis INT = NULL, @AlertsThis INT = NULL, @ErrorsThis INT = NULL, @HtmlBody VARCHAR(MAX) = NULL OUTPUT AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_BuildWeeklyHtml]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_BuildWeeklyHtml] @ServerName NVARCHAR(128) = NULL, @WeekStr NVARCHAR(50) = NULL, @CpuAvgThis INT = NULL, @CpuAvgLast INT = NULL, @PleAvgThis INT = NULL, @BlockingThis INT = NULL, @AlertsThis INT = NULL, @ErrorsThis INT = NULL, @HtmlBody VARCHAR(MAX) = NULL OUTPUT AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

ALTER PROCEDURE [monitor].[usp_BuildWeeklyHtml]
    @ServerName NVARCHAR(128),
    @WeekStr    NVARCHAR(50),
    -- Scalar metrics passed directly for guaranteed display
    @CpuAvgThis INT = NULL,
    @CpuAvgLast INT = NULL,
    @PleAvgThis INT = NULL,
    @BlockingThis INT = NULL,
    @AlertsThis INT = NULL,
    @ErrorsThis INT = NULL,
    -- Tabular sections come from caller-created temp tables:
    --   #WeeklyWoW, #WeeklyDiskCapacity, #WeeklyChanges,
    --   #WeeklyTopQueries, #WeeklyRecommendations, #WeeklyTopWaits
    @HtmlBody   VARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- Default NULL scalars to 0 for safe display
    SET @CpuAvgThis = ISNULL(@CpuAvgThis, 0);
    SET @CpuAvgLast = ISNULL(@CpuAvgLast, 0);
    SET @PleAvgThis = ISNULL(@PleAvgThis, 0);
    SET @BlockingThis = ISNULL(@BlockingThis, 0);
    SET @AlertsThis = ISNULL(@AlertsThis, 0);
    SET @ErrorsThis = ISNULL(@ErrorsThis, 0);

    -- Calculate trend for key metrics
    DECLARE @CpuTrendPct INT = CASE WHEN @CpuAvgLast > 0 THEN CAST(ROUND((@CpuAvgThis - @CpuAvgLast) * 100.0 / @CpuAvgLast, 0) AS INT) ELSE 0 END;

    -- ---- Shared CSS ----
    DECLARE @Css VARCHAR(MAX) =
        'body{font-family:Arial,sans-serif;font-size:13px;color:#222;margin:0;padding:0;background:#f4f4f4}'
        + '.wrap{max-width:820px;margin:20px auto;background:#fff;border:1px solid #ddd;border-radius:4px}'
        + '.hdr{background:#1a1a2e;color:#fff;padding:18px 24px}'
        + '.hdr h1{margin:0;font-size:18px;font-weight:700}'
        + '.hdr .sub{color:#aaa;font-size:11px;margin-top:4px}'
        + '.band{background:#1a5276;color:#fff;padding:10px 24px;font-size:12px}'
        + '.body{padding:20px 24px}'
        + 'h2{font-size:12px;text-transform:uppercase;letter-spacing:1px;color:#555;border-bottom:2px solid #eee;padding-bottom:5px;margin:20px 0 10px}'
        + 'table{width:100%;border-collapse:collapse;font-size:12px}'
        + 'th{background:#f5f5f5;text-align:left;padding:7px 9px;font-weight:600;border-bottom:2px solid #ddd}'
        + 'td{padding:6px 9px;border-bottom:1px solid #eee}'
        + '.badge{display:inline-block;padding:2px 7px;border-radius:3px;font-size:11px;font-weight:700}'
        + '.crit{background:#c0392b;color:#fff}'
        + '.warn{background:#f39c12;color:#fff}'
        + '.ok{background:#1e8449;color:#fff}'
        + '.p1{background:#c0392b;color:#fff}'
        + '.p2{background:#f39c12;color:#fff}'
        + '.p3{background:#7f8c8d;color:#fff}'
        + '.up{color:#c0392b;font-weight:700}'
        + '.dn{color:#1e8449;font-weight:700}'
        + '.ftr{background:#f5f5f5;padding:10px 24px;font-size:11px;color:#888;border-top:1px solid #eee}';

    SET @HtmlBody = '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>SQL Health Monitor - Weekly</title>'
        + '<style>' + @Css + '</style></head><body><div class="wrap">';

    -- Header
    SET @HtmlBody += '<div class="hdr"><h1>SQL Health Monitor &mdash; Weekly Deep Dive</h1>'
        + '<div class="sub">Server: ' + @ServerName + ' &nbsp;|&nbsp; Period: ' + @WeekStr + '</div></div>';
    SET @HtmlBody += '<div class="band">7-day analysis &nbsp;&mdash;&nbsp; Week-over-week comparison &nbsp;&mdash;&nbsp; Capacity projections &nbsp;&mdash;&nbsp; Recommendations</div>';
    SET @HtmlBody += '<div class="body">';

    -- ---- Key Metrics Summary (from scalar params) ----
    SET @HtmlBody += '<h2>Key Metrics Summary</h2>'
        + '<table><tr><th>Metric</th><th>Value</th><th>Trend</th></tr>'
        + '<tr><td>CPU Average (%)</td><td>' + CAST(@CpuAvgThis AS VARCHAR) + '%</td>'
        + '<td>' + CASE WHEN @CpuTrendPct > 0 THEN '<span class="up">+' + CAST(@CpuTrendPct AS VARCHAR) + '% vs last week</span>'
                       WHEN @CpuTrendPct < 0 THEN '<span class="dn">' + CAST(@CpuTrendPct AS VARCHAR) + '% vs last week</span>'
                       ELSE 'stable' END + '</td></tr>'
        + '<tr><td>Page Life Expectancy (s)</td><td>' + CAST(@PleAvgThis AS VARCHAR) + '</td><td>&mdash;</td></tr>'
        + '<tr><td>Blocking Events</td><td>' + CAST(@BlockingThis AS VARCHAR) + '</td><td>&mdash;</td></tr>'
        + '<tr><td>Alerts Fired</td><td>' + CAST(@AlertsThis AS VARCHAR) + '</td><td>&mdash;</td></tr>'
        + '<tr><td>Critical Errors</td><td>' + CAST(@ErrorsThis AS VARCHAR) + '</td><td>&mdash;</td></tr>'
        + '</table>';

    -- ---- Week-over-Week (from #WeeklyWoW) ----
    IF OBJECT_ID('tempdb..#WeeklyWoW') IS NOT NULL AND EXISTS (SELECT 1 FROM #WeeklyWoW)
    BEGIN
        SET @HtmlBody += '<h2>Week-over-Week Comparison</h2>'
            + '<table><tr><th>Metric</th><th>This Week</th><th>Last Week</th><th>Change</th></tr>';

        DECLARE @wMetric NVARCHAR(50), @wThis DECIMAL(18,2), @wLast DECIMAL(18,2), @wChg DECIMAL(5,1);
        DECLARE cur_wow CURSOR LOCAL FAST_FORWARD FOR
            SELECT MetricName, ThisWeek, LastWeek,
                CASE WHEN LastWeek = 0 THEN NULL
                     ELSE CAST(ROUND((ThisWeek - LastWeek) * 100.0 / NULLIF(LastWeek,0), 1) AS DECIMAL(5,1)) END
            FROM #WeeklyWoW;
        OPEN cur_wow;
        FETCH NEXT FROM cur_wow INTO @wMetric, @wThis, @wLast, @wChg;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @HtmlBody += '<tr><td>' + @wMetric + '</td>'
                + '<td>' + CAST(@wThis AS VARCHAR) + '</td>'
                + '<td>' + CAST(@wLast AS VARCHAR) + '</td>'
                + '<td>' + CASE WHEN @wChg IS NULL THEN '&mdash;'
                                WHEN @wChg > 0  THEN '<span class="up">+' + CAST(@wChg AS VARCHAR) + '%</span>'
                                WHEN @wChg < 0  THEN '<span class="dn">' + CAST(@wChg AS VARCHAR) + '%</span>'
                                ELSE 'stable' END + '</td></tr>';
            FETCH NEXT FROM cur_wow INTO @wMetric, @wThis, @wLast, @wChg;
        END;
        CLOSE cur_wow; DEALLOCATE cur_wow;
        SET @HtmlBody += '</table>';
    END;

    -- ---- Disk Capacity (from #WeeklyDiskCapacity) ----
    IF OBJECT_ID('tempdb..#WeeklyDiskCapacity') IS NOT NULL AND EXISTS (SELECT 1 FROM #WeeklyDiskCapacity)
    BEGIN
        SET @HtmlBody += '<h2>Disk Capacity Planning</h2>'
            + '<table><tr><th>Drive</th><th>Total</th><th>Used</th><th>Free</th><th>Used %</th><th>Weekly Growth</th><th>Days to 95%</th><th>Status</th></tr>';

        DECLARE @dDrive NVARCHAR(10), @dTotalGB DECIMAL(10,1), @dUsedGB DECIMAL(10,1),
                @dFreeGB DECIMAL(10,1), @dUsedPct DECIMAL(5,1), @dGrowthGB DECIMAL(10,2),
                @dDays INT, @dStat NVARCHAR(10);
        DECLARE cur_disk CURSOR LOCAL FAST_FORWARD FOR
            SELECT DriveLetter, TotalGB, UsedGB, FreeGB, UsedPct, WeeklyGrowthGB, DaysUntil95, CapStatus
            FROM #WeeklyDiskCapacity ORDER BY UsedPct DESC;
        OPEN cur_disk;
        FETCH NEXT FROM cur_disk INTO @dDrive, @dTotalGB, @dUsedGB, @dFreeGB, @dUsedPct, @dGrowthGB, @dDays, @dStat;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @HtmlBody += '<tr><td>' + @dDrive
                + '</td><td>' + CAST(@dTotalGB AS VARCHAR) + ' GB'
                + '</td><td>' + CAST(@dUsedGB  AS VARCHAR) + ' GB'
                + '</td><td>' + CAST(@dFreeGB  AS VARCHAR) + ' GB'
                + '</td><td>' + CAST(@dUsedPct AS VARCHAR) + '%'
                + '</td><td>' + CAST(@dGrowthGB AS VARCHAR) + ' GB'
                + '</td><td>' + CASE WHEN @dDays >= 9999 THEN '&mdash;' ELSE CAST(@dDays AS VARCHAR) END
                + '</td><td><span class="badge ' + CASE @dStat WHEN 'critical' THEN 'crit' WHEN 'warning' THEN 'warn' ELSE 'ok' END + '">'
                + UPPER(@dStat) + '</span></td></tr>';
            FETCH NEXT FROM cur_disk INTO @dDrive, @dTotalGB, @dUsedGB, @dFreeGB, @dUsedPct, @dGrowthGB, @dDays, @dStat;
        END;
        CLOSE cur_disk; DEALLOCATE cur_disk;
        SET @HtmlBody += '</table>';
    END;

    -- ---- What Changed (from #WeeklyChanges) ----
    IF OBJECT_ID('tempdb..#WeeklyChanges') IS NOT NULL AND EXISTS (SELECT 1 FROM #WeeklyChanges)
    BEGIN
        SET @HtmlBody += '<h2>What Changed This Week</h2>'
            + '<table><tr><th>Type</th><th>Date</th><th>Description</th><th>Impact</th></tr>';

        DECLARE @chType NVARCHAR(50), @chDate DATETIME2, @chDesc NVARCHAR(500), @chImp NVARCHAR(10);
        DECLARE cur_chg CURSOR LOCAL FAST_FORWARD FOR
            SELECT ChangeType, ChangeDate, Description, Impact FROM #WeeklyChanges
            ORDER BY CASE Impact WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END, ChangeDate DESC;
        OPEN cur_chg;
        FETCH NEXT FROM cur_chg INTO @chType, @chDate, @chDesc, @chImp;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @HtmlBody += '<tr><td>' + @chType
                + '</td><td>' + FORMAT(@chDate,'MMM dd HH:mm')
                + '</td><td>' + @chDesc
                + '</td><td><span class="badge ' + CASE @chImp WHEN 'HIGH' THEN 'crit' WHEN 'MEDIUM' THEN 'warn' ELSE 'ok' END + '">'
                + @chImp + '</span></td></tr>';
            FETCH NEXT FROM cur_chg INTO @chType, @chDate, @chDesc, @chImp;
        END;
        CLOSE cur_chg; DEALLOCATE cur_chg;
        SET @HtmlBody += '</table>';
    END;

    -- ---- Top Degraded Queries (from #WeeklyTopQueries) ----
    IF OBJECT_ID('tempdb..#WeeklyTopQueries') IS NOT NULL AND EXISTS (SELECT 1 FROM #WeeklyTopQueries)
    BEGIN
        SET @HtmlBody += '<h2>Top Degraded Queries</h2>'
            + '<table><tr><th>Database</th><th>CPU This Wk (ms)</th><th>CPU Last Wk (ms)</th><th>Change</th><th>Executions</th><th>Query</th></tr>';

        DECLARE @qDb NVARCHAR(128), @qThis BIGINT, @qLast BIGINT,
                @qChg DECIMAL(10,1), @qExec BIGINT, @qText NVARCHAR(200);
        DECLARE cur_qry CURSOR LOCAL FAST_FORWARD FOR
            SELECT DatabaseName, CpuMsThis, CpuMsLast, ChangePct, Executions, QueryText
            FROM #WeeklyTopQueries ORDER BY CpuMsThis DESC;
        OPEN cur_qry;
        FETCH NEXT FROM cur_qry INTO @qDb, @qThis, @qLast, @qChg, @qExec, @qText;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @HtmlBody += '<tr><td>' + @qDb
                + '</td><td>' + CAST(@qThis AS VARCHAR)
                + '</td><td>' + CAST(@qLast AS VARCHAR)
                + '</td><td>' + CASE WHEN @qChg IS NULL THEN '<span class="warn">new</span>'
                                     ELSE '<span class="up">+' + CAST(@qChg AS VARCHAR) + '%</span>' END
                + '</td><td>' + CAST(@qExec AS VARCHAR)
                + '</td><td style="font-size:11px;font-family:monospace">'
                + REPLACE(REPLACE(ISNULL(@qText,''), '<', '&lt;'), '>', '&gt;')
                + '</td></tr>';
            FETCH NEXT FROM cur_qry INTO @qDb, @qThis, @qLast, @qChg, @qExec, @qText;
        END;
        CLOSE cur_qry; DEALLOCATE cur_qry;
        SET @HtmlBody += '</table>';
    END;

    -- ---- Recommendations (from #WeeklyRecommendations) ----
    IF OBJECT_ID('tempdb..#WeeklyRecommendations') IS NOT NULL AND EXISTS (SELECT 1 FROM #WeeklyRecommendations)
    BEGIN
        SET @HtmlBody += '<h2>Recommendations</h2>'
            + '<table><tr><th>Priority</th><th>Area</th><th>Issue</th><th>Action</th></tr>';

        DECLARE @rPri INT, @rCat NVARCHAR(50), @rMsg NVARCHAR(500), @rAct NVARCHAR(500);
        DECLARE cur_rec CURSOR LOCAL FAST_FORWARD FOR
            SELECT Priority, Category, Message, ActionItem FROM #WeeklyRecommendations ORDER BY Priority, Category;
        OPEN cur_rec;
        FETCH NEXT FROM cur_rec INTO @rPri, @rCat, @rMsg, @rAct;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @HtmlBody += '<tr>'
                + '<td><span class="badge p' + CAST(@rPri AS VARCHAR) + '">P' + CAST(@rPri AS VARCHAR) + '</span></td>'
                + '<td>' + @rCat + '</td>'
                + '<td>' + @rMsg + '</td>'
                + '<td>' + @rAct + '</td></tr>';
            FETCH NEXT FROM cur_rec INTO @rPri, @rCat, @rMsg, @rAct;
        END;
        CLOSE cur_rec; DEALLOCATE cur_rec;
        SET @HtmlBody += '</table>';
    END;

    -- ---- Top Wait Types (from #WeeklyTopWaits) ----
    IF OBJECT_ID('tempdb..#WeeklyTopWaits') IS NOT NULL AND EXISTS (SELECT 1 FROM #WeeklyTopWaits)
    BEGIN
        SET @HtmlBody += '<h2>Top Wait Types</h2>'
            + '<table><tr><th>Wait Type</th><th>This Week (ms)</th><th>Last Week (ms)</th><th>Change</th></tr>';

        DECLARE @wtType NVARCHAR(100), @wtThis BIGINT, @wtLast BIGINT, @wtChg DECIMAL(10,1);
        DECLARE cur_wt2 CURSOR LOCAL FAST_FORWARD FOR
            SELECT WaitType, DeltaMsThis, DeltaMsLast,
                CASE WHEN DeltaMsLast = 0 THEN NULL
                     ELSE CAST(ROUND((DeltaMsThis - DeltaMsLast) * 100.0 / NULLIF(DeltaMsLast,0),1) AS DECIMAL(10,1)) END
            FROM #WeeklyTopWaits ORDER BY DeltaMsThis DESC;
        OPEN cur_wt2;
        FETCH NEXT FROM cur_wt2 INTO @wtType, @wtThis, @wtLast, @wtChg;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @HtmlBody += '<tr><td>' + @wtType
                + '</td><td>' + CAST(@wtThis AS VARCHAR)
                + '</td><td>' + CAST(@wtLast AS VARCHAR)
                + '</td><td>' + CASE WHEN @wtChg IS NULL THEN 'new'
                                     WHEN @wtChg > 0  THEN '<span class="up">+' + CAST(@wtChg AS VARCHAR) + '%</span>'
                                     WHEN @wtChg < 0  THEN '<span class="dn">' + CAST(@wtChg AS VARCHAR) + '%</span>'
                                     ELSE 'stable' END + '</td></tr>';
            FETCH NEXT FROM cur_wt2 INTO @wtType, @wtThis, @wtLast, @wtChg;
        END;
        CLOSE cur_wt2; DEALLOCATE cur_wt2;
        SET @HtmlBody += '</table>';
    END;

    -- ---- Index Recommendations (from #WeeklyIndexRecommendations) ----
    IF OBJECT_ID('tempdb..#WeeklyIndexRecommendations') IS NOT NULL AND EXISTS (SELECT 1 FROM #WeeklyIndexRecommendations)
    BEGIN
        SET @HtmlBody += '<h2>Index Recommendations</h2>'
            + '<p style="color:#888;font-size:11px">Based on SQL Server missing index DMVs. Impact score = estimated improvement %.</p>'
            + '<table><tr><th>Database</th><th>Table</th><th>Type</th><th>Impact</th><th>Seeking Columns</th><th>Action</th></tr>';

        DECLARE @irDb NVARCHAR(128), @irSchema NVARCHAR(128), @irTable NVARCHAR(128),
                @irType NVARCHAR(50), @irImpact DECIMAL(18,2), @irEq NVARCHAR(MAX),
                @irIneq NVARCHAR(MAX), @irInc NVARCHAR(MAX), @irSeeks BIGINT, @irAction NVARCHAR(MAX);
        DECLARE cur_idx CURSOR LOCAL FAST_FORWARD FOR
            SELECT DatabaseName, SchemaName, TableName, RecommendationType, ImpactScore,
                   EqualityColumns, InequalityColumns, IncludeColumns, UserSeeks, RecommendedAction
            FROM #WeeklyIndexRecommendations ORDER BY ImpactScore DESC;
        OPEN cur_idx;
        FETCH NEXT FROM cur_idx INTO @irDb, @irSchema, @irTable, @irType, @irImpact, @irEq, @irIneq, @irInc, @irSeeks, @irAction;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @HtmlBody += '<tr>'
                + '<td>' + ISNULL(@irDb,'') + '</td>'
                + '<td>' + ISNULL(@irSchema,'') + '.' + ISNULL(@irTable,'') + '</td>'
                + '<td><span class="badge warn">' + ISNULL(@irType,'') + '</span></td>'
                + '<td><strong>' + CAST(CAST(@irImpact AS INT) AS VARCHAR) + '%</strong></td>'
                + '<td style="font-size:11px;font-family:monospace">' + ISNULL(@irEq,'') + CASE WHEN @irIneq IS NOT NULL THEN ', ' + @irIneq ELSE '' END + '</td>'
                + '<td><pre style="margin:0;font-size:10px;white-space:pre-wrap">' + REPLACE(REPLACE(LEFT(ISNULL(@irAction,''),200),'<','&lt;'),'>','&gt;') + '</pre></td>'
                + '</tr>';
            FETCH NEXT FROM cur_idx INTO @irDb, @irSchema, @irTable, @irType, @irImpact, @irEq, @irIneq, @irInc, @irSeeks, @irAction;
        END;
        CLOSE cur_idx; DEALLOCATE cur_idx;
        SET @HtmlBody += '</table>';
    END;

    -- ---- Top Queries by Multiple Dimensions (from #WeeklyTopQueriesQS) ----
    IF OBJECT_ID('tempdb..#WeeklyTopQueriesQS') IS NOT NULL AND EXISTS (SELECT 1 FROM #WeeklyTopQueriesQS)
    BEGIN
        -- CPU dimension
        SET @HtmlBody += '<h2>Top Queries by CPU</h2>'
            + '<table><tr><th>Database</th><th>Query</th><th>Total CPU (ms)</th><th>Avg CPU (ms)</th><th>Executions</th></tr>';

        DECLARE @qsDb NVARCHAR(128), @qsId INT, @qsCpu DECIMAL(18,2), @qsAvgCpu DECIMAL(18,2),
                @qsDur DECIMAL(18,2), @qsAvgDur DECIMAL(18,2), @qsReads BIGINT, @qsAvgReads DECIMAL(18,2),
                @qsWrites BIGINT, @qsExec BIGINT, @qsText NVARCHAR(4000), @qsDim NVARCHAR(20);
        DECLARE cur_qs CURSOR LOCAL FAST_FORWARD FOR
            SELECT TOP 10 DatabaseName, QueryId, TotalCpuMs, AvgCpuMs, TotalDurationMs, AvgDurationMs,
                   TotalLogicalReads, AvgLogicalReads, TotalWrites, ExecutionCount, QueryText, QueryDimension
            FROM #WeeklyTopQueriesQS WHERE QueryDimension = 'CPU'
            ORDER BY TotalCpuMs DESC;
        OPEN cur_qs;
        FETCH NEXT FROM cur_qs INTO @qsDb, @qsId, @qsCpu, @qsAvgCpu, @qsDur, @qsAvgDur, @qsReads, @qsAvgReads, @qsWrites, @qsExec, @qsText, @qsDim;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @HtmlBody += '<tr><td>' + ISNULL(@qsDb,'')
                + '</td><td style="font-size:10px;font-family:monospace;max-width:400px;overflow:hidden;text-overflow:ellipsis">' + REPLACE(REPLACE(LEFT(ISNULL(@qsText,''),100),'<','&lt;'),'>','&gt;')
                + '</td><td>' + CAST(CAST(@qsCpu AS BIGINT) AS VARCHAR)
                + '</td><td>' + CAST(CAST(@qsAvgCpu AS BIGINT) AS VARCHAR)
                + '</td><td>' + CAST(@qsExec AS VARCHAR) + '</td></tr>';
            FETCH NEXT FROM cur_qs INTO @qsDb, @qsId, @qsCpu, @qsAvgCpu, @qsDur, @qsAvgDur, @qsReads, @qsAvgReads, @qsWrites, @qsExec, @qsText, @qsDim;
        END;
        CLOSE cur_qs; DEALLOCATE cur_qs;
        SET @HtmlBody += '</table>';

        -- Duration dimension
        SET @HtmlBody += '<h2>Top Queries by Duration</h2>'
            + '<table><tr><th>Database</th><th>Query</th><th>Total Duration (ms)</th><th>Avg Duration (ms)</th><th>Executions</th></tr>';

        DECLARE cur_qs2 CURSOR LOCAL FAST_FORWARD FOR
            SELECT TOP 10 DatabaseName, QueryId, TotalCpuMs, AvgCpuMs, TotalDurationMs, AvgDurationMs,
                   TotalLogicalReads, AvgLogicalReads, TotalWrites, ExecutionCount, QueryText, QueryDimension
            FROM #WeeklyTopQueriesQS WHERE QueryDimension = 'DURATION'
            ORDER BY TotalDurationMs DESC;
        OPEN cur_qs2;
        FETCH NEXT FROM cur_qs2 INTO @qsDb, @qsId, @qsCpu, @qsAvgCpu, @qsDur, @qsAvgDur, @qsReads, @qsAvgReads, @qsWrites, @qsExec, @qsText, @qsDim;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @HtmlBody += '<tr><td>' + ISNULL(@qsDb,'')
                + '</td><td style="font-size:10px;font-family:monospace;max-width:400px;overflow:hidden;text-overflow:ellipsis">' + REPLACE(REPLACE(LEFT(ISNULL(@qsText,''),100),'<','&lt;'),'>','&gt;')
                + '</td><td>' + CAST(CAST(@qsDur AS BIGINT) AS VARCHAR)
                + '</td><td>' + CAST(CAST(@qsAvgDur AS BIGINT) AS VARCHAR)
                + '</td><td>' + CAST(@qsExec AS VARCHAR) + '</td></tr>';
            FETCH NEXT FROM cur_qs2 INTO @qsDb, @qsId, @qsCpu, @qsAvgCpu, @qsDur, @qsAvgDur, @qsReads, @qsAvgReads, @qsWrites, @qsExec, @qsText, @qsDim;
        END;
        CLOSE cur_qs2; DEALLOCATE cur_qs2;
        SET @HtmlBody += '</table>';

        -- Reads dimension
        SET @HtmlBody += '<h2>Top Queries by I/O (Reads)</h2>'
            + '<table><tr><th>Database</th><th>Query</th><th>Total Reads</th><th>Avg Reads</th><th>Executions</th></tr>';

        DECLARE cur_qs3 CURSOR LOCAL FAST_FORWARD FOR
            SELECT TOP 10 DatabaseName, QueryId, TotalCpuMs, AvgCpuMs, TotalDurationMs, AvgDurationMs,
                   TotalLogicalReads, AvgLogicalReads, TotalWrites, ExecutionCount, QueryText, QueryDimension
            FROM #WeeklyTopQueriesQS WHERE QueryDimension = 'READS'
            ORDER BY TotalLogicalReads DESC;
        OPEN cur_qs3;
        FETCH NEXT FROM cur_qs3 INTO @qsDb, @qsId, @qsCpu, @qsAvgCpu, @qsDur, @qsAvgDur, @qsReads, @qsAvgReads, @qsWrites, @qsExec, @qsText, @qsDim;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @HtmlBody += '<tr><td>' + ISNULL(@qsDb,'')
                + '</td><td style="font-size:10px;font-family:monospace;max-width:400px;overflow:hidden;text-overflow:ellipsis">' + REPLACE(REPLACE(LEFT(ISNULL(@qsText,''),100),'<','&lt;'),'>','&gt;')
                + '</td><td>' + CAST(@qsReads AS VARCHAR)
                + '</td><td>' + CAST(CAST(@qsAvgReads AS BIGINT) AS VARCHAR)
                + '</td><td>' + CAST(@qsExec AS VARCHAR) + '</td></tr>';
            FETCH NEXT FROM cur_qs3 INTO @qsDb, @qsId, @qsCpu, @qsAvgCpu, @qsDur, @qsAvgDur, @qsReads, @qsAvgReads, @qsWrites, @qsExec, @qsText, @qsDim;
        END;
        CLOSE cur_qs3; DEALLOCATE cur_qs3;
        SET @HtmlBody += '</table>';
    END;

    -- Footer
    SET @HtmlBody += '</div>'
        + '<div class="ftr">SQL Health Monitor &nbsp;|&nbsp; ' + @ServerName
        + ' &nbsp;|&nbsp; Generated automatically by SQL Agent Job.'
        + '</div></div></body></html>';
END;
GO

PRINT '+ Procedure [monitor].[usp_BuildWeeklyHtml] created.';
GO
