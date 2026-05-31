/*
    SQL Health Monitor - Waits Collector
    Collects wait statistics and system bottlenecks.
    
    Schedule: Every 2 minutes
    Compatibility: SQL Server 2016+
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_Waits]
AS
BEGIN
    SET NOCOUNT ON;

    -- Current wait statistics
    INSERT INTO [monitor].[WaitHistory]
        (SampleTime, WaitType, WaitTimeMS, WaitCount, 
         PercentTotalWaits, AverageWaitTimeMS, DatabaseName, 
         SessionID, QueryText)
    SELECT
        SYSDATETIME() AS SampleTime,
        ws.wait_type AS WaitType,
        ws.wait_time_ms AS WaitTimeMS,
        ws.waiting_tasks_count AS WaitCount,
        NULL AS PercentTotalWaits,  -- Calculated in application layer
        CASE WHEN ws.waiting_tasks_count > 0 THEN ws.wait_time_ms / ws.waiting_tasks_count ELSE 0 END AS AverageWaitTimeMS,
        NULL AS DatabaseName,
        NULL AS SessionID,
        NULL AS QueryText
    FROM sys.dm_os_wait_stats ws
    WHERE ws.wait_type NOT IN (
        -- Filter out common waits that aren't problematic
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
      AND ws.waiting_tasks_count > 0
    ORDER BY ws.wait_time_ms DESC;
    
    -- Wait statistics by database
    INSERT INTO [monitor].[WaitDatabaseHistory]
        (SampleTime, DatabaseName, WaitType, WaitTimeMS, WaitCount)
    SELECT
        SYSDATETIME() AS SampleTime,
        DB_NAME(qs.database_id) AS DatabaseName,
        ws.wait_type AS WaitType,
        ws.wait_time_ms AS WaitTimeMS,
        ws.waiting_tasks_count AS WaitCount
    FROM sys.dm_exec_requests qs
    INNER JOIN sys.dm_os_wait_stats ws ON qs.wait_type = ws.wait_type
    WHERE qs.database_id > 4  -- Exclude system databases
      AND qs.wait_type IS NOT NULL
      AND qs.wait_time_ms > 0;
END;
GO
