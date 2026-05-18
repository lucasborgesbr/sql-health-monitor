/*
    SQL Health Monitor - CPU Collector
    Collects SQL Server and system CPU utilization from ring buffer.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_CPU]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ts BIGINT = (SELECT cpu_ticks / (cpu_ticks / ms_ticks) FROM sys.dm_os_sys_info);

    INSERT INTO [monitor].[CpuHistory] (SqlCpuPct, SystemCpuPct, IdleCpuPct)
    SELECT TOP 1
        SQLProcessUtilization AS SqlCpuPct,
        SystemIdle AS IdleCpuPct,
        100 - SystemIdle - SQLProcessUtilization AS SystemCpuPct
    FROM (
        SELECT
            record.value('(./Record/@id)[1]', 'int') AS record_id,
            record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemIdle,
            record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization,
            [timestamp]
        FROM (
            SELECT [timestamp], CONVERT(XML, record) AS record
            FROM sys.dm_os_ring_buffers
            WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
                AND record LIKE '%<SystemHealth>%'
        ) AS x
    ) AS y
    ORDER BY record_id DESC;
END;
GO
