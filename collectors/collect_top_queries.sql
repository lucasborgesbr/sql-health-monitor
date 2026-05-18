/*
    SQL Health Monitor - Top Queries Collector
    Collects top resource-consuming queries from plan cache.
    
    Schedule: Every 30 minutes
    Compatibility: SQL Server 2016+
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_TopQueries]
    @TopN INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [monitor].[TopQueriesHistory]
        (DatabaseName, QueryHash, TotalCpuMs, TotalReads, TotalWrites,
         ExecutionCount, AvgDurationMs, QueryText, PlanHandle)
    SELECT TOP (@TopN)
        DB_NAME(qt.dbid) AS DatabaseName,
        qs.query_hash AS QueryHash,
        qs.total_worker_time / 1000 AS TotalCpuMs,
        qs.total_logical_reads AS TotalReads,
        qs.total_logical_writes AS TotalWrites,
        qs.execution_count AS ExecutionCount,
        (qs.total_elapsed_time / qs.execution_count) / 1000 AS AvgDurationMs,
        SUBSTRING(qt.text, 
            (qs.statement_start_offset / 2) + 1,
            CASE WHEN qs.statement_end_offset = -1 THEN LEN(qt.text)
                 ELSE (qs.statement_end_offset - qs.statement_start_offset) / 2 + 1 END
        ) AS QueryText,
        qs.plan_handle AS PlanHandle
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
    WHERE qs.execution_count > 1
        AND qt.dbid IS NOT NULL
        AND qt.dbid > 4  -- Exclude system databases
    ORDER BY qs.total_worker_time DESC;
END;
GO
