/*
    SQL Health Monitor - Top Queries Collector
    Collects top resource-consuming queries.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+
*/

IF OBJECT_ID('[monitor].[usp_Collect_TopQueries]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_TopQueries]  AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_TopQueries]', 'P') IS NULL
    
        E
        X
        E
        C
        (
        '
        

         
         
         
         
        C
        R
        E
        A
        T
        E
         
        P
        R
        O
        C
        E
        D
        U
        R
        E
         
        [
        m
        o
        n
        i
        t
        o
        r
        ]
        .
        [
        u
        s
        p
        _
        C
        o
        l
        l
        e
        c
        t
        _
        T
        o
        p
        Q
        u
        e
        r
        i
        e
        s
        ]
        

         
         
         
         
         
         
         
         
        

         
         
         
         
        A
        S
        

         
         
         
         
        B
        E
        G
        I
        N
        

         
         
         
         
         
         
         
         
        S
        E
        T
         
        N
        O
        C
        O
        U
        N
        T
         
        O
        N
        ;
        

         
         
         
         
         
         
         
         
        P
        R
        I
        N
        T
         
        '
        '
        P
        l
        a
        c
        e
        h
        o
        l
        d
        e
        r
        '
        '
        ;
        

         
         
         
         
        E
        N
        D
        ;
        

         
         
         
         
        '
        )
        ;
        
GO

ALTER PROCEDURE [monitor].[usp_Collect_TopQueries]
    
AS
BEGIN
    SET NOCOUNT ON;

    -- Top queries by CPU usage
    INSERT INTO [monitor].[TopQueriesHistory]
        (SampleTime, DatabaseName, QueryText, QueryHash, 
         ExecutionCount, TotalCPUms, AverageCPUms, 
         TotalLogicalReads, AverageLogicalReads, 
         TotalLogicalWrites, AverageLogicalWrites, 
         QueryPlanHash, LastExecutionTime)
    SELECT
        SYSDATETIME() AS SampleTime,
        DB_NAME(qs.database_id) AS DatabaseName,
        SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
            ((CASE qs.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE qs.statement_end_offset
            END - qs.statement_start_offset)/2) + 1) AS QueryText,
        qs.query_hash AS QueryHash,
        qs.execution_count AS ExecutionCount,
        qs.total_worker_time AS TotalCPUms,
        CASE WHEN qs.execution_count > 0 THEN qs.total_worker_time / qs.execution_count ELSE 0 END AS AverageCPUms,
        qs.total_logical_reads AS TotalLogicalReads,
        CASE WHEN qs.execution_count > 0 THEN qs.total_logical_reads / qs.execution_count ELSE 0 END AS AverageLogicalReads,
        qs.total_logical_writes AS TotalLogicalWrites,
        CASE WHEN qs.execution_count > 0 THEN qs.total_logical_writes / qs.execution_count ELSE 0 END AS AverageLogicalWrites,
        qs.query_plan_hash AS QueryPlanHash,
        qs.last_execution_time AS LastExecutionTime
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
    WHERE qs.execution_count > 0
      AND qs.total_worker_time > 0
      AND qs.last_execution_time > DATEADD(HOUR, -1, SYSDATETIME())
    ORDER BY qs.total_worker_time DESC
    OPTION (MAXDOP 1);
    
    -- Top queries by I/O usage
    INSERT INTO [monitor].[TopQueriesIOHistory]
        (SampleTime, DatabaseName, QueryText, QueryHash, 
         ExecutionCount, TotalReads, AverageReads, 
         TotalWrites, AverageWrites, TotalElapsedTimeMS)
    SELECT
        SYSDATETIME() AS SampleTime,
        DB_NAME(qs.database_id) AS DatabaseName,
        SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
            ((CASE qs.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE qs.statement_end_offset
            END - qs.statement_start_offset)/2) + 1) AS QueryText,
        qs.query_hash AS QueryHash,
        qs.execution_count AS ExecutionCount,
        qs.total_logical_reads AS TotalReads,
        CASE WHEN qs.execution_count > 0 THEN qs.total_logical_reads / qs.execution_count ELSE 0 END AS AverageReads,
        qs.total_logical_writes AS TotalWrites,
        CASE WHEN qs.execution_count > 0 THEN qs.total_logical_writes / qs.execution_count ELSE 0 END AS AverageWrites,
        qs.total_elapsed_time AS TotalElapsedTimeMS
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
    WHERE qs.execution_count > 0
      AND qs.total_logical_reads > 0
      AND qs.last_execution_time > DATEADD(HOUR, -1, SYSDATETIME())
    ORDER BY qs.total_logical_reads DESC
    OPTION (MAXDOP 1);
END;
GO
