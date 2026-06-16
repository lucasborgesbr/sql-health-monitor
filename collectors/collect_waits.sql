/*
    SQL Health Monitor - Waits Collector
    Collects wait statistics and system bottlenecks.
    
    Schedule: Every 2 minutes
    Compatibility: SQL Server 2016+
*/

IF OBJECT_ID('[monitor].[usp_Collect_Waits]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_Waits] AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_Waits]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_Collect_Waits] AS SET NOCOUNT ON; PRINT ''Placeholder'';');
GO
ALTER PROCEDURE [monitor].[usp_Collect_Waits]
AS
BEGIN
    SET NOCOUNT ON;

    -- Schema columns: CollectedAt, WaitType, WaitingTasksCount, WaitTimeMs,
    --                 SignalWaitTimeMs, DeltaWaitTimeMs
    INSERT INTO [monitor].[WaitStatsHistory]
        (WaitType, WaitingTasksCount, WaitTimeMs, SignalWaitTimeMs, DeltaWaitTimeMs)
    SELECT
        ws.wait_type          AS WaitType,
        ws.waiting_tasks_count AS WaitingTasksCount,
        ws.wait_time_ms        AS WaitTimeMs,
        ws.signal_wait_time_ms AS SignalWaitTimeMs,
        NULL                   AS DeltaWaitTimeMs  -- Delta calculated externally or in reporting layer
    FROM sys.dm_os_wait_stats ws
    WHERE ws.wait_type NOT IN (
        'BROKER_EVENTHANDLER', 'BROKER_RECEIVE_WAITFOR', 'BROKER_TASK_STOP',
        'BROKER_TO_FLUSH', 'BROKER_TRANSMITTER', 'CHECKPOINT_QUEUE',
        'CHKPT', 'CLR_AUTO_EVENT', 'CLR_MANUAL_EVENT', 'CLR_SEMAPHORE',
        'DBMIRROR_DBM_MUTEX', 'DBMIRROR_EVENTS_QUEUE', 'DBMIRROR_SEND',
        'DBMIRROR_WORKER_QUEUE', 'DBMIRRORING_CMD', 'DIRTY_PAGE_POLL',
        'DISPATCHER_QUEUE_TASK_CALL', 'EXECSYNC', 'FSAGENT',
        'FT_IFTS_SCHEDULER_IDLE_WAIT', 'FT_IFTSHC_MUTEX', 'LOGMGR_QUEUE',
        'ONDEMAND_TASK_QUEUE', 'PREEMPTIVE_XE_BUFFER_TARGET', 'PREEMPTIVE_XE_DISPATCHER',
        'PREEMPTIVE_XE_GETTARGETSTATE', 'PREEMPTIVE_XE_SESSION_FLUSH',
        'PREEMPTIVE_XE_TARGET initialization', 'PRINT_ROLLBACK_PROGRESS',
        'QLALCHEMY_LOCK', 'QUERY_NOTIFICATION_SUBSCRIPTION',
        'QUERY_NOTIFICATION_TABLE_MGR', 'REPLICA_WRITES', 'SM object creation',
        'SLEEP_SYSTEMTASK', 'SLEEP_TASK', 'SOS_SCHEDULER_YIELD',
        'SQLTRACE_BUFFER_FLUSH', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
        'SQLTRACE_WAIT_ENTRIES', 'WAITFOR', 'WRITELOG', 'XE_BUFFERMGR_ALLPROCESSED_EVENT',
        'XE_DISPATCHER_JOIN', 'XE_DISPATCHER_WAIT', 'XE_LIVE_TARGET_EVENT',
        'XE_SESSION_CREATED', 'XE_SESSION_SHUTDOWN', 'XE_TIMER_EVENT',
        'XE_TIMER_DISPATCHER'
    )
      AND ws.wait_time_ms > 0
      AND ws.waiting_tasks_count > 0;

    -- Note: WaitHistory and WaitDatabaseHistory tables do not exist in the schema;
    -- the per-database breakdown insert has been removed.
END;
GO