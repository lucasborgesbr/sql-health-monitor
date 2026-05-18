/*
    SQL Health Monitor - Blocking Collector
    Detects and records blocking chains.
    
    Schedule: Every 1 minute
    Compatibility: SQL Server 2016+
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_Blocking]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ThresholdSec INT = 
        ISNULL((SELECT CAST(SettingValue AS INT) FROM [monitor].[Settings] 
                WHERE Category = 'Thresholds' AND SettingName = 'BlockingThresholdSec'), 30);

    INSERT INTO [monitor].[BlockingHistory]
        (BlockingSpid, BlockedSpid, BlockingDurationSec, 
         BlockingQuery, BlockedQuery, DatabaseName, WaitType)
    SELECT
        blocker.session_id AS BlockingSpid,
        blocked.session_id AS BlockedSpid,
        DATEDIFF(SECOND, blocked.last_wait_time, GETDATE()) AS BlockingDurationSec,
        (SELECT TOP 1 SUBSTRING(st.text, 
            (blocker_req.statement_start_offset / 2) + 1,
            CASE WHEN blocker_req.statement_end_offset = -1 THEN LEN(st.text)
                 ELSE (blocker_req.statement_end_offset - blocker_req.statement_start_offset) / 2 + 1 END)
         FROM sys.dm_exec_requests blocker_req
         CROSS APPLY sys.dm_exec_sql_text(blocker_req.sql_handle) st
         WHERE blocker_req.session_id = blocker.session_id) AS BlockingQuery,
        SUBSTRING(blocked_text.text,
            (blocked_req.statement_start_offset / 2) + 1,
            CASE WHEN blocked_req.statement_end_offset = -1 THEN LEN(blocked_text.text)
                 ELSE (blocked_req.statement_end_offset - blocked_req.statement_start_offset) / 2 + 1 END
        ) AS BlockedQuery,
        DB_NAME(blocked_req.database_id) AS DatabaseName,
        blocked.wait_type AS WaitType
    FROM sys.dm_exec_sessions blocked
    INNER JOIN sys.dm_exec_requests blocked_req ON blocked_req.session_id = blocked.session_id
    INNER JOIN sys.dm_exec_sessions blocker ON blocker.session_id = blocked_req.blocking_session_id
    CROSS APPLY sys.dm_exec_sql_text(blocked_req.sql_handle) blocked_text
    WHERE blocked_req.blocking_session_id > 0
        AND DATEDIFF(SECOND, blocked.last_wait_time, GETDATE()) >= @ThresholdSec;
END;
GO
