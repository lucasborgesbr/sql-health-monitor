/*
    SQL Health Monitor - Memory Collector
    Collects memory usage and buffer pool statistics.
    
    Schedule: Every 2 minutes
    Compatibility: SQL Server 2016+
*/

IF OBJECT_ID('[monitor].[usp_Collect_Memory]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_Memory]  AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_Memory]', 'P') IS NULL
    
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
        M
        e
        m
        o
        r
        y
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

ALTER PROCEDURE [monitor].[usp_Collect_Memory]
    
    INSERT INTO [monitor].[MemoryHistory]
        (SampleTime, TotalMemoryMB, BufferPoolMB, CacheMemoryMB, 
         MemoryTargetMB, MemoryPressurePercent, PlanCacheMB, 
         ConnectionMemoryMB, GrantedMemoryMB)
    SELECT
        SYSDATETIME() AS SampleTime,
        CAST((SELECT cntr_value FROM sys.dm_os_performance_counters 
              WHERE counter_name = 'Total Server Memory (KB)') / 1024.0 AS DECIMAL(10, 2)) AS TotalMemoryMB,
        CAST((SELECT cntr_value FROM sys.dm_os_performance_counters 
              WHERE counter_name = 'Stolen Server Memory (KB)') / 1024.0 AS DECIMAL(10, 2)) AS BufferPoolMB,
        CAST((SELECT cntr_value FROM sys.dm_os_performance_counters 
              WHERE counter_name = 'Cache Pages (KB)') / 1024.0 AS DECIMAL(10, 2)) AS CacheMemoryMB,
        CAST((SELECT cntr_value FROM sys.dm_os_performance_counters 
              WHERE counter_name = 'Target Server Memory (KB)') / 1024.0 AS DECIMAL(10, 2)) AS MemoryTargetMB,
        NULL AS MemoryPressurePercent,
        NULL AS PlanCacheMB,
        NULL AS ConnectionMemoryMB,
        NULL AS GrantedMemoryMB
    WHERE EXISTS (SELECT 1 FROM sys.dm_os_performance_counters 
                 WHERE counter_name IN ('Total Server Memory (KB)', 'Stolen Server Memory (KB)', 
                                       'Cache Pages (KB)', 'Target Server Memory (KB)'));
    
    -- Also collect memory grants
    INSERT INTO [monitor].[MemoryGrantHistory]
        (SessionID, RequestID, DatabaseName, QueryText, 
         GrantedMemoryKB, RequiredMemoryKB, WaitTimeMS, 
         QueryCost, QueryHash)
    SELECT
        mg.session_id AS SessionID,
        mg.request_id AS RequestID,
        DB_NAME(mg.database_id) AS DatabaseName,
        SUBSTRING(st.text, (mg.statement_start_offset/2)+1,
            ((CASE mg.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE mg.statement_end_offset
            END - mg.statement_start_offset)/2) + 1) AS QueryText,
        mg.granted_memory_kb AS GrantedMemoryKB,
        mg.required_memory_kb AS RequiredMemoryKB,
        mg.wait_time_ms AS WaitTimeMS,
        mg.query_cost AS QueryCost,
        mg.query_hash AS QueryHash
    FROM sys.dm_exec_memory_grants mg
    CROSS APPLY sys.dm_exec_sql_text(mg.sql_handle) AS st
    WHERE mg.granted_memory_kb > 0
      AND mg.request_time > DATEADD(MINUTE, -5, SYSDATETIME());
END;
GO
