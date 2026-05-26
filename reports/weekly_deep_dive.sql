/*
    SQL Health Monitor - Weekly Deep Dive Report Generator
    Aggregates 7 days of collector data into structured result sets.
    
    Includes:
        - Week-over-week comparison for key metrics
        - Capacity planning: growth projections (disk, database size, log usage)
        - Top N degraded queries (this week vs last week)
        - "What Changed This Week" (growth spikes, new errors, config drift)
        - Anomalies vs Baseline summary
        - Prioritized recommendations
    
    Output structured for PowerShell Send-HealthReport consumption.
    
    Schema: [monitor]
    Compatibility: SQL Server 2016+
    Author: Lucas Allan Borges
    
    Parameters:
        @OverrideLanguage    CHAR(5)       - Override language (default: from Settings)
        @OverrideRecipients  NVARCHAR(500) - Override email recipients
        @DebugMode           BIT           - 1 = SELECT results instead of sending email
    
    Example Usage:
        -- Generate and send weekly report
        EXEC [monitor].[usp_GenerateWeeklyReport];
        
        -- Debug mode
        EXEC [monitor].[usp_GenerateWeeklyReport] @DebugMode = 1;
        
        -- Portuguese output
        EXEC [monitor].[usp_GenerateWeeklyReport] @OverrideLanguage = 'ptbr', @DebugMode = 1;
*/

USE [DBA_Monitor];
GO

