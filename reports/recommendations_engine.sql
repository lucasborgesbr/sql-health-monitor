/*
    SQL Health Monitor - Recommendations Engine
    Analyzes collected monitoring data and generates actionable recommendations.
    
    Categories:
      - Index maintenance (fragmentation, missing, unused)
      - Backup compliance
      - Capacity planning (disk, log growth)
      - Performance (CPU, memory, waits)
      - AG health
      - Deadlock patterns
      - TempDB pressure
    
    Each recommendation includes:
      - Priority (Critical, High, Medium, Low)
      - Category
      - Description with specific details
      - Suggested action
      - Estimated impact
    
    Compatibility: SQL Server 2016+
*/

USE [DBA_Monitor];
GO

----------------------------------------------------------------------
-- RECOMMENDATIONS TABLE
----------------------------------------------------------------------
IF OBJECT_ID('monitor.Recommendations', 'U') IS NULL
CREATE TABLE [monitor].[Recommendations] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    GeneratedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    Category        NVARCHAR(50)  NOT NULL,
    Priority        NVARCHAR(20)  NOT NULL,  -- Critical, High, Medium, Low
    Title           NVARCHAR(200) NOT NULL,
    Description     NVARCHAR(MAX) NOT NULL,
    SuggestedAction NVARCHAR(MAX) NULL,
    Impact          NVARCHAR(200) NULL,
    MetricName      NVARCHAR(100) NULL,
    CurrentValue    NVARCHAR(100) NULL,
    DatabaseName    NVARCHAR(128) NULL,
    ObjectName      NVARCHAR(256) NULL,
    IsActive        BIT           NOT NULL DEFAULT 1,
    DismissedAt     DATETIME2     NULL,
    DismissedBy     NVARCHAR(128) NULL,
    INDEX IX_Rec_Generated NONCLUSTERED (GeneratedAt),
    INDEX IX_Rec_Priority NONCLUSTERED (Priority, IsActive),
    INDEX IX_Rec_Category NONCLUSTERED (Category, IsActive)
);
GO

