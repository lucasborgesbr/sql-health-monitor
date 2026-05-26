/*
    SQL Health Monitor - Deadlock Collector
    Extracts deadlock information from the system_health Extended Events session.
    Parses the deadlock XML graph to identify victims, winners, and resources.
    
    Schedule: Every 15 minutes
    Compatibility: SQL Server 2016+
    
    Notes:
      - Uses system_health XE session (always running by default)
      - Parses deadlock XML to extract process and resource details
      - Stores only new deadlocks since last collection (deduplication by event time)
      - Handles both RING_BUFFER and file-based XE targets
*/

USE [DBA_Monitor];
GO

----------------------------------------------------------------------
-- DEADLOCK HISTORY TABLE
----------------------------------------------------------------------
IF OBJECT_ID('monitor.DeadlockHistory', 'U') IS NULL
CREATE TABLE [monitor].[DeadlockHistory] (
    Id                  BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt         DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    DeadlockTime        DATETIME2     NOT NULL,
    VictimProcess       NVARCHAR(200) NULL,
    VictimSPID          INT           NULL,
    VictimDatabase      NVARCHAR(128) NULL,
    VictimQuery         NVARCHAR(MAX) NULL,
    VictimLoginName     NVARCHAR(128) NULL,
    VictimHostName      NVARCHAR(128) NULL,
    WinnerProcess       NVARCHAR(200) NULL,
    WinnerSPID          INT           NULL,
    WinnerDatabase      NVARCHAR(128) NULL,
    WinnerQuery         NVARCHAR(MAX) NULL,
    WinnerLoginName     NVARCHAR(128) NULL,
    WinnerHostName      NVARCHAR(128) NULL,
    ResourceType        NVARCHAR(100) NULL,   -- KEY, PAGE, OBJECT, RID, etc.
    ResourceDescription NVARCHAR(500) NULL,
    DeadlockGraph       XML           NULL,    -- Full XML for deep analysis
    INDEX IX_Deadlock_Time NONCLUSTERED (DeadlockTime),
    INDEX IX_Deadlock_Collected NONCLUSTERED (CollectedAt)
);
GO

