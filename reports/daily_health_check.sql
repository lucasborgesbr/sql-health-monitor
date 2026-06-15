/*
    SQL Health Monitor - Daily Health Report Generator
    Aggregates last 24h of collector data into structured result sets.
    
    Calls:
        - vw_CurrentHealth for traffic light status
        - Recommendations engine for action items
        - Baseline anomaly detection for deviations
    
    Output sections:
        1. Executive Summary (overall health score + status)
        2. Health Score (per-metric traffic light)
        3. Top Issues (blocking, failed jobs, errors)
        4. Anomalies vs Baseline
        5. Recommendations (prioritized action items)
    
    Schema: [monitor]
    Compatibility: SQL Server 2016+
    Author: Lucas Allan Borges
    
    Parameters:
        @OverrideLanguage    CHAR(5)       - Override language (default: from Settings)
        @OverrideRecipients  NVARCHAR(500) - Override email recipients
        @DebugMode           BIT           - 1 = SELECT results instead of sending email
    
    Example Usage:
        -- Generate and send daily report
        EXEC [monitor].[usp_GenerateDailyReport];
        
        -- Debug mode - view structured output
        EXEC [monitor].[usp_GenerateDailyReport] @DebugMode = 1;
        
        -- Override language
        EXEC [monitor].[usp_GenerateDailyReport] @OverrideLanguage = 'ptbr', @DebugMode = 1;
*/

USE [SQLHealthMonitor];
GO

/*
    SQL Health Monitor - Daily Health Report Generator
    Aggregates last 24h of collector data into structured result sets.
    
    Calls:
        - vw_CurrentHealth for traffic light status
        - Recommendations engine for action items
        - Baseline anomaly detection for deviations
    
    Output sections:
        1. Executive Summary (overall health score + status)
        2. Health Score (per-metric traffic light)
        3. Top Issues (blocking, failed jobs, errors)
        4. Anomalies vs Baseline
        5. Recommendations (prioritized action items)
    
    Schema: [monitor]
    Compatibility: SQL Server 2016+
    Author: Lucas Allan Borges
    
    Parameters:
        @OverrideLanguage    CHAR(5)       - Override language (default: from Settings)
        @OverrideRecipients  NVARCHAR(500) - Override email recipients
        @DebugMode           BIT           - 1 = SELECT results instead of sending email
    
    Example Usage:
        -- Generate and send daily report
        EXEC [monitor].[usp_GenerateDailyReport];
        
        -- Debug mode - view structured output
        EXEC [monitor].[usp_GenerateDailyReport] @DebugMode = 1;
        
        -- Override language
        EXEC [monitor].[usp_GenerateDailyReport] @OverrideLanguage = 'ptbr', @DebugMode = 1;
*/

USE [SQLHealthMonitor];
GO

