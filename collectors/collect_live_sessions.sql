/*
    SQL Health Monitor - Live Sessions Collector
    Captures current active sessions with sp_WhoIsActive-style information.

    Features:
    - Current running queries
    - Blocked/blocking session chains
    - Wait info per session
    - Query plans (optional)
    - Input buffers

    Schedule: Every 5 minutes or on-demand
    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

IF OBJECT_ID('[monitor].[usp_Collect_LiveSessions]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_LiveSessions] @IncludePlans BIT = 0, @DebugMode BIT = 0 AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_LiveSessions]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_Collect_LiveSessions] @IncludePlans BIT = 0, @DebugMode BIT = 0 AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

ALTER PROCEDURE [monitor].[usp_Collect_LiveSessions]
    @IncludePlans BIT = 0,  -- 1 = capture query plans (expensive)
    @DebugMode    BIT = 0   -- 1 = SELECT results instead of inserting
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CollectedAt DATETIME2 = SYSUTCDATETIME();

    -- Create temp table for collection
    CREATE TABLE #LiveSessions (
        SessionId           INT,
        SessionStatus       NVARCHAR(30),
        LoginName          NVARCHAR(128),
        HostName           NVARCHAR(128),
        ProgramName        NVARCHAR(128),
        DatabaseName       NVARCHAR(128),
        CommandType        NVARCHAR(30),
        QueryText          NVARCHAR(MAX),
        QueryHash          BINARY(8),
        WaitType           NVARCHAR(120),
        WaitTimeMs         BIGINT,
        BlockedBy          INT,
        BlockingCount      INT,
        CpuTimeMs          BIGINT,
        TotalElapsedTimeMs BIGINT,
        Reads              BIGINT,
        Writes             BIGINT,
        MemoryGrantKB      BIGINT,
        RowCount           BIGINT,
        PercentComplete    INT,
        StartTime          DATETIME2,
        LoginTime          DATETIME2,
        InputBuffer        NVARCHAR(MAX),
        QueryPlan          XML NULL
    );

    -- Capture active sessions
    INSERT INTO #LiveSessions (
        SessionId, SessionStatus, LoginName, HostName, ProgramName,
        DatabaseName, CommandType, QueryText, QueryHash,
        WaitType, WaitTimeMs, BlockedBy, BlockingCount,
        CpuTimeMs, TotalElapsedTimeMs, Reads, Writes,
        MemoryGrantKB, RowCount, PercentComplete, StartTime, LoginTime
    )
    SELECT
        s.session_id                         AS SessionId,
        s.status                             AS SessionStatus,
        s.login_name                         AS LoginName,
        s.host_name                          AS HostName,
        s.program_name                       AS ProgramName,
        DB_NAME(r.database_id)               AS DatabaseName,
        r.command                            AS CommandType,
        SUBSTRING(t.text, 1, 4000)           AS QueryText,
        r.query_hash                         AS QueryHash,
        r.wait_type                          AS WaitType,
        r.wait_time                          AS WaitTimeMs,
        r.blocking_session_id                AS BlockedBy,
        (SELECT COUNT(*) FROM sys.dm_exec_requests r2
         WHERE r2.blocking_session_id = s.session_id) AS BlockingCount,
        r.cpu_time                           AS CpuTimeMs,
        r.total_elapsed_time                 AS TotalElapsedTimeMs,
        r.reads                              AS Reads,
        r.writes                             AS Writes,
        r.memory_grant_kb                    AS MemoryGrantKB,
        r.row_count                          AS RowCount,
        r.percent_complete                   AS PercentComplete,
        r.start_time                         AS StartTime,
        s.login_time                         AS LoginTime
    FROM sys.dm_exec_sessions s
    INNER JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE s.session_id > 50  -- Exclude system sessions
      AND s.is_user_process = 1;

    -- Also capture sleeping sessions that are blocking
    INSERT INTO #LiveSessions (
        SessionId, SessionStatus, LoginName, HostName, ProgramName,
        DatabaseName, CommandType, QueryText,
        WaitType, WaitTimeMs, BlockedBy, BlockingCount,
        CpuTimeMs, TotalElapsedTimeMs, Reads, Writes,
        MemoryGrantKB, RowCount, PercentComplete, StartTime, LoginTime
    )
    SELECT
        s.session_id                         AS SessionId,
        s.status                             AS SessionStatus,
        s.login_name                         AS LoginName,
        s.host_name                          AS HostName,
        s.program_name                       AS ProgramName,
        DB_NAME(r.database_id)               AS DatabaseName,
        'UNLOCKED'                          AS CommandType,
        SUBSTRING(t.text, 1, 4000)          AS QueryText,
        NULL                                 AS QueryHash,
        'CXPACKET'                           AS WaitType,  -- Sleeping but blocking
        0                                    AS WaitTimeMs,
        0                                    AS BlockedBy,
        0                                    AS BlockingCount,
        0                                    AS CpuTimeMs,
        0                                    AS TotalElapsedTimeMs,
        0                                    AS Reads,
        0                                    AS Writes,
        0                                    AS MemoryGrantKB,
        0                                    AS RowCount,
        0                                    AS PercentComplete,
        NULL                                 AS StartTime,
        s.login_time                         AS LoginTime
    FROM sys.dm_exec_sessions s
    INNER JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE s.session_id > 50
      AND s.is_user_process = 1
      AND s.status = 'sleeping'
      AND EXISTS (
          SELECT 1 FROM sys.dm_exec_requests r2
          WHERE r2.blocking_session_id = s.session_id
      );

    -- Get input buffers for blocking sessions
    UPDATE ls
    SET ls.InputBuffer = ib.event_info
    FROM #LiveSessions ls
    CROSS APPLY sys.dm_exec_input_buffer(ls.SessionId, NULL) ib
    WHERE ls.BlockedBy > 0 OR ls.BlockingCount > 0;

    -- Get query plans if requested (expensive)
    IF @IncludePlans = 1
    BEGIN
        UPDATE ls
        SET ls.QueryPlan = qp.query_plan
        FROM #LiveSessions ls
        CROSS APPLY sys.dm_exec_query_plan(ls.SessionId) qp
        WHERE ls.SessionId IN (SELECT session_id FROM sys.dm_exec_requests);
    END

    -- Insert into history
    INSERT INTO [monitor].[LiveSessionsHistory] (
        CollectedAt, SessionId, SessionStatus, LoginName, HostName,
        ProgramName, DatabaseName, CommandType, QueryText, QueryHash,
        WaitType, WaitTimeMs, BlockedBy, BlockingCount,
        CpuTimeMs, TotalElapsedTimeMs, Reads, Writes,
        MemoryGrantKB, RowCount, PercentComplete, StartTime,
        InputBuffer, QueryPlan
    )
    SELECT
        @CollectedAt, SessionId, SessionStatus, LoginName, HostName,
        ProgramName, DatabaseName, CommandType, QueryText, QueryHash,
        WaitType, WaitTimeMs, BlockedBy, BlockingCount,
        CpuTimeMs, TotalElapsedTimeMs, Reads, Writes,
        MemoryGrantKB, RowCount, PercentComplete, StartTime,
        InputBuffer, QueryPlan
    FROM #LiveSessions;

    -- Also log blocking chains to BlockingHistory
    INSERT INTO [monitor].[BlockingHistory] (
        DetectedAt, BlockingSpid, BlockedSpid, BlockingDurationSec,
        BlockingQuery, BlockedQuery, DatabaseName, WaitType
    )
    SELECT DISTINCT
        @CollectedAt,
        ls.BlockedBy                    AS BlockingSpid,
        ls.SessionId                     AS BlockedSpid,
        0                                AS BlockingDurationSec,
        (SELECT TOP 1 QueryText FROM #LiveSessions WHERE SessionId = ls.BlockedBy) AS BlockingQuery,
        ls.QueryText                     AS BlockedQuery,
        ls.DatabaseName,
        ls.WaitType
    FROM #LiveSessions ls
    WHERE ls.BlockedBy > 0;

    -- Output or return
    IF @DebugMode = 1
    BEGIN
        SELECT * FROM #LiveSessions ORDER BY
            CASE WHEN BlockedBy > 0 THEN 0 ELSE 1 END,
            CpuTimeMs DESC;
    END

    DROP TABLE #LiveSessions;

    PRINT '+ Live sessions collected at ' + CONVERT(NVARCHAR, @CollectedAt, 120);
END;
GO

PRINT '+ Procedure [monitor].[usp_Collect_LiveSessions] created.';
GO
