/*
    SQL Health Monitor - Top Queries Collector
    Collects top resource-consuming queries.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+
*/

IF OBJECT_ID('[monitor].[usp_Collect_TopQueries]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_TopQueries] AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_TopQueries]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_Collect_TopQueries] AS SET NOCOUNT ON; PRINT ''Placeholder'';');
GO
ALTER PROCEDURE [monitor].[usp_Collect_TopQueries]
AS
BEGIN
    SET NOCOUNT ON;

    -- Schema columns: CollectedAt, DatabaseName, QueryHash, TotalCpuMs, TotalReads,
    --                 TotalWrites, ExecutionCount, AvgDurationMs, QueryText, PlanHandle
    INSERT INTO [monitor].[TopQueriesHistory]
        (DatabaseName, QueryHash, TotalCpuMs, TotalReads, TotalWrites,
         ExecutionCount, AvgDurationMs, QueryText, PlanHandle)
    SELECT
        DB_NAME(st.dbid)                                                         AS DatabaseName,
        qs.query_hash                                                            AS QueryHash,
        qs.total_worker_time                                                     AS TotalCpuMs,
        qs.total_logical_reads                                                   AS TotalReads,
        qs.total_logical_writes                                                  AS TotalWrites,
        qs.execution_count                                                       AS ExecutionCount,
        CASE WHEN qs.execution_count > 0
             THEN qs.total_elapsed_time / qs.execution_count
             ELSE 0 END                                                          AS AvgDurationMs,
        SUBSTRING(st.text,
            (qs.statement_start_offset / 2) + 1,
            ((CASE qs.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE qs.statement_end_offset
              END - qs.statement_start_offset) / 2) + 1)                        AS QueryText,
        qs.plan_handle                                                           AS PlanHandle
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
    WHERE qs.execution_count > 0
      AND qs.total_worker_time > 0
      AND qs.last_execution_time > DATEADD(HOUR, -1, SYSDATETIME())
    ORDER BY qs.total_worker_time DESC
    OPTION (MAXDOP 1);

    -- Note: TopQueriesIOHistory table does not exist in the schema; that insert has been removed.
END;
GO