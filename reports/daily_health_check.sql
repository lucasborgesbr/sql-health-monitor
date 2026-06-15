/*
    SQL Health Monitor - Daily Health Report
    Collects last 24h metrics, populates temp tables, calls usp_BuildDailyHtml, sends via Database Mail.

    Parameters:
        @OverrideLanguage    CHAR(5)        - Override language (default: from Settings)
        @OverrideRecipients  NVARCHAR(1000) - Override email recipients (semicolon-separated)
        @DebugMode           BIT            - 1 = SELECT HTML body instead of sending email

    Example usage:
        EXEC [monitor].[usp_GenerateDailyReport];
        EXEC [monitor].[usp_GenerateDailyReport] @DebugMode = 1;
        EXEC [monitor].[usp_GenerateDailyReport] @OverrideRecipients = 'dba@company.com';

    Depends on: usp_BuildDailyHtml (html_builder_daily.sql)

    Schema: [monitor]
    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

IF OBJECT_ID('[monitor].[usp_GenerateDailyReport]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_GenerateDailyReport] @OverrideLanguage CHAR(5) = NULL, @OverrideRecipients NVARCHAR(1000) = NULL, @DebugMode BIT = 0 AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_GenerateDailyReport]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_GenerateDailyReport] @OverrideLanguage CHAR(5) = NULL, @OverrideRecipients NVARCHAR(1000) = NULL, @DebugMode BIT = 0 AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

ALTER PROCEDURE [monitor].[usp_GenerateDailyReport]
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
        (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'Email' AND SettingName = 'Recipients_Daily'));
    IF @Recipients IS NULL OR @Recipients = ''
        SELECT @Recipients = SettingValue FROM [monitor].[Settings] WHERE Category = 'Email' AND SettingName = 'Recipients';

    DECLARE @StartDate DATETIME2 = DATEADD(HOUR, -24, SYSUTCDATETIME());
    DECLARE @DateStr   NVARCHAR(50) = FORMAT(SYSUTCDATETIME(), 'yyyy-MM-dd HH:mm') + ' UTC';

    -- ============================================================
    -- SCALAR METRICS
    -- ============================================================
    DECLARE @CpuAvg     INT, @CpuMax    INT, @CpuStatus  NVARCHAR(10);
    DECLARE @PleMin     INT, @PleAvg    INT, @MemStatus  NVARCHAR(10);
    DECLARE @DiskMaxPct DECIMAL(5,2),        @DiskStatus NVARCHAR(10);
    DECLARE @AgMaxLag   INT,                 @AgStatus   NVARCHAR(10);
    DECLARE @BlockingCount INT, @FailedJobs INT, @ErrorCount INT;
    DECLARE @OverallStatus NVARCHAR(10), @HealthScore INT;

    SELECT @CpuAvg = AVG(SqlCpuPct), @CpuMax = MAX(SqlCpuPct)
    FROM [monitor].[CpuHistory] WHERE CollectedAt >= @StartDate;
    SET @CpuStatus = CASE WHEN @CpuMax >= 95 THEN 'critical' WHEN @CpuMax >= 80 THEN 'warning' ELSE 'healthy' END;

    SELECT @PleMin = MIN(PageLifeExpectancy), @PleAvg = AVG(PageLifeExpectancy)
    FROM [monitor].[MemoryHistory] WHERE CollectedAt >= @StartDate;
    SET @MemStatus = CASE WHEN @PleMin <= 100 THEN 'critical' WHEN @PleMin <= 300 THEN 'warning' ELSE 'healthy' END;

    SELECT @DiskMaxPct = MAX(UsedPct)
    FROM [monitor].[DiskHistory] WHERE CollectedAt >= @StartDate;
    SET @DiskStatus = CASE WHEN @DiskMaxPct >= 95 THEN 'critical' WHEN @DiskMaxPct >= 85 THEN 'warning' ELSE 'healthy' END;

    SELECT @AgMaxLag = MAX(SecondsBehindPrimary)
    FROM [monitor].[AgHealthHistory] WHERE CollectedAt >= @StartDate;
    SET @AgStatus = CASE WHEN @AgMaxLag >= 120 THEN 'critical' WHEN @AgMaxLag >= 30 THEN 'warning' ELSE 'healthy' END;

    SELECT @BlockingCount = COUNT(*) FROM [monitor].[BlockingHistory]  WHERE DetectedAt  >= @StartDate;
    SELECT @FailedJobs    = COUNT(DISTINCT JobName) FROM [monitor].[JobHistory]
        WHERE CollectedAt >= @StartDate AND LastRunStatus = 'Failed';
    SELECT @ErrorCount    = COUNT(*) FROM [monitor].[ErrorLogHistory]
        WHERE CollectedAt >= @StartDate AND Severity IN ('Critical', 'Error');

    SET @OverallStatus = CASE
        WHEN @CpuStatus = 'critical' OR @MemStatus = 'critical' OR @DiskStatus = 'critical' OR @AgStatus = 'critical' THEN 'critical'
        WHEN @CpuStatus = 'warning'  OR @MemStatus = 'warning'  OR @DiskStatus = 'warning'  OR @AgStatus = 'warning'  THEN 'warning'
        ELSE 'healthy' END;

    SET @HealthScore = 100
        - CASE @CpuStatus  WHEN 'critical' THEN 25 WHEN 'warning' THEN 10 ELSE 0 END
        - CASE @MemStatus  WHEN 'critical' THEN 25 WHEN 'warning' THEN 10 ELSE 0 END
        - CASE @DiskStatus WHEN 'critical' THEN 20 WHEN 'warning' THEN  8 ELSE 0 END
        - CASE @AgStatus   WHEN 'critical' THEN 20 WHEN 'warning' THEN  8 ELSE 0 END
        - CASE WHEN @BlockingCount > 50 THEN 10 WHEN @BlockingCount > 10 THEN 5 ELSE 0 END
        - CASE WHEN @FailedJobs    >  5 THEN 10 WHEN @FailedJobs    >  0 THEN 3 ELSE 0 END;
    IF @HealthScore < 0 SET @HealthScore = 0;

    -- ============================================================
    -- TABULAR SECTIONS (read by usp_BuildDailyHtml)
    -- ============================================================
    CREATE TABLE #ReportRecommendations (
        Priority   INT,
        Category   NVARCHAR(50),
        Message    NVARCHAR(500),
        ActionItem NVARCHAR(500)
    );

    IF @DiskMaxPct >= 95
        INSERT #ReportRecommendations VALUES (1,'Disk',
            'Disk usage at ' + CAST(CAST(@DiskMaxPct AS INT) AS NVARCHAR) + '%. Immediate action required.',
            'Free disk space, extend volume, or archive old data.');
    IF @PleMin <= 100
        INSERT #ReportRecommendations VALUES (1,'Memory',
            'PLE dropped to ' + CAST(@PleMin AS NVARCHAR) + 's. Severe memory pressure.',
            'Identify memory-intensive queries. Consider adding RAM or optimizing workload.');
    IF ISNULL(@AgMaxLag,0) >= 120
        INSERT #ReportRecommendations VALUES (1,'AG',
            'AG replication lag reached ' + CAST(@AgMaxLag AS NVARCHAR) + 's. Data loss risk.',
            'Check network, redo queue, and secondary replica health.');
    IF @CpuMax >= 80
        INSERT #ReportRecommendations VALUES (2,'CPU',
            'CPU peaked at ' + CAST(@CpuMax AS NVARCHAR) + '%.',
            'Review top CPU consumers in TopQueriesHistory. Consider query tuning or index optimization.');
    IF @DiskMaxPct >= 85 AND @DiskMaxPct < 95
        INSERT #ReportRecommendations VALUES (2,'Disk',
            'Disk usage at ' + CAST(CAST(@DiskMaxPct AS INT) AS NVARCHAR) + '%. Plan capacity expansion.',
            'Project growth rate and schedule disk expansion before reaching 95%.');
    IF @BlockingCount > 10
        INSERT #ReportRecommendations VALUES (2,'Blocking',
            CAST(@BlockingCount AS NVARCHAR) + ' blocking events in 24h.',
            'Review blocking queries. Consider RCSI or query optimization.');
    IF @FailedJobs > 0
        INSERT #ReportRecommendations VALUES (2,'Jobs',
            CAST(@FailedJobs AS NVARCHAR) + ' SQL Agent job(s) failed.',
            'Check job history for error details. Fix and re-run failed jobs.');
    IF @ErrorCount > 50
        INSERT #ReportRecommendations VALUES (3,'ErrorLog',
            CAST(@ErrorCount AS NVARCHAR) + ' error entries in 24h.',
            'Review error log patterns. May indicate underlying issue.');
    IF OBJECT_ID('monitor.BaselineAnomalies','U') IS NOT NULL
        INSERT #ReportRecommendations (Priority, Category, Message, ActionItem)
        SELECT DISTINCT
            CASE Severity WHEN 'Critical' THEN 1 ELSE 2 END,
            'Baseline',
            MetricName + ' deviating ' + CAST(CAST(DeviationMultiplier AS DECIMAL(5,1)) AS NVARCHAR) + N'σ from baseline (' + Severity + ')',
            'Current: ' + CAST(CAST(CurrentValue AS DECIMAL(10,2)) AS NVARCHAR)
                + ' vs Baseline: ' + CAST(CAST(BaselineAvg AS DECIMAL(10,2)) AS NVARCHAR)
        FROM [monitor].[BaselineAnomalies]
        WHERE DetectedAt >= DATEADD(HOUR,-1,SYSUTCDATETIME()) AND Acknowledged = 0;

    CREATE TABLE #ReportTopWaits (
        WaitType          NVARCHAR(100),
        TotalWaitMs       BIGINT,
        TotalDeltaMs      BIGINT,
        TotalWaitingTasks BIGINT
    );
    INSERT #ReportTopWaits
    SELECT TOP 10
        WaitType,
        SUM(WaitTimeMs),
        SUM(ISNULL(DeltaWaitTimeMs,0)),
        SUM(WaitingTasksCount)
    FROM [monitor].[WaitStatsHistory]
    WHERE CollectedAt >= @StartDate
    GROUP BY WaitType
    ORDER BY SUM(ISNULL(DeltaWaitTimeMs,WaitTimeMs)) DESC;

    CREATE TABLE #ReportAnomalies (
        MetricName          NVARCHAR(100),
        CurrentValue        DECIMAL(18,4),
        BaselineAvg         DECIMAL(18,4),
        DeviationMultiplier DECIMAL(8,2),
        Severity            NVARCHAR(20)
    );
    IF OBJECT_ID('monitor.BaselineAnomalies','U') IS NOT NULL
        INSERT #ReportAnomalies
        SELECT MetricName, CurrentValue, BaselineAvg, DeviationMultiplier, Severity
        FROM [monitor].[BaselineAnomalies]
        WHERE DetectedAt >= @StartDate
        ORDER BY CASE Severity WHEN 'Critical' THEN 1 ELSE 2 END, DeviationMultiplier DESC;

    -- ============================================================
    -- BUILD HTML
    -- ============================================================
    DECLARE @HtmlBody VARCHAR(MAX);

    EXEC [monitor].[usp_BuildDailyHtml]
        @ServerName    = @ServerName,
        @DateStr       = @DateStr,
        @HealthScore   = @HealthScore,
        @OverallStatus = @OverallStatus,
        @CpuAvg        = @CpuAvg,
        @CpuMax        = @CpuMax,
        @CpuStatus     = @CpuStatus,
        @PleAvg        = @PleAvg,
        @PleMin        = @PleMin,
        @MemStatus     = @MemStatus,
        @DiskMaxPct    = @DiskMaxPct,
        @DiskStatus    = @DiskStatus,
        @AgMaxLag      = @AgMaxLag,
        @AgStatus      = @AgStatus,
        @BlockingCount = @BlockingCount,
        @FailedJobs    = @FailedJobs,
        @ErrorCount    = @ErrorCount,
        @HtmlBody      = @HtmlBody OUTPUT;

    -- ============================================================
    -- SEND OR DEBUG
    -- ============================================================
    IF @DebugMode = 1
    BEGIN
        SELECT @HealthScore AS HealthScore, @OverallStatus AS OverallStatus, @HtmlBody AS HtmlBody;
        RETURN;
    END;

    IF @MailProfile IS NULL OR @MailProfile = ''
        RAISERROR('Email.ProfileName is not configured in monitor.Settings.', 16, 1);

    IF @Recipients IS NULL OR @Recipients = ''
        RAISERROR('No email recipients configured. Set Email.Recipients_Daily or Email.Recipients in monitor.Settings.', 16, 1);

    DECLARE @Subject NVARCHAR(255) =
        '[' + UPPER(@OverallStatus) + '] SQL Health ' + CAST(@HealthScore AS VARCHAR) + '/100'
        + ' - ' + @ServerName + ' - Daily Report';

    EXEC msdb.dbo.sp_send_dbmail
        @profile_name = @MailProfile,
        @recipients   = @Recipients,
        @subject      = @Subject,
        @body         = @HtmlBody,
        @body_format  = 'HTML';

    INSERT INTO [monitor].[ReportHistory] (ReportType, Recipients, Language, Success)
    VALUES ('Daily', @Recipients, @Language, 1);

    PRINT '+ Daily report sent. Score: ' + CAST(@HealthScore AS VARCHAR) + '/100 (' + @OverallStatus + ')';
END;
GO

PRINT '+ Procedure [monitor].[usp_GenerateDailyReport] created.';
GO
