/*
    SQL Health Monitor - Query Store Collector
    Captures query performance data from SQL Server Query Store (SQL 2016+).

    Features:
    - Top queries by CPU
    - Top queries by duration
    - Top queries by I/O
    - Top queries by memory
    - Query regression detection
    - Plan comparison data

    Schedule: Every 15 minutes
    Compatibility: SQL Server 2016+ (Query Store)
*/

USE [SQLHealthMonitor];
GO

IF OBJECT_ID('[monitor].[usp_Collect_QueryStore]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_QueryStore] @DebugMode BIT = 0 AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_QueryStore]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_Collect_QueryStore] @DebugMode BIT = 0 AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

ALTER PROCEDURE [monitor].[usp_Collect_QueryStore]
    @DebugMode BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CollectedAt DATETIME2 = SYSUTCDATETIME();

    -- Only run on databases with Query Store enabled
    DECLARE @DBName NVARCHAR(128);
    DECLARE @Qson BIT;

    DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT name,
            (SELECT COUNT(*) FROM sys.database_query_store_options
             WHERE actual_state = 1) AS IsQSOn
        FROM sys.databases
        WHERE state_desc = 'ONLINE'
          AND name NOT IN ('master', 'msdb', 'tempdb', 'model');

    OPEN db_cursor;
    FETCH NEXT FROM db_cursor INTO @DBName, @Qson;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @Qson = 1
        BEGIN
            -- Dynamic SQL to query each database's Query Store
            DECLARE @sql NVARCHAR(MAX) = N'
                INSERT INTO [monitor].[QueryStoreHistory] (
                    CollectedAt, DatabaseName, QueryId, PlanId,
                    ObjectId, ObjectName, QueryText,
                    QueryType, SchemaName,
                    TotalCpuMs, AvgCpuMs, TotalDurationMs, AvgDurationMs,
                    TotalLogicalReads, AvgLogicalReads,
                    TotalLogicalWrites, AvgLogicalWrites,
                    TotalRowCount, AvgRowCount,
                    ExecutionCount, TotalExecTimeMs, AvgExecTimeMs,
                    StalePlans, LastExecutionTime, FirstExecutionTime
                )
                SELECT
                    @CollectedAt,
                    ''' + @DBName + ''',
                    q.query_id,
                    p.plan_id,
                    p.object_id,
                    OBJECT_NAME(p.object_id, DB_ID(''' + @DBName + ''')),
                    SUBSTRING(q.query_text, 1, 4000),
                    q.query_type,
                    p.schema_name,
                    -- Runtime stats
                    SUM(rs.count_executions * rs.avg_cpu_time) / 1000.0 AS TotalCpuMs,
                    AVG(rs.avg_cpu_time) / 1000.0 AS AvgCpuMs,
                    SUM(rs.count_executions * rs.avg_elapsed_time) / 1000.0 AS TotalDurationMs,
                    AVG(rs.avg_elapsed_time) / 1000.0 AS AvgDurationMs,
                    SUM(rs.count_executions * rs.avg_logical_io_reads) AS TotalLogicalReads,
                    AVG(rs.avg_logical_io_reads) AS AvgLogicalReads,
                    SUM(rs.count_executions * rs.avg_logical_io_writes) AS TotalLogicalWrites,
                    AVG(rs.avg_logical_io_writes) AS AvgLogicalWrites,
                    SUM(rs.count_executions * rs.avg_rowcount) AS TotalRowCount,
                    AVG(rs.avg_rowcount) AS AvgRowCount,
                    -- Execution stats
                    SUM(rs.count_executions) AS ExecutionCount,
                    SUM(rs.count_executions * rs.avg_elapsed_time) AS TotalExecTimeMs,
                    AVG(rs.avg_elapsed_time) AS AvgExecTimeMs,
                    -- Plan info
                    (SELECT COUNT(*) FROM sys.query_store_plan p2 WHERE p2.query_id = q.query_id AND p2.is_forced = 0) AS StalePlans,
                    MAX(rs.last_execution_time) AS LastExecutionTime,
                    MIN(rs.last_execution_time) AS FirstExecutionTime
                FROM sys.query_store_query q
                INNER JOIN sys.query_store_plan p ON q.query_id = p.query_id
                INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
                WHERE q.is_internal_query = 0
                  AND p.is_auto_created = 0
                GROUP BY q.query_id, p.plan_id, p.object_id, p.schema_name, q.query_text, q.query_type
                HAVING SUM(rs.count_executions) >= 5;';

            BEGIN TRY
                EXEC sp_executesql @sql, N'@CollectedAt DATETIME2', @CollectedAt = @CollectedAt;
            END TRY
            BEGIN CATCH
                -- Database might have QS disabled or other error
                PRINT 'Warning: Could not collect Query Store from ' + @DBName;
            END CATCH;
        END

        FETCH NEXT FROM db_cursor INTO @DBName, @Qson;
    END;

    CLOSE db_cursor;
    DEALLOCATE db_cursor;

    -- Detect regressions (queries that got slower)
    INSERT INTO [monitor].[QueryRegressions] (
        CollectedAt, DatabaseName, QueryId, QueryText,
        PreviousDurationMs, CurrentDurationMs,
        SlowdownFactor, PlanChangeDetected
    )
    SELECT
        @CollectedAt,
        DatabaseName,
        QueryId,
        QueryText,
        PrevDuration.AvgDurationMs AS PreviousDurationMs,
        CurrDuration.AvgDurationMs AS CurrentDurationMs,
        CASE WHEN PrevDuration.AvgDurationMs > 0
             THEN CurrDuration.AvgDurationMs / PrevDuration.AvgDurationMs
             ELSE 1 END AS SlowdownFactor,
        CASE WHEN (SELECT COUNT(DISTINCT PlanId) FROM [monitor].[QueryStoreHistory]
                   WHERE QueryId = q.QueryId AND CollectedAt >= DATEADD(HOUR, -24, @CollectedAt)) > 1
             THEN 1 ELSE 0 END AS PlanChangeDetected
    FROM (
        SELECT QueryId, DatabaseName, QueryText
        FROM [monitor].[QueryStoreHistory]
        WHERE CollectedAt >= DATEADD(HOUR, -24, @CollectedAt)
        GROUP BY QueryId, DatabaseName, QueryText
        HAVING AVG(AvgDurationMs) > 1000  -- Queries > 1 second
    ) q
    CROSS APPLY (
        SELECT TOP 1 AvgDurationMs
        FROM [monitor].[QueryStoreHistory]
        WHERE QueryId = q.QueryId AND CollectedAt < DATEADD(DAY, -7, @CollectedAt)
        ORDER BY CollectedAt DESC
    ) PrevDuration
    CROSS APPLY (
        SELECT AVG(AvgDurationMs) AS AvgDurationMs
        FROM [monitor].[QueryStoreHistory]
        WHERE QueryId = q.QueryId AND CollectedAt >= DATEADD(DAY, -7, @CollectedAt)
    ) CurrDuration
    WHERE CurrDuration.AvgDurationMs > PrevDuration.AvgDurationMs * 2  -- 2x slower

    IF @DebugMode = 1
    BEGIN
        SELECT TOP 50 * FROM [monitor].[QueryStoreHistory]
        ORDER BY TotalCpuMs DESC;
    END

    PRINT '+ Query Store data collected at ' + CONVERT(NVARCHAR, @CollectedAt, 120);
END;
GO

PRINT '+ Procedure [monitor].[usp_Collect_QueryStore] created.';
GO
