/*
    SQL Health Monitor - Disk Space & IO Collector
    Collects drive space and IO latency metrics.
    
    Schedule: Every 15 minutes
    Compatibility: SQL Server 2016+
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_Disk]
AS
BEGIN
    SET NOCOUNT ON;

    -- Disk space from sys.dm_os_volume_stats
    INSERT INTO [monitor].[DiskHistory]
        (DriveLetter, TotalSpaceMB, FreeSpaceMB, UsedPct, AvgReadLatencyMs, AvgWriteLatencyMs)
    SELECT DISTINCT
        vs.volume_mount_point AS DriveLetter,
        vs.total_bytes / 1048576 AS TotalSpaceMB,
        vs.available_bytes / 1048576 AS FreeSpaceMB,
        CAST((1.0 - (CAST(vs.available_bytes AS DECIMAL(18,2)) / NULLIF(vs.total_bytes, 0))) * 100 AS DECIMAL(5,2)) AS UsedPct,
        io.AvgReadLatencyMs,
        io.AvgWriteLatencyMs
    FROM sys.master_files mf
    CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
    OUTER APPLY (
        SELECT
            CASE WHEN SUM(num_of_reads) > 0 
                 THEN CAST(SUM(io_stall_read_ms) * 1.0 / SUM(num_of_reads) AS DECIMAL(10,2))
                 ELSE 0 END AS AvgReadLatencyMs,
            CASE WHEN SUM(num_of_writes) > 0 
                 THEN CAST(SUM(io_stall_write_ms) * 1.0 / SUM(num_of_writes) AS DECIMAL(10,2))
                 ELSE 0 END AS AvgWriteLatencyMs
        FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
        INNER JOIN sys.master_files mf2 ON mf2.database_id = vfs.database_id AND mf2.file_id = vfs.file_id
        CROSS APPLY sys.dm_os_volume_stats(mf2.database_id, mf2.file_id) vs2
        WHERE vs2.volume_mount_point = vs.volume_mount_point
    ) io;
END;
GO
