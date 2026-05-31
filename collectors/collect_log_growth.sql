/*
    SQL Health Monitor - Log Growth Collector
    Collects transaction log growth and space usage.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_LogGrowth]
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [monitor].[LogGrowthHistory]
        (DatabaseName, LogSizeMB, LogSpaceUsedPercent, 
         LogBackupSizeMB, LogGrowthRateMB, LastBackupDate, 
         LastTruncationDate, VirtualLogFileCount)
    SELECT
        d.name AS DatabaseName,
        CAST((SELECT SUM(size) FROM sys.master_files mf 
              WHERE mf.database_id = d.database_id AND mf.type = 1) / 1024.0 / 1024.0 AS DECIMAL(10, 2)) AS LogSizeMB,
        NULL AS LogSpaceUsedPercent,  -- Requires sys.dm_db_log_space_usage
        NULL AS LogBackupSizeMB,
        NULL AS LogGrowthRateMB,
        NULL AS LastBackupDate,
        NULL AS LastTruncationDate,
        NULL AS VirtualLogFileCount
    FROM sys.databases d
    WHERE d.database_id > 4  -- Exclude system databases
      AND d.state_desc = 'ONLINE'
      AND d.is_in_standby = 0  -- Exclude secondary databases
      AND d.is_read_only = 0;  -- Exclude read-only databases
      
    -- Note: Real log space usage requires sys.dm_db_log_space_usage
    -- This is a simplified version - consider implementing full log monitoring
END;
GO
