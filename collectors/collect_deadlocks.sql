/*
    SQL Health Monitor - Deadlocks Collector
    Collects deadlock information from extended events or system views.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_Deadlocks]
AS
BEGIN
    SET NOCOUNT ON;

    -- Check if extended events are available for deadlock capture
    IF EXISTS (SELECT 1 FROM sys.dm_xe_sessions WHERE name = 'system_health')
    BEGIN
        -- Query system_health session for deadlock events
        INSERT INTO [monitor].[DeadlockHistory]
            (DeadlockDate, DeadlockGraph, VictimSPID, VictimDatabase, 
             VictimObject, WaitType, WaitDuration, BlockingSPID)
        SELECT
            SYSDATETIME() AS DeadlockDate,
            NULL AS DeadlockGraph,
            NULL AS VictimSPID,
            NULL AS VictimDatabase,
            NULL AS VictimObject,
            NULL AS WaitType,
            NULL AS WaitDuration,
            NULL AS BlockingSPID
        WHERE 1 = 0;  -- Placeholder for extended events query
        
        -- Note: Extended events query requires specific target configuration
        -- This is a simplified version - consider using a dedicated deadlock capture session
    END
    ELSE
    BEGIN
        -- Alternative: Check recent deadlock activity from system views
        INSERT INTO [monitor].[DeadlockHistory]
            (DeadlockDate, DeadlockGraph, VictimSPID, VictimDatabase, 
             VictimObject, WaitType, WaitDuration, BlockingSPID)
        SELECT
            SYSDATETIME() AS DeadlockDate,
            NULL AS DeadlockGraph,
            NULL AS VictimSPID,
            NULL AS VictimDatabase,
            NULL AS VictimObject,
            NULL AS WaitType,
            NULL AS WaitDuration,
            NULL AS BlockingSPID
        WHERE 1 = 0;  -- Placeholder for deadlock detection
        
        -- Note: Real deadlock detection requires extended events or trace flags
    END;
END;
GO
