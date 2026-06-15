/*
    SQL Health Monitor - CPU Collector
    Collects CPU usage statistics and top CPU consumers.
    
    Schedule: Every 2 minutes
    Compatibility: SQL Server 2016+
*/

IF OBJECT_ID('[monitor].[usp_Collect_CPU]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_CPU]  AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_CPU]', 'P') IS NULL
    
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
        C
        P
        U
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

ALTER PROCEDURE [monitor].[usp_Collect_CPU]
    
    INSERT INTO [monitor].[CPUHistory]
        (SampleTime, TotalCPUms, SQLServerCPUms, SystemCPUms, 
         TopConsumerSPID, TopConsumerCPUms, TopConsumerQueryText)
    SELECT
        SYSDATETIME() AS SampleTime,
        SUM(total_worker_time) AS TotalCPUms,
        SUM(total_worker_time) AS SQLServerCPUms,
        0 AS SystemCPUms,  -- Calculated from OS level
        TOP 1 WITH TIES session_id AS TopConsumerSPID,
        total_worker_time AS TopConsumerCPUms,
        SUBSTRING(text, (statement_start_offset/2)+1,
            ((CASE statement_end_offset
                WHEN -1 THEN DATALENGTH(text)
                ELSE statement_end_offset
            END - statement_start_offset)/2) + 1) AS TopConsumerQueryText
    FROM sys.dm_exec_query_stats
    CROSS APPLY sys.dm_exec_sql_text(sql_handle)
    ORDER BY total_worker_time DESC
    OPTION (MAXDOP 1);

    -- Also collect OS-level CPU stats if available
    DECLARE @CPUStats TABLE (
        cpu_time_ms INT,
        idle_time_ms INT,
        kernel_time_ms INT,
        user_time_ms INT
    );

    INSERT INTO @CPUStats
    EXEC xp_cmdshell 'wmic cpu get loadpercentage /value 2>nul';

    -- Note: OS-level CPU collection requires additional setup
    -- This is a simplified version - consider using extended events or DMVs for full CPU stats
END;
GO