CREATE OR ALTER PROCEDURE [monitor].[usp_GenerateWeeklyReport]
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

    -- Date ranges
    DECLARE @ThisWeekStart DATETIME2 = DATEADD(DAY, -7, SYSUTCDATETIME());
    DECLARE @LastWeekStart DATETIME2 = DATEADD(DAY, -14, SYSUTCDATETIME());
    DECLARE @LastWeekEnd DATETIME2 = DATEADD(DAY, -7, SYSUTCDATETIME());
    DECLARE @Now DATETIME2 = SYSUTCDATETIME();
    DECLARE @WeekStr NVARCHAR(50) = FORMAT(@ThisWeekStart, 'MMM dd') + ' - ' + FORMAT(@Now, 'MMM dd, yyyy');

    -- ============================================================
    -- RESULT SET 1: WEEK-OVER-WEEK COMPARISON
    -- ============================================================
    DECLARE @CpuAvgThis INT, @CpuMaxThis INT, @CpuAvgLast INT, @CpuMaxLast INT;
    DECLARE @PleAvgThis INT, @PleMinThis INT, @PleAvgLast INT, @PleMinLast INT;
    DECLARE @BlockingThis INT, @BlockingLast INT;
    DECLARE @AlertsThis INT, @AlertsLast INT;
    DECLARE @ErrorsThis INT, @ErrorsLast INT;
    DECLARE @FailedJobsThis INT, @FailedJobsLast INT;

    SELECT @CpuAvgThis = AVG(SqlCpuPct), @CpuMaxThis = MAX(SqlCpuPct)
    FROM [monitor].[CpuHistory] WHERE CollectedAt >= @ThisWeekStart;
    SELECT @CpuAvgLast = AVG(SqlCpuPct), @CpuMaxLast = MAX(SqlCpuPct)
    FROM [monitor].[CpuHistory] WHERE CollectedAt >= @LastWeekStart AND CollectedAt < @LastWeekEnd;

    SELECT @PleAvgThis = AVG(PageLifeExpectancy), @PleMinThis = MIN(PageLifeExpectancy)
    FROM [monitor].[MemoryHistory] WHERE CollectedAt >= @ThisWeekStart;
    SELECT @PleAvgLast = AVG(PageLifeExpectancy), @PleMinLast = MIN(PageLifeExpectancy)
    FROM [monitor].[MemoryHistory] WHERE CollectedAt >= @LastWeekStart AND CollectedAt < @LastWeekEnd;

    SELECT @BlockingThis = COUNT(*) FROM [monitor].[BlockingHistory] WHERE DetectedAt >= @ThisWeekStart;
    SELECT @BlockingLast = COUNT(*) FROM [monitor].[BlockingHistory] WHERE DetectedAt >= @LastWeekStart AND DetectedAt < @LastWeekEnd;

    SELECT @AlertsThis = COUNT(*) FROM [monitor].[AlertHistory] WHERE FiredAt >= @ThisWeekStart;
    SELECT @AlertsLast = COUNT(*) FROM [monitor].[AlertHistory] WHERE FiredAt >= @LastWeekStart AND FiredAt < @LastWeekEnd;

    SELECT @ErrorsThis = COUNT(*) FROM [monitor].[ErrorLogHistory] WHERE CollectedAt >= @ThisWeekStart AND Severity IN ('Critical', 'Error');
    SELECT @ErrorsLast = COUNT(*) FROM [monitor].[ErrorLogHistory] WHERE CollectedAt >= @LastWeekStart AND CollectedAt < @LastWeekEnd AND Severity IN ('Critical', 'Error');

    SELECT @FailedJobsThis = COUNT(DISTINCT JobName) FROM [monitor].[JobHistory] WHERE CollectedAt >= @ThisWeekStart AND LastRunStatus = 'Failed';
    SELECT @FailedJobsLast = COUNT(DISTINCT JobName) FROM [monitor].[JobHistory] WHERE CollectedAt >= @LastWeekStart AND CollectedAt < @LastWeekEnd AND LastRunStatus = 'Failed';

    SELECT 
        @ServerName AS ServerName,
        @WeekStr AS ReportPeriod,
        MetricName, ThisWeek, LastWeek,
        CASE 
            WHEN LastWeek = 0 AND ThisWeek = 0 THEN 'stable'
            WHEN LastWeek = 0 THEN 'new'
            WHEN ThisWeek > LastWeek THEN 'up'
            WHEN ThisWeek < LastWeek THEN 'down'
            ELSE 'stable'
        END AS Trend,
        CASE 
            WHEN LastWeek = 0 THEN NULL
            ELSE CAST(ROUND((CAST(ThisWeek - LastWeek AS DECIMAL(18,2)) / NULLIF(LastWeek, 0)) * 100, 1) AS DECIMAL(5,1))
        END AS ChangePct
    FROM (
        VALUES
            ('CPU Avg %',       CAST(ISNULL(@CpuAvgThis, 0) AS DECIMAL(18,2)),  CAST(ISNULL(@CpuAvgLast, 0) AS DECIMAL(18,2))),
            ('CPU Max %',       CAST(ISNULL(@CpuMaxThis, 0) AS DECIMAL(18,2)),  CAST(ISNULL(@CpuMaxLast, 0) AS DECIMAL(18,2))),
            ('PLE Avg (s)',     CAST(ISNULL(@PleAvgThis, 0) AS DECIMAL(18,2)),  CAST(ISNULL(@PleAvgLast, 0) AS DECIMAL(18,2))),
            ('PLE Min (s)',     CAST(ISNULL(@PleMinThis, 0) AS DECIMAL(18,2)),  CAST(ISNULL(@PleMinLast, 0) AS DECIMAL(18,2))),
            ('Blocking Events', CAST(ISNULL(@BlockingThis, 0) AS DECIMAL(18,2)), CAST(ISNULL(@BlockingLast, 0) AS DECIMAL(18,2))),
            ('Alerts Fired',    CAST(ISNULL(@AlertsThis, 0) AS DECIMAL(18,2)),  CAST(ISNULL(@AlertsLast, 0) AS DECIMAL(18,2))),
            ('Error Log Entries', CAST(ISNULL(@ErrorsThis, 0) AS DECIMAL(18,2)), CAST(ISNULL(@ErrorsLast, 0) AS DECIMAL(18,2))),
            ('Failed Jobs',     CAST(ISNULL(@FailedJobsThis, 0) AS DECIMAL(18,2)), CAST(ISNULL(@FailedJobsLast, 0) AS DECIMAL(18,2)))
    ) AS v(MetricName, ThisWeek, LastWeek);

    -- ============================================================
    -- RESULT SET 2: CAPACITY PLANNING (Disk Growth Projections)
    -- ============================================================
    SELECT 
        curr.DriveLetter,
        CAST(curr.TotalSpaceMB / 1024.0 AS DECIMAL(10,1)) AS TotalGB,
        CAST((curr.TotalSpaceMB - curr.FreeSpaceMB) / 1024.0 AS DECIMAL(10,1)) AS UsedGB,
        CAST(curr.FreeSpaceMB / 1024.0 AS DECIMAL(10,1)) AS FreeGB,
        CAST(curr.UsedPct AS DECIMAL(5,1)) AS UsedPct,
        CAST(ISNULL(growth.WeeklyGrowthMB, 0) / 1024.0 AS DECIMAL(10,2)) AS WeeklyGrowthGB,
        CAST(ISNULL(growth.WeeklyGrowthMB, 0) / 1024.0 * 4 AS DECIMAL(10,2)) AS ProjectedMonthlyGrowthGB,
        CASE 
            WHEN ISNULL(growth.DailyGrowthMB, 0) <= 0 THEN 9999
            ELSE CAST((curr.FreeSpaceMB - (curr.TotalSpaceMB * 0.05)) / NULLIF(growth.DailyGrowthMB, 0) AS INT)
        END AS DaysUntil95Pct,
        CASE 
            WHEN ISNULL(growth.DailyGrowthMB, 0) <= 0 THEN 'No growth'
            WHEN (curr.FreeSpaceMB - (curr.TotalSpaceMB * 0.05)) / NULLIF(growth.DailyGrowthMB, 0) <= 30 THEN 'CRITICAL'
            WHEN (curr.FreeSpaceMB - (curr.TotalSpaceMB * 0.05)) / NULLIF(growth.DailyGrowthMB, 0) <= 90 THEN 'WARNING'
            ELSE 'OK'
        END AS CapacityStatus
    FROM (
        -- Current disk state (latest collection)
        SELECT DriveLetter, AVG(TotalSpaceMB) AS TotalSpaceMB, AVG(FreeSpaceMB) AS FreeSpaceMB, AVG(UsedPct) AS UsedPct
        FROM [monitor].[DiskHistory]
        WHERE CollectedAt >= DATEADD(HOUR, -6, @Now)
        GROUP BY DriveLetter
    ) curr
    LEFT JOIN (
        -- Growth calculation: difference between this week start and now
        SELECT 
            n.DriveLetter,
            (n.UsedMB - ISNULL(o.UsedMB, n.UsedMB)) AS WeeklyGrowthMB,
            (n.UsedMB - ISNULL(o.UsedMB, n.UsedMB)) / 7.0 AS DailyGrowthMB
        FROM (
            SELECT DriveLetter, AVG(TotalSpaceMB - FreeSpaceMB) AS UsedMB
            FROM [monitor].[DiskHistory]
            WHERE CollectedAt >= DATEADD(HOUR, -6, @Now)
            GROUP BY DriveLetter
        ) n
        LEFT JOIN (
            SELECT DriveLetter, AVG(TotalSpaceMB - FreeSpaceMB) AS UsedMB
            FROM [monitor].[DiskHistory]
            WHERE CollectedAt >= @ThisWeekStart AND CollectedAt < DATEADD(HOUR, 6, @ThisWeekStart)
            GROUP BY DriveLetter
        ) o ON n.DriveLetter = o.DriveLetter
    ) growth ON curr.DriveLetter = growth.DriveLetter
    ORDER BY curr.UsedPct DESC;

    -- Database file growth projections
    SELECT 
        fg.DatabaseName,
        fg.FileType,
        SUM(fg.CurrentSizeMB) AS CurrentSizeMB,
        SUM(fg.TotalGrowthMB) AS WeeklyGrowthMB,
        SUM(fg.TotalGrowthMB) * 4 AS ProjectedMonthlyGrowthMB,
        CASE 
            WHEN SUM(fg.TotalGrowthMB) > 1024 THEN 'HIGH'
            WHEN SUM(fg.TotalGrowthMB) > 256 THEN 'MODERATE'
            ELSE 'LOW'
        END AS GrowthRate
    FROM (
        SELECT 
            DatabaseName, FileType,
            MAX(SizeMB) AS CurrentSizeMB,
            SUM(ISNULL(GrowthMB, 0)) AS TotalGrowthMB
        FROM [monitor].[FileGrowthHistory]
        WHERE CollectedAt >= @ThisWeekStart
        GROUP BY DatabaseName, FileName, FileType
    ) fg
    GROUP BY fg.DatabaseName, fg.FileType
    HAVING SUM(fg.TotalGrowthMB) > 0
    ORDER BY SUM(fg.TotalGrowthMB) DESC;

    -- ============================================================
    -- RESULT SET 3: TOP DEGRADED QUERIES (This Week vs Last Week)
    -- ============================================================
    SELECT TOP 15
        tw.DatabaseName,
        tw.QueryHash,
        tw.TotalCpuMs AS CpuMs_ThisWeek,
        ISNULL(lw.TotalCpuMs, 0) AS CpuMs_LastWeek,
        CASE 
            WHEN ISNULL(lw.TotalCpuMs, 0) = 0 THEN NULL
            ELSE CAST(ROUND((CAST(tw.TotalCpuMs - ISNULL(lw.TotalCpuMs, 0) AS DECIMAL(18,2)) / NULLIF(lw.TotalCpuMs, 0)) * 100, 1) AS DECIMAL(10,1))
        END AS CpuChangePct,
        tw.TotalReads AS Reads_ThisWeek,
        ISNULL(lw.TotalReads, 0) AS Reads_LastWeek,
        tw.ExecutionCount AS Execs_ThisWeek,
        ISNULL(lw.ExecutionCount, 0) AS Execs_LastWeek,
        tw.AvgDurationMs AS AvgDurMs_ThisWeek,
        ISNULL(lw.AvgDurationMs, 0) AS AvgDurMs_LastWeek,
        LEFT(ISNULL(tw.QueryText, ''), 200) AS QueryText
    FROM (
        SELECT DatabaseName, QueryHash,
            SUM(TotalCpuMs) AS TotalCpuMs, SUM(TotalReads) AS TotalReads,
            SUM(ExecutionCount) AS ExecutionCount, AVG(AvgDurationMs) AS AvgDurationMs,
            MAX(QueryText) AS QueryText
        FROM [monitor].[TopQueriesHistory]
        WHERE CollectedAt >= @ThisWeekStart
        GROUP BY DatabaseName, QueryHash
    ) tw
    LEFT JOIN (
        SELECT DatabaseName, QueryHash,
            SUM(TotalCpuMs) AS TotalCpuMs, SUM(TotalReads) AS TotalReads,
            SUM(ExecutionCount) AS ExecutionCount, AVG(AvgDurationMs) AS AvgDurationMs
        FROM [monitor].[TopQueriesHistory]
        WHERE CollectedAt >= @LastWeekStart AND CollectedAt < @LastWeekEnd
        GROUP BY DatabaseName, QueryHash
    ) lw ON tw.DatabaseName = lw.DatabaseName AND tw.QueryHash = lw.QueryHash
    WHERE tw.TotalCpuMs > ISNULL(lw.TotalCpuMs, 0)  -- Only degraded queries
    ORDER BY (tw.TotalCpuMs - ISNULL(lw.TotalCpuMs, 0)) DESC;

    -- ============================================================
    -- RESULT SET 4: WHAT CHANGED THIS WEEK
    -- ============================================================
    DECLARE @Changes TABLE (
        ChangeType  NVARCHAR(50),
        ChangeDate  DATETIME2,
        Description NVARCHAR(500),
        Impact      NVARCHAR(20)  -- HIGH, MEDIUM, LOW
    );

    -- Disk growth spikes (any drive grew > 5GB in a day)
    INSERT INTO @Changes (ChangeType, ChangeDate, Description, Impact)
    SELECT 'Disk Growth Spike', CollectedAt, 
        DriveLetter + ': grew ' + CAST(CAST(GrowthMB / 1024.0 AS DECIMAL(10,1)) AS NVARCHAR) + ' GB in one collection',
        CASE WHEN GrowthMB > 10240 THEN 'HIGH' WHEN GrowthMB > 5120 THEN 'MEDIUM' ELSE 'LOW' END
    FROM (
        SELECT DriveLetter, CollectedAt,
            (TotalSpaceMB - FreeSpaceMB) - LAG(TotalSpaceMB - FreeSpaceMB) OVER (PARTITION BY DriveLetter ORDER BY CollectedAt) AS GrowthMB
        FROM [monitor].[DiskHistory]
        WHERE CollectedAt >= @ThisWeekStart
    ) d
    WHERE GrowthMB > 5120;  -- > 5GB spike

    -- Database file auto-growth events
    INSERT INTO @Changes (ChangeType, ChangeDate, Description, Impact)
    SELECT TOP 10 'File Auto-Growth', CollectedAt,
        DatabaseName + '.' + FileName + ' (' + FileType + '): grew ' + CAST(GrowthMB AS NVARCHAR) + ' MB',
        CASE WHEN GrowthMB > 1024 THEN 'HIGH' WHEN GrowthMB > 256 THEN 'MEDIUM' ELSE 'LOW' END
    FROM [monitor].[FileGrowthHistory]
    WHERE CollectedAt >= @ThisWeekStart AND ISNULL(GrowthMB, 0) > 100
    ORDER BY GrowthMB DESC;

    -- New error patterns (errors that didn't appear last week)
    INSERT INTO @Changes (ChangeType, ChangeDate, Description, Impact)
    SELECT TOP 5 'New Error Pattern', MIN(LogDate),
        LEFT(ErrorMessage, 200) + ' (appeared ' + CAST(COUNT(*) AS NVARCHAR) + ' times)',
        CASE WHEN COUNT(*) > 100 THEN 'HIGH' WHEN COUNT(*) > 10 THEN 'MEDIUM' ELSE 'LOW' END
    FROM [monitor].[ErrorLogHistory] e
    WHERE e.CollectedAt >= @ThisWeekStart
        AND e.Severity IN ('Critical', 'Error')
        AND NOT EXISTS (
            SELECT 1 FROM [monitor].[ErrorLogHistory] prev
            WHERE prev.CollectedAt >= @LastWeekStart AND prev.CollectedAt < @LastWeekEnd
                AND prev.ErrorMessage = e.ErrorMessage
        )
    GROUP BY LEFT(ErrorMessage, 200)
    HAVING COUNT(*) >= 3
    ORDER BY COUNT(*) DESC;

    -- AG state changes
    INSERT INTO @Changes (ChangeType, ChangeDate, Description, Impact)
    SELECT DISTINCT 'AG State Change', CollectedAt,
        AgName + '/' + ReplicaServer + ': ' + SyncState + ' (' + SyncHealth + ')',
        CASE WHEN SyncHealth <> 'HEALTHY' THEN 'HIGH' ELSE 'MEDIUM' END
    FROM [monitor].[AgHealthHistory]
    WHERE CollectedAt >= @ThisWeekStart
        AND (SyncHealth <> 'HEALTHY' OR SyncState = 'NOT SYNCHRONIZING');

    -- Jobs that started failing this week
    INSERT INTO @Changes (ChangeType, ChangeDate, Description, Impact)
    SELECT 'Job Started Failing', MAX(jt.LastRunDate),
        jt.JobName + ' failed ' + CAST(COUNT(*) AS NVARCHAR) + ' times this week (was OK last week)',
        CASE WHEN COUNT(*) > 5 THEN 'HIGH' ELSE 'MEDIUM' END
    FROM [monitor].[JobHistory] jt
    WHERE jt.CollectedAt >= @ThisWeekStart AND jt.LastRunStatus = 'Failed'
        AND NOT EXISTS (
            SELECT 1 FROM [monitor].[JobHistory] jl
            WHERE jl.CollectedAt >= @LastWeekStart AND jl.CollectedAt < @LastWeekEnd
                AND jl.JobName = jt.JobName AND jl.LastRunStatus = 'Failed'
        )
    GROUP BY jt.JobName;

    SELECT ChangeType, ChangeDate, Description, Impact
    FROM @Changes
    ORDER BY 
        CASE Impact WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END,
        ChangeDate DESC;

    -- ============================================================
    -- RESULT SET 5: BASELINE ANOMALIES (Weekly Summary)
    -- ============================================================
    IF OBJECT_ID('monitor.BaselineAnomalies', 'U') IS NOT NULL
    BEGIN
        SELECT 
            MetricName,
            COUNT(*) AS OccurrenceCount,
            MAX(DeviationMultiplier) AS MaxDeviation,
            AVG(DeviationMultiplier) AS AvgDeviation,
            MAX(Severity) AS WorstSeverity,
            MIN(DetectedAt) AS FirstDetected,
            MAX(DetectedAt) AS LastDetected,
            MAX(Message) AS LatestMessage
        FROM [monitor].[BaselineAnomalies]
        WHERE DetectedAt >= @ThisWeekStart
        GROUP BY MetricName
        ORDER BY MAX(CASE Severity WHEN 'Critical' THEN 1 ELSE 2 END), COUNT(*) DESC;
    END
    ELSE
    BEGIN
        SELECT 
            CAST(NULL AS NVARCHAR(100)) AS MetricName,
            CAST(NULL AS INT) AS OccurrenceCount,
            CAST(NULL AS DECIMAL(8,2)) AS MaxDeviation,
            CAST(NULL AS DECIMAL(8,2)) AS AvgDeviation,
            CAST(NULL AS NVARCHAR(20)) AS WorstSeverity,
            CAST(NULL AS DATETIME2) AS FirstDetected,
            CAST(NULL AS DATETIME2) AS LastDetected,
            CAST(NULL AS NVARCHAR(500)) AS LatestMessage
        WHERE 1 = 0;
    END;

    -- ============================================================
    -- RESULT SET 6: RECOMMENDATIONS
    -- ============================================================
    DECLARE @Recommendations TABLE (
        Priority    INT,
        Category    NVARCHAR(50),
        Message     NVARCHAR(500),
        ActionItem  NVARCHAR(500)
    );

    -- Capacity critical
    IF EXISTS (
        SELECT 1 FROM [monitor].[DiskHistory] 
        WHERE CollectedAt >= DATEADD(HOUR, -6, @Now) AND UsedPct >= 90
    )
        INSERT INTO @Recommendations VALUES (1, 'Capacity',
            'One or more drives above 90% usage.',
            'Immediate capacity expansion or data archival required.');

    -- CPU trending up significantly
    IF @CpuAvgThis > ISNULL(@CpuAvgLast, 0) * 1.2 AND @CpuAvgThis > 50
        INSERT INTO @Recommendations VALUES (2, 'Performance',
            'CPU avg increased ' + CAST(CASE WHEN @CpuAvgLast > 0 
                THEN CAST(ROUND((@CpuAvgThis - @CpuAvgLast) * 100.0 / @CpuAvgLast, 0) AS INT) ELSE 0 END AS NVARCHAR) + '% week-over-week.',
            'Review top queries. Consider index optimization or workload redistribution.');

    -- PLE degradation
    IF @PleAvgThis < ISNULL(@PleAvgLast, 9999) * 0.7 AND @PleAvgThis < 1000
        INSERT INTO @Recommendations VALUES (2, 'Memory',
            'PLE dropped significantly vs last week (avg ' + CAST(ISNULL(@PleAvgThis, 0) AS NVARCHAR) + 's vs ' + CAST(ISNULL(@PleAvgLast, 0) AS NVARCHAR) + 's).',
            'Investigate memory-intensive queries. Consider memory increase.');

    -- Blocking doubled
    IF @BlockingThis > ISNULL(@BlockingLast, 0) * 2 AND @BlockingThis > 10
        INSERT INTO @Recommendations VALUES (2, 'Concurrency',
            'Blocking events doubled (' + CAST(@BlockingThis AS NVARCHAR) + ' vs ' + CAST(@BlockingLast AS NVARCHAR) + ').',
            'Review blocking chains. Consider RCSI, query tuning, or lock escalation settings.');

    -- Index maintenance needed
    DECLARE @FragIndexCount INT;
    SELECT @FragIndexCount = COUNT(DISTINCT IndexName) 
    FROM [monitor].[IndexHealthHistory]
    WHERE CollectedAt >= @ThisWeekStart AND FragmentationPct >= 30 AND PageCount >= 1000;
    
    IF @FragIndexCount > 0
        INSERT INTO @Recommendations VALUES (2, 'Maintenance',
            CAST(@FragIndexCount AS NVARCHAR) + ' indexes with >30% fragmentation.',
            'Schedule index rebuild during maintenance window.');

    -- Error rate increase
    IF @ErrorsThis > ISNULL(@ErrorsLast, 0) * 2 AND @ErrorsThis > 20
        INSERT INTO @Recommendations VALUES (2, 'Reliability',
            'Error log entries increased significantly (' + CAST(@ErrorsThis AS NVARCHAR) + ' vs ' + CAST(@ErrorsLast AS NVARCHAR) + ').',
            'Review new error patterns in "What Changed" section.');

    -- Backup gaps
    IF EXISTS (SELECT 1 FROM [monitor].[BackupHistory] WHERE CollectedAt >= DATEADD(HOUR, -6, @Now) AND BackupType = 'D' AND HoursSinceLastBackup > 48)
        INSERT INTO @Recommendations VALUES (1, 'DR',
            'Databases with full backup older than 48 hours detected.',
            'Verify backup jobs. Check for disk space issues on backup target.');

    -- Baseline anomalies summary
    DECLARE @AnomalyCount INT = 0;
    IF OBJECT_ID('monitor.BaselineAnomalies', 'U') IS NOT NULL
        SELECT @AnomalyCount = COUNT(DISTINCT MetricName) FROM [monitor].[BaselineAnomalies] WHERE DetectedAt >= @ThisWeekStart;
    
    IF @AnomalyCount > 0
        INSERT INTO @Recommendations VALUES (2, 'Baseline',
            CAST(@AnomalyCount AS NVARCHAR) + ' metric(s) deviated from baseline this week.',
            'Review baseline anomalies section. Consider recapturing baselines if workload changed intentionally.');

    SELECT Priority, Category, Message, ActionItem
    FROM @Recommendations
    ORDER BY Priority, Category;

    -- ============================================================
    -- RESULT SET 7: TOP WAITS COMPARISON
    -- ============================================================
    SELECT 
        ISNULL(tw.WaitType, lw.WaitType) AS WaitType,
        ISNULL(tw.TotalDeltaMs, 0) AS DeltaMs_ThisWeek,
        ISNULL(lw.TotalDeltaMs, 0) AS DeltaMs_LastWeek,
        CASE 
            WHEN ISNULL(lw.TotalDeltaMs, 0) = 0 THEN NULL
            ELSE CAST(ROUND((CAST(ISNULL(tw.TotalDeltaMs, 0) - ISNULL(lw.TotalDeltaMs, 0) AS DECIMAL(18,2)) / NULLIF(lw.TotalDeltaMs, 0)) * 100, 1) AS DECIMAL(10,1))
        END AS ChangePct
    FROM (
        SELECT TOP 10 WaitType, SUM(ISNULL(DeltaWaitTimeMs, WaitTimeMs)) AS TotalDeltaMs
        FROM [monitor].[WaitStatsHistory]
        WHERE CollectedAt >= @ThisWeekStart
        GROUP BY WaitType
        ORDER BY SUM(ISNULL(DeltaWaitTimeMs, WaitTimeMs)) DESC
    ) tw
    FULL OUTER JOIN (
        SELECT TOP 10 WaitType, SUM(ISNULL(DeltaWaitTimeMs, WaitTimeMs)) AS TotalDeltaMs
        FROM [monitor].[WaitStatsHistory]
        WHERE CollectedAt >= @LastWeekStart AND CollectedAt < @LastWeekEnd
        GROUP BY WaitType
        ORDER BY SUM(ISNULL(DeltaWaitTimeMs, WaitTimeMs)) DESC
    ) lw ON tw.WaitType = lw.WaitType
    ORDER BY ISNULL(tw.TotalDeltaMs, 0) DESC;

    -- ============================================================
    -- LOG REPORT GENERATION
    -- ============================================================
    IF @DebugMode = 0
    BEGIN
        INSERT INTO [monitor].[ReportHistory] (ReportType, Recipients, Language, Success)
        VALUES ('Weekly', ISNULL(@OverrideRecipients, 'PowerShell'), @Language, 1);
    END;

    PRINT '✓ Weekly deep dive report generated for period: ' + @WeekStr;
END;
GO

PRINT '✓ Procedure [monitor].[usp_GenerateWeeklyReport] created.';
GO
