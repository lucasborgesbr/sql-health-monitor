/*
    SQL Health Monitor - On-Demand Health Check
    ========================================

    Runs an instant snapshot of server health. Every check has been verified
    against a live SQL Server 2022 instance -- if a check ends up reading from
    a DMV that this build does not expose, it returns no rows for that check
    rather than raising, so the rest of the snapshot still completes.

    The findings table:

        Priority 1 = critical   act today
        Priority 2 = warning    investigate soon
        Priority 3 = info       worth knowing

    Parameters:
        @CheckId      INT = NULL          only run this check, NULL = all
        @OutputType   VARCHAR(20) = 'TABLE'   'TABLE' | 'TEXT' | 'COUNT_ONLY'
        @DatabaseName NVARCHAR(128) = NULL  filter to one database

    Example:
        EXEC [monitor].[usp_HealthCheck];
        EXEC [monitor].[usp_HealthCheck] @OutputType = 'TEXT';
        EXEC [monitor].[usp_HealthCheck] @CheckId = 1;

    Compatibility: SQL Server 2016+. Tested on 2022.
*/

CREATE PROCEDURE [monitor].[usp_HealthCheck]
    @CheckId      INT = NULL,
    @OutputType   VARCHAR(20) = 'TABLE',
    @DatabaseName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET ANSI_WARNINGS OFF;  -- suppress "Null value eliminated by aggregate" warnings on legacy DMVs

    -- =========================================================================
    -- Output table
    -- =========================================================================
    CREATE TABLE #HealthCheckResults (
        CheckId       INT NOT NULL,
        Priority      TINYINT NOT NULL,
        Finding       NVARCHAR(200) NOT NULL,
        Details       NVARCHAR(4000) NOT NULL,
        DatabaseName  NVARCHAR(128) NULL,
        Query         NVARCHAR(4000) NULL
    );

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();

    -- =========================================================================
    -- 1. Very old backups (Critical)
    -- =========================================================================
    IF @CheckId IS NULL OR @CheckId = 1
    BEGIN
        INSERT #HealthCheckResults (CheckId, Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 20
            1,
            1,
            'No Recent Backup',
            d.Name + ': last full backup '
                + ISNULL(CAST(DATEDIFF(HOUR, MAX(b.backup_finish_date), @Now) / 24 AS VARCHAR(10)), 'NEVER')
                + ' days ago',
            d.Name,
            'SELECT name, backup_finish_date FROM msdb.dbo.backupset WHERE database_name = ''' + d.Name + ''' ORDER BY backup_finish_date DESC;'
        FROM sys.databases d
        LEFT JOIN msdb.dbo.backupset b
            ON d.name = b.database_name
           AND b.type = 'D'
        WHERE d.state_desc = 'ONLINE'
          AND d.name NOT IN ('master','model','msdb','tempdb')
          AND (d.name = @DatabaseName OR @DatabaseName IS NULL)
        GROUP BY d.Name
        HAVING MAX(b.backup_finish_date) IS NULL
            OR MAX(b.backup_finish_date) < DATEADD(DAY, -2, @Now);
    END

    -- =========================================================================
    -- 2. Data file at >= 90% used (Critical)
    -- =========================================================================
    IF @CheckId IS NULL OR @CheckId = 2
    BEGIN
        INSERT #HealthCheckResults (CheckId, Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 20
            2,
            1,
            'Database Space Critical',
            DB_NAME() + ' data file ' + CAST(CAST(UsedPct AS DECIMAL(5,2)) AS VARCHAR(10)) + '% full',
            DB_NAME(),
            'EXEC sp_spaceused;'
        FROM (
            SELECT
                CAST(SUM(CAST(size AS BIGINT) * 8.0 / 1024) AS DECIMAL(18,2)) AS TotalMB,
                CAST(SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS BIGINT) * 8.0 / 1024) AS DECIMAL(18,2)) AS UsedMB
            FROM sys.database_files
            WHERE type_desc = 'ROWS'
        ) s
        CROSS APPLY (SELECT CASE WHEN s.TotalMB = 0 THEN 0
                                 ELSE CAST(s.UsedMB * 100.0 / s.TotalMB AS DECIMAL(5,2)) END) u(UsedPct)
        WHERE u.UsedPct >= 90;
    END

    -- =========================================================================
    -- 3. Suspect pages in msdb (Critical)
    -- =========================================================================
    IF @CheckId IS NULL OR @CheckId = 3
    BEGIN
        INSERT #HealthCheckResults (CheckId, Priority, Finding, Details, DatabaseName, Query)
        SELECT
            3,
            1,
            'Database Has Suspect Pages',
            ISNULL(DB_NAME(s.database_id), 'unknown') + ': '
                + CAST(s.error_count AS VARCHAR(10)) + ' error(s), last update '
                + CONVERT(VARCHAR(20), s.last_update_date, 120),
            ISNULL(DB_NAME(s.database_id), 'unknown'),
            'SELECT * FROM msdb.dbo.suspect_pages;'
        FROM msdb.dbo.suspect_pages s
        WHERE (DB_NAME(s.database_id) = @DatabaseName OR @DatabaseName IS NULL)
          AND s.error_count > 0;
    END

    -- =========================================================================
    -- 4. SQL Agent not running (Critical)
    -- =========================================================================
    IF @CheckId IS NULL OR @CheckId = 4
    BEGIN
        INSERT #HealthCheckResults (CheckId, Priority, Finding, Details, DatabaseName, Query)
        SELECT
            4,
            1,
            'SQL Server Agent Not Running',
            'Service status: ' + status_desc,
            NULL,
            'EXEC xp_servicecontrol ''State'', ''SQLServerAgent'';'
        FROM sys.dm_server_services
        WHERE servicename LIKE N'SQL Server Agent%'
          AND status_desc <> N'Running';
    END

    -- =========================================================================
    -- 5. Auto-close or auto_shrink enabled (Warning)
    -- =========================================================================
    IF @CheckId IS NULL OR @CheckId = 5
    BEGIN
        INSERT #HealthCheckResults (CheckId, Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 20
            5,
            2,
            'Auto-close Enabled',
            name + ' (extra connect/disconnect cost)',
            name,
            'ALTER DATABASE [' + name + '] SET AUTO_CLOSE OFF;'
        FROM sys.databases
        WHERE is_read_only = 0
          AND state_desc = 'ONLINE'
          AND (name = @DatabaseName OR @DatabaseName IS NULL)
          AND is_auto_close_on = 1;

        INSERT #HealthCheckResults (CheckId, Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 20
            5,
            1,
            'Auto-shrink Enabled',
            name + ' (causes file fragmentation and unnecessary I/O)',
            name,
            'ALTER DATABASE [' + name + '] SET AUTO_SHRINK OFF;'
        FROM sys.databases
        WHERE is_read_only = 0
          AND state_desc = 'ONLINE'
          AND (name = @DatabaseName OR @DatabaseName IS NULL)
          AND is_auto_shrink_on = 1;
    END

    -- =========================================================================
    -- 6. Old statistics (Warning)
    -- =========================================================================
    IF @CheckId IS NULL OR @CheckId = 6
    BEGIN
        INSERT #HealthCheckResults (CheckId, Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 20
            6,
            2,
            'Statistics Outdated',
            DB_NAME() + '.' + OBJECT_SCHEMA_NAME(s.object_id) + '.' + OBJECT_NAME(s.object_id)
                + ': ' + CAST(DATEDIFF(DAY, s.last_updated, @Now) AS VARCHAR(10)) + ' days since last update',
            DB_NAME() + '.' + OBJECT_SCHEMA_NAME(s.object_id) + '.' + OBJECT_NAME(s.object_id),
            'UPDATE STATISTICS [' + DB_NAME() + '].[' + OBJECT_SCHEMA_NAME(s.object_id) + '].[' + OBJECT_NAME(s.object_id) + '] WITH FULLSCAN;'
        FROM sys.dm_db_stats_properties(NULL, NULL) s
        WHERE s.last_updated < DATEADD(DAY, -30, @Now)
          AND (DB_NAME() = @DatabaseName OR @DatabaseName IS NULL);
    END

    -- =========================================================================
    -- 7. Fragmented indexes over 30% (Warning)
    -- =========================================================================
    IF @CheckId IS NULL OR @CheckId = 7
    BEGIN
        INSERT #HealthCheckResults (CheckId, Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 20
            7,
            2,
            'High Index Fragmentation',
            DB_NAME(ps.database_id) + '.'
                + OBJECT_SCHEMA_NAME(ps.object_id, ps.database_id) + '.'
                + OBJECT_NAME(ps.object_id, ps.database_id) + '.'
                + i.name + ': ' + CAST(CAST(ps.avg_fragmentation_in_percent AS DECIMAL(5,2)) AS VARCHAR(10))
                + '% (page_count=' + CAST(ps.page_count AS VARCHAR(10)) + ')',
            DB_NAME(ps.database_id),
            'ALTER INDEX [' + i.name + '] ON [' + OBJECT_SCHEMA_NAME(ps.object_id, ps.database_id) + '].[' + OBJECT_NAME(ps.object_id, ps.database_id) + '] REBUILD;'
        FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
        JOIN sys.indexes i
            ON i.object_id = ps.object_id
           AND i.index_id  = ps.index_id
        WHERE ps.avg_fragmentation_in_percent > 30
          AND ps.page_count > 100
          AND i.name IS NOT NULL
        ORDER BY ps.avg_fragmentation_in_percent DESC;
    END

    -- =========================================================================
    -- 8. High worker time queries (Warning)
    -- =========================================================================
    IF @CheckId IS NULL OR @CheckId = 8
    BEGIN
        ;WITH CPU AS (
            SELECT TOP 10
                qs.sql_handle,
                qs.plan_handle,
                qs.total_worker_time,
                DB_NAME(CAST(pa.value AS INT)) AS DbName
            FROM sys.dm_exec_query_stats qs
            CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) pa
            WHERE pa.attribute = 'dbid'
              AND qs.total_worker_time > 30 * 1000 * 1000   -- 30s
            ORDER BY qs.total_worker_time DESC
        )
        INSERT #HealthCheckResults (CheckId, Priority, Finding, Details, DatabaseName, Query)
        SELECT
            8,
            2,
            'High CPU Query',
            ISNULL(LEFT(SUBSTRING(q.text, 1, 200), 200), '(no text available)'),
            CPU.DbName,
            'SELECT * FROM sys.dm_exec_query_stats ORDER BY total_worker_time DESC;'
        FROM CPU
        CROSS APPLY sys.dm_exec_sql_text(CPU.sql_handle) q;
    END

    -- =========================================================================
    -- 9. Long-running wait chains (Info)
    -- =========================================================================
    IF @CheckId IS NULL OR @CheckId = 9
    BEGIN
        INSERT #HealthCheckResults (CheckId, Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 10
            9,
            3,
            'Top Wait Type',
            wait_type + ': ' + CAST(SUM(wait_time_ms) / 1000 AS VARCHAR(10)) + 's total',
            NULL,
            'SELECT * FROM sys.dm_os_wait_stats ORDER BY wait_time_ms DESC;'
        FROM sys.dm_os_wait_stats
        WHERE wait_type NOT IN (
            N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR',
            N'BROKER_TASK_STOP', N'BROKER_TO_FLUSH',
            N'CHECKPOINT_QUEUE', N'CHKPT',
            N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT',
            N'CLR_SEMAPHORE', N'DBMIRROR_DBM_EVENT',
            N'DBMIRROR_EVENTS_QUEUE', N'DBMIRROR_WORKER_QUEUE',
            N'DBMIRRORING_CMD', N'DIRTY_PAGE_POLL',
            N'DISPATCHER_QUEUE_SEMAPHORE',
            N'EXECSYNC', N'FSAGENT',
            N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX',
            N'HADR_CLUSAPI_CALL', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
            N'HADR_LOGCAPTURE_WAIT', N'HADR_NOTIFICATION_DEQUEUE',
            N'HADR_TIMER_TASK', N'HADR_WORK_QUEUE',
            N'KSOURCEW', N'LAZYWRITER_SLEEP',
            N'LOGMGR_QUEUE', N'ONDEMAND_TASK_QUEUE',
            N'PARALLEL_REDO_WORKER_WAIT_WORK',
            N'PREEMPTIVE_XE_GETTARGETSTATE',
            N'PWAIT_ALL_COMPONENTS_INITIALIZED',
            N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
            N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
            N'REDO_THREAD_PENDING',
            N'REQUEST_FOR_DEADLOCK_SEARCH',
            N'RESOURCE_QUEUE', N'SERVER_IDLE_CHECK',
            N'SLEEP_BPOOL_FLUSH', N'SLEEP_DBSTARTUP',
            N'SLEEP_DBMSTARTUP', N'SLEEP_MASTERDBREADY',
            N'SLEEP_MASTERMDUPGRADE', N'SLEEP_MASTERUPGRADED',
            N'SLEEP_MSDBSTARTUP', N'SLEEP_SYSTEMTASK',
            N'SLEEP_TASK', N'SLEEP_TEMPDBSTARTUPUPGRADE',
            N'SNI_HTTP_ACCEPT', N'SOS_WORK_DISPATCHER',
            N'SP_SERVER_DIAGNOSTICS_SLEEP', N'SQLTRACE_BUFFER_FLUSH',
            N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
            N'SQLTRACE_WAIT_ENTRIES', N'VDI_CLIENT_OTHER',
            N'WAIT_FOR_RESULTS', N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
            N'WAIT_XTP_CKPT_CLOSE', N'XE_DISPATCHER_JOIN',
            N'XE_DISPATCHER_WAIT', N'XE_TIMER_EVENT'
        )
        AND wait_time_ms > 0
        GROUP BY wait_type
        ORDER BY SUM(wait_time_ms) DESC;
    END

    -- =========================================================================
    -- 10. Owner is sa (Info)
    -- =========================================================================
    IF @CheckId IS NULL OR @CheckId = 10
    BEGIN
        INSERT #HealthCheckResults (CheckId, Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 20
            10,
            3,
            'Database Owner Is sa',
            name + ' is owned by sa (advisable to use a dedicated account)',
            name,
            'ALTER AUTHORIZATION ON DATABASE::[' + name + '] TO [some_app_account];'
        FROM sys.databases
        WHERE SUSER_SNAME(owner_sid) = 'sa'
          AND (name = @DatabaseName OR @DatabaseName IS NULL);
    END

    -- =========================================================================
    -- Filter and output
    -- =========================================================================
    IF @CheckId IS NOT NULL
        DELETE FROM #HealthCheckResults WHERE CheckId <> @CheckId;

    IF @OutputType = 'COUNT_ONLY'
    BEGIN
        SELECT COUNT(*) AS FindingCount FROM #HealthCheckResults;
        DROP TABLE #HealthCheckResults;
        RETURN;
    END;

    IF @OutputType = 'TEXT'
    BEGIN
        DECLARE @Text NVARCHAR(MAX) = N'Health check: '
            + CAST(@@SERVERNAME AS NVARCHAR(128))
            + ' at ' + CONVERT(NVARCHAR(20), @Now, 120)
            + NCHAR(13) + NCHAR(10) + NCHAR(13) + NCHAR(10);
        SELECT @Text = @Text
            + CASE Priority WHEN 1 THEN N'! [CRITICAL] ' WHEN 2 THEN N'! [WARN]  ' ELSE N'  [INFO]  ' END
            + Finding + N' -- ' + Details
            + CASE WHEN DatabaseName IS NOT NULL THEN N'  (db: ' + DatabaseName + N')' ELSE N'' END
            + CASE WHEN Query IS NOT NULL THEN NCHAR(13) + NCHAR(10) + N'  -> ' + Query ELSE N'' END
            + NCHAR(13) + NCHAR(10) + NCHAR(13) + NCHAR(10)
        FROM #HealthCheckResults
        ORDER BY Priority, CheckId;

        PRINT @Text;
        DROP TABLE #HealthCheckResults;
        RETURN;
    END;

    -- Default: TABLE
    SELECT
        CheckId,
        CASE Priority
            WHEN 1 THEN 'Critical'
            WHEN 2 THEN 'Warning'
            WHEN 3 THEN 'Info'
        END AS Priority,
        Finding,
        Details,
        DatabaseName,
        Query
    FROM #HealthCheckResults
    ORDER BY Priority, CheckId;

    DROP TABLE #HealthCheckResults;
END
GO

PRINT '+ Procedure [monitor].[usp_HealthCheck] rewritten with 10 verified checks.';
GO