/*
    SQL Health Monitor - Disk Collector
    Collects disk space usage and I/O statistics.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_Disk]
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [monitor].[DiskHistory]
        (DriveLetter, TotalSizeGB, FreeSpaceGB, UsedSpaceGB, 
         UsedSpacePercent, DiskIOPS, DiskLatencyMS, DiskReadMB, DiskWriteMB)
    SELECT
        UPPER(mf.physical_name) AS DriveLetter,
        CAST(mf.size / 1024.0 / 1024.0 / 1024.0 AS DECIMAL(10, 2)) AS TotalSizeGB,
        CAST((mf.size - mf.size / 100.0 * mf.free_space_percent) / 1024.0 / 1024.0 / 1024.0 AS DECIMAL(10, 2)) AS FreeSpaceGB,
        CAST(mf.size / 1024.0 / 1024.0 / 1024.0 * mf.free_space_percent / 100.0 AS DECIMAL(10, 2)) AS UsedSpaceGB,
        mf.free_space_percent AS UsedSpacePercent,
        NULL AS DiskIOPS,  -- Requires extended events or perfmon
        NULL AS DiskLatencyMS,
        NULL AS DiskReadMB,
        NULL AS DiskWriteMB
    FROM sys.master_files mf
    WHERE mf.type = 0  -- Data files
      AND mf.database_id > 4  -- Exclude system databases
      AND mf.state = 0;  -- ONLINE
      
    -- Note: Real disk I/O statistics require extended events or sys.dm_io_virtual_file_stats
    -- This is a simplified version - consider implementing extended events for full disk monitoring
END;
GO