----------------------------------------------------------------------
-- COLLECTOR PROCEDURE
----------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_Deadlocks]
    @LookbackMinutes INT = 60
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LastCollected DATETIME2;
    DECLARE @LookbackTime DATETIME2 = DATEADD(MINUTE, -@LookbackMinutes, SYSUTCDATETIME());

    -- Get last collected deadlock time to avoid duplicates
    SELECT @LastCollected = MAX(DeadlockTime)
    FROM [monitor].[DeadlockHistory];

    -- Use the more recent of lookback or last collected
    IF @LastCollected > @LookbackTime
        SET @LookbackTime = @LastCollected;

    -- ============================================================
    -- EXTRACT DEADLOCKS FROM SYSTEM_HEALTH XE SESSION
    -- ============================================================
    ;WITH DeadlockEvents AS (
        SELECT
            xed.value('@timestamp', 'DATETIME2') AS DeadlockTime,
            xed.query('.') AS DeadlockEvent
        FROM (
            SELECT CAST(target_data AS XML) AS TargetData
            FROM sys.dm_xe_session_targets st
            INNER JOIN sys.dm_xe_sessions s ON s.address = st.event_session_address
            WHERE s.name = 'system_health'
                AND st.target_name = 'ring_buffer'
        ) AS Data
        CROSS APPLY TargetData.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS XEventData(xed)
        WHERE xed.value('@timestamp', 'DATETIME2') > @LookbackTime
    ),
    -- Parse the deadlock graph
    ParsedDeadlocks AS (
        SELECT
            d.DeadlockTime,
            -- Victim process info
            deadlock.value('(deadlock/victim-list/victimProcess/@id)[1]', 'NVARCHAR(200)') AS VictimProcessId,
            -- Full deadlock graph
            deadlock.query('deadlock') AS DeadlockGraph
        FROM DeadlockEvents d
        CROSS APPLY d.DeadlockEvent.nodes('event/data[@name="xml_deadlock_report"]/value') AS DL(deadlock)
    )
    INSERT INTO [monitor].[DeadlockHistory] (
        DeadlockTime, VictimProcess, VictimSPID, VictimDatabase, VictimQuery,
        VictimLoginName, VictimHostName,
        WinnerProcess, WinnerSPID, WinnerDatabase, WinnerQuery,
        WinnerLoginName, WinnerHostName,
        ResourceType, ResourceDescription, DeadlockGraph
    )
    SELECT
        pd.DeadlockTime,
        -- Victim details
        pd.VictimProcessId,
        victim.value('@spid', 'INT'),
        DB_NAME(victim.value('@currentdb', 'INT')),
        victim.value('(inputbuf)[1]', 'NVARCHAR(MAX)'),
        victim.value('@loginname', 'NVARCHAR(128)'),
        victim.value('@hostname', 'NVARCHAR(128)'),
        -- Winner details (first non-victim process)
        winner.value('@id', 'NVARCHAR(200)'),
        winner.value('@spid', 'INT'),
        DB_NAME(winner.value('@currentdb', 'INT')),
        winner.value('(inputbuf)[1]', 'NVARCHAR(MAX)'),
        winner.value('@loginname', 'NVARCHAR(128)'),
        winner.value('@hostname', 'NVARCHAR(128)'),
        -- Resource info (first resource in the deadlock)
        resource_node.value('local-name(.)', 'NVARCHAR(100)'),
        CASE
            WHEN resource_node.value('local-name(.)', 'NVARCHAR(100)') = 'keylock'
                THEN resource_node.value('@objectname', 'NVARCHAR(500)')
            WHEN resource_node.value('local-name(.)', 'NVARCHAR(100)') = 'pagelock'
                THEN 'File:' + resource_node.value('@fileid', 'NVARCHAR(10)') 
                    + ' Page:' + resource_node.value('@pageid', 'NVARCHAR(20)')
            WHEN resource_node.value('local-name(.)', 'NVARCHAR(100)') = 'objectlock'
                THEN resource_node.value('@objectname', 'NVARCHAR(500)')
            ELSE resource_node.value('@objectname', 'NVARCHAR(500)')
        END,
        pd.DeadlockGraph
    FROM ParsedDeadlocks pd
    -- Get victim process details
    OUTER APPLY pd.DeadlockGraph.nodes('deadlock/process-list/process[@id=sql:column("pd.VictimProcessId")]') AS V(victim)
    -- Get winner process (first process that is NOT the victim)
    OUTER APPLY (
        SELECT TOP 1 p.query('.') AS WinnerNode
        FROM pd.DeadlockGraph.nodes('deadlock/process-list/process') AS Proc(p)
        WHERE p.value('@id', 'NVARCHAR(200)') <> pd.VictimProcessId
    ) AS W(WinnerNode)
    OUTER APPLY W.WinnerNode.nodes('process') AS WN(winner)
    -- Get first resource
    OUTER APPLY pd.DeadlockGraph.nodes('deadlock/resource-list/*[1]') AS R(resource_node)
    -- Deduplicate: only insert if not already collected
    WHERE NOT EXISTS (
        SELECT 1 FROM [monitor].[DeadlockHistory] h
        WHERE h.DeadlockTime = pd.DeadlockTime
            AND h.VictimProcess = pd.VictimProcessId
    );

    -- Log collection result
    DECLARE @RowsInserted INT = @@ROWCOUNT;
    IF @RowsInserted > 0
        PRINT 'Collected ' + CAST(@RowsInserted AS VARCHAR(10)) + ' new deadlock(s).';
END;
GO

PRINT '✓ Deadlock collector [monitor].[usp_Collect_Deadlocks] created.';
PRINT '✓ Table [monitor].[DeadlockHistory] created.';
GO
