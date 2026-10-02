/*
    SQL Health Monitor - Weekly Deep Dive Report
    Collects 7 days of metrics, populates temp tables, calls usp_BuildWeeklyHtml, sends via Database Mail.

    Includes:
        - Week-over-week comparison for key metrics
        - Capacity planning: disk and database growth projections
        - Top degraded queries (this week vs last week)
        - What changed this week (growth spikes, new errors, new failing jobs, AG changes)
        - Baseline anomaly summary
        - Prioritized recommendations

    Parameters:
        @OverrideLanguage    CHAR(5)        - Override language (default: from Settings)
        @OverrideRecipients  NVARCHAR(1000) - Override email recipients (semicolon-separated)
        @DebugMode           BIT            - 1 = SELECT HTML body instead of sending email

    Example usage:
        EXEC [monitor].[usp_GenerateWeeklyReport];
        EXEC [monitor].[usp_GenerateWeeklyReport] @DebugMode = 1;

    Depends on: usp_BuildWeeklyHtml (html_builder_weekly.sql)

    Schema: [monitor]
    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

IF OBJECT_ID('[monitor].[usp_GenerateWeeklyReport]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_GenerateWeeklyReport] @OverrideLanguage CHAR(5) = NULL, @OverrideRecipients NVARCHAR(1000) = NULL, @DebugMode BIT = 0 AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_GenerateWeeklyReport]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_GenerateWeeklyReport] @OverrideLanguage CHAR(5) = NULL, @OverrideRecipients NVARCHAR(1000) = NULL, @DebugMode BIT = 0 AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

ALTER PROCEDURE [monitor].[usp_GenerateWeeklyReport]
    @OverrideLanguage    CHAR(5)        = NULL,
    @OverrideRecipients  NVARCHAR(1000) = NULL,
    @DebugMode           BIT            = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ============================================================
    -- CONFIGURATION
    -- ============================================================
    DECLARE @Language    CHAR(5)        = ISNULL(@OverrideLanguage,
        (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'General' AND SettingName = 'Language'));
    SET @Language = ISNULL(@Language, 'en');

    DECLARE @ServerName  NVARCHAR(128)  = ISNULL(
        (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'General' AND SettingName = 'ServerName'),
        @@SERVERNAME);

    DECLARE @MailProfile NVARCHAR(128)  =
        (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'Email' AND SettingName = 'ProfileName');

    DECLARE @Recipients  NVARCHAR(1000) = ISNULL(@OverrideRecipients,
        (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'Email' AND SettingName = 'Recipients_Weekly'));
    IF @Recipients IS NULL OR @Recipients = ''
        SELECT @Recipients = SettingValue FROM [monitor].[Settings] WHERE Category = 'Email' AND SettingName = 'Recipients';

    DECLARE @Now           DATETIME2 = SYSUTCDATETIME();
    DECLARE @ThisWeekStart DATETIME2 = DATEADD(DAY, -7,  @Now);
    DECLARE @LastWeekStart DATETIME2 = DATEADD(DAY, -14, @Now);
    DECLARE @LastWeekEnd   DATETIME2 = @ThisWeekStart;
    DECLARE @WeekStr       NVARCHAR(50) = FORMAT(@ThisWeekStart,'MMM dd') + ' - ' + FORMAT(@Now,'MMM dd, yyyy') + ' UTC';

    -- ============================================================
    -- SCALAR METRICS (week-over-week)
    -- ============================================================
    DECLARE @CpuAvgThis INT, @CpuMaxThis INT, @CpuAvgLast INT;
    DECLARE @PleAvgThis INT, @PleMinThis INT, @PleAvgLast INT;
    DECLARE @BlockingThis INT, @BlockingLast INT;
    DECLARE @AlertsThis INT, @AlertsLast INT;
    DECLARE @ErrorsThis INT, @ErrorsLast INT;
    DECLARE @FailedJobsThis INT, @FailedJobsLast INT;

    SELECT @CpuAvgThis = AVG(SqlCpuPct), @CpuMaxThis = MAX(SqlCpuPct)
    FROM [monitor].[CpuHistory] WHERE CollectedAt >= @ThisWeekStart;
    SELECT @CpuAvgLast = AVG(SqlCpuPct)
    FROM [monitor].[CpuHistory] WHERE CollectedAt >= @LastWeekStart AND CollectedAt < @LastWeekEnd;

    SELECT @PleAvgThis = AVG(PageLifeExpectancy), @PleMinThis = MIN(PageLifeExpectancy)
    FROM [monitor].[MemoryHistory] WHERE CollectedAt >= @ThisWeekStart;
    SELECT @PleAvgLast = AVG(PageLifeExpectancy)
    FROM [monitor].[MemoryHistory] WHERE CollectedAt >= @LastWeekStart AND CollectedAt < @LastWeekEnd;

    SELECT @BlockingThis = COUNT(*) FROM [monitor].[BlockingHistory] WHERE DetectedAt >= @ThisWeekStart;
    SELECT @BlockingLast = COUNT(*) FROM [monitor].[BlockingHistory] WHERE DetectedAt >= @LastWeekStart AND DetectedAt < @LastWeekEnd;

    SELECT @AlertsThis = COUNT(*) FROM [monitor].[AlertHistory] WHERE FiredAt >= @ThisWeekStart;
    SELECT @AlertsLast = COUNT(*) FROM [monitor].[AlertHistory] WHERE FiredAt >= @LastWeekStart AND FiredAt < @LastWeekEnd;

    SELECT @ErrorsThis = COUNT(*) FROM [monitor].[ErrorLogHistory]
    WHERE CollectedAt >= @ThisWeekStart AND Severity IN ('Critical','Error');
    SELECT @ErrorsLast = COUNT(*) FROM [monitor].[ErrorLogHistory]
    WHERE CollectedAt >= @LastWeekStart AND CollectedAt < @LastWeekEnd AND Severity IN ('Critical','Error');

    SELECT @FailedJobsThis = COUNT(DISTINCT JobName) FROM [monitor].[JobHistory]
    WHERE CollectedAt >= @ThisWeekStart AND LastRunStatus = 'Failed';
    SELECT @FailedJobsLast = COUNT(DISTINCT JobName) FROM [monitor].[JobHistory]
    WHERE CollectedAt >= @LastWeekStart AND CollectedAt < @LastWeekEnd AND LastRunStatus = 'Failed';

    -- ============================================================
    -- TABULAR SECTIONS (read by usp_BuildWeeklyHtml)
    -- ============================================================

    -- Week-over-week summary rows
    CREATE TABLE #WeeklyWoW (MetricName NVARCHAR(50), ThisWeek DECIMAL(18,2), LastWeek DECIMAL(18,2));
    INSERT #WeeklyWoW VALUES
        ('CPU Avg %',         ISNULL(@CpuAvgThis,0),     ISNULL(@CpuAvgLast,0)),
        ('PLE Avg (s)',        ISNULL(@PleAvgThis,0),     ISNULL(@PleAvgLast,0)),
        ('PLE Min (s)',        ISNULL(@PleMinThis,0),     0),
        ('Blocking Events',    ISNULL(@BlockingThis,0),   ISNULL(@BlockingLast,0)),
        ('Alerts Fired',       ISNULL(@AlertsThis,0),     ISNULL(@AlertsLast,0)),
        ('Error Log Entries',  ISNULL(@ErrorsThis,0),     ISNULL(@ErrorsLast,0)),
        ('Failed Jobs',        ISNULL(@FailedJobsThis,0), ISNULL(@FailedJobsLast,0));

    -- Disk capacity planning
    CREATE TABLE #WeeklyDiskCapacity (
        DriveLetter    NVARCHAR(10),
        TotalGB        DECIMAL(10,1),
        UsedGB         DECIMAL(10,1),
        FreeGB         DECIMAL(10,1),
        UsedPct        DECIMAL(5,1),
        WeeklyGrowthGB DECIMAL(10,2),
        DaysUntil95    INT,
        CapStatus      NVARCHAR(10)
    );
    INSERT #WeeklyDiskCapacity
    SELECT curr.DriveLetter,
        CAST(curr.TotalSpaceMB / 1024.0 AS DECIMAL(10,1)),
        CAST((curr.TotalSpaceMB - curr.FreeSpaceMB) / 1024.0 AS DECIMAL(10,1)),
        CAST(curr.FreeSpaceMB / 1024.0 AS DECIMAL(10,1)),
        CAST(curr.UsedPct AS DECIMAL(5,1)),
        CAST(ISNULL(g.WeeklyGrowthMB,0) / 1024.0 AS DECIMAL(10,2)),
        CASE WHEN ISNULL(g.DailyGrowthMB,0) <= 0 THEN 9999
             ELSE CAST((curr.FreeSpaceMB - curr.TotalSpaceMB * 0.05) / NULLIF(g.DailyGrowthMB,0) AS INT) END,
        CASE WHEN ISNULL(g.DailyGrowthMB,0) <= 0 THEN 'ok'
             WHEN (curr.FreeSpaceMB - curr.TotalSpaceMB * 0.05) / NULLIF(g.DailyGrowthMB,0) <= 30 THEN 'critical'
             WHEN (curr.FreeSpaceMB - curr.TotalSpaceMB * 0.05) / NULLIF(g.DailyGrowthMB,0) <= 90 THEN 'warning'
             ELSE 'ok' END
    FROM (
        SELECT DriveLetter, AVG(TotalSpaceMB) AS TotalSpaceMB, AVG(FreeSpaceMB) AS FreeSpaceMB, AVG(UsedPct) AS UsedPct
        FROM [monitor].[DiskHistory] WHERE CollectedAt >= DATEADD(HOUR,-6,@Now) GROUP BY DriveLetter
    ) curr
    LEFT JOIN (
        SELECT n.DriveLetter,
            (n.UsedMB - ISNULL(o.UsedMB,n.UsedMB)) AS WeeklyGrowthMB,
            (n.UsedMB - ISNULL(o.UsedMB,n.UsedMB)) / 7.0 AS DailyGrowthMB
        FROM (
            SELECT DriveLetter, AVG(TotalSpaceMB - FreeSpaceMB) AS UsedMB
            FROM [monitor].[DiskHistory] WHERE CollectedAt >= DATEADD(HOUR,-6,@Now) GROUP BY DriveLetter
        ) n
        LEFT JOIN (
            SELECT DriveLetter, AVG(TotalSpaceMB - FreeSpaceMB) AS UsedMB
            FROM [monitor].[DiskHistory]
            WHERE CollectedAt >= @ThisWeekStart AND CollectedAt < DATEADD(HOUR,6,@ThisWeekStart)
            GROUP BY DriveLetter
        ) o ON n.DriveLetter = o.DriveLetter
    ) g ON curr.DriveLetter = g.DriveLetter;

    -- What changed this week
    CREATE TABLE #WeeklyChanges (
        ChangeType  NVARCHAR(50),
        ChangeDate  DATETIME2,
        Description NVARCHAR(500),
        Impact      NVARCHAR(10)
    );
    INSERT #WeeklyChanges
    SELECT 'Disk Growth Spike', CollectedAt,
        DriveLetter + ': grew ' + CAST(CAST(GrowthMB/1024.0 AS DECIMAL(10,1)) AS NVARCHAR) + ' GB in one interval',
        CASE WHEN GrowthMB > 10240 THEN 'HIGH' WHEN GrowthMB > 5120 THEN 'MEDIUM' ELSE 'LOW' END
    FROM (
        SELECT DriveLetter, CollectedAt,
            (TotalSpaceMB - FreeSpaceMB)
            - LAG(TotalSpaceMB - FreeSpaceMB) OVER (PARTITION BY DriveLetter ORDER BY CollectedAt) AS GrowthMB
        FROM [monitor].[DiskHistory] WHERE CollectedAt >= @ThisWeekStart
    ) d WHERE GrowthMB > 5120;

    INSERT #WeeklyChanges
    SELECT TOP 10 'File Auto-Growth', CollectedAt,
        DatabaseName + '.' + FileName + ' (' + FileType + '): +' + CAST(GrowthMB AS NVARCHAR) + ' MB',
        CASE WHEN GrowthMB > 1024 THEN 'HIGH' WHEN GrowthMB > 256 THEN 'MEDIUM' ELSE 'LOW' END
    FROM [monitor].[FileGrowthHistory]
    WHERE CollectedAt >= @ThisWeekStart AND ISNULL(GrowthMB,0) > 100
    ORDER BY GrowthMB DESC;

    INSERT #WeeklyChanges
    SELECT TOP 5 'New Error Pattern', MIN(LogDate),
        LEFT(ErrorMessage,200) + ' (x' + CAST(COUNT(*) AS NVARCHAR) + ')',
        CASE WHEN COUNT(*) > 100 THEN 'HIGH' WHEN COUNT(*) > 10 THEN 'MEDIUM' ELSE 'LOW' END
    FROM [monitor].[ErrorLogHistory] e
    WHERE e.CollectedAt >= @ThisWeekStart AND e.Severity IN ('Critical','Error')
        AND NOT EXISTS (
            SELECT 1 FROM [monitor].[ErrorLogHistory] p
            WHERE p.CollectedAt >= @LastWeekStart AND p.CollectedAt < @LastWeekEnd AND p.ErrorMessage = e.ErrorMessage)
    GROUP BY LEFT(ErrorMessage,200) HAVING COUNT(*) >= 3
    ORDER BY COUNT(*) DESC;

    INSERT #WeeklyChanges
    SELECT DISTINCT 'AG State Change', CollectedAt,
        AgName + '/' + ReplicaServer + ': ' + SyncState + ' (' + SyncHealth + ')',
        CASE WHEN SyncHealth <> 'HEALTHY' THEN 'HIGH' ELSE 'MEDIUM' END
    FROM [monitor].[AgHealthHistory]
    WHERE CollectedAt >= @ThisWeekStart AND (SyncHealth <> 'HEALTHY' OR SyncState = 'NOT SYNCHRONIZING');

    INSERT #WeeklyChanges
    SELECT 'Job Started Failing', MAX(jt.LastRunDate),
        jt.JobName + ' failed ' + CAST(COUNT(*) AS NVARCHAR) + ' time(s) this week',
        CASE WHEN COUNT(*) > 5 THEN 'HIGH' ELSE 'MEDIUM' END
    FROM [monitor].[JobHistory] jt
    WHERE jt.CollectedAt >= @ThisWeekStart AND jt.LastRunStatus = 'Failed'
        AND NOT EXISTS (
            SELECT 1 FROM [monitor].[JobHistory] jl
            WHERE jl.CollectedAt >= @LastWeekStart AND jl.CollectedAt < @LastWeekEnd
                AND jl.JobName = jt.JobName AND jl.LastRunStatus = 'Failed')
    GROUP BY jt.JobName;

    -- Top degraded queries
    CREATE TABLE #WeeklyTopQueries (
        DatabaseName NVARCHAR(128),
        CpuMsThis    BIGINT,
        CpuMsLast    BIGINT,
        ChangePct    DECIMAL(10,1),
        Executions   BIGINT,
        QueryText    NVARCHAR(200)
    );
    INSERT #WeeklyTopQueries
    SELECT TOP 10 tw.DatabaseName, tw.TotalCpuMs, ISNULL(lw.TotalCpuMs,0),
        CASE WHEN ISNULL(lw.TotalCpuMs,0) = 0 THEN NULL
             ELSE CAST(ROUND((tw.TotalCpuMs - ISNULL(lw.TotalCpuMs,0)) * 100.0 / NULLIF(lw.TotalCpuMs,0),1) AS DECIMAL(10,1)) END,
        tw.ExecutionCount,
        LEFT(ISNULL(tw.QueryText,''),200)
    FROM (
        SELECT DatabaseName, QueryHash,
            SUM(TotalCpuMs) AS TotalCpuMs, SUM(ExecutionCount) AS ExecutionCount, MAX(QueryText) AS QueryText
        FROM [monitor].[TopQueriesHistory] WHERE CollectedAt >= @ThisWeekStart
        GROUP BY DatabaseName, QueryHash
    ) tw
    LEFT JOIN (
        SELECT DatabaseName, QueryHash, SUM(TotalCpuMs) AS TotalCpuMs
        FROM [monitor].[TopQueriesHistory]
        WHERE CollectedAt >= @LastWeekStart AND CollectedAt < @LastWeekEnd
        GROUP BY DatabaseName, QueryHash
    ) lw ON tw.DatabaseName = lw.DatabaseName AND tw.QueryHash = lw.QueryHash
    WHERE tw.TotalCpuMs > ISNULL(lw.TotalCpuMs,0)
    ORDER BY (tw.TotalCpuMs - ISNULL(lw.TotalCpuMs,0)) DESC;

    -- Recommendations
    CREATE TABLE #WeeklyRecommendations (
        Priority   INT,
        Category   NVARCHAR(50),
        Message    NVARCHAR(500),
        ActionItem NVARCHAR(500)
    );
    IF EXISTS (SELECT 1 FROM [monitor].[DiskHistory] WHERE CollectedAt >= DATEADD(HOUR,-6,@Now) AND UsedPct >= 90)
        INSERT #WeeklyRecommendations VALUES (1,'Capacity','One or more drives above 90% usage.','Immediate capacity expansion or data archival required.');
    IF EXISTS (SELECT 1 FROM [monitor].[BackupHistory] WHERE CollectedAt >= DATEADD(HOUR,-6,@Now) AND BackupType = 'D' AND HoursSinceLastBackup > 48)
        INSERT #WeeklyRecommendations VALUES (1,'DR','Databases with full backup older than 48h detected.','Verify backup jobs. Check for disk space issues on backup target.');
    IF @CpuAvgThis > ISNULL(@CpuAvgLast,0) * 1.2 AND @CpuAvgThis > 50
        INSERT #WeeklyRecommendations VALUES (2,'Performance',
            'CPU avg increased ' + CAST(CASE WHEN @CpuAvgLast > 0 THEN CAST(ROUND((@CpuAvgThis - @CpuAvgLast) * 100.0 / @CpuAvgLast,0) AS INT) ELSE 0 END AS NVARCHAR) + '% week-over-week.',
            'Review top queries. Consider index optimization or workload redistribution.');
    IF @PleAvgThis < ISNULL(@PleAvgLast,9999) * 0.7 AND @PleAvgThis < 1000
        INSERT #WeeklyRecommendations VALUES (2,'Memory',
            'PLE dropped significantly vs last week (avg ' + CAST(ISNULL(@PleAvgThis,0) AS NVARCHAR) + 's vs ' + CAST(ISNULL(@PleAvgLast,0) AS NVARCHAR) + 's).',
            'Investigate memory-intensive queries. Consider memory increase.');
    IF @BlockingThis > ISNULL(@BlockingLast,0) * 2 AND @BlockingThis > 10
        INSERT #WeeklyRecommendations VALUES (2,'Concurrency',
            'Blocking events doubled (' + CAST(@BlockingThis AS NVARCHAR) + ' vs ' + CAST(@BlockingLast AS NVARCHAR) + ').',
            'Review blocking chains. Consider RCSI, query tuning, or lock escalation settings.');
    DECLARE @FragIndexCount INT;
    SELECT @FragIndexCount = COUNT(DISTINCT IndexName) FROM [monitor].[IndexHealthHistory]
    WHERE CollectedAt >= @ThisWeekStart AND FragmentationPct >= 30 AND PageCount >= 1000;
    IF @FragIndexCount > 0
        INSERT #WeeklyRecommendations VALUES (2,'Maintenance',
            CAST(@FragIndexCount AS NVARCHAR) + ' indexes with >30% fragmentation.',
            'Schedule index rebuild during maintenance window.');
    IF @ErrorsThis > ISNULL(@ErrorsLast,0) * 2 AND @ErrorsThis > 20
        INSERT #WeeklyRecommendations VALUES (2,'Reliability',
            'Error log entries increased significantly (' + CAST(@ErrorsThis AS NVARCHAR) + ' vs ' + CAST(@ErrorsLast AS NVARCHAR) + ').',
            'Review new error patterns in the ''What Changed'' section.');
    DECLARE @AnomalyCount INT = 0;
    IF OBJECT_ID('monitor.BaselineAnomalies','U') IS NOT NULL
        SELECT @AnomalyCount = COUNT(DISTINCT MetricName) FROM [monitor].[BaselineAnomalies] WHERE DetectedAt >= @ThisWeekStart;
    IF @AnomalyCount > 0
        INSERT #WeeklyRecommendations VALUES (2,'Baseline',
            CAST(@AnomalyCount AS NVARCHAR) + ' metric(s) deviated from baseline this week.',
            'Review baseline anomalies. Consider recapturing baselines if workload changed intentionally.');

    -- Top wait types comparison
    CREATE TABLE #WeeklyTopWaits (WaitType NVARCHAR(100), DeltaMsThis BIGINT, DeltaMsLast BIGINT);
    INSERT #WeeklyTopWaits
    SELECT ISNULL(tw.WaitType,lw.WaitType), ISNULL(tw.TotalDeltaMs,0), ISNULL(lw.TotalDeltaMs,0)
    FROM (
        SELECT TOP 10 WaitType, SUM(ISNULL(DeltaWaitTimeMs,WaitTimeMs)) AS TotalDeltaMs
        FROM [monitor].[WaitStatsHistory] WHERE CollectedAt >= @ThisWeekStart
        GROUP BY WaitType ORDER BY SUM(ISNULL(DeltaWaitTimeMs,WaitTimeMs)) DESC
    ) tw
    FULL OUTER JOIN (
        SELECT TOP 10 WaitType, SUM(ISNULL(DeltaWaitTimeMs,WaitTimeMs)) AS TotalDeltaMs
        FROM [monitor].[WaitStatsHistory]
        WHERE CollectedAt >= @LastWeekStart AND CollectedAt < @LastWeekEnd
        GROUP BY WaitType ORDER BY SUM(ISNULL(DeltaWaitTimeMs,WaitTimeMs)) DESC
    ) lw ON tw.WaitType = lw.WaitType;

    -- Index Recommendations (from DMVs)
    CREATE TABLE #WeeklyIndexRecommendations (
        DatabaseName     NVARCHAR(128),
        SchemaName       NVARCHAR(128),
        TableName        NVARCHAR(128),
        RecommendationType NVARCHAR(50),
        ImpactScore      DECIMAL(18,2),
        EqualityColumns  NVARCHAR(MAX),
        InequalityColumns NVARCHAR(MAX),
        IncludeColumns   NVARCHAR(MAX),
        UserSeeks        BIGINT,
        RecommendedAction NVARCHAR(MAX)
    );
    INSERT #WeeklyIndexRecommendations
    SELECT TOP 10
        DatabaseName, SchemaName, TableName,
        RecommendationType, ImpactScore,
        EqualityColumns, InequalityColumns, IncludeColumns,
        UserSeeks, RecommendedAction
    FROM [monitor].[IndexRecommendations]
    WHERE CollectedAt >= DATEADD(DAY,-1,@Now)
      AND RecommendationType = 'MISSING_INDEX'
    ORDER BY ImpactScore DESC;

    -- Query Store Top Queries (multi-dimension)
    CREATE TABLE #WeeklyTopQueriesQS (
        DatabaseName     NVARCHAR(128),
        QueryId          INT,
        TotalCpuMs       DECIMAL(18,2),
        AvgCpuMs         DECIMAL(18,2),
        TotalDurationMs   DECIMAL(18,2),
        AvgDurationMs    DECIMAL(18,2),
        TotalLogicalReads BIGINT,
        AvgLogicalReads  DECIMAL(18,2),
        TotalWrites      BIGINT,
        ExecutionCount   BIGINT,
        QueryText        NVARCHAR(4000),
        QueryDimension   NVARCHAR(20)
    );
    INSERT #WeeklyTopQueriesQS
    -- Top by CPU
    SELECT DatabaseName, QueryId,
        SUM(TotalCpuMs), MAX(AvgCpuMs), SUM(TotalDurationMs), MAX(AvgDurationMs),
        SUM(TotalLogicalReads), MAX(AvgLogicalReads), SUM(TotalLogicalWrites),
        SUM(ExecutionCount), MAX(QueryText), 'CPU'
    FROM [monitor].[QueryStoreHistory]
    WHERE CollectedAt >= @ThisWeekStart
    GROUP BY DatabaseName, QueryId
    HAVING SUM(TotalCpuMs) > 0
    ORDER BY SUM(TotalCpuMs) DESC;

    -- Top by Duration
    INSERT #WeeklyTopQueriesQS
    SELECT DatabaseName, QueryId,
        SUM(TotalCpuMs), MAX(AvgCpuMs), SUM(TotalDurationMs), MAX(AvgDurationMs),
        SUM(TotalLogicalReads), MAX(AvgLogicalReads), SUM(TotalLogicalWrites),
        SUM(ExecutionCount), MAX(QueryText), 'DURATION'
    FROM [monitor].[QueryStoreHistory]
    WHERE CollectedAt >= @ThisWeekStart
    GROUP BY DatabaseName, QueryId
    HAVING SUM(TotalDurationMs) > 0
    ORDER BY SUM(TotalDurationMs) DESC;

    -- Top by Reads
    INSERT #WeeklyTopQueriesQS
    SELECT DatabaseName, QueryId,
        SUM(TotalCpuMs), MAX(AvgCpuMs), SUM(TotalDurationMs), MAX(AvgDurationMs),
        SUM(TotalLogicalReads), MAX(AvgLogicalReads), SUM(TotalLogicalWrites),
        SUM(ExecutionCount), MAX(QueryText), 'READS'
    FROM [monitor].[QueryStoreHistory]
    WHERE CollectedAt >= @ThisWeekStart
    GROUP BY DatabaseName, QueryId
    HAVING SUM(TotalLogicalReads) > 0
    ORDER BY SUM(TotalLogicalReads) DESC;

    -- ============================================================
    -- BUILD HTML
    -- ============================================================
    DECLARE @HtmlBody VARCHAR(MAX);

    EXEC [monitor].[usp_BuildWeeklyHtml]
        @ServerName = @ServerName,
        @WeekStr    = @WeekStr,
        @CpuAvgThis = @CpuAvgThis,
        @CpuAvgLast = @CpuAvgLast,
        @PleAvgThis = @PleAvgThis,
        @BlockingThis = @BlockingThis,
        @AlertsThis = @AlertsThis,
        @ErrorsThis = @ErrorsThis,
        @HtmlBody   = @HtmlBody OUTPUT;

    -- ============================================================
    -- SEND OR DEBUG
    -- ============================================================
    IF @DebugMode = 1
    BEGIN
        SELECT @HtmlBody AS HtmlBody;
        RETURN;
    END;

    IF @MailProfile IS NULL OR @MailProfile = ''
        RAISERROR('Email.ProfileName is not configured in monitor.Settings.', 16, 1);

    IF @Recipients IS NULL OR @Recipients = ''
        RAISERROR('No email recipients configured. Set Email.Recipients_Weekly or Email.Recipients in monitor.Settings.', 16, 1);

    DECLARE @Subject NVARCHAR(255) =
        '[Weekly] SQL Health Monitor - ' + @ServerName + ' - ' + @WeekStr;

    EXEC msdb.dbo.sp_send_dbmail
        @profile_name = @MailProfile,
        @recipients   = @Recipients,
        @subject      = @Subject,
        @body         = @HtmlBody,
        @body_format  = 'HTML';

    INSERT INTO [monitor].[ReportHistory] (ReportType, Recipients, Language, Success)
    VALUES ('Weekly', @Recipients, @Language, 1);

    PRINT '+ Weekly report sent for period: ' + @WeekStr;
END;
GO

PRINT '+ Procedure [monitor].[usp_GenerateWeeklyReport] created.';
GO
