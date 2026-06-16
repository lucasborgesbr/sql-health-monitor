/*
    SQL Health Monitor - Memory Collector
    Collects memory usage and buffer pool statistics.
    
    Schedule: Every 2 minutes
    Compatibility: SQL Server 2016+
*/

IF OBJECT_ID('[monitor].[usp_Collect_Memory]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_Memory] AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_Memory]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_Collect_Memory] AS SET NOCOUNT ON; PRINT ''Placeholder'';');
GO
ALTER PROCEDURE [monitor].[usp_Collect_Memory]
AS
BEGIN
    SET NOCOUNT ON;

    -- Schema columns: TotalServerMemoryMB, TargetServerMemoryMB, AvailableMemoryMB,
    --                 PageLifeExpectancy, BufferCacheHitRatio, MemoryGrantsPending
    INSERT INTO [monitor].[MemoryHistory]
        (TotalServerMemoryMB, TargetServerMemoryMB, AvailableMemoryMB,
         PageLifeExpectancy, BufferCacheHitRatio, MemoryGrantsPending)
    SELECT
        CAST((SELECT TOP 1 cntr_value FROM sys.dm_os_performance_counters
              WHERE counter_name = 'Total Server Memory (KB)'
                AND object_name LIKE '%Memory Manager%') / 1024 AS BIGINT) AS TotalServerMemoryMB,
        CAST((SELECT TOP 1 cntr_value FROM sys.dm_os_performance_counters
              WHERE counter_name = 'Target Server Memory (KB)'
                AND object_name LIKE '%Memory Manager%') / 1024 AS BIGINT) AS TargetServerMemoryMB,
        CAST((SELECT TOP 1 cntr_value FROM sys.dm_os_performance_counters
              WHERE counter_name = 'Free Memory (KB)'
                AND object_name LIKE '%Memory Manager%') / 1024 AS BIGINT) AS AvailableMemoryMB,
        CAST(ISNULL((SELECT TOP 1 cntr_value FROM sys.dm_os_performance_counters
              WHERE counter_name = 'Page life expectancy'
                AND object_name LIKE '%Buffer Manager%'), 0) AS INT) AS PageLifeExpectancy,
        CAST(ISNULL(
            (SELECT TOP 1 cntr_value FROM sys.dm_os_performance_counters
              WHERE counter_name = 'Buffer cache hit ratio'
                AND object_name LIKE '%Buffer Manager%') * 100.0
            / NULLIF((SELECT TOP 1 cntr_value FROM sys.dm_os_performance_counters
              WHERE counter_name = 'Buffer cache hit ratio base'
                AND object_name LIKE '%Buffer Manager%'), 0)
        , 0) AS DECIMAL(5,2)) AS BufferCacheHitRatio,
        CAST(ISNULL((SELECT TOP 1 cntr_value FROM sys.dm_os_performance_counters
              WHERE counter_name = 'Memory Grants Pending'
                AND object_name LIKE '%Memory Manager%'), 0) AS INT) AS MemoryGrantsPending;

    -- Note: CollectedAt has a DEFAULT of SYSUTCDATETIME() on the table.
    -- MemoryGrantHistory table does not exist in the schema; that collection is omitted.
END;
GO