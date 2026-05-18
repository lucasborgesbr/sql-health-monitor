/*
    SQL Health Monitor - Memory Collector
    Collects memory metrics: PLE, buffer pool, memory grants.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_Memory]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PLE INT, @TotalMB BIGINT, @TargetMB BIGINT, @AvailMB BIGINT;
    DECLARE @BufferHitRatio DECIMAL(5,2), @GrantsPending INT;

    -- Page Life Expectancy
    SELECT @PLE = cntr_value
    FROM sys.dm_os_performance_counters
    WHERE object_name LIKE '%Buffer Manager%'
        AND counter_name = 'Page life expectancy';

    -- Total/Target Server Memory
    SELECT @TotalMB = cntr_value / 1024
    FROM sys.dm_os_performance_counters
    WHERE object_name LIKE '%Memory Manager%'
        AND counter_name = 'Total Server Memory (KB)';

    SELECT @TargetMB = cntr_value / 1024
    FROM sys.dm_os_performance_counters
    WHERE object_name LIKE '%Memory Manager%'
        AND counter_name = 'Target Server Memory (KB)';

    -- Available physical memory
    SELECT @AvailMB = available_physical_memory_kb / 1024
    FROM sys.dm_os_sys_memory;

    -- Buffer cache hit ratio
    SELECT @BufferHitRatio = 
        CAST((SELECT cntr_value FROM sys.dm_os_performance_counters 
              WHERE object_name LIKE '%Buffer Manager%' AND counter_name = 'Buffer cache hit ratio') AS DECIMAL(18,2))
        /
        NULLIF((SELECT cntr_value FROM sys.dm_os_performance_counters 
                WHERE object_name LIKE '%Buffer Manager%' AND counter_name = 'Buffer cache hit ratio base'), 0)
        * 100;

    -- Memory grants pending
    SELECT @GrantsPending = cntr_value
    FROM sys.dm_os_performance_counters
    WHERE object_name LIKE '%Memory Manager%'
        AND counter_name = 'Memory Grants Pending';

    INSERT INTO [monitor].[MemoryHistory] 
        (TotalServerMemoryMB, TargetServerMemoryMB, AvailableMemoryMB, 
         PageLifeExpectancy, BufferCacheHitRatio, MemoryGrantsPending)
    VALUES 
        (@TotalMB, @TargetMB, @AvailMB, @PLE, @BufferHitRatio, @GrantsPending);
END;
GO