IF OBJECT_ID('[monitor].[usp_GenerateDailyReport]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_GenerateDailyReport] @OverrideLanguage CHAR(5) = NULL, @OverrideRecipients NVARCHAR(500) = NULL, @DebugMode BIT = NULL AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_GenerateDailyReport]', 'P') IS NULL
    EXEC('
    CREATE PROCEDURE [monitor].[usp_GenerateDailyReport]
        
        @OverrideLanguage CHAR(5) = NULL,
        @OverrideRecipients NVARCHAR(500) = NULL,
        @DebugMode BIT = 0
    AS
    BEGIN
        SET NOCOUNT ON;
        PRINT ''Placeholder'';
    END;
    ');
GO

ALTER PROCEDURE [monitor].[usp_GenerateDailyReport]
    @OverrideLanguage CHAR(5) = NULL,
    @OverrideRecipients NVARCHAR(500) = NULL,
    @DebugMode BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ============================================================
    -- CONFIGURATION
    -- ============================================================
    DECLARE @Language CHAR(5) = ISNULL(@OverrideLanguage, 
        (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'General' AND SettingName = 'Language'));
    SET @Language = ISNULL(@Language, 'en');

    DECLARE @ServerName NVARCHAR(128) = ISNULL(
        (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'General' AND SettingName = 'ServerName'),
        @@SERVERNAME);

    -- Date range: last 24 hours
    DECLARE @StartDate DATETIME2 = DATEADD(HOUR, -24, SYSUTCDATETIME());
    DECLARE @EndDate DATETIME2 = SYSUTCDATETIME();
    DECLARE @DateStr NVARCHAR(20) = FORMAT(SYSUTCDATETIME(), 'yyyy-MM-dd');

    -- ============================================================
    -- RESULT SET 1: EXECUTIVE SUMMARY
    -- ============================================================
    DECLARE @CpuAvg INT, @CpuMax INT, @CpuStatus NVARCHAR(10);
    DECLARE @PleMin INT, @PleAvg INT, @MemStatus NVARCHAR(10);
    DECLARE @DiskMaxPct DECIMAL(5,2), @DiskStatus NVARCHAR(10);
    DECLARE @AgMaxLag INT, @AgStatus NVARCHAR(10);
    DECLARE @BlockingCount INT, @FailedJobs INT, @ErrorCount INT;
    DECLARE @OverallStatus NVARCHAR(10);
    DECLARE @HealthScore INT;

    -- CPU
    SELECT @CpuAvg = AVG(SqlCpuPct), @CpuMax = MAX(SqlCpuPct)
    FROM [monitor].[CpuHistory] WHERE CollectedAt >= @StartDate;
    SET @CpuStatus = CASE WHEN @CpuMax >= 95 THEN 'critical' WHEN @CpuMax >= 80 THEN 'warning' ELSE 'healthy' END;

    -- Memory (PLE)
    SELECT @PleMin = MIN(PageLifeExpectancy), @PleAvg = AVG(PageLifeExpectancy)
    FROM [monitor].[MemoryHistory] WHERE CollectedAt >= @StartDate;
    SET @MemStatus = CASE WHEN @PleMin <= 100 THEN 'critical' WHEN @PleMin <= 300 THEN 'warning' ELSE 'healthy' END;

    -- Disk
    SELECT @DiskMaxPct = MAX(UsedPct)
    FROM [monitor].[DiskHistory] WHERE CollectedAt >= @StartDate;
    SET @DiskStatus = CASE WHEN @DiskMaxPct >= 95 THEN 'critical' WHEN @DiskMaxPct >= 85 THEN 'warning' ELSE 'healthy' END;

    -- AG
    SELECT @AgMaxLag = MAX(SecondsBehindPrimary)
    FROM [monitor].[AgHealthHistory] WHERE CollectedAt >= @StartDate;
    SET @AgStatus = CASE WHEN @AgMaxLag >= 120 THEN 'critical' WHEN @AgMaxLag >= 30 THEN 'warning' ELSE 'healthy' END;

    -- Issues
    SELECT @BlockingCount = COUNT(*) FROM [monitor].[BlockingHistory] WHERE DetectedAt >= @StartDate;
    SELECT @FailedJobs = COUNT(DISTINCT JobName) FROM [monitor].[JobHistory] 
        WHERE CollectedAt >= @StartDate AND LastRunStatus = 'Failed';
    SELECT @ErrorCount = COUNT(*) FROM [monitor].[ErrorLogHistory] 
        WHERE CollectedAt >= @StartDate AND Severity IN ('Critical', 'Error');

    -- Overall status
    SET @OverallStatus = CASE 
        WHEN @CpuStatus = 'critical' OR @MemStatus = 'critical' OR @DiskStatus = 'critical' OR @AgStatus = 'critical' THEN 'critical'
        WHEN @CpuStatus = 'warning' OR @MemStatus = 'warning' OR @DiskStatus = 'warning' OR @AgStatus = 'warning' THEN 'warning'
        ELSE 'healthy' END;

    -- Health Score (0-100, higher is better)
    SET @HealthScore = 100
        - CASE @CpuStatus WHEN 'critical' THEN 25 WHEN 'warning' THEN 10 ELSE 0 END
        - CASE @MemStatus WHEN 'critical' THEN 25 WHEN 'warning' THEN 10 ELSE 0 END
        - CASE @DiskStatus WHEN 'critical' THEN 20 WHEN 'warning' THEN 8 ELSE 0 END
        - CASE @AgStatus WHEN 'critical' THEN 20 WHEN 'warning' THEN 8 ELSE 0 END
        - CASE WHEN @BlockingCount > 50 THEN 10 WHEN @BlockingCount > 10 THEN 5 ELSE 0 END
        - CASE WHEN @FailedJobs > 5 THEN 10 WHEN @FailedJobs > 0 THEN 3 ELSE 0 END;
    IF @HealthScore < 0 SET @HealthScore = 0;

    -- Output Result Set 1: Executive Summary
    SELECT 
        @ServerName AS ServerName,
        @DateStr AS ReportDate,
        @OverallStatus AS OverallStatus,
        @HealthScore AS HealthScore,
        @CpuAvg AS CpuAvg,
        @CpuMax AS CpuMax,
        @CpuStatus AS CpuStatus,
        @PleAvg AS PleAvg,
        @PleMin AS PleMin,
        @MemStatus AS MemoryStatus,
        @DiskMaxPct AS DiskMaxUsedPct,
        @DiskStatus AS DiskStatus,
        ISNULL(@AgMaxLag, 0) AS AgMaxLagSeconds,
        @AgStatus AS AgStatus,
        @BlockingCount AS BlockingEvents24h,
        @FailedJobs AS FailedJobs24h,
        @ErrorCount AS ErrorLogEntries24h;

    -- ============================================================
    -- RESULT SET 2: HEALTH SCORE BREAKDOWN (Traffic Light)
    -- ============================================================
    SELECT MetricName, MetricValue, Status, Details
    FROM (
        VALUES
            ('CPU',      CAST(ISNULL(@CpuAvg, 0) AS NVARCHAR) + '% avg / ' + CAST(ISNULL(@CpuMax, 0) AS NVARCHAR) + '% max', @CpuStatus, 
                CASE @CpuStatus WHEN 'critical' THEN 'CPU sustained above 95%' WHEN 'warning' THEN 'CPU peaked above 80%' ELSE 'Normal' END),
            ('Memory',   CAST(ISNULL(@PleAvg, 0) AS NVARCHAR) + 's avg / ' + CAST(ISNULL(@PleMin, 0) AS NVARCHAR) + 's min PLE', @MemStatus,
                CASE @MemStatus WHEN 'critical' THEN 'PLE dropped below 100s - severe memory pressure' WHEN 'warning' THEN 'PLE below 300s - memory pressure detected' ELSE 'Normal' END),
            ('Disk',     CAST(ISNULL(CAST(@DiskMaxPct AS INT), 0) AS NVARCHAR) + '% max used', @DiskStatus,
                CASE @DiskStatus WHEN 'critical' THEN 'Disk above 95% - immediate action needed' WHEN 'warning' THEN 'Disk above 85% - monitor closely' ELSE 'Normal' END),
            ('AG Sync',  CAST(ISNULL(@AgMaxLag, 0) AS NVARCHAR) + 's max lag', @AgStatus,
                CASE @AgStatus WHEN 'critical' THEN 'AG lag > 120s - potential data loss risk' WHEN 'warning' THEN 'AG lag > 30s - investigate' ELSE 'Normal' END),
            ('Blocking', CAST(@BlockingCount AS NVARCHAR) + ' events', 
                CASE WHEN @BlockingCount > 50 THEN 'critical' WHEN @BlockingCount > 10 THEN 'warning' ELSE 'healthy' END,
                CASE WHEN @BlockingCount > 50 THEN 'Excessive blocking detected' WHEN @BlockingCount > 10 THEN 'Elevated blocking' ELSE 'Normal' END),
            ('Jobs',     CAST(@FailedJobs AS NVARCHAR) + ' failed',
                CASE WHEN @FailedJobs > 5 THEN 'critical' WHEN @FailedJobs > 0 THEN 'warning' ELSE 'healthy' END,
                CASE WHEN @FailedJobs > 0 THEN CAST(@FailedJobs AS NVARCHAR) + ' job(s) failed in last 24h' ELSE 'All jobs healthy' END)
    ) AS v(MetricName, MetricValue, Status, Details);

    -- ============================================================
    -- RESULT SET 3: TOP ISSUES
    -- ============================================================
    
    -- Top blocking events
    SELECT TOP 10
        'Blocking' AS IssueType,
        DetectedAt,
        DatabaseName,
        BlockingSpid,
        BlockedSpid,
        BlockingDurationSec,
        LEFT(ISNULL(BlockingQuery, ''), 200) AS BlockingQuery,
        LEFT(ISNULL(BlockedQuery, ''), 200) AS BlockedQuery
    FROM [monitor].[BlockingHistory]
    WHERE DetectedAt >= @StartDate
    ORDER BY BlockingDurationSec DESC;

    -- Failed jobs detail
    SELECT TOP 10
        'FailedJob' AS IssueType,
        CollectedAt,
        JobName,
        LastRunDate,
        LastRunStatus,
        LastRunDuration
    FROM [monitor].[JobHistory]
    WHERE CollectedAt >= @StartDate AND LastRunStatus = 'Failed'
    ORDER BY LastRunDate DESC;

    -- Critical/Error log entries
    SELECT TOP 20
        'ErrorLog' AS IssueType,
        LogDate,
        Severity,
        ProcessInfo,
        LEFT(ErrorMessage, 300) AS ErrorMessage
    FROM [monitor].[ErrorLogHistory]
    WHERE CollectedAt >= @StartDate AND Severity IN ('Critical', 'Error')
    ORDER BY LogDate DESC;

    -- ============================================================
    -- RESULT SET 4: ANOMALIES VS BASELINE
    -- ============================================================
    IF OBJECT_ID('monitor.BaselineCapture', 'U') IS NOT NULL
        AND EXISTS (SELECT 1 FROM [monitor].[BaselineCapture] WHERE IsActive = 1)
    BEGIN
        -- Run anomaly detection for last 60 minutes and return results
        SELECT 
            ba.MetricName,
            ba.CurrentValue,
            ba.BaselineAvg,
            ba.BaselineStdDev,
            ba.DeviationMultiplier,
            ba.Severity,
            ba.Direction,
            ba.Message
        FROM [monitor].[BaselineAnomalies] ba
        WHERE ba.DetectedAt >= @StartDate
        ORDER BY 
            CASE ba.Severity WHEN 'Critical' THEN 1 WHEN 'Warning' THEN 2 ELSE 3 END,
            ba.DeviationMultiplier DESC;
    END
    ELSE
    BEGIN
        -- Return empty result set with schema
        SELECT 
            CAST(NULL AS NVARCHAR(100)) AS MetricName,
            CAST(NULL AS DECIMAL(18,4)) AS CurrentValue,
            CAST(NULL AS DECIMAL(18,4)) AS BaselineAvg,
            CAST(NULL AS DECIMAL(18,4)) AS BaselineStdDev,
            CAST(NULL AS DECIMAL(8,2)) AS DeviationMultiplier,
            CAST(NULL AS NVARCHAR(20)) AS Severity,
            CAST(NULL AS NVARCHAR(10)) AS Direction,
            CAST(NULL AS NVARCHAR(500)) AS Message
        WHERE 1 = 0;
    END;

    -- ============================================================
    -- RESULT SET 5: RECOMMENDATIONS
    -- ============================================================
    DECLARE @Recommendations TABLE (
        Priority    INT,
        Category    NVARCHAR(50),
        Message     NVARCHAR(500),
        ActionItem  NVARCHAR(500)
    );

    -- P1: Critical disk
    IF @DiskMaxPct >= 95
        INSERT INTO @Recommendations VALUES (1, 'Disk', 
            'Disk usage at ' + CAST(CAST(@DiskMaxPct AS INT) AS NVARCHAR) + '%. Immediate action required.',
            'Free disk space, extend volume, or archive old data.');

    -- P1: Critical memory
    IF @PleMin <= 100
        INSERT INTO @Recommendations VALUES (1, 'Memory',
            'PLE dropped to ' + CAST(@PleMin AS NVARCHAR) + 's. Severe memory pressure.',
            'Identify memory-intensive queries. Consider adding RAM or optimizing workload.');

    -- P1: AG critical lag
    IF ISNULL(@AgMaxLag, 0) >= 120
        INSERT INTO @Recommendations VALUES (1, 'AG',
            'AG replication lag reached ' + CAST(@AgMaxLag AS NVARCHAR) + 's. Data loss risk.',
            'Check network, redo queue, and secondary replica health.');

    -- P2: Warning-level issues
    IF @CpuMax >= 80
        INSERT INTO @Recommendations VALUES (2, 'CPU',
            'CPU peaked at ' + CAST(@CpuMax AS NVARCHAR) + '%. Investigate top queries.',
            'Review top CPU consumers in TopQueriesHistory. Consider query tuning or index optimization.');

    IF @DiskMaxPct >= 85 AND @DiskMaxPct < 95
        INSERT INTO @Recommendations VALUES (2, 'Disk',
            'Disk usage at ' + CAST(CAST(@DiskMaxPct AS INT) AS NVARCHAR) + '%. Plan capacity expansion.',
            'Project growth rate and schedule disk expansion before reaching 95%.');

    IF @BlockingCount > 10
        INSERT INTO @Recommendations VALUES (2, 'Blocking',
            CAST(@BlockingCount AS NVARCHAR) + ' blocking events in 24h.',
            'Review blocking queries. Consider RCSI or query optimization.');

    IF @FailedJobs > 0
        INSERT INTO @Recommendations VALUES (2, 'Jobs',
            CAST(@FailedJobs AS NVARCHAR) + ' SQL Agent job(s) failed.',
            'Check job history for error details. Fix and re-run failed jobs.');

    -- P3: Informational
    IF @ErrorCount > 50
        INSERT INTO @Recommendations VALUES (3, 'ErrorLog',
            CAST(@ErrorCount AS NVARCHAR) + ' error entries in 24h. Elevated error rate.',
            'Review error log patterns. May indicate underlying issue.');

    -- Add baseline anomaly recommendations
    IF OBJECT_ID('monitor.BaselineAnomalies', 'U') IS NOT NULL
    BEGIN
        INSERT INTO @Recommendations (Priority, Category, Message, ActionItem)
        SELECT DISTINCT
            CASE Severity WHEN 'Critical' THEN 1 ELSE 2 END,
            'Baseline',
            MetricName + ' deviating ' + CAST(CAST(DeviationMultiplier AS DECIMAL(5,1)) AS NVARCHAR) 
                + 'σ from baseline (' + Severity + ')',
            'Investigate root cause. Current: ' + CAST(CAST(CurrentValue AS DECIMAL(10,2)) AS NVARCHAR)
                + ' vs Baseline: ' + CAST(CAST(BaselineAvg AS DECIMAL(10,2)) AS NVARCHAR)
        FROM [monitor].[BaselineAnomalies]
        WHERE DetectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
            AND Acknowledged = 0;
    END;

    SELECT Priority, Category, Message, ActionItem
    FROM @Recommendations
    ORDER BY Priority, Category;

    -- ============================================================
    -- TOP WAITS (bonus result set for PowerShell consumption)
    -- ============================================================
    SELECT TOP 10
        WaitType,
        SUM(WaitTimeMs) AS TotalWaitMs,
        SUM(ISNULL(DeltaWaitTimeMs, 0)) AS TotalDeltaMs,
        SUM(WaitingTasksCount) AS TotalWaitingTasks
    FROM [monitor].[WaitStatsHistory]
    WHERE CollectedAt >= @StartDate
    GROUP BY WaitType
    ORDER BY SUM(ISNULL(DeltaWaitTimeMs, WaitTimeMs)) DESC;

    -- ============================================================
    -- LOG REPORT GENERATION
    -- ============================================================
    IF @DebugMode = 0
    BEGIN
        INSERT INTO [monitor].[ReportHistory] (ReportType, Recipients, Language, Success)
        VALUES ('Daily', ISNULL(@OverrideRecipients, 'PowerShell'), @Language, 1);
    END;

    PRINT '✓ Daily report generated. Health Score: ' + CAST(@HealthScore AS NVARCHAR) + '/100 (' + @OverallStatus + ')';
END;
GO

PRINT '✓ Procedure [monitor].[usp_GenerateDailyReport] created.';
GO

    @OverrideLanguage CHAR(5) = NULL,
    @OverrideRecipients NVARCHAR(500) = NULL,
    @DebugMode BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ============================================================
    -- CONFIGURATION
    -- ============================================================
    DECLARE @Language CHAR(5) = ISNULL(@OverrideLanguage, 
        (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'General' AND SettingName = 'Language'));
    SET @Language = ISNULL(@Language, 'en');

    DECLARE @ServerName NVARCHAR(128) = ISNULL(
        (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'General' AND SettingName = 'ServerName'),
        @@SERVERNAME);

    -- Date range: last 24 hours
    DECLARE @StartDate DATETIME2 = DATEADD(HOUR, -24, SYSUTCDATETIME());
    DECLARE @EndDate DATETIME2 = SYSUTCDATETIME();
    DECLARE @DateStr NVARCHAR(20) = FORMAT(SYSUTCDATETIME(), 'yyyy-MM-dd');

    -- ============================================================
    -- RESULT SET 1: EXECUTIVE SUMMARY
    -- ============================================================
    DECLARE @CpuAvg INT, @CpuMax INT, @CpuStatus NVARCHAR(10);
    DECLARE @PleMin INT, @PleAvg INT, @MemStatus NVARCHAR(10);
    DECLARE @DiskMaxPct DECIMAL(5,2), @DiskStatus NVARCHAR(10);
    DECLARE @AgMaxLag INT, @AgStatus NVARCHAR(10);
    DECLARE @BlockingCount INT, @FailedJobs INT, @ErrorCount INT;
    DECLARE @OverallStatus NVARCHAR(10);
    DECLARE @HealthScore INT;

    -- CPU
    SELECT @CpuAvg = AVG(SqlCpuPct), @CpuMax = MAX(SqlCpuPct)
    FROM [monitor].[CpuHistory] WHERE CollectedAt >= @StartDate;
    SET @CpuStatus = CASE WHEN @CpuMax >= 95 THEN 'critical' WHEN @CpuMax >= 80 THEN 'warning' ELSE 'healthy' END;

    -- Memory (PLE)
    SELECT @PleMin = MIN(PageLifeExpectancy), @PleAvg = AVG(PageLifeExpectancy)
    FROM [monitor].[MemoryHistory] WHERE CollectedAt >= @StartDate;
    SET @MemStatus = CASE WHEN @PleMin <= 100 THEN 'critical' WHEN @PleMin <= 300 THEN 'warning' ELSE 'healthy' END;

    -- Disk
    SELECT @DiskMaxPct = MAX(UsedPct)
    FROM [monitor].[DiskHistory] WHERE CollectedAt >= @StartDate;
    SET @DiskStatus = CASE WHEN @DiskMaxPct >= 95 THEN 'critical' WHEN @DiskMaxPct >= 85 THEN 'warning' ELSE 'healthy' END;

    -- AG
    SELECT @AgMaxLag = MAX(SecondsBehindPrimary)
    FROM [monitor].[AgHealthHistory] WHERE CollectedAt >= @StartDate;
    SET @AgStatus = CASE WHEN @AgMaxLag >= 120 THEN 'critical' WHEN @AgMaxLag >= 30 THEN 'warning' ELSE 'healthy' END;

    -- Issues
    SELECT @BlockingCount = COUNT(*) FROM [monitor].[BlockingHistory] WHERE DetectedAt >= @StartDate;
    SELECT @FailedJobs = COUNT(DISTINCT JobName) FROM [monitor].[JobHistory] 
        WHERE CollectedAt >= @StartDate AND LastRunStatus = 'Failed';
    SELECT @ErrorCount = COUNT(*) FROM [monitor].[ErrorLogHistory] 
        WHERE CollectedAt >= @StartDate AND Severity IN ('Critical', 'Error');

    -- Overall status
    SET @OverallStatus = CASE 
        WHEN @CpuStatus = 'critical' OR @MemStatus = 'critical' OR @DiskStatus = 'critical' OR @AgStatus = 'critical' THEN 'critical'
        WHEN @CpuStatus = 'warning' OR @MemStatus = 'warning' OR @DiskStatus = 'warning' OR @AgStatus = 'warning' THEN 'warning'
        ELSE 'healthy' END;

    -- Health Score (0-100, higher is better)
    SET @HealthScore = 100
        - CASE @CpuStatus WHEN 'critical' THEN 25 WHEN 'warning' THEN 10 ELSE 0 END
        - CASE @MemStatus WHEN 'critical' THEN 25 WHEN 'warning' THEN 10 ELSE 0 END
        - CASE @DiskStatus WHEN 'critical' THEN 20 WHEN 'warning' THEN 8 ELSE 0 END
        - CASE @AgStatus WHEN 'critical' THEN 20 WHEN 'warning' THEN 8 ELSE 0 END
        - CASE WHEN @BlockingCount > 50 THEN 10 WHEN @BlockingCount > 10 THEN 5 ELSE 0 END
        - CASE WHEN @FailedJobs > 5 THEN 10 WHEN @FailedJobs > 0 THEN 3 ELSE 0 END;
    IF @HealthScore < 0 SET @HealthScore = 0;

    -- Output Result Set 1: Executive Summary
    SELECT 
        @ServerName AS ServerName,
        @DateStr AS ReportDate,
        @OverallStatus AS OverallStatus,
        @HealthScore AS HealthScore,
        @CpuAvg AS CpuAvg,
        @CpuMax AS CpuMax,
        @CpuStatus AS CpuStatus,
        @PleAvg AS PleAvg,
        @PleMin AS PleMin,
        @MemStatus AS MemoryStatus,
        @DiskMaxPct AS DiskMaxUsedPct,
        @DiskStatus AS DiskStatus,
        ISNULL(@AgMaxLag, 0) AS AgMaxLagSeconds,
        @AgStatus AS AgStatus,
        @BlockingCount AS BlockingEvents24h,
        @FailedJobs AS FailedJobs24h,
        @ErrorCount AS ErrorLogEntries24h;

    -- ============================================================
    -- RESULT SET 2: HEALTH SCORE BREAKDOWN (Traffic Light)
    -- ============================================================
    SELECT MetricName, MetricValue, Status, Details
    FROM (
        VALUES
            ('CPU',      CAST(ISNULL(@CpuAvg, 0) AS NVARCHAR) + '% avg / ' + CAST(ISNULL(@CpuMax, 0) AS NVARCHAR) + '% max', @CpuStatus, 
                CASE @CpuStatus WHEN 'critical' THEN 'CPU sustained above 95%' WHEN 'warning' THEN 'CPU peaked above 80%' ELSE 'Normal' END),
            ('Memory',   CAST(ISNULL(@PleAvg, 0) AS NVARCHAR) + 's avg / ' + CAST(ISNULL(@PleMin, 0) AS NVARCHAR) + 's min PLE', @MemStatus,
                CASE @MemStatus WHEN 'critical' THEN 'PLE dropped below 100s - severe memory pressure' WHEN 'warning' THEN 'PLE below 300s - memory pressure detected' ELSE 'Normal' END),
            ('Disk',     CAST(ISNULL(CAST(@DiskMaxPct AS INT), 0) AS NVARCHAR) + '% max used', @DiskStatus,
                CASE @DiskStatus WHEN 'critical' THEN 'Disk above 95% - immediate action needed' WHEN 'warning' THEN 'Disk above 85% - monitor closely' ELSE 'Normal' END),
            ('AG Sync',  CAST(ISNULL(@AgMaxLag, 0) AS NVARCHAR) + 's max lag', @AgStatus,
                CASE @AgStatus WHEN 'critical' THEN 'AG lag > 120s - potential data loss risk' WHEN 'warning' THEN 'AG lag > 30s - investigate' ELSE 'Normal' END),
            ('Blocking', CAST(@BlockingCount AS NVARCHAR) + ' events', 
                CASE WHEN @BlockingCount > 50 THEN 'critical' WHEN @BlockingCount > 10 THEN 'warning' ELSE 'healthy' END,
                CASE WHEN @BlockingCount > 50 THEN 'Excessive blocking detected' WHEN @BlockingCount > 10 THEN 'Elevated blocking' ELSE 'Normal' END),
            ('Jobs',     CAST(@FailedJobs AS NVARCHAR) + ' failed',
                CASE WHEN @FailedJobs > 5 THEN 'critical' WHEN @FailedJobs > 0 THEN 'warning' ELSE 'healthy' END,
                CASE WHEN @FailedJobs > 0 THEN CAST(@FailedJobs AS NVARCHAR) + ' job(s) failed in last 24h' ELSE 'All jobs healthy' END)
    ) AS v(MetricName, MetricValue, Status, Details);

    -- ============================================================
    -- RESULT SET 3: TOP ISSUES
    -- ============================================================
    
    -- Top blocking events
    SELECT TOP 10
        'Blocking' AS IssueType,
        DetectedAt,
        DatabaseName,
        BlockingSpid,
        BlockedSpid,
        BlockingDurationSec,
        LEFT(ISNULL(BlockingQuery, ''), 200) AS BlockingQuery,
        LEFT(ISNULL(BlockedQuery, ''), 200) AS BlockedQuery
    FROM [monitor].[BlockingHistory]
    WHERE DetectedAt >= @StartDate
    ORDER BY BlockingDurationSec DESC;

    -- Failed jobs detail
    SELECT TOP 10
        'FailedJob' AS IssueType,
        CollectedAt,
        JobName,
        LastRunDate,
        LastRunStatus,
        LastRunDuration
    FROM [monitor].[JobHistory]
    WHERE CollectedAt >= @StartDate AND LastRunStatus = 'Failed'
    ORDER BY LastRunDate DESC;

    -- Critical/Error log entries
    SELECT TOP 20
        'ErrorLog' AS IssueType,
        LogDate,
        Severity,
        ProcessInfo,
        LEFT(ErrorMessage, 300) AS ErrorMessage
    FROM [monitor].[ErrorLogHistory]
    WHERE CollectedAt >= @StartDate AND Severity IN ('Critical', 'Error')
    ORDER BY LogDate DESC;

    -- ============================================================
    -- RESULT SET 4: ANOMALIES VS BASELINE
    -- ============================================================
    IF OBJECT_ID('monitor.BaselineCapture', 'U') IS NOT NULL
        AND EXISTS (SELECT 1 FROM [monitor].[BaselineCapture] WHERE IsActive = 1)
    BEGIN
        -- Run anomaly detection for last 60 minutes and return results
        SELECT 
            ba.MetricName,
            ba.CurrentValue,
            ba.BaselineAvg,
            ba.BaselineStdDev,
            ba.DeviationMultiplier,
            ba.Severity,
            ba.Direction,
            ba.Message
        FROM [monitor].[BaselineAnomalies] ba
        WHERE ba.DetectedAt >= @StartDate
        ORDER BY 
            CASE ba.Severity WHEN 'Critical' THEN 1 WHEN 'Warning' THEN 2 ELSE 3 END,
            ba.DeviationMultiplier DESC;
    END
    ELSE
    BEGIN
        -- Return empty result set with schema
        SELECT 
            CAST(NULL AS NVARCHAR(100)) AS MetricName,
            CAST(NULL AS DECIMAL(18,4)) AS CurrentValue,
            CAST(NULL AS DECIMAL(18,4)) AS BaselineAvg,
            CAST(NULL AS DECIMAL(18,4)) AS BaselineStdDev,
            CAST(NULL AS DECIMAL(8,2)) AS DeviationMultiplier,
            CAST(NULL AS NVARCHAR(20)) AS Severity,
            CAST(NULL AS NVARCHAR(10)) AS Direction,
            CAST(NULL AS NVARCHAR(500)) AS Message
        WHERE 1 = 0;
    END;

    -- ============================================================
    -- RESULT SET 5: RECOMMENDATIONS
    -- ============================================================
    DECLARE @Recommendations TABLE (
        Priority    INT,
        Category    NVARCHAR(50),
        Message     NVARCHAR(500),
        ActionItem  NVARCHAR(500)
    );

    -- P1: Critical disk
    IF @DiskMaxPct >= 95
        INSERT INTO @Recommendations VALUES (1, 'Disk', 
            'Disk usage at ' + CAST(CAST(@DiskMaxPct AS INT) AS NVARCHAR) + '%. Immediate action required.',
            'Free disk space, extend volume, or archive old data.');

    -- P1: Critical memory
    IF @PleMin <= 100
        INSERT INTO @Recommendations VALUES (1, 'Memory',
            'PLE dropped to ' + CAST(@PleMin AS NVARCHAR) + 's. Severe memory pressure.',
            'Identify memory-intensive queries. Consider adding RAM or optimizing workload.');

    -- P1: AG critical lag
    IF ISNULL(@AgMaxLag, 0) >= 120
        INSERT INTO @Recommendations VALUES (1, 'AG',
            'AG replication lag reached ' + CAST(@AgMaxLag AS NVARCHAR) + 's. Data loss risk.',
            'Check network, redo queue, and secondary replica health.');

    -- P2: Warning-level issues
    IF @CpuMax >= 80
        INSERT INTO @Recommendations VALUES (2, 'CPU',
            'CPU peaked at ' + CAST(@CpuMax AS NVARCHAR) + '%. Investigate top queries.',
            'Review top CPU consumers in TopQueriesHistory. Consider query tuning or index optimization.');

    IF @DiskMaxPct >= 85 AND @DiskMaxPct < 95
        INSERT INTO @Recommendations VALUES (2, 'Disk',
            'Disk usage at ' + CAST(CAST(@DiskMaxPct AS INT) AS NVARCHAR) + '%. Plan capacity expansion.',
            'Project growth rate and schedule disk expansion before reaching 95%.');

    IF @BlockingCount > 10
        INSERT INTO @Recommendations VALUES (2, 'Blocking',
            CAST(@BlockingCount AS NVARCHAR) + ' blocking events in 24h.',
            'Review blocking queries. Consider RCSI or query optimization.');

    IF @FailedJobs > 0
        INSERT INTO @Recommendations VALUES (2, 'Jobs',
            CAST(@FailedJobs AS NVARCHAR) + ' SQL Agent job(s) failed.',
            'Check job history for error details. Fix and re-run failed jobs.');

    -- P3: Informational
    IF @ErrorCount > 50
        INSERT INTO @Recommendations VALUES (3, 'ErrorLog',
            CAST(@ErrorCount AS NVARCHAR) + ' error entries in 24h. Elevated error rate.',
            'Review error log patterns. May indicate underlying issue.');

    -- Add baseline anomaly recommendations
    IF OBJECT_ID('monitor.BaselineAnomalies', 'U') IS NOT NULL
    BEGIN
        INSERT INTO @Recommendations (Priority, Category, Message, ActionItem)
        SELECT DISTINCT
            CASE Severity WHEN 'Critical' THEN 1 ELSE 2 END,
            'Baseline',
            MetricName + ' deviating ' + CAST(CAST(DeviationMultiplier AS DECIMAL(5,1)) AS NVARCHAR) 
                + 'σ from baseline (' + Severity + ')',
            'Investigate root cause. Current: ' + CAST(CAST(CurrentValue AS DECIMAL(10,2)) AS NVARCHAR)
                + ' vs Baseline: ' + CAST(CAST(BaselineAvg AS DECIMAL(10,2)) AS NVARCHAR)
        FROM [monitor].[BaselineAnomalies]
        WHERE DetectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
            AND Acknowledged = 0;
    END;

    SELECT Priority, Category, Message, ActionItem
    FROM @Recommendations
    ORDER BY Priority, Category;

    -- ============================================================
    -- TOP WAITS (bonus result set for PowerShell consumption)
    -- ============================================================
    SELECT TOP 10
        WaitType,
        SUM(WaitTimeMs) AS TotalWaitMs,
        SUM(ISNULL(DeltaWaitTimeMs, 0)) AS TotalDeltaMs,
        SUM(WaitingTasksCount) AS TotalWaitingTasks
    FROM [monitor].[WaitStatsHistory]
    WHERE CollectedAt >= @StartDate
    GROUP BY WaitType
    ORDER BY SUM(ISNULL(DeltaWaitTimeMs, WaitTimeMs)) DESC;

    -- ============================================================
    -- LOG REPORT GENERATION
    -- ============================================================
    IF @DebugMode = 0
    BEGIN
        INSERT INTO [monitor].[ReportHistory] (ReportType, Recipients, Language, Success)
        VALUES ('Daily', ISNULL(@OverrideRecipients, 'PowerShell'), @Language, 1);
    END;

    PRINT '✓ Daily report generated. Health Score: ' + CAST(@HealthScore AS NVARCHAR) + '/100 (' + @OverallStatus + ')';
END;
GO

PRINT '✓ Procedure [monitor].[usp_GenerateDailyReport] created.';
GO
