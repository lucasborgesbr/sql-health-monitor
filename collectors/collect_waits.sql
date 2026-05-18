/*
    SQL Health Monitor - Wait Stats Collector (Delta)
    Collects wait statistics with delta calculation from previous snapshot.
    
    Schedule: Every 15 minutes
    Compatibility: SQL Server 2016+
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_WaitStats]
AS
BEGIN
    SET NOCOUNT ON;

    -- Benign waits to exclude (noise)
    DECLARE @ExcludeWaits TABLE (WaitType NVARCHAR(120));
    INSERT INTO @ExcludeWaits VALUES
        ('BROKER_EVENTHANDLER'), ('BROKER_RECEIVE_WAITFOR'), ('BROKER_TASK_STOP'),
        ('BROKER_TO_FLUSH'), ('BROKER_TRANSMITTER'), ('CHECKPOINT_QUEUE'),
        ('CHKPT'), ('CLR_AUTO_EVENT'), ('CLR_MANUAL_EVENT'), ('CLR_SEMAPHORE'),
        ('DBMIRROR_DBM_EVENT'), ('DBMIRROR_EVENTS_QUEUE'), ('DBMIRROR_WORKER_QUEUE'),
        ('DBMIRRORING_CMD'), ('DIRTY_PAGE_POLL'), ('DISPATCHER_QUEUE_SEMAPHORE'),
        ('EXECSYNC'), ('FSAGENT'), ('FT_IFTS_SCHEDULER_IDLE_WAIT'),
        ('FT_IFTSHC_MUTEX'), ('HADR_CLUSAPI_CALL'), ('HADR_FILESTREAM_IOMGR_IOCOMPLETION'),
        ('HADR_LOGCAPTURE_WAIT'), ('HADR_NOTIFICATION_DEQUEUE'), ('HADR_TIMER_TASK'),
        ('HADR_WORK_QUEUE'), ('KSOURCE_WAKEUP'), ('LAZYWRITER_SLEEP'),
        ('LOGMGR_QUEUE'), ('MEMORY_ALLOCATION_EXT'), ('ONDEMAND_TASK_QUEUE'),
        ('PARALLEL_REDO_DRAIN_WORKER'), ('PARALLEL_REDO_LOG_CACHE'),
        ('PARALLEL_REDO_TRAN_LIST'), ('PARALLEL_REDO_WORKER_SYNC'),
        ('PARALLEL_REDO_WORKER_WAIT_WORK'), ('PREEMPTIVE_OS_FLUSHFILEBUFFERS'),
        ('PREEMPTIVE_XE_GETTARGETSTATE'), ('PVS_PREALLOCATE'),
        ('PWAIT_ALL_COMPONENTS_INITIALIZED'), ('PWAIT_DIRECTLOGCONSUMER_GETNEXT'),
        ('QDS_PERSIST_TASK_MAIN_LOOP_SLEEP'), ('QDS_ASYNC_QUEUE'),
        ('QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP'),
        ('QDS_SHUTDOWN_QUEUE'), ('REDO_THREAD_PENDING_WORK'),
        ('REQUEST_FOR_DEADLOCK_SEARCH'), ('RESOURCE_QUEUE'),
        ('SERVER_IDLE_CHECK'), ('SLEEP_BPOOL_FLUSH'), ('SLEEP_DBSTARTUP'),
        ('SLEEP_DCOMSTARTUP'), ('SLEEP_MASTERDBREADY'), ('SLEEP_MASTERMDREADY'),
        ('SLEEP_MASTERUPGRADED'), ('SLEEP_MSDBSTARTUP'), ('SLEEP_SYSTEMTASK'),
        ('SLEEP_TASK'), ('SLEEP_TEMPDBSTARTUP'), ('SNI_HTTP_ACCEPT'),
        ('SOS_WORK_DISPATCHER'), ('SP_SERVER_DIAGNOSTICS_SLEEP'),
        ('SQLTRACE_BUFFER_FLUSH'), ('SQLTRACE_INCREMENTAL_FLUSH_SLEEP'),
        ('SQLTRACE_WAIT_ENTRIES'), ('VDI_CLIENT_OTHER'),
        ('WAIT_FOR_RESULTS'), ('WAITFOR'), ('WAITFOR_TASKSHUTDOWN'),
        ('WAIT_XTP_CKPT_CLOSE'), ('WAIT_XTP_HOST_WAIT'),
        ('WAIT_XTP_OFFLINE_CKPT_NEW_LOG'), ('WAIT_XTP_RECOVERY'),
        ('XE_BUFFERMGR_ALLPROCESSED_EVENT'), ('XE_DISPATCHER_JOIN'),
        ('XE_DISPATCHER_WAIT'), ('XE_TIMER_EVENT');

    -- Get current snapshot with delta from last collection
    ;WITH CurrentWaits AS (
        SELECT
            wait_type AS WaitType,
            waiting_tasks_count AS WaitingTasksCount,
            wait_time_ms AS WaitTimeMs,
            signal_wait_time_ms AS SignalWaitTimeMs
        FROM sys.dm_os_wait_stats
        WHERE wait_type NOT IN (SELECT WaitType FROM @ExcludeWaits)
            AND waiting_tasks_count > 0
    ),
    LastSnapshot AS (
        SELECT WaitType, WaitTimeMs
        FROM [monitor].[WaitStatsHistory]
        WHERE CollectedAt = (
            SELECT MAX(CollectedAt) FROM [monitor].[WaitStatsHistory]
        )
    )
    INSERT INTO [monitor].[WaitStatsHistory]
        (WaitType, WaitingTasksCount, WaitTimeMs, SignalWaitTimeMs, DeltaWaitTimeMs)
    SELECT TOP 20
        cw.WaitType,
        cw.WaitingTasksCount,
        cw.WaitTimeMs,
        cw.SignalWaitTimeMs,
        CASE WHEN ls.WaitTimeMs IS NOT NULL 
             THEN cw.WaitTimeMs - ls.WaitTimeMs 
             ELSE NULL END AS DeltaWaitTimeMs
    FROM CurrentWaits cw
    LEFT JOIN LastSnapshot ls ON ls.WaitType = cw.WaitType
    ORDER BY ISNULL(cw.WaitTimeMs - ls.WaitTimeMs, cw.WaitTimeMs) DESC;
END;
GO
