/*
    SQL Health Monitor - CPU Collector
    Collects CPU usage statistics and top CPU consumers.
    
    Schedule: Every 2 minutes
    Compatibility: SQL Server 2016+
*/

IF OBJECT_ID('[monitor].[usp_Collect_CPU]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_CPU] AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_CPU]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_Collect_CPU] AS SET NOCOUNT ON; PRINT ''Placeholder'';');
GO
ALTER PROCEDURE [monitor].[usp_Collect_CPU]
AS
BEGIN
    SET NOCOUNT ON;

    -- Collect CPU utilization from ring buffer (SqlCpuPct, SystemCpuPct, IdleCpuPct)
    DECLARE @CpuRing TABLE (
        SqlCpuPct   TINYINT,
        SystemCpuPct TINYINT,
        IdleCpuPct  TINYINT
    );

    INSERT INTO @CpuRing (SqlCpuPct, SystemCpuPct, IdleCpuPct)
    SELECT TOP 1
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'TINYINT') AS SqlCpuPct,
        record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'TINYINT')         AS IdleCpuPct,
        100
            - record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'TINYINT')
            - record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'TINYINT')   AS SystemCpuPct
    FROM (
        SELECT CAST(record AS XML) AS record
        FROM sys.dm_os_ring_buffers
        WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
          AND record LIKE '%<SystemHealth>%'
    ) t
    ORDER BY record.value('(./Record/@id)[1]', 'BIGINT') DESC;

    INSERT INTO [monitor].[CpuHistory]
        (SqlCpuPct, SystemCpuPct, IdleCpuPct)
    SELECT
        ISNULL(SqlCpuPct, 0),
        ISNULL(SystemCpuPct, 0),
        ISNULL(IdleCpuPct, 0)
    FROM @CpuRing;

    -- Note: CollectedAt has a DEFAULT of SYSUTCDATETIME() on the table
END;
GO