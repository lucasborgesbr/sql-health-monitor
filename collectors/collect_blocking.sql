/*
    SQL Health Monitor - Blocking Collector
    Collects current blocking sessions and blocking chains.
    
    Schedule: Every 2 minutes
    Compatibility: SQL Server 2016+
*/

IF OBJECT_ID('[monitor].[usp_Collect_Blocking]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_Blocking] AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_Blocking]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_Collect_Blocking] AS SET NOCOUNT ON; PRINT ''Placeholder'';');
GO
ALTER PROCEDURE [monitor].[usp_Collect_Blocking]
AS
BEGIN
    SET NOCOUNT ON;

    -- Schema columns: DetectedAt, BlockingSpid, BlockedSpid, BlockingDurationSec,
    --                 BlockingQuery, BlockedQuery, DatabaseName, WaitType
    INSERT INTO [monitor].[BlockingHistory]
        (BlockingSpid, BlockedSpid, BlockingDurationSec,
         BlockingQuery, BlockedQuery, DatabaseName, WaitType)
    SELECT
        blocker.session_id                                              AS BlockingSpid,
        blocked.session_id                                             AS BlockedSpid,
        blocked.wait_time / 1000                                       AS BlockingDurationSec,
        SUBSTRING(st_blocker.text,
            (blocker.statement_start_offset / 2) + 1,
            ((CASE blocker.statement_end_offset
                WHEN -1 THEN DATALENGTH(st_blocker.text)
                ELSE blocker.statement_end_offset
              END - blocker.statement_start_offset) / 2) + 1)         AS BlockingQuery,
        SUBSTRING(st_blocked.text,
            (blocked.statement_start_offset / 2) + 1,
            ((CASE blocked.statement_end_offset
                WHEN -1 THEN DATALENGTH(st_blocked.text)
                ELSE blocked.statement_end_offset
              END - blocked.statement_start_offset) / 2) + 1)         AS BlockedQuery,
        DB_NAME(blocked.database_id)                                   AS DatabaseName,
        blocked.wait_type                                              AS WaitType
    FROM sys.dm_exec_requests blocker
    INNER JOIN sys.dm_exec_requests blocked
        ON blocked.blocking_session_id = blocker.session_id
    CROSS APPLY sys.dm_exec_sql_text(blocker.sql_handle) AS st_blocker
    CROSS APPLY sys.dm_exec_sql_text(blocked.sql_handle)  AS st_blocked
    WHERE blocked.blocking_session_id <> 0
      AND blocked.wait_type IS NOT NULL
      AND blocked.wait_type <> 'TASK_COMPLETION';
END;
GO