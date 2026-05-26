/*
    SQL Health Monitor - Current Health Dashboard View
    Single SELECT that shows overall health status with traffic light indicators.
    
    Provides at-a-glance view of:
      - CPU, Memory, Disk utilization
      - AG synchronization status
      - Backup compliance
      - Blocking events
      - Deadlocks
      - Overall health score
    
    Traffic light system:
      🟢 GREEN  = Healthy (within normal thresholds)
      🟡 YELLOW = Warning (approaching thresholds)
      🔴 RED    = Critical (threshold exceeded)
    
    Compatibility: SQL Server 2016+
*/

USE [DBA_Monitor];
GO

CREATE OR ALTER VIEW [monitor].[vw_CurrentHealth]
AS
WITH LatestCPU AS (
    SELECT TOP 1
        SqlCpuPct,
        SystemCpuPct,
        CollectedAt
    FROM [monitor].[CpuHistory]
    ORDER BY CollectedAt DESC
),
LatestMemory AS (
    SELECT TOP 1
        PageLifeExpectancy,
        MemoryGrantsPending,
        BufferCacheHitRatio,
        TotalServerMemoryMB,
        AvailableMemoryMB,
        CollectedAt
    FROM [monitor].[MemoryHistory]
    ORDER BY CollectedAt DESC
),
LatestDisk AS (
    SELECT
        MAX(UsedPct) AS MaxUsedPct,
        MAX(AvgReadLatencyMs) AS MaxReadLatencyMs,
        MAX(AvgWriteLatencyMs) AS MaxWriteLatencyMs,
        MAX(CollectedAt) AS CollectedAt
    FROM [monitor].[DiskHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[DiskHistory])
),
LatestAG AS (
    SELECT
        MAX(SecondsBehindPrimary) AS MaxSecondsBehind,
        MAX(LogSendQueueSizeKB) AS MaxLogSendQueueKB,
        MAX(RedoQueueSizeKB) AS MaxRedoQueueKB,
        MIN(CASE WHEN SyncHealth = 'HEALTHY' THEN 1 ELSE 0 END) AS AllHealthy,
        MAX(CollectedAt) AS CollectedAt
    FROM [monitor].[AgHealthHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[AgHealthHistory])
),
BackupStatus AS (
    SELECT
        MAX(CASE WHEN BackupType = 'D' THEN DATEDIFF(HOUR, LastBackupDate, SYSUTCDATETIME()) END) AS MaxHoursSinceFull,
        MAX(CASE WHEN BackupType = 'L' THEN DATEDIFF(HOUR, LastBackupDate, SYSUTCDATETIME()) END) AS MaxHoursSinceLog,
        SUM(CASE WHEN BackupType = 'D' AND DATEDIFF(HOUR, LastBackupDate, SYSUTCDATETIME()) > 48 THEN 1 ELSE 0 END) AS OverdueFullCount,
        MAX(CollectedAt) AS CollectedAt
    FROM [monitor].[BackupHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[BackupHistory])
),
ActiveBlocking AS (
    SELECT
        COUNT(*) AS BlockingCount,
        MAX(BlockingDurationSec) AS MaxBlockingDurationSec
    FROM [monitor].[BlockingHistory]
    WHERE DetectedAt >= DATEADD(MINUTE, -15, SYSUTCDATETIME())
),
RecentDeadlocks AS (
    SELECT COUNT(*) AS DeadlockCount24h
    FROM [monitor].[DeadlockHistory]
    WHERE DeadlockTime >= DATEADD(HOUR, -24, SYSUTCDATETIME())
),
RecentAlerts AS (
    SELECT
        SUM(CASE WHEN Severity = 'Critical' THEN 1 ELSE 0 END) AS CriticalAlerts24h,
        SUM(CASE WHEN Severity = 'Warning' THEN 1 ELSE 0 END) AS WarningAlerts24h
    FROM [monitor].[AlertHistory]
    WHERE FiredAt >= DATEADD(HOUR, -24, SYSUTCDATETIME())
),
FailedJobs AS (
    SELECT COUNT(*) AS FailedJobCount
    FROM [monitor].[JobHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[JobHistory])
        AND LastRunStatus = 'Failed'
),
Thresholds AS (
    SELECT MetricName, WarningValue, CriticalValue, Operator
    FROM [monitor].[Thresholds]
    WHERE IsEnabled = 1
)
SELECT
    -- Timestamp
    SYSUTCDATETIME() AS SnapshotTime,
    
    -- CPU Status
    cpu.SqlCpuPct,
    cpu.SystemCpuPct,
    CASE
        WHEN cpu.SqlCpuPct >= (SELECT CriticalValue FROM Thresholds WHERE MetricName = 'CPU_SqlPct') THEN 'RED'
        WHEN cpu.SqlCpuPct >= (SELECT WarningValue FROM Thresholds WHERE MetricName = 'CPU_SqlPct') THEN 'YELLOW'
        ELSE 'GREEN'
    END AS CpuStatus,
    cpu.CollectedAt AS CpuLastCollected,

    -- Memory Status
    mem.PageLifeExpectancy,
    mem.MemoryGrantsPending,
    mem.BufferCacheHitRatio,
    CASE
        WHEN mem.PageLifeExpectancy <= (SELECT CriticalValue FROM Thresholds WHERE MetricName = 'Memory_PLE') THEN 'RED'
        WHEN mem.PageLifeExpectancy <= (SELECT WarningValue FROM Thresholds WHERE MetricName = 'Memory_PLE') THEN 'YELLOW'
        ELSE 'GREEN'
    END AS MemoryStatus,
    mem.CollectedAt AS MemoryLastCollected,

    -- Disk Status
    dsk.MaxUsedPct AS DiskMaxUsedPct,
    dsk.MaxReadLatencyMs,
    dsk.MaxWriteLatencyMs,
    CASE
        WHEN dsk.MaxUsedPct >= (SELECT CriticalValue FROM Thresholds WHERE MetricName = 'Disk_UsedPct') THEN 'RED'
        WHEN dsk.MaxUsedPct >= (SELECT WarningValue FROM Thresholds WHERE MetricName = 'Disk_UsedPct') THEN 'YELLOW'
        ELSE 'GREEN'
    END AS DiskStatus,
    dsk.CollectedAt AS DiskLastCollected,

    -- AG Status
    ag.MaxSecondsBehind AS AgMaxLagSeconds,
    ag.AllHealthy AS AgAllHealthy,
    CASE
        WHEN ag.AllHealthy = 0 THEN 'RED'
        WHEN ag.MaxSecondsBehind >= (SELECT CriticalValue FROM Thresholds WHERE MetricName = 'AG_SecondsBehind') THEN 'RED'
        WHEN ag.MaxSecondsBehind >= (SELECT WarningValue FROM Thresholds WHERE MetricName = 'AG_SecondsBehind') THEN 'YELLOW'
        WHEN ag.MaxSecondsBehind IS NULL THEN 'GREEN'  -- No AG configured
        ELSE 'GREEN'
    END AS AgStatus,
    ag.CollectedAt AS AgLastCollected,

    -- Backup Status
    bkp.MaxHoursSinceFull,
    bkp.MaxHoursSinceLog,
    bkp.OverdueFullCount,
    CASE
        WHEN bkp.MaxHoursSinceFull >= (SELECT CriticalValue FROM Thresholds WHERE MetricName = 'Backup_FullHours') THEN 'RED'
        WHEN bkp.MaxHoursSinceFull >= (SELECT WarningValue FROM Thresholds WHERE MetricName = 'Backup_FullHours') THEN 'YELLOW'
        ELSE 'GREEN'
    END AS BackupStatus,

    -- Blocking Status
    blk.BlockingCount AS ActiveBlockingCount,
    blk.MaxBlockingDurationSec,
    CASE
        WHEN blk.MaxBlockingDurationSec >= (SELECT CriticalValue FROM Thresholds WHERE MetricName = 'Blocking_DurationSec') THEN 'RED'
        WHEN blk.MaxBlockingDurationSec >= (SELECT WarningValue FROM Thresholds WHERE MetricName = 'Blocking_DurationSec') THEN 'YELLOW'
        WHEN blk.BlockingCount = 0 THEN 'GREEN'
        ELSE 'GREEN'
    END AS BlockingStatus,

    -- Deadlocks (24h)
    dl.DeadlockCount24h,
    CASE
        WHEN dl.DeadlockCount24h >= (SELECT CriticalValue FROM Thresholds WHERE MetricName = 'Deadlocks_Count') THEN 'RED'
        WHEN dl.DeadlockCount24h >= (SELECT WarningValue FROM Thresholds WHERE MetricName = 'Deadlocks_Count') THEN 'YELLOW'
        ELSE 'GREEN'
    END AS DeadlockStatus,

    -- Failed Jobs
    jobs.FailedJobCount,
    CASE
        WHEN jobs.FailedJobCount >= (SELECT CriticalValue FROM Thresholds WHERE MetricName = 'Jobs_FailedCount') THEN 'RED'
        WHEN jobs.FailedJobCount >= (SELECT WarningValue FROM Thresholds WHERE MetricName = 'Jobs_FailedCount') THEN 'YELLOW'
        ELSE 'GREEN'
    END AS JobsStatus,

    -- Alert Summary (24h)
    alerts.CriticalAlerts24h,
    alerts.WarningAlerts24h,

    -- Overall Health Score
    CASE
        WHEN cpu.SqlCpuPct >= (SELECT CriticalValue FROM Thresholds WHERE MetricName = 'CPU_SqlPct')
            OR mem.PageLifeExpectancy <= (SELECT CriticalValue FROM Thresholds WHERE MetricName = 'Memory_PLE')
            OR dsk.MaxUsedPct >= (SELECT CriticalValue FROM Thresholds WHERE MetricName = 'Disk_UsedPct')
            OR ISNULL(ag.AllHealthy, 1) = 0
            OR bkp.MaxHoursSinceFull >= (SELECT CriticalValue FROM Thresholds WHERE MetricName = 'Backup_FullHours')
            OR blk.MaxBlockingDurationSec >= (SELECT CriticalValue FROM Thresholds WHERE MetricName = 'Blocking_DurationSec')
        THEN 'CRITICAL'
        WHEN cpu.SqlCpuPct >= (SELECT WarningValue FROM Thresholds WHERE MetricName = 'CPU_SqlPct')
            OR mem.PageLifeExpectancy <= (SELECT WarningValue FROM Thresholds WHERE MetricName = 'Memory_PLE')
            OR dsk.MaxUsedPct >= (SELECT WarningValue FROM Thresholds WHERE MetricName = 'Disk_UsedPct')
            OR bkp.MaxHoursSinceFull >= (SELECT WarningValue FROM Thresholds WHERE MetricName = 'Backup_FullHours')
            OR blk.MaxBlockingDurationSec >= (SELECT WarningValue FROM Thresholds WHERE MetricName = 'Blocking_DurationSec')
            OR jobs.FailedJobCount >= (SELECT WarningValue FROM Thresholds WHERE MetricName = 'Jobs_FailedCount')
        THEN 'WARNING'
        ELSE 'HEALTHY'
    END AS OverallStatus

FROM LatestCPU cpu
CROSS JOIN LatestMemory mem
CROSS JOIN LatestDisk dsk
CROSS JOIN LatestAG ag
CROSS JOIN BackupStatus bkp
CROSS JOIN ActiveBlocking blk
CROSS JOIN RecentDeadlocks dl
CROSS JOIN RecentAlerts alerts
CROSS JOIN FailedJobs jobs;
GO

PRINT '✓ Dashboard view [monitor].[vw_CurrentHealth] created.';
GO
