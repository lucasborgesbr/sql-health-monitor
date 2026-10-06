/*
    SQL Health Monitor - Daily Report HTML Builder
    Pure HTML renderer — no queries to permanent tables.
    All data comes from parameters (scalars) and temp tables (tabular sections).

    Caller must create and populate these temp tables before calling:

        CREATE TABLE #ReportRecommendations (
            Priority   INT,
            Category   NVARCHAR(50),
            Message    NVARCHAR(500),
            ActionItem NVARCHAR(500)
        );
        CREATE TABLE #ReportTopWaits (
            WaitType          NVARCHAR(100),
            TotalWaitMs       BIGINT,
            TotalDeltaMs      BIGINT,
            TotalWaitingTasks BIGINT
        );
        CREATE TABLE #ReportAnomalies (
            MetricName          NVARCHAR(100),
            CurrentValue        DECIMAL(18,4),
            BaselineAvg         DECIMAL(18,4),
            DeviationMultiplier DECIMAL(8,2),
            Severity            NVARCHAR(20)
        );

    Output:
        @HtmlBody VARCHAR(MAX) OUTPUT  -- Complete HTML email body

    Schema: [monitor]
    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

IF OBJECT_ID('[monitor].[usp_BuildDailyHtml]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_BuildDailyHtml] @ServerName NVARCHAR(128) = NULL, @DateStr NVARCHAR(50) = NULL, @HealthScore INT = 0, @OverallStatus NVARCHAR(10) = NULL, @CpuAvg INT = 0, @CpuMax INT = 0, @CpuStatus NVARCHAR(10) = NULL, @PleAvg INT = 0, @PleMin INT = 0, @MemStatus NVARCHAR(10) = NULL, @DiskMaxPct DECIMAL(5,2) = 0, @DiskStatus NVARCHAR(10) = NULL, @AgMaxLag INT = 0, @AgStatus NVARCHAR(10) = NULL, @BlockingCount INT = 0, @FailedJobs INT = 0, @ErrorCount INT = 0, @HtmlBody VARCHAR(MAX) = NULL OUTPUT AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_BuildDailyHtml]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_BuildDailyHtml] @ServerName NVARCHAR(128) = NULL, @DateStr NVARCHAR(50) = NULL, @HealthScore INT = 0, @OverallStatus NVARCHAR(10) = NULL, @CpuAvg INT = 0, @CpuMax INT = 0, @CpuStatus NVARCHAR(10) = NULL, @PleAvg INT = 0, @PleMin INT = 0, @MemStatus NVARCHAR(10) = NULL, @DiskMaxPct DECIMAL(5,2) = 0, @DiskStatus NVARCHAR(10) = NULL, @AgMaxLag INT = 0, @AgStatus NVARCHAR(10) = NULL, @BlockingCount INT = 0, @FailedJobs INT = 0, @ErrorCount INT = 0, @HtmlBody VARCHAR(MAX) = NULL OUTPUT AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

ALTER PROCEDURE [monitor].[usp_BuildDailyHtml]
    -- Scalar metrics
    @ServerName    NVARCHAR(128),
    @DateStr       NVARCHAR(50),
    @HealthScore   INT,
    @OverallStatus NVARCHAR(10),   -- 'healthy' | 'warning' | 'critical'
    @CpuAvg        INT,
    @CpuMax        INT,
    @CpuStatus     NVARCHAR(10),
    @PleAvg        INT,
    @PleMin        INT,
    @MemStatus     NVARCHAR(10),
    @DiskMaxPct    DECIMAL(5,2),
    @DiskStatus    NVARCHAR(10),
    @AgMaxLag      INT,
    @AgStatus      NVARCHAR(10),
    @BlockingCount INT,
    @FailedJobs    INT,
    @ErrorCount    INT,
    -- Output
    @HtmlBody      VARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- Tabular sections come from caller-created temp tables:
    --   #ReportRecommendations, #ReportTopWaits, #ReportAnomalies

    DECLARE @StatusColor VARCHAR(7) = CASE @OverallStatus WHEN 'critical' THEN '#c0392b' WHEN 'warning' THEN '#d68910' ELSE '#1e8449' END;

    -- ---- Shared CSS ----
    DECLARE @Css VARCHAR(MAX) =
        'body{font-family:Arial,sans-serif;font-size:13px;color:#222;margin:0;padding:0;background:#f4f4f4}'
        + '.wrap{max-width:780px;margin:20px auto;background:#fff;border:1px solid #ddd;border-radius:4px}'
        + '.hdr{background:#1a1a2e;color:#fff;padding:18px 24px}'
        + '.hdr h1{margin:0;font-size:18px;font-weight:700}'
        + '.hdr .sub{color:#aaa;font-size:11px;margin-top:4px}'
        + '.score{background:' + @StatusColor + ';color:#fff;padding:16px 24px}'
        + '.score-num{font-size:52px;font-weight:700;display:inline-block;vertical-align:middle;margin-right:16px}'
        + '.score-lbl{display:inline-block;vertical-align:middle;font-size:13px}'
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
        + '.ftr{background:#f5f5f5;padding:10px 24px;font-size:11px;color:#888;border-top:1px solid #eee}';

    -- ---- Helper: badge class from status string ----
    -- (inline CASE expressions used directly in string concat below)

    SET @HtmlBody = '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>SQL Health Monitor</title>'
        + '<style>' + @Css + '</style></head><body><div class="wrap">';

    -- Header
    SET @HtmlBody += '<div class="hdr"><h1>SQL Health Monitor &mdash; Daily Report</h1>'
        + '<div class="sub">Server: ' + @ServerName + ' &nbsp;|&nbsp; Generated: ' + @DateStr + '</div></div>';

    -- Score card
    SET @HtmlBody += '<div class="score">'
        + '<span class="score-num">' + CAST(@HealthScore AS VARCHAR) + '</span>'
        + '<span class="score-lbl"><strong>' + UPPER(@OverallStatus) + '</strong><br>Health Score / 100 &nbsp;&mdash;&nbsp; Last 24 hours</span>'
        + '</div>';

    -- Metric summary table
    SET @HtmlBody += '<div class="body"><h2>Metric Summary</h2>'
        + '<table><tr><th>Metric</th><th>Value</th><th>Status</th><th>Notes</th></tr>';

    -- CPU row
    SET @HtmlBody += '<tr><td>CPU</td>'
        + '<td>' + CAST(ISNULL(@CpuAvg,0) AS VARCHAR) + '% avg / ' + CAST(ISNULL(@CpuMax,0) AS VARCHAR) + '% max</td>'
        + '<td><span class="badge ' + CASE @CpuStatus WHEN 'critical' THEN 'crit' WHEN 'warning' THEN 'warn' ELSE 'ok' END + '">' + UPPER(@CpuStatus) + '</span></td>'
        + '<td>' + CASE @CpuStatus WHEN 'critical' THEN 'Sustained above 95%' WHEN 'warning' THEN 'Peaked above 80%' ELSE 'Normal' END + '</td></tr>';

    -- Memory row
    SET @HtmlBody += '<tr><td>Memory (PLE)</td>'
        + '<td>' + CAST(ISNULL(@PleAvg,0) AS VARCHAR) + 's avg / ' + CAST(ISNULL(@PleMin,0) AS VARCHAR) + 's min</td>'
        + '<td><span class="badge ' + CASE @MemStatus WHEN 'critical' THEN 'crit' WHEN 'warning' THEN 'warn' ELSE 'ok' END + '">' + UPPER(@MemStatus) + '</span></td>'
        + '<td>' + CASE @MemStatus WHEN 'critical' THEN 'PLE &lt;100s &mdash; severe memory pressure' WHEN 'warning' THEN 'PLE &lt;300s &mdash; memory pressure' ELSE 'Normal' END + '</td></tr>';

    -- Disk row
    SET @HtmlBody += '<tr><td>Disk</td>'
        + '<td>' + CAST(ISNULL(CAST(@DiskMaxPct AS INT),0) AS VARCHAR) + '% max used</td>'
        + '<td><span class="badge ' + CASE @DiskStatus WHEN 'critical' THEN 'crit' WHEN 'warning' THEN 'warn' ELSE 'ok' END + '">' + UPPER(@DiskStatus) + '</span></td>'
        + '<td>' + CASE @DiskStatus WHEN 'critical' THEN 'Above 90% &mdash; immediate action needed' WHEN 'warning' THEN 'Above 80% &mdash; monitor closely' ELSE 'Normal' END + '</td></tr>';

    -- AG row
    SET @HtmlBody += '<tr><td>AG Sync</td>'
        + '<td>' + CAST(ISNULL(@AgMaxLag,0) AS VARCHAR) + 's max lag</td>'
        + '<td><span class="badge ' + CASE @AgStatus WHEN 'critical' THEN 'crit' WHEN 'warning' THEN 'warn' ELSE 'ok' END + '">' + UPPER(@AgStatus) + '</span></td>'
        + '<td>' + CASE @AgStatus WHEN 'critical' THEN 'Lag &gt;120s &mdash; data loss risk' WHEN 'warning' THEN 'Lag &gt;30s &mdash; investigate' ELSE 'Normal' END + '</td></tr>';

    -- Blocking row
    SET @HtmlBody += '<tr><td>Blocking</td>'
        + '<td>' + CAST(@BlockingCount AS VARCHAR) + ' events</td>'
        + '<td><span class="badge ' + CASE WHEN @BlockingCount > 50 THEN 'crit' WHEN @BlockingCount > 10 THEN 'warn' ELSE 'ok' END + '">'
        + CASE WHEN @BlockingCount > 50 THEN 'CRITICAL' WHEN @BlockingCount > 10 THEN 'WARNING' ELSE 'HEALTHY' END + '</span></td>'
        + '<td>' + CASE WHEN @BlockingCount > 50 THEN 'Excessive blocking' WHEN @BlockingCount > 10 THEN 'Elevated blocking' ELSE 'Normal' END + '</td></tr>';

    -- Jobs row
    SET @HtmlBody += '<tr><td>SQL Agent Jobs</td>'
        + '<td>' + CAST(@FailedJobs AS VARCHAR) + ' failed</td>'
        + '<td><span class="badge ' + CASE WHEN @FailedJobs > 5 THEN 'crit' WHEN @FailedJobs > 0 THEN 'warn' ELSE 'ok' END + '">'
        + CASE WHEN @FailedJobs > 5 THEN 'CRITICAL' WHEN @FailedJobs > 0 THEN 'WARNING' ELSE 'HEALTHY' END + '</span></td>'
        + '<td>' + CASE WHEN @FailedJobs > 0 THEN CAST(@FailedJobs AS VARCHAR) + ' job(s) failed in last 24h' ELSE 'All jobs healthy' END + '</td></tr>'
        + '</table>';

    -- ---- Recommendations (from #ReportRecommendations) ----
    IF OBJECT_ID('tempdb..#ReportRecommendations') IS NOT NULL AND EXISTS (SELECT 1 FROM #ReportRecommendations)
    BEGIN
        SET @HtmlBody += '<h2>Recommendations</h2>'
            + '<table><tr><th>Priority</th><th>Area</th><th>Issue</th><th>Action</th></tr>';

        DECLARE @rPri INT, @rCat NVARCHAR(50), @rMsg NVARCHAR(500), @rAct NVARCHAR(500);
        DECLARE cur_rec CURSOR LOCAL FAST_FORWARD FOR
            SELECT Priority, Category, Message, ActionItem FROM #ReportRecommendations ORDER BY Priority, Category;
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

    -- ---- Top Waits (from #ReportTopWaits) ----
    IF OBJECT_ID('tempdb..#ReportTopWaits') IS NOT NULL AND EXISTS (SELECT 1 FROM #ReportTopWaits)
    BEGIN
        SET @HtmlBody += '<h2>Top Wait Types (24h)</h2>'
            + '<table><tr><th>Wait Type</th><th>Total Wait (ms)</th><th>Delta (ms)</th><th>Waiting Tasks</th></tr>';

        DECLARE @wType NVARCHAR(100), @wTotal BIGINT, @wDelta BIGINT, @wTasks BIGINT;
        DECLARE cur_wt CURSOR LOCAL FAST_FORWARD FOR
            SELECT WaitType, TotalWaitMs, TotalDeltaMs, TotalWaitingTasks
            FROM #ReportTopWaits ORDER BY TotalDeltaMs DESC;
        OPEN cur_wt;
        FETCH NEXT FROM cur_wt INTO @wType, @wTotal, @wDelta, @wTasks;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @HtmlBody += '<tr><td>' + @wType + '</td><td>' + CAST(@wTotal AS VARCHAR)
                + '</td><td>' + CAST(@wDelta AS VARCHAR)
                + '</td><td>' + CAST(@wTasks AS VARCHAR) + '</td></tr>';
            FETCH NEXT FROM cur_wt INTO @wType, @wTotal, @wDelta, @wTasks;
        END;
        CLOSE cur_wt; DEALLOCATE cur_wt;
        SET @HtmlBody += '</table>';
    END;

    -- ---- Baseline Anomalies (from #ReportAnomalies) ----
    IF OBJECT_ID('tempdb..#ReportAnomalies') IS NOT NULL AND EXISTS (SELECT 1 FROM #ReportAnomalies)
    BEGIN
        SET @HtmlBody += '<h2>Baseline Anomalies</h2>'
            + '<table><tr><th>Metric</th><th>Current</th><th>Baseline Avg</th><th>Deviation</th><th>Severity</th></tr>';

        DECLARE @aMetric NVARCHAR(100), @aCurr DECIMAL(18,4), @aAvg DECIMAL(18,4),
                @aDev DECIMAL(8,2), @aSev NVARCHAR(20);
        DECLARE cur_an CURSOR LOCAL FAST_FORWARD FOR
            SELECT MetricName, CurrentValue, BaselineAvg, DeviationMultiplier, Severity
            FROM #ReportAnomalies
            ORDER BY CASE Severity WHEN 'Critical' THEN 1 ELSE 2 END, DeviationMultiplier DESC;
        OPEN cur_an;
        FETCH NEXT FROM cur_an INTO @aMetric, @aCurr, @aAvg, @aDev, @aSev;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @HtmlBody += '<tr><td>' + @aMetric
                + '</td><td>' + CAST(CAST(@aCurr AS DECIMAL(10,2)) AS VARCHAR)
                + '</td><td>' + CAST(CAST(@aAvg  AS DECIMAL(10,2)) AS VARCHAR)
                + '</td><td>' + CAST(CAST(@aDev  AS DECIMAL(5,1))  AS VARCHAR) + N'&sigma;'
                + '</td><td><span class="badge ' + CASE @aSev WHEN 'Critical' THEN 'crit' ELSE 'warn' END + '">'
                + UPPER(@aSev) + '</span></td></tr>';
            FETCH NEXT FROM cur_an INTO @aMetric, @aCurr, @aAvg, @aDev, @aSev;
        END;
        CLOSE cur_an; DEALLOCATE cur_an;
        SET @HtmlBody += '</table>';
    END;

    -- Footer
    SET @HtmlBody += '</div>'
        + '<div class="ftr">SQL Health Monitor &nbsp;|&nbsp; ' + @ServerName
        + ' &nbsp;|&nbsp; Generated automatically by SQL Agent Job.'
        + '</div></div></body></html>';
END;
GO

PRINT '+ Procedure [monitor].[usp_BuildDailyHtml] created.';
GO
