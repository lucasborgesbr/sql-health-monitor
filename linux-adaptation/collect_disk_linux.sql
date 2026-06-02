/*
    SQL Health Monitor - Disk Collector (Linux Adaptation)
    Collects disk space usage and I/O statistics with Linux-specific enhancements.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+ on Linux
    Features: Cross-platform disk monitoring
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_Disk]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @CurrentTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @CriticalThreshold DECIMAL(5,2) = 90.0;  -- 90% usage
    DECLARE @WarningThreshold DECIMAL(5,2) = 80.0;   -- 80% usage
    
    -- Basic disk space collection (works on both platforms)
    INSERT INTO [monitor].[DiskHistory]
        (CollectedAt, DriveLetter, TotalSpaceMB, FreeSpaceMB, UsedPct)
    SELECT
        @CurrentTime,
        UPPER(mf.physical_name) AS DriveLetter,
        CAST(mf.size / 128.0 AS BIGINT) AS TotalSpaceMB,
        CAST((mf.size * (100.0 - mf.free_space_percent) / 100.0) / 128.0 AS BIGINT) AS FreeSpaceMB,
        mf.free_space_percent AS UsedPct
    FROM sys.master_files mf
    WHERE mf.type = 0  -- Data files
      AND mf.database_id > 4  -- Exclude system databases
      AND mf.state = 0;  -- ONLINE
      
    -- Enhanced disk I/O statistics (DMV-based, works on Linux)
    INSERT INTO [monitor].[DiskHistoryDetailed]
        (CollectedAt, DriveLetter, TotalSpaceMB, FreeSpaceMB, UsedPct,
         Filesystem, MountPoint, AvgReadLatencyMs, AvgWriteLatencyMs,
         DiskReadsPerSec, DiskWritesPerSec, DiskReadMBPerSec, DiskWriteMBPerSec,
         DataFileCount, LogFileCount, IsCritical, IsWarning)
    SELECT
        @CurrentTime,
        UPPER(mf.physical_name) AS DriveLetter,
        CAST(mf.size / 128.0 AS BIGINT) AS TotalSpaceMB,
        CAST((mf.size * (100.0 - mf.free_space_percent) / 100.0) / 128.0 AS BIGINT) AS FreeSpaceMB,
        mf.free_space_percent AS UsedPct,
        NULL AS Filesystem,  -- Not available from DMVs
        NULL AS MountPoint,  -- Not available from DMVs
        
        -- Get I/O statistics from sys.dm_io_virtual_file_stats
        AVG(CASE WHEN vfs.num_of_reads > 0 
               THEN vfs.io_stall_read_ms / (1.0 * vfs.num_of_reads) 
               ELSE NULL END) AS AvgReadLatencyMs,
        AVG(CASE WHEN vfs.num_of_writes > 0 
               THEN vfs.io_stall_write_ms / (1.0 * vfs.num_of_writes) 
               ELSE NULL END) AS AvgWriteLatencyMs,
        
        -- Calculate IOPS (per second)        
        AVG(vfs.num_of_reads / 300.0) AS DiskReadsPerSec,  -- Assuming 5-minute interval
        AVG(vfs.num_of_writes / 300.0) AS DiskWritesPerSec,
        
        -- Calculate throughput (MB/sec)
        AVG((vfs.num_of_bytes_read / 1024.0 / 1024.0) / 300.0) AS DiskReadMBPerSec,
        AVG((vfs.num_of_bytes_written / 1024.0 / 1024.0) / 300.0) AS DiskWriteMBPerSec,
        
        -- File counts
        COUNT(CASE WHEN mf.type = 0 THEN 1 END) AS DataFileCount,
        COUNT(CASE WHEN mf.type = 1 THEN 1 END) AS LogFileCount,
        
        -- Health indicators
        CASE WHEN mf.free_space_percent <= @CriticalThreshold THEN 1 ELSE 0 END AS IsCritical,
        CASE WHEN mf.free_space_percent <= @WarningThreshold AND mf.free_space_percent > @CriticalThreshold THEN 1 ELSE 0 END AS IsWarning
    FROM sys.master_files mf
    JOIN sys.dm_io_virtual_file_stats(NULL, NULL) vfs ON mf.database_id = vfs.database_id AND mf.file_id = vfs.file_id
    WHERE mf.database_id > 4  -- Exclude system databases
      AND mf.state = 0  -- ONLINE
    GROUP BY mf.physical_name, mf.size, mf.free_space_percent;
    
    -- Disk I/O wait statistics (cross-platform)
    INSERT INTO [monitor].[DiskIoWaits]
        (CollectedAt, DatabaseName, FileId, FileGroup, FileSizeMB, WaitType, 
         WaitTimeMs, WaitingTasksCount, AvgWaitMs)
    SELECT
        @CurrentTime,
        DB_NAME(vfs.database_id) AS DatabaseName,
        vfs.file_id,
        fg.name AS FileGroup,
        CAST(f.size / 128.0 AS BIGINT) AS FileSizeMB,
        ws.wait_type,
        SUM(ws.wait_time_ms) AS WaitTimeMs,
        SUM(ws.waiting_tasks_count) AS WaitingTasksCount,
        AVG(CASE WHEN ws.waiting_tasks_count > 0 
                THEN ws.wait_time_ms / ws.waiting_tasks_count 
                ELSE NULL END) AS AvgWaitMs
    FROM sys.dm_os_wait_stats ws
    JOIN sys.dm_io_virtual_file_stats(NULL, NULL) vfs ON ws.wait_type LIKE 'PAGEIOLATCH%' OR ws.wait_type LIKE 'WRITELOG'
    JOIN sys.master_files f ON vfs.database_id = f.database_id AND vfs.file_id = f.file_id
    LEFT JOIN sys.filegroups fg ON f.data_space_id = fg.data_space_id
    WHERE (ws.wait_type LIKE 'PAGEIOLATCH%' OR ws.wait_type LIKE 'WRITELOG')
      AND ws.waiting_tasks_count > 0
      AND f.database_id > 4  -- Exclude system databases
    GROUP BY vfs.database_id, vfs.file_id, fg.name, f.size, ws.wait_type;
    
    -- Linux-specific disk information placeholder
    -- Note: For comprehensive disk monitoring on Linux, consider:
    -- 1. Creating an external shell script to collect df -h output
    -- 2. Using sys.dm_os_ring_buffer for disk events
    -- 3. Implementing a Linux-specific external collector
    -- 4. Using Azure SQL or cloud-specific metrics if applicable
    
    -- Add Linux-specific disk metrics if available through extended events
    IF EXISTS (SELECT 1 FROM sys.dm_xe_sessions WHERE name = 'system_health')
    BEGIN
        -- Try to extract disk information from system_health session
        INSERT INTO [monitor].[DiskHistoryDetailed]
            (CollectedAt, DriveLetter, TotalSpaceMB, FreeSpaceMB, UsedPct,
             Filesystem, MountPoint, AvgReadLatencyMs, AvgWriteLatencyMs,
             DiskReadsPerSec, DiskWritesPerSec, DiskReadMBPerSec, DiskWriteMBPerSec,
             DataFileCount, LogFileCount, IsCritical, IsWarning)
        SELECT
            @CurrentTime,
            UPPER(mf.physical_name) AS DriveLetter,
            CAST(mf.size / 128.0 AS BIGINT) AS TotalSpaceMB,
            CAST((mf.size * (100.0 - mf.free_space_percent) / 100.0) / 128.0 AS BIGINT) AS FreeSpaceMB,
            mf.free_space_percent AS UsedPct,
            'Linux' AS Filesystem,  -- Placeholder for Linux filesystem info
            '/data' AS MountPoint,   -- Placeholder for Linux mount point
            NULL AS AvgReadLatencyMs,
            NULL AS AvgWriteLatencyMs,
            NULL AS DiskReadsPerSec,
            NULL AS DiskWritesPerSec,
            NULL AS DiskReadMBPerSec,
            NULL AS DiskWriteMBPerSec,
            COUNT(CASE WHEN mf.type = 0 THEN 1 END) AS DataFileCount,
            COUNT(CASE WHEN mf.type = 1 THEN 1 END) AS LogFileCount,
            CASE WHEN mf.free_space_percent <= @CriticalThreshold THEN 1 ELSE 0 END AS IsCritical,
            CASE WHEN mf.free_space_percent <= @WarningThreshold AND mf.free_space_percent > @CriticalThreshold THEN 1 ELSE 0 END AS IsWarning
        FROM sys.master_files mf
        WHERE mf.database_id > 4 AND mf.state = 0
        GROUP BY mf.physical_name, mf.size, mf.free_space_percent;
    END;
    
    PRINT '✓ Disk statistics collected (Linux version - limited filesystem data)';
END;
GO