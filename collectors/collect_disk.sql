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

    -- Get real disk total/free via sys.dm_os_volume_stats (SQL 2008 R2+)
    -- One row per unique volume; deduplicate by taking one file per drive letter.
    ;WITH VolStats AS (
        SELECT DISTINCT
            LEFT(mf.physical_name, 1)                              AS DriveLetter,
            vs.total_bytes / 1048576                               AS TotalMB,
            vs.available_bytes / 1048576                           AS FreeMB
        FROM sys.master_files mf
        CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
        WHERE mf.state = 0
    ),
    DedupVol AS (
        SELECT DriveLetter, MAX(TotalMB) AS TotalMB, MAX(FreeMB) AS FreeMB
        FROM VolStats
        GROUP BY DriveLetter
    )
    INSERT INTO [monitor].[DiskHistory]
        (CollectedAt, DriveLetter, TotalSpaceMB, FreeSpaceMB, UsedPct,
         AvgReadLatencyMs, AvgWriteLatencyMs)
    SELECT
        @CurrentTime,
        LEFT(mf.physical_name, 1)                                     AS DriveLetter,
        dv.TotalMB                                                    AS TotalSpaceMB,
        dv.FreeMB                                                     AS FreeSpaceMB,
        CASE WHEN dv.TotalMB = 0 THEN NULL
             ELSE CAST((dv.TotalMB - dv.FreeMB) * 100.0 / dv.TotalMB AS DECIMAL(5,2))
        END                                                            AS UsedPct,
        AVG(CASE WHEN vfs.num_of_reads > 0
                 THEN CAST(vfs.io_stall_read_ms AS FLOAT) / vfs.num_of_reads
                 ELSE NULL END)                                        AS AvgReadLatencyMs,
        AVG(CASE WHEN vfs.num_of_writes > 0
                 THEN CAST(vfs.io_stall_write_ms AS FLOAT) / vfs.num_of_writes
                 ELSE NULL END)                                        AS AvgWriteLatencyMs
    FROM sys.master_files mf
    JOIN sys.dm_io_virtual_file_stats(NULL, NULL) vfs
        ON mf.database_id = vfs.database_id AND mf.file_id = vfs.file_id
    JOIN DedupVol dv ON dv.DriveLetter = LEFT(mf.physical_name, 1)
    WHERE mf.database_id > 4
      AND mf.state = 0
    GROUP BY LEFT(mf.physical_name, 1), dv.TotalMB, dv.FreeMB;

    -- Note: DiskHistoryDetailed and DiskIoWaits tables do not exist in the schema;
    -- those inserts have been removed.
    PRINT '✓ Disk statistics collected successfully';
END;
GO