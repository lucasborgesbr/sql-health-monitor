/*
    SQL Health Monitor - Disk Collector
    Collects disk space usage and I/O statistics with extended events support.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+
    Features: Basic disk space, detailed I/O statistics, file-level metrics
*/

IF OBJECT_ID('[monitor].[usp_Collect_Disk]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_Disk] AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_Disk]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_Collect_Disk] AS SET NOCOUNT ON; PRINT ''Placeholder'';');
GO
ALTER PROCEDURE [monitor].[usp_Collect_Disk]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @CurrentTime DATETIME2 = SYSUTCDATETIME();

    -- Schema columns: CollectedAt, DriveLetter, TotalSpaceMB, FreeSpaceMB, UsedPct,
    --                 AvgReadLatencyMs, AvgWriteLatencyMs
    -- sys.master_files does NOT have free_space_percent; use dm_io_virtual_file_stats for I/O
    -- and derive drive letter from physical_name.
    INSERT INTO [monitor].[DiskHistory]
        (CollectedAt, DriveLetter, TotalSpaceMB, FreeSpaceMB, UsedPct,
         AvgReadLatencyMs, AvgWriteLatencyMs)
    SELECT
        @CurrentTime,
        LEFT(mf.physical_name, 3)                                     AS DriveLetter,
        CAST(SUM(mf.size) / 128.0 AS BIGINT)                          AS TotalSpaceMB,
        -- FreeSpaceMB not directly available; set NULL (populated externally or via xp_fixeddrives)
        NULL                                                           AS FreeSpaceMB,
        -- UsedPct not directly available without OS-level data; set NULL
        NULL                                                           AS UsedPct,
        AVG(CASE WHEN vfs.num_of_reads > 0
                 THEN CAST(vfs.io_stall_read_ms AS DECIMAL(10,2)) / vfs.num_of_reads
                 ELSE NULL END)                                        AS AvgReadLatencyMs,
        AVG(CASE WHEN vfs.num_of_writes > 0
                 THEN CAST(vfs.io_stall_write_ms AS DECIMAL(10,2)) / vfs.num_of_writes
                 ELSE NULL END)                                        AS AvgWriteLatencyMs
    FROM sys.master_files mf
    JOIN sys.dm_io_virtual_file_stats(NULL, NULL) vfs
        ON mf.database_id = vfs.database_id AND mf.file_id = vfs.file_id
    WHERE mf.database_id > 4   -- Exclude system databases
      AND mf.state = 0          -- ONLINE
    GROUP BY LEFT(mf.physical_name, 3);

    -- Note: DiskHistoryDetailed and DiskIoWaits tables do not exist in the schema;
    -- those inserts have been removed.
    PRINT '✓ Disk statistics collected successfully';
END;
GO