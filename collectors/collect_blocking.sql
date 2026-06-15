/*
    SQL Health Monitor - Blocking Collector
    Collects current blocking sessions and blocking chains.
    
    Schedule: Every 2 minutes
    Compatibility: SQL Server 2016+
*/

IF OBJECT_ID('[monitor].[usp_Collect_Blocking]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_Blocking]  AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_Blocking]', 'P') IS NULL
    
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
        B
        l
        o
        c
        k
        i
        n
        g
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

ALTER PROCEDURE [monitor].[usp_Collect_Blocking]
    
    INSERT INTO [monitor].[BlockingHistory]
        (BlockedBySPID, BlockingSPID, WaitType, WaitTimeMs, QueryText, SessionLogin, BlockingQueryText, BlockingSessionLogin)
    SELECT
        blocked.session_id AS BlockedBySPID,
        blocker.session_id AS BlockingSPID,
        wait_resource,
        wait_time,
        SUBSTRING(st_blocked.text, (qs_blocked.statement_start_offset/2)+1,
            ((CASE qs_blocked.statement_end_offset
                WHEN -1 THEN DATALENGTH(st_blocked.text)
                ELSE qs_blocked.statement_end_offset
            END - qs_blocked.statement_start_offset)/2) + 1) AS QueryText,
        s_blocked.login_name AS SessionLogin,
        SUBSTRING(st_blocker.text, (qs_blocker.statement_start_offset/2)+1,
            ((CASE qs_blocker.statement_end_offset
                WHEN -1 THEN DATALENGTH(st_blocker.text)
                ELSE qs_blocker.statement_end_offset
            END - qs_blocker.statement_start_offset)/2) + 1) AS BlockingQueryText,
        s_blocker.login_name AS BlockingSessionLogin
    FROM sys.dm_exec_requests blocker
    INNER JOIN sys.dm_exec_requests blocked ON blocked.blocking_session_id = blocker.session_id
    INNER JOIN sys.dm_exec_sessions s_blocker ON s_blocker.session_id = blocker.session_id
    INNER JOIN sys.dm_exec_sessions s_blocked ON s_blocked.session_id = blocked.session_id
    CROSS APPLY sys.dm_exec_sql_text(blocker.session_id) AS st_blocker
    CROSS APPLY sys.dm_exec_sql_text(blocked.session_id) AS st_blocked
    WHERE blocker.blocking_session_id <> 0
      AND blocker.wait_type IS NOT NULL
      AND blocker.wait_type <> 'TASK_COMPLETION'
      AND blocker.wait_resource IS NOT NULL;
END;
GO
