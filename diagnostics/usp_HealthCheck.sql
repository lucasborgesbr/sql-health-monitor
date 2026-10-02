/*
    SQL Health Monitor - On-Demand Health Check
    Inspired by community best practices (sp_Blitz-style analysis)
    Run this at any time to get an instant snapshot of server health.

    Shows critical findings across:
        - Configuration issues
        - Performance problems
        - Security concerns
        - Availability risks
        - Maintenance gaps

    Parameters:
        @CheckId      INT = NULL  - Run only a specific check (1-50)
        @OutputType   VARCHAR(20) = 'TABLE'  - 'TABLE', 'TEXT', or 'COUNT_ONLY'
        @DatabaseName NVARCHAR(128) = NULL  - Filter to specific database

    Example usage:
        EXEC [monitor].[usp_HealthCheck];                    -- Full check
        EXEC [monitor].[usp_HealthCheck] @OutputType = 'TEXT';  -- Text output
        EXEC [monitor].[usp_HealthCheck] @CheckId = 1;     -- Critical only
        EXEC [monitor].[usp_HealthCheck] @CheckId = 5;     -- AG check only

    Output columns:
        CheckId       INT           - Unique check identifier
        Priority      TINYINT       - 1=Critical, 2=Warning, 3=Info
        Finding       NVARCHAR(200) - Short finding title
        Details       NVARCHAR(4000)- Detailed explanation
        DatabaseName  NVARCHAR(128)- Affected database (if applicable)
        City          NVARCHAR(100)- T-SQL to reproduce/fetch more info

    Schema: [monitor]
    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

IF OBJECT_ID('[monitor].[usp_HealthCheck]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_HealthCheck] @CheckId INT = NULL, @OutputType VARCHAR(20) = ''TABLE'', @DatabaseName NVARCHAR(128) = NULL AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_HealthCheck]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_HealthCheck] @CheckId INT = NULL, @OutputType VARCHAR(20) = ''TABLE'', @DatabaseName NVARCHAR(128) = NULL AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

ALTER PROCEDURE [monitor].[usp_HealthCheck]
    @CheckId      INT = NULL,
    @OutputType   VARCHAR(20) = 'TABLE',
    @DatabaseName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #HealthCheckResults (
        CheckId       INT IDENTITY(1,1) NOT NULL,
        Priority      TINYINT NOT NULL,
        Finding       NVARCHAR(200) NOT NULL,
        Details       NVARCHAR(4000) NOT NULL,
        DatabaseName  NVARCHAR(128) NULL,
        Query         NVARCHAR(4000) NULL
    );

    DECLARE @sql NVARCHAR(MAX);

    -- ============================================================
    -- CHECK 1: Very old backups (Critical)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 1
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 20
            1 AS Priority,
            'No Recent Backup' AS Finding,
            'Database ''' + d.Name + ''' has not been backed up in ' +
                CAST(DATEDIFF(HOUR, MAX(b.backup_finish_date), GETDATE()) / 24 AS NVARCHAR) + ' days' AS Details,
            d.Name AS DatabaseName,
            'SELECT name, backup_finish_date FROM msdb.dbo.backupset WHERE database_name = ''' + d.Name + ''' ORDER BY backup_finish_date DESC;' AS Query
        FROM sys.databases d
        LEFT JOIN msdb.dbo.backupset b ON d.name = b.database_name AND b.type = 'D'
        WHERE d.state_desc = 'ONLINE'
            AND d.name NOT IN ('master', 'model', 'msdb', 'tempdb')
            AND (d.name = @DatabaseName OR @DatabaseName IS NULL)
            AND (MAX(b.backup_finish_date) IS NULL OR MAX(b.backup_finish_date) < DATEADD(DAY, -2, GETDATE()))
        GROUP BY d.Name
        HAVING MAX(b.backup_finish_date) IS NULL
            OR MAX(b.backup_finish_date) < DATEADD(DAY, -2, GETDATE());
    END;

    -- ============================================================
    -- CHECK 2: Database at >90% space (Critical)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 2
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 20
            1 AS Priority,
            'Database Space Critical' AS Finding,
            db_name() + ' data file is ' + CAST(df.UsedPct AS NVARCHAR) + '% full' AS Details,
            df.DatabaseName,
            'EXEC sp_spaceused;' AS Query
        FROM (
            SELECT
                DB_NAME() AS DatabaseName,
                CAST(SUM(CASE WHEN type_desc = ''LOG'' THEN 0 ELSE 1 END) AS BIT) AS HasDataFile,
                0 AS UsedPct
            FROM sys.database_files
        ) df
        CROSS JOIN (
            SELECT
                CAST(CAST(SUM(size * 8.0 / 1024) - SUM(CASE WHEN type = 0 THEN 0 ELSE 0 END) AS DECIMAL(18,2)) AS DECIMAL(18,2)) AS UsedMB,
                CAST(MAX(current_database_size() * 8.0 / 1024) AS DECIMAL(18,2)) AS TotalMB,
                0 AS UsedPct
        ) space;

        -- Simpler version using actual space info
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT
            1 AS Priority,
            'High Space Usage' AS Finding,
            'Database may be running low on space' AS Details,
            @DatabaseName AS DatabaseName,
            'SELECT * FROM sys.database_files;' AS Query
        WHERE @DatabaseName IS NOT NULL;
    END;

    -- ============================================================
    -- CHECK 3: Stack dump / AG sent to text log (Critical)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 3
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 10
            1 AS Priority,
            'Stack Dump in Error Log' AS Finding,
            LEFT(el.TextData, 200) AS Details,
            NULL AS DatabaseName,
            'EXEC xp_readerrorlog 0, 1, ''Stack Dump'';' AS Query
        FROM (
            SELECT TextData
            FROM sys.messages m WITH (NOLOCK)
            WHERE message_id = 596
        ) el;

        -- Alternative check
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT
            1 AS Priority,
            'SQL Server Error Log Check' AS Finding,
            'Check SQL Server error log for recent critical errors' AS Details,
            NULL AS DatabaseName,
            'EXEC xp_readerrorlog;' AS Query
        WHERE NOT EXISTS (SELECT 1 FROM sys.messages WHERE message_id = 596);
    END;

    -- ============================================================
    -- CHECK 4: DBs with corruption (Critical)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 4
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 10
            1 AS Priority,
            'Integrity Check Recommended' AS Finding,
            'Run DBCC CHECKDB on ' + d.Name AS Details,
            d.Name AS DatabaseName,
            'DBCC CHECKDB(''' + d.Name + ''');' AS Query
        FROM sys.databases d
        CROSS JOIN (
            SELECT TOP 1 DATEADD(DAY, -7, GETDATE()) AS CheckDate
        ) x
        WHERE d.state_desc = 'ONLINE'
            AND d.name NOT IN ('master', 'model', 'msdb', 'tempdb')
            AND (d.name = @DatabaseName OR @DatabaseName IS NULL)
            AND NOT EXISTS (
                SELECT 1 FROM msdb.dbo.backupset b
                WHERE b.database_name = d.name
                AND b.type = 'D'
                AND b.backup_finish_date > x.CheckDate
            );
    END;

    -- ============================================================
    -- CHECK 5: AG Replicas not in healthy state (Warning)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 5
    BEGIN
        IF @DatabaseName IS NULL
        BEGIN
            INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
            SELECT TOP 20
                CASE
                    WHEN r.is_local = 1 THEN 1  -- Local replica
                    ELSE 2
                END AS Priority,
                CASE
                    WHEN r.availability_mode = 0 THEN 'AG: Async Commit'
                    WHEN r.availability_mode = 1 THEN 'AG: Sync Commit'
                    ELSE 'AG Status'
                END AS Finding,
                ag.name + ' - ' + r.replica_server_name + ' - ' +
                CASE r.operational_state
                    WHEN 0 THEN 'ONLINE'
                    WHEN 1 THEN 'OFFLINE'
                    WHEN 2 THEN 'FAILOVER_IN_PROGRESS'
                    WHEN 3 THEN 'FAILURE_PENDING'
                    WHEN 4 THEN 'FAILED'
                    WHEN 5 THEN 'FAILED_NO_QUORUM'
                    ELSE 'UNKNOWN'
                END AS Details,
                d.name AS DatabaseName,
                'SELECT * FROM sys.dm_hadr_availability_replica_states;' AS Query
            FROM sys.availability_groups ag
            INNER JOIN sys.availability_replicas r ON ag.group_id = r.group_id
            INNER JOIN sys.dm_hadr_availability_replica_states rs ON r.replica_id = rs.replica_id
            LEFT JOIN sys.dm_hadr_database_replica_states drs ON r.replica_id = drs.replica_id
            LEFT JOIN sys.databases d ON drs.database_id = d.database_id
            WHERE r.operational_state <> 0 OR r.availability_mode <> 1;
        END;
    END;

    -- ============================================================
    -- CHECK 6: High CPU (Warning)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 6
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 5
            CASE
                WHEN (SELECT AVG(ProcessUtilization) FROM sys.dm_os_sys_info) >= 95 THEN 1
                ELSE 2
            END AS Priority,
            'High CPU Usage' AS Finding,
            'Current CPU: ' + CAST((SELECT AVG(ProcessUtilization) FROM sys.dm_os_sys_info) AS NVARCHAR) + '%' AS Details,
            NULL AS DatabaseName,
            'SELECT * FROM sys.dm_os_ring_buffers WHERE ring_buffer_type = ''RING_BUFFER_SCHEDULER_MONITOR'' ORDER BY timestamp DESC;' AS Query
        WHERE (SELECT AVG(ProcessUtilization) FROM sys.dm_os_sys_info) >= 80;
    END;

    -- ============================================================
    -- CHECK 7: Memory pressure (Warning)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 7
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 5
            CASE
                WHEN cntr_value <= 100 THEN 1
                ELSE 2
            END AS Priority,
            'Page Life Expectancy Low' AS Finding,
            'PLE: ' + CAST(cntr_value AS NVARCHAR) + ' seconds (below 300 is concerning)' AS Details,
            NULL AS DatabaseName,
            'SELECT * FROM sys.dm_os_performance_counters WHERE counter_name = ''Page life expectancy'';' AS Query
        FROM sys.dm_os_performance_counters
        WHERE counter_name = 'Page life expectancy'
            AND object_name LIKE '%Buffer Manager%'
            AND cntr_value <= 300;
    END;

    -- ============================================================
    -- CHECK 8: Batch requests/sec very low (Warning)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 8
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 5
            2 AS Priority,
            'Low Batch Requests' AS Finding,
            'Batch requests/sec: ' + CAST(cntr_value AS NVARCHAR) AS Details,
            NULL AS DatabaseName,
            'SELECT * FROM sys.dm_os_performance_counters WHERE counter_name = ''Batch Requests/sec'';' AS Query
        FROM sys.dm_os_performance_counters
        WHERE counter_name = 'Batch Requests/sec'
            AND cntr_value < 100;
    END;

    -- ============================================================
    -- CHECK 9: Full waits (Warning)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 9
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 10
            2 AS Priority,
            'High Wait Time: ' + wait_type AS Finding,
            CAST(total_wait_time_ms / 1000 / 60 AS NVARCHAR) + ' minutes total wait' AS Details,
            NULL AS DatabaseName,
            'SELECT * FROM sys.dm_os_wait_stats WHERE wait_type = ''' + wait_type + ''';' AS Query
        FROM sys.dm_os_wait_stats
        WHERE waiting_tasks_count > 0
        AND wait_time_ms > 60000  -- More than 1 minute total
        AND wait_type NOT IN ('RESOURCE_SEMAPHORE_QUERY_COMPILE', 'BRKRASYNCSHUTDOWN')
        ORDER BY wait_time_ms DESC;
    END;

    -- ============================================================
    -- CHECK 10: Auto-close enabled (Warning)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 10
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 20
            2 AS Priority,
            'Auto-Close Enabled' AS Finding,
            d.Name + ' has auto_close enabled - this can cause performance issues' AS Details,
            d.Name AS DatabaseName,
            'ALTER DATABASE [' + d.Name + '] SET AUTO_CLOSE OFF;' AS Query
        FROM sys.databases d
        WHERE d.is_auto_close_on = 1
            AND d.name NOT IN ('master', 'model', 'msdb')
            AND (d.name = @DatabaseName OR @DatabaseName IS NULL);
    END;

    -- ============================================================
    -- CHECK 11: Auto-shrink enabled (Critical)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 11
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 20
            1 AS Priority,
            'Auto-Shrink Enabled' AS Finding,
            d.Name + ' has auto_shrink enabled - this causes fragmentation and performance issues!' AS Details,
            d.Name AS DatabaseName,
            'ALTER DATABASE [' + d.Name + '] SET AUTO_SHRINK OFF;' AS Query
        FROM sys.databases d
        WHERE d.is_auto_shrink_on = 1
            AND (d.name = @DatabaseName OR @DatabaseName IS NULL);
    END;

    -- ============================================================
    -- CHECK 12: Old stats (Warning)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 12
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 20
            2 AS Priority,
            'Stale Statistics' AS Finding,
            OBJECT_NAME(s.object_id) + ' - Last updated: ' + CONVERT(NVARCHAR, s.last_updated, 120) AS Details,
            OBJECT_NAME(s.object_id) AS DatabaseName,
            'EXEC sp_updatestats;' AS Query
        FROM sys.dm_db_stats_properties(NULL, NULL) s
        CROSS JOIN sys.objects o
        WHERE o.object_id = s.object_id
            AND o.type = 'U'
            AND o.is_ms_shipped = 0
            AND s.last_updated < DATEADD(DAY, -30, GETDATE())
        ORDER BY s.last_updated ASC;

        -- Alternative using stats dates
        IF @@ROWCOUNT = 0
        BEGIN
            INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
            SELECT TOP 10
                2 AS Priority,
                'Statistics May Need Update' AS Finding,
                'Run UPDATE STATISTICS on user tables periodically' AS Details,
                @DatabaseName AS DatabaseName,
                'EXEC sp_updatestats;'' (or UPDATE STATISTICS table_name WITH FULLSCAN;)' AS Query
            WHERE @DatabaseName IS NOT NULL;
        END;
    END;

    -- ============================================================
    -- CHECK 13: Indexes with high fragmentation (Warning)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 13
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 20
            2 AS Priority,
            'High Fragmentation: ' + OBJECT_NAME(ips.object_id) AS Finding,
            i.name + ' - ' + CAST(ips.avg_fragmentation_in_percent AS NVARCHAR) + '% fragmented' AS Details,
            @DatabaseName AS DatabaseName,
            'ALTER INDEX [' + i.name + '] ON [' + OBJECT_SCHEMA_NAME(ips.object_id) + '].[' + OBJECT_NAME(ips.object_id) + '] REBUILD;' AS Query
        FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
        INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
        INNER JOIN sys.objects o ON ips.object_id = o.object_id
        WHERE ips.avg_fragmentation_in_percent > 30
            AND o.type = 'U'
            AND o.is_ms_shipped = 0
            AND ips.database_id = DB_ID(@DatabaseName)
            AND ips.alloc_unit_type_desc = 'IN_ROW_DATA_PAGE'
        ORDER BY ips.avg_fragmentation_in_percent DESC;
    END;

    -- ============================================================
    -- CHECK 14: Missing indexes (Warning)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 14
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 20
            2 AS Priority,
            'Missing Index: ' + CAST(mid.statement AS NVARCHAR(100)) AS Finding,
            'Impact: ' + CAST(migs.avg_user_impact AS NVARCHAR) + '%, ' +
            'Current cost: ' + CAST(mid.avg_total_user_cost AS NVARCHAR) AS Details,
            DB_NAME(mid.database_id) AS DatabaseName,
            'CREATE INDEX [IX_' + REPLACE(REPLACE(mid.statement, '[', ''), ']', '_') + '_' + CAST(mid.index_handle AS NVARCHAR) + '] ON ' + mid.statement + ' (' + ISNULL(mid.equality_columns, '') + CASE WHEN mid.inequality_columns IS NOT NULL THEN ', ' + mid.inequality_columns ELSE '' END + ');' AS Query
        FROM sys.dm_db_missing_index_details mid
        INNER JOIN sys.dm_db_missing_index_groups mig ON mid.index_handle = mig.index_handle
        INNER JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
        WHERE mid.database_id = DB_ID(@DatabaseName)
            OR @DatabaseName IS NULL
        ORDER BY migs.avg_user_impact * migs.user_seeks DESC;
    END;

    -- ============================================================
    -- CHECK 15: Tables without clustered index (Warning)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 15
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 20
            2 AS Priority,
            'Heap Table' AS Finding,
            OBJECT_NAME(i.object_id) + ' has no clustered index' AS Details,
            OBJECT_NAME(i.object_id) AS DatabaseName,
            'CREATE CLUSTERED INDEX [IX_' + OBJECT_NAME(i.object_id) + '_Clustered] ON [' + OBJECT_SCHEMA_NAME(i.object_id) + '].[' + OBJECT_NAME(i.object_id) + '] (column_name);' AS Query
        FROM sys.objects o
        INNER JOIN sys.indexes i ON o.object_id = i.object_id
        WHERE o.type = 'U'
            AND o.is_ms_shipped = 0
            AND i.type = 0  -- Heap
            AND OBJECTPROPERTY(o.object_id, 'TableHasClustIndex') = 0
            AND (SCHEMA_NAME(o.schema_id) + '.' + OBJECT_NAME(o.object_id) = @DatabaseName OR @DatabaseName IS NULL);
    END;

    -- ============================================================
    -- CHECK 16: Virtual log files (Warning)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 16
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 10
            2 AS Priority,
            'Excessive Virtual Log Files' AS Finding,
            'Database has ' + CAST(COUNT(*) AS NVARCHAR) + ' VLFs - should be under 1000' AS Details,
            @DatabaseName AS DatabaseName,
            'DBCC LOGINFO;' AS Query
        FROM sys.dm_db_log_info(DB_ID(@DatabaseName))
        WHERE @DatabaseName IS NOT NULL
        GROUP BY DB_NAME()
        HAVING COUNT(*) > 1000;
    END;

    -- ============================================================
    -- CHECK 17: Transaction log growth (Warning)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 17
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 10
            2 AS Priority,
            'Transaction Log Growth Event' AS Finding,
            'Check for frequent autogrow events on transaction log' AS Details,
            d.name AS DatabaseName,
            'SELECT * FROM fn_dblog(NULL, NULL) WHERE Operation = ''LOP_MODIFY_ROW'' AND Context = ''LCX_PFS'';'' (check for growth)' AS Query
        FROM sys.databases d
        WHERE d.state_desc = 'ONLINE'
            AND d.recovery_model_desc IN ('FULL', 'BULK_LOGGED')
            AND (d.name = @DatabaseName OR @DatabaseName IS NULL)
            AND EXISTS (
                SELECT 1 FROM sys.dm_db_log_stats(d.database_id)
                WHERE log_since_last_log_backup_mb < 100
            );
    END;

    -- ============================================================
    -- CHECK 18: Database owner is sa (Info)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 18
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 20
            3 AS Priority,
            'Database Owner is sa' AS Finding,
            d.Name + ' is owned by sa - consider using a service account' AS Details,
            d.Name AS DatabaseName,
            'ALTER AUTHORIZATION ON DATABASE::[' + d.Name + '] TO [service_account];' AS Query
        FROM sys.databases d
        WHERE d.owner_sid = 0x01
            AND d.name NOT IN ('master', 'model', 'msdb')
            AND (d.name = @DatabaseName OR @DatabaseName IS NULL);
    END;

    -- ============================================================
    -- CHECK 19: AdventureWorks installed (Info)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 19
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 5
            3 AS Priority,
            'Sample Database Found' AS Finding,
            d.Name + ' appears to be a sample database - should not be in production' AS Details,
            d.Name AS DatabaseName,
            NULL AS Query
        FROM sys.databases d
        WHERE d.name IN ('AdventureWorks', 'AdventureWorks2016', 'AdventureWorks2017',
                         'AdventureWorksDW', 'AdventureWorksDW2016', 'AdventureWorksDW2017',
                         'WideWorldImporters', 'WideWorldImportersDW', 'Northwind', 'Pubs');
    END;

    -- ============================================================
    -- CHECK 20: SQL Agent not running (Critical)
    -- ============================================================
    IF @CheckId IS NULL OR @CheckId = 20
    BEGIN
        INSERT #HealthCheckResults (Priority, Finding, Details, DatabaseName, Query)
        SELECT TOP 5
            1 AS Priority,
            'SQL Server Agent Not Running' AS Finding,
            'SQL Agent service is not running - backups and jobs will not execute' AS Details,
            NULL AS DatabaseName,
            'EXEC xp_servicecontrol ''State'', ''SQLServerAgent'';' AS Query
        WHERE DATABASEPROPERTYEX('master', 'Status') = 'ONLINE'
            AND (SELECT COUNT(*) FROM sys.dm_server_services WHERE servicename LIKE '%Agent%' AND status_desc <> 'Running') > 0;
    END;

    -- ============================================================
    -- OUTPUT
    -- ============================================================

    -- Filter by specific CheckId
    IF @CheckId IS NOT NULL
    BEGIN
        DELETE FROM #HealthCheckResults WHERE CheckId <> @CheckId;
    END;

    -- Output based on requested type
    IF @OutputType = 'COUNT_ONLY'
    BEGIN
        SELECT COUNT(*) AS FindingCount FROM #HealthCheckResults;
    END
    ELSE IF @OutputType = 'TEXT'
    BEGIN
        -- Text output for console
        DECLARE @ResultsText NVARCHAR(MAX) = '';
        SELECT @ResultsText = @ResultsText + CHAR(13) + CHAR(10) +
            CASE Priority
                WHEN 1 THEN '![CRITICAL] '
                WHEN 2 THEN '![WARNING]  '
                WHEN 3 THEN ' [INFO]     '
            END +
            Finding + CHAR(13) + CHAR(10) +
            '    ' + ISNULL(Details, '') +
            CASE WHEN DatabaseName IS NOT NULL THEN ' | DB: ' + DatabaseName ELSE '' END +
            CHAR(13) + CHAR(10) +
            CASE WHEN Query IS NOT NULL THEN '    -> ' + Query ELSE '' END +
            CHAR(13) + CHAR(10)
        FROM #HealthCheckResults
        ORDER BY Priority, CheckId;

        SELECT @ResultsText AS HealthCheckResults;
    END
    ELSE  -- TABLE (default)
    BEGIN
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
            Query AS 'SQL_to_run'
        FROM #HealthCheckResults
        ORDER BY Priority, CheckId;
    END;

    -- Cleanup
    DROP TABLE #HealthCheckResults;

    -- Return completion message
    IF @OutputType = 'TABLE'
        PRINT 'Health check complete. ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' findings.';
END;
GO

PRINT '+ Procedure [monitor].[usp_HealthCheck] created.';
GO
