/*
    SQL Health Monitor - AG Health Collector
    Collects AlwaysOn Availability Group synchronization status.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+ with AG configured
*/

IF OBJECT_ID('[monitor].[usp_Collect_AG_Health]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_AG_Health]  AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_AG_Health]', 'P') IS NULL
    
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
        A
        G
        _
        H
        e
        a
        l
        t
        h
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

ALTER PROCEDURE [monitor].[usp_Collect_AG_Health]
    
    -- Only run if AG is configured
    IF NOT EXISTS (SELECT 1 FROM sys.availability_groups)
        RETURN;

    INSERT INTO [monitor].[AgHealthHistory] 
        (AgName, ReplicaServer, DatabaseName, SyncState, SyncHealth,
         LogSendQueueSizeKB, RedoQueueSizeKB, LastCommitTime, SecondsBehindPrimary)
    SELECT
        ag.name AS AgName,
        ar.replica_server_name AS ReplicaServer,
        db.name AS DatabaseName,
        drs.synchronization_state_desc AS SyncState,
        drs.synchronization_health_desc AS SyncHealth,
        drs.log_send_queue_size AS LogSendQueueSizeKB,
        drs.redo_queue_size AS RedoQueueSizeKB,
        drs.last_commit_time AS LastCommitTime,
        DATEDIFF(SECOND, drs.last_commit_time, 
            (SELECT MAX(drs2.last_commit_time) 
             FROM sys.dm_hadr_database_replica_states drs2 
             WHERE drs2.group_id = drs.group_id 
               AND drs2.database_id = drs.database_id
               AND drs2.is_primary_replica = 1)
        ) AS SecondsBehindPrimary
    FROM sys.dm_hadr_database_replica_states drs
    INNER JOIN sys.availability_groups ag ON ag.group_id = drs.group_id
    INNER JOIN sys.availability_replicas ar ON ar.replica_id = drs.replica_id
    INNER JOIN sys.databases db ON db.database_id = drs.database_id
    WHERE drs.is_local = 0  -- Remote replicas (to see lag)
       OR drs.is_primary_replica = 1;  -- Primary for baseline
END;
GO