----------------------------------------------------------------------
-- RECOMMENDATIONS ENGINE PROCEDURE
----------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [monitor].[usp_GenerateRecommendations]
    @PurgeOlderThanDays INT = 7,
    @DebugMode BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();
    DECLARE @Language CHAR(5) = (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'General' AND SettingName = 'Language');

    -- Deactivate old recommendations (will regenerate current ones)
    UPDATE [monitor].[Recommendations]
    SET IsActive = 0
    WHERE IsActive = 1
        AND GeneratedAt < DATEADD(HOUR, -6, @Now);

    -- Purge very old recommendations
    DELETE FROM [monitor].[Recommendations]
    WHERE GeneratedAt < DATEADD(DAY, -@PurgeOlderThanDays, @Now)
        AND IsActive = 0;

    -- ============================================================
    -- 1. INDEX HEALTH RECOMMENDATIONS
    -- ============================================================

    -- Indexes needing REBUILD (fragmentation > 90%)
    INSERT INTO [monitor].[Recommendations] (Category, Priority, Title, Description, SuggestedAction, Impact, MetricName, CurrentValue, DatabaseName, ObjectName)
    SELECT
        'Index Maintenance',
        'High',
        'Index rebuild recommended: ' + IndexName,
        'Index [' + SchemaName + '].[' + TableName + '].[' + ISNULL(IndexName, 'HEAP') + '] '
            + 'in database [' + DatabaseName + '] has ' + CAST(CAST(FragmentationPct AS INT) AS VARCHAR) + '% fragmentation '
            + '(' + CAST(PageCount AS VARCHAR) + ' pages).',
        'ALTER INDEX [' + ISNULL(IndexName, 'ALL') + '] ON [' + DatabaseName + '].[' + SchemaName + '].[' + TableName + '] REBUILD WITH (ONLINE = ON);',
        'Improved query performance, reduced I/O',
        'IndexFragmentation',
        CAST(FragmentationPct AS VARCHAR) + '%',
        DatabaseName,
        SchemaName + '.' + TableName + '.' + ISNULL(IndexName, 'HEAP')
    FROM [monitor].[IndexHealthHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[IndexHealthHistory])
        AND FragmentationPct >= 90
        AND PageCount >= 1000
        AND IndexName IS NOT NULL;

    -- Indexes needing REORGANIZE (fragmentation 30-90%)
    INSERT INTO [monitor].[Recommendations] (Category, Priority, Title, Description, SuggestedAction, Impact, MetricName, CurrentValue, DatabaseName, ObjectName)
    SELECT
        'Index Maintenance',
        'Medium',
        'Index reorganize recommended: ' + IndexName,
        'Index [' + SchemaName + '].[' + TableName + '].[' + ISNULL(IndexName, 'HEAP') + '] '
            + 'in database [' + DatabaseName + '] has ' + CAST(CAST(FragmentationPct AS INT) AS VARCHAR) + '% fragmentation.',
        'ALTER INDEX [' + ISNULL(IndexName, 'ALL') + '] ON [' + DatabaseName + '].[' + SchemaName + '].[' + TableName + '] REORGANIZE;',
        'Moderate performance improvement',
        'IndexFragmentation',
        CAST(FragmentationPct AS VARCHAR) + '%',
        DatabaseName,
        SchemaName + '.' + TableName + '.' + ISNULL(IndexName, 'HEAP')
    FROM [monitor].[IndexHealthHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[IndexHealthHistory])
        AND FragmentationPct >= 30 AND FragmentationPct < 90
        AND PageCount >= 1000
        AND IndexName IS NOT NULL;

    -- ============================================================
    -- 2. BACKUP COMPLIANCE RECOMMENDATIONS
    -- ============================================================

    -- No full backup in over 48 hours
    INSERT INTO [monitor].[Recommendations] (Category, Priority, Title, Description, SuggestedAction, Impact, MetricName, CurrentValue, DatabaseName)
    SELECT
        'Backup',
        'Critical',
        'Full backup overdue: ' + DatabaseName,
        'Database [' + DatabaseName + '] has not had a full backup in ' 
            + CAST(DATEDIFF(HOUR, LastBackupDate, SYSUTCDATETIME()) AS VARCHAR) + ' hours. '
            + 'RPO may be at risk.',
        'BACKUP DATABASE [' + DatabaseName + '] TO DISK = N''<path>\' + DatabaseName + '_FULL_' + FORMAT(@Now, 'yyyyMMdd') + '.bak'' WITH COMPRESSION, CHECKSUM;',
        'Data loss risk — immediate action required',
        'Backup_FullHours',
        CAST(DATEDIFF(HOUR, LastBackupDate, SYSUTCDATETIME()) AS VARCHAR) + 'h',
        DatabaseName
    FROM [monitor].[BackupHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[BackupHistory])
        AND BackupType = 'D'
        AND DATEDIFF(HOUR, LastBackupDate, SYSUTCDATETIME()) > 48;

    -- No log backup in over 4 hours (for databases in FULL recovery)
    INSERT INTO [monitor].[Recommendations] (Category, Priority, Title, Description, SuggestedAction, Impact, MetricName, CurrentValue, DatabaseName)
    SELECT
        'Backup',
        'High',
        'Log backup overdue: ' + DatabaseName,
        'Database [' + DatabaseName + '] has not had a log backup in ' 
            + CAST(DATEDIFF(HOUR, LastBackupDate, SYSUTCDATETIME()) AS VARCHAR) + ' hours. '
            + 'Transaction log may be growing unchecked.',
        'BACKUP LOG [' + DatabaseName + '] TO DISK = N''<path>\' + DatabaseName + '_LOG_' + FORMAT(@Now, 'yyyyMMddHHmm') + '.trn'' WITH COMPRESSION;',
        'Log growth risk, increased RPO',
        'Backup_LogHours',
        CAST(DATEDIFF(HOUR, LastBackupDate, SYSUTCDATETIME()) AS VARCHAR) + 'h',
        DatabaseName
    FROM [monitor].[BackupHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[BackupHistory])
        AND BackupType = 'L'
        AND DATEDIFF(HOUR, LastBackupDate, SYSUTCDATETIME()) > 4;

    -- ============================================================
    -- 3. CAPACITY & GROWTH RECOMMENDATIONS
    -- ============================================================

    -- Disk space critical
    INSERT INTO [monitor].[Recommendations] (Category, Priority, Title, Description, SuggestedAction, Impact, MetricName, CurrentValue)
    SELECT
        'Capacity',
        CASE WHEN UsedPct >= 95 THEN 'Critical' ELSE 'High' END,
        'Disk space ' + CASE WHEN UsedPct >= 95 THEN 'critical' ELSE 'warning' END + ': Drive ' + DriveLetter,
        'Drive ' + DriveLetter + ' is at ' + CAST(CAST(UsedPct AS INT) AS VARCHAR) + '% capacity. '
            + 'Free space: ' + CAST(FreeSpaceMB AS VARCHAR) + ' MB.',
        'Review and clean up old backups, shrink unused files, or expand storage.',
        'Potential database autogrow failure, service interruption',
        'Disk_UsedPct',
        CAST(UsedPct AS VARCHAR) + '%'
    FROM [monitor].[DiskHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[DiskHistory])
        AND UsedPct >= 85;

    -- Database log file grew significantly in 7 days
    INSERT INTO [monitor].[Recommendations] (Category, Priority, Title, Description, SuggestedAction, Impact, MetricName, CurrentValue, DatabaseName)
    SELECT
        'Capacity',
        'High',
        'Log file rapid growth: ' + curr.DatabaseName,
        'Log file [' + curr.FileLogicalName + '] in database [' + curr.DatabaseName + '] grew from '
            + CAST(CAST(prev.SizeMB AS INT) AS VARCHAR) + ' MB to ' + CAST(CAST(curr.SizeMB AS INT) AS VARCHAR) + ' MB '
            + '(' + CAST(CAST((curr.SizeMB - prev.SizeMB) * 100.0 / NULLIF(prev.SizeMB, 0) AS INT) AS VARCHAR) + '% increase) in 7 days.',
        'Investigate long-running transactions, missing log backups, or index rebuild operations.',
        'Disk space exhaustion, autogrow performance impact',
        'DbGrowth_LogPctWeek',
        CAST(CAST((curr.SizeMB - prev.SizeMB) * 100.0 / NULLIF(prev.SizeMB, 0) AS INT) AS VARCHAR) + '%',
        curr.DatabaseName
    FROM [monitor].[DatabaseGrowthHistory] curr
    INNER JOIN (
        SELECT DatabaseName, FileLogicalName, SizeMB
        FROM [monitor].[DatabaseGrowthHistory]
        WHERE FileType = 'LOG'
            AND CollectedAt >= DATEADD(DAY, -8, @Now)
            AND CollectedAt < DATEADD(DAY, -6, @Now)
    ) prev ON curr.DatabaseName = prev.DatabaseName AND curr.FileLogicalName = prev.FileLogicalName
    WHERE curr.CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[DatabaseGrowthHistory])
        AND curr.FileType = 'LOG'
        AND prev.SizeMB > 0
        AND (curr.SizeMB - prev.SizeMB) * 100.0 / prev.SizeMB >= 30;

    -- ============================================================
    -- 4. PERFORMANCE RECOMMENDATIONS
    -- ============================================================

    -- Sustained high CPU
    INSERT INTO [monitor].[Recommendations] (Category, Priority, Title, Description, SuggestedAction, Impact, MetricName, CurrentValue)
    SELECT
        'Performance',
        CASE WHEN AvgCpu >= 90 THEN 'Critical' ELSE 'High' END,
        'Sustained high CPU utilization',
        'Average SQL CPU over the last 24 hours: ' + CAST(AvgCpu AS VARCHAR) + '% '
            + '(peak: ' + CAST(MaxCpu AS VARCHAR) + '%). '
            + 'This indicates consistent resource pressure.',
        'Review top CPU-consuming queries in [monitor].[TopQueriesHistory]. Consider query tuning, missing indexes, or hardware upgrade.',
        'Query timeouts, degraded user experience',
        'CPU_SqlPct',
        CAST(AvgCpu AS VARCHAR) + '% avg'
    FROM (
        SELECT 
            AVG(SqlCpuPct) AS AvgCpu,
            MAX(SqlCpuPct) AS MaxCpu
        FROM [monitor].[CpuHistory]
        WHERE CollectedAt >= DATEADD(HOUR, -24, @Now)
    ) cpu
    WHERE AvgCpu >= 75;

    -- Memory pressure (low PLE)
    INSERT INTO [monitor].[Recommendations] (Category, Priority, Title, Description, SuggestedAction, Impact, MetricName, CurrentValue)
    SELECT
        'Performance',
        CASE WHEN PageLifeExpectancy <= 300 THEN 'Critical' ELSE 'High' END,
        'Memory pressure detected (low PLE)',
        'Page Life Expectancy is ' + CAST(PageLifeExpectancy AS VARCHAR) + ' seconds. '
            + 'Memory grants pending: ' + CAST(MemoryGrantsPending AS VARCHAR) + '. '
            + 'Buffer cache hit ratio: ' + CAST(CAST(BufferCacheHitRatio AS DECIMAL(5,1)) AS VARCHAR) + '%.',
        'Review memory-intensive queries, check for missing indexes causing scans, consider increasing max server memory.',
        'Excessive disk I/O, slow queries, memory grant waits',
        'Memory_PLE',
        CAST(PageLifeExpectancy AS VARCHAR) + 's'
    FROM [monitor].[MemoryHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[MemoryHistory])
        AND PageLifeExpectancy <= 600;

    -- ============================================================
    -- 5. AG HEALTH RECOMMENDATIONS
    -- ============================================================

    INSERT INTO [monitor].[Recommendations] (Category, Priority, Title, Description, SuggestedAction, Impact, MetricName, CurrentValue, DatabaseName)
    SELECT
        'Availability',
        CASE WHEN SecondsBehindPrimary >= 120 THEN 'Critical' ELSE 'High' END,
        'AG replica lagging: ' + ReplicaServer,
        'Replica [' + ReplicaServer + '] for AG [' + AgName + '] is ' 
            + CAST(SecondsBehindPrimary AS VARCHAR) + ' seconds behind primary. '
            + 'Log send queue: ' + CAST(CAST(LogSendQueueSizeKB / 1024.0 AS INT) AS VARCHAR) + ' MB, '
            + 'Redo queue: ' + CAST(CAST(RedoQueueSizeKB / 1024.0 AS INT) AS VARCHAR) + ' MB.',
        'Check network bandwidth between replicas, verify redo thread is not blocked, review large transaction activity.',
        'Potential data loss on failover, read-routing stale data',
        'AG_SecondsBehind',
        CAST(SecondsBehindPrimary AS VARCHAR) + 's',
        DatabaseName
    FROM [monitor].[AgHealthHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[AgHealthHistory])
        AND SecondsBehindPrimary >= 30;

    -- ============================================================
    -- 6. DEADLOCK RECOMMENDATIONS
    -- ============================================================

    INSERT INTO [monitor].[Recommendations] (Category, Priority, Title, Description, SuggestedAction, Impact, MetricName, CurrentValue)
    SELECT
        'Concurrency',
        CASE WHEN DeadlockCount >= 10 THEN 'High' ELSE 'Medium' END,
        'Frequent deadlocks detected (' + CAST(DeadlockCount AS VARCHAR) + ' in 24h)',
        'Detected ' + CAST(DeadlockCount AS VARCHAR) + ' deadlocks in the last 24 hours. '
            + 'Most common resource type: ' + ISNULL(TopResource, 'N/A') + '.',
        'Review deadlock graphs in [monitor].[DeadlockHistory]. Common fixes: consistent access order, shorter transactions, appropriate isolation levels.',
        'Transaction rollbacks, application errors, retry overhead',
        'Deadlocks_Count',
        CAST(DeadlockCount AS VARCHAR)
    FROM (
        SELECT 
            COUNT(*) AS DeadlockCount,
            (SELECT TOP 1 ResourceType FROM [monitor].[DeadlockHistory] 
             WHERE DeadlockTime >= DATEADD(HOUR, -24, SYSUTCDATETIME())
             GROUP BY ResourceType ORDER BY COUNT(*) DESC) AS TopResource
        FROM [monitor].[DeadlockHistory]
        WHERE DeadlockTime >= DATEADD(HOUR, -24, @Now)
    ) dl
    WHERE DeadlockCount >= 3;

    -- ============================================================
    -- 7. TEMPDB RECOMMENDATIONS
    -- ============================================================

    INSERT INTO [monitor].[Recommendations] (Category, Priority, Title, Description, SuggestedAction, Impact, MetricName, CurrentValue)
    SELECT
        'Performance',
        CASE WHEN UsedPct >= 90 THEN 'Critical' ELSE 'High' END,
        'TempDB under pressure (' + CAST(UsedPct AS VARCHAR) + '% used)',
        'TempDB is at ' + CAST(UsedPct AS VARCHAR) + '% capacity. '
            + 'Used: ' + CAST(UsedSpaceMB AS VARCHAR) + ' MB / ' + CAST(TotalSizeMB AS VARCHAR) + ' MB. '
            + ISNULL('Version store: ' + CAST(VersionStoreMB AS VARCHAR) + ' MB.', ''),
        'Identify sessions using excessive temp space (version store, temp tables, spills). Check for long-running RCSI/snapshot transactions.',
        'Query failures, sort/hash spills to disk',
        'TempDB_UsedPct',
        CAST(UsedPct AS VARCHAR) + '%'
    FROM (
        SELECT 
            TotalSizeMB, UsedSpaceMB, VersionStoreMB,
            CAST(UsedSpaceMB * 100.0 / NULLIF(TotalSizeMB, 0) AS INT) AS UsedPct
        FROM [monitor].[TempDbHistory]
        WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[TempDbHistory])
    ) t
    WHERE UsedPct >= 75;

    -- ============================================================
    -- OUTPUT
    -- ============================================================
    IF @DebugMode = 1
    BEGIN
        SELECT * FROM [monitor].[Recommendations]
        WHERE IsActive = 1
        ORDER BY 
            CASE Priority 
                WHEN 'Critical' THEN 1 
                WHEN 'High' THEN 2 
                WHEN 'Medium' THEN 3 
                ELSE 4 
            END,
            Category, GeneratedAt DESC;
    END;

    DECLARE @RecCount INT = (SELECT COUNT(*) FROM [monitor].[Recommendations] WHERE IsActive = 1 AND GeneratedAt >= DATEADD(MINUTE, -1, @Now));
    PRINT 'Generated ' + CAST(@RecCount AS VARCHAR(10)) + ' new recommendation(s).';
END;
GO

PRINT '✓ Recommendations engine [monitor].[usp_GenerateRecommendations] created.';
PRINT '✓ Table [monitor].[Recommendations] created.';
GO
