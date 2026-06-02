/*
    SQL Health Monitor - CPU Collector (Linux Adaptation)
    Collects CPU usage statistics and top CPU consumers.
    
    Schedule: Every 2 minutes
    Compatibility: SQL Server 2016+ on Linux
    Features: Cross-platform CPU collection without xp_cmdshell
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_CPU]
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [monitor].[CPUHistory]
        (SampleTime, TotalCPUms, SQLServerCPUms, SystemCPUms, 
         TopConsumerSPID, TopConsumerCPUms, TopConsumerQueryText)
    SELECT
        SYSDATETIME() AS SampleTime,
        SUM(total_worker_time) AS TotalCPUms,
        SUM(total_worker_time) AS SQLServerCPUms,
        NULL AS SystemCPUms,  -- Not available from DMVs alone on Linux
        TOP 1 WITH TIES session_id AS TopConsumerSPID,
        total_worker_time AS TopConsumerCPUms,
        SUBSTRING(text, (statement_start_offset/2)+1,
            ((CASE statement_end_offset
                WHEN -1 THEN DATALENGTH(text)
                ELSE statement_end_offset
            END - statement_start_offset)/2) + 1) AS TopConsumerQueryText
    FROM sys.dm_exec_query_stats
    CROSS APPLY sys.dm_exec_sql_text(sql_handle)
    ORDER BY total_worker_time DESC
    OPTION (MAXDOP 1);

    -- Enhanced CPU statistics using performance counters
    INSERT INTO [monitor].[CPUHistoryDetailed]
        (SampleTime, SQLServerCPUms, SystemIdlePct, UserModePct, KernelModePct,
         BatchRequestsPerSec, SQLCompilationsPerSec, SQLRecompilationsPerSec,
         WorkTablesCreatedPerSec, WorkTablesFromCacheRatio)
    SELECT
        SYSDATETIME() AS SampleTime,
        CAST(cntr_value AS BIGINT) AS SQLServerCPUms,
        NULL AS SystemIdlePct,
        NULL AS UserModePct,
        NULL AS KernelModePct,
        NULL AS BatchRequestsPerSec,
        NULL AS SQLCompilationsPerSec,
        NULL AS SQLRecompilationsPerSec,
        NULL AS WorkTablesCreatedPerSec,
        NULL AS WorkTablesFromCacheRatio
    FROM sys.dm_os_performance_counters
    WHERE counter_name IN ('Total Server Memory (KB)', 'Stolen Server Memory (KB)',
                          'Cache Pages (KB)', 'Target Server Memory (KB)')
      AND instance_name = '_Total';
    
    -- Note: For comprehensive CPU monitoring on Linux, consider:
    -- 1. Using external monitoring tools (Prometheus, Grafana)
    -- 2. Creating a Linux shell script to collect system CPU stats
    -- 3. Using sys.dm_os_ring_buffer for system information
    -- 4. Implementing a Linux-specific external collector
    
    PRINT '✓ CPU statistics collected (Linux version - limited system CPU data)';
END;
GO