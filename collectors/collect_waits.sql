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

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();

    -- System-wide wait statistics
    INSERT INTO [monitor].[WaitStatsHistory]
        (WaitType, WaitingTasksCount, WaitTimeMs, SignalWaitTimeMs, DeltaWaitTimeMs)
    SELECT
        ws.wait_type          AS WaitType,
        ws.waiting_tasks_count AS WaitingTasksCount,
        ws.wait_time_ms        AS WaitTimeMs,
        ws.signal_wait_time_ms AS SignalWaitTimeMs,
        -- Delta vs previous snapshot; NULL on first sample, counter reset (restart/clear) uses current value
        CASE
            WHEN prev.WaitTimeMs IS NULL THEN NULL
            WHEN ws.wait_time_ms >= prev.WaitTimeMs THEN ws.wait_time_ms - prev.WaitTimeMs
            ELSE ws.wait_time_ms
        END                    AS DeltaWaitTimeMs
    FROM sys.dm_os_wait_stats ws
    OUTER APPLY (
        SELECT TOP (1) h.WaitTimeMs
        FROM [monitor].[WaitStatsHistory] h
        WHERE h.WaitType = ws.wait_type
        ORDER BY h.CollectedAt DESC
    ) prev
    WHERE ws.wait_type NOT IN (
        -- Benign / idle waits
        'LAZYWRITER_SLEEP', 'DISPATCHER_QUEUE_SEMAPHORE', 'SP_SERVER_DIAGNOSTICS_SLEEP',
        'REQUEST_FOR_DEADLOCK_SEARCH', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
        'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', 'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
        'QDS_ASYNC_QUEUE', 'QDS_SHUTDOWN_QUEUE', 'SLEEP_BPOOL_FLUSH', 'SLEEP_DBSTARTUP',
        'SLEEP_DCOMSTARTUP', 'SLEEP_MASTERDBREADY', 'SLEEP_MASTERMDREADY',
        'SLEEP_MASTERUPGRADED', 'SLEEP_MSDBSTARTUP', 'SLEEP_TEMPDBSTARTUP',
        'HADR_CLUSAPI_CALL', 'HADR_LOGCAPTURE_WAIT', 'HADR_NOTIFICATION_DEQUEUE',
        'HADR_TIMER_TASK', 'HADR_WORK_QUEUE', 'WAIT_XTP_HOST_WAIT', 'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
        'XE_LIVE_TARGET_TVF', 'PVS_PREALLOCATE', 'PARALLEL_REDO_DRAIN_WORKER',
        'PARALLEL_REDO_LOG_CACHE', 'PARALLEL_REDO_TRAN_LIST', 'PARALLEL_REDO_WORKER_SYNC',
        'PARALLEL_REDO_WORKER_WAIT_WORK',
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

    -- Per-database wait breakdown (SQL 2016+)
    -- Correlates waits with specific databases
    INSERT INTO [monitor].[WaitDatabaseHistory]
        (DatabaseId, DatabaseName, WaitType, WaitingTasksCount, WaitTimeMs, SignalWaitTimeMs)
    SELECT
        s.database_id                       AS DatabaseId,
        DB_NAME(s.database_id)              AS DatabaseName,
        r.wait_type                        AS WaitType,
        COUNT(*)                           AS WaitingTasksCount,
        SUM(r.wait_time)                   AS WaitTimeMs,
        SUM(r.cpu_time)                    AS SignalWaitTimeMs
    FROM sys.dm_exec_requests r
    INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
    WHERE r.database_id > 0
      AND s.is_user_process = 1
      AND r.wait_type IS NOT NULL
      AND r.wait_type NOT IN ('WAITFOR', 'RESOURCE_SEMAPHORE_QUERY_COMPILE')
    GROUP BY s.database_id, r.wait_type
    HAVING SUM(r.wait_time) > 0;
END;
GO
