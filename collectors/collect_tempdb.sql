/*
    SQL Health Monitor - TempDB Collector
    Collects tempdb size, usage, and growth statistics.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_TempDB]
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [monitor].[TempDBHistory]
        (SampleTime, TotalSizeMB, DataSizeMB, LogSizeMB, 
         UserObjectsCount, SessionObjectsCount, TempDBSizeMB, 
         AutoGrowthCount, AutoGrowthSizeMB)
    SELECT
        SYSDATETIME() AS SampleTime,
        CAST((SELECT SUM(size) FROM sys.master_files mf 
              WHERE mf.database_id = DB_ID('tempdb')) / 1024.0 / 1024.0 AS DECIMAL(10, 2)) AS TotalSizeMB,
        CAST((SELECT SUM(size) FROM sys.master_files mf 
              WHERE mf.database_id = DB_ID('tempdb') AND mf.type = 0) / 1024.0 / 1024.0 AS DECIMAL(10, 2)) AS DataSizeMB,
        CAST((SELECT SUM(size) FROM sys.master_files mf 
              WHERE mf.database_id = DB_ID('tempdb') AND mf.type = 1) / 1024.0 / 1024.0 AS DECIMAL(10, 2)) AS LogSizeMB,
        (SELECT COUNT(*) FROM sys.dm_db_task_space_usage) AS UserObjectsCount,
        (SELECT COUNT(*) FROM sys.dm_db_session_space_usage) AS SessionObjectsCount,
        CAST((SELECT SUM(allocated_extent_page_count) FROM sys.dm_db_file_space_usage) * 8.0 / 1024.0 AS DECIMAL(10, 2)) AS TempDBSizeMB,
        NULL AS AutoGrowthCount,
        NULL AS AutoGrowthSizeMB
    WHERE EXISTS (SELECT 1 FROM sys.dm_os_performance_counters 
                 WHERE counter_name = 'TempDB Database Size (KB)');
    
    -- Note: Auto-growth statistics require extended events or SQL Trace
    -- This is a simplified version - consider implementing full tempdb monitoring
END;
GO
