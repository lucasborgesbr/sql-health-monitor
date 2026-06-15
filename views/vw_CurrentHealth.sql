-- vw_CurrentHealth.sql - Aggregated current health status view
-- Provides current health status across all monitored metrics
-- Updated: 2026-06-02 for release-ready version

IF OBJECT_ID('[monitor].[vw_CurrentHealth]', 'V') IS NOT NULL
    EXEC('ALTER VIEW [monitor].[vw_CurrentHealth] AS SELECT 1 AS Dummy;');
GO

IF OBJECT_ID('[monitor].[vw_CurrentHealth]', 'V') IS NULL
    EXEC('CREATE VIEW [monitor].[vw_CurrentHealth] AS SELECT 1 AS Dummy;');
GO

ALTER VIEW [monitor].[vw_CurrentHealth]
AS
SELECT
    ch.Id,
    ch.CollectedAt,
    
    -- CPU Metrics
    ch.SqlCpuPct,
    ch.SystemCpuPct,
    ch.IdleCpuPct,
    
    -- Memory Metrics  
    mh.TotalServerMemoryMB,
    mh.TargetServerMemoryMB,
    mh.AvailableMemoryMB,
    mh.BufferCacheHitRatio,
    
    -- Disk Metrics
    dh.DriveLetter,
    dh.TotalSpaceMB,
    dh.FreeSpaceMB,
    dh.UsedPct,
    
    -- Database Health
    CASE WHEN bh.HoursSinceLastBackup > 24 THEN 'CRITICAL'
         WHEN bh.HoursSinceLastBackup > 12 THEN 'WARNING'
         ELSE 'OK' END AS BackupStatus,
    
    -- AG Health
    ah.SyncState,
    ah.SyncHealth,
    
    -- Alert Status
    CASE WHEN ah.AlertCount > 0 THEN 'ALERT'
         ELSE 'OK' END AS OverallStatus
FROM
    (SELECT TOP 1 * FROM [monitor].[CPUHistory] ORDER BY CollectedAt DESC) ch
LEFT JOIN [monitor].[MemoryHistory] mh ON ch.CollectedAt >= DATEADD(MINUTE, -5, mh.CollectedAt)
LEFT JOIN [monitor].[DiskHistory] dh ON ch.CollectedAt >= DATEADD(MINUTE, -5, dh.CollectedAt)
LEFT JOIN [monitor].[BackupHistory] bh ON ch.CollectedAt >= DATEADD(HOUR, -24, bh.CollectedAt)
LEFT JOIN [monitor].[AgHealthHistory] ah ON ch.CollectedAt >= DATEADD(MINUTE, -5, ah.CollectedAt)
WHERE ch.Id IS NOT NULL;

GO

PRINT '✓ Current health view created successfully.';
GO
