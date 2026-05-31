/*
    SQL Health Monitor - Alert Actions
    Custom automated actions per alert type.
    
    Actions:
      - Kill blocking sessions after threshold
      - Auto-shrink tempdb log if critical
      - Capture diagnostic info on critical alerts
    
    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

CREATE OR ALTER PROCEDURE [monitor].[usp_AlertAction_Execute]
    @MetricName NVARCHAR(100),
    @Severity NVARCHAR(20),
    @CurrentValue DECIMAL(18,2),
    @Context NVARCHAR(500) = NULL,
    @DebugMode BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ActionTaken NVARCHAR(MAX) = NULL;

    -- ============================================================
    -- ACTION: Kill blocking sessions exceeding critical threshold
    -- ============================================================
    IF @MetricName = 'Blocking_DurationSec' AND @Severity = 'Critical'
    BEGIN
        DECLARE @KillThresholdSec INT = ISNULL(
            (SELECT CAST(CriticalValue AS INT) FROM [monitor].[Thresholds] WHERE MetricName = 'Blocking_DurationSec'), 120);

        -- Only kill if blocking exceeds 2x the critical threshold (safety margin)
        IF @CurrentValue >= @KillThresholdSec * 2
        BEGIN
            DECLARE @BlockerSpid INT;
            DECLARE @KillCmd NVARCHAR(50);

            -- Get the lead blocker (not blocked by anyone else)
            SELECT TOP 1 @BlockerSpid = BlockingSpid
            FROM [monitor].[BlockingHistory]
            WHERE DetectedAt >= DATEADD(MINUTE, -5, SYSUTCDATETIME())
                AND BlockingDurationSec >= @KillThresholdSec * 2
                AND BlockingSpid NOT IN (
                    SELECT BlockedSpid FROM [monitor].[BlockingHistory]
                    WHERE DetectedAt >= DATEADD(MINUTE, -5, SYSUTCDATETIME())
                )
            ORDER BY BlockingDurationSec DESC;

            IF @BlockerSpid IS NOT NULL AND @DebugMode = 0
            BEGIN
                SET @KillCmd = 'KILL ' + CAST(@BlockerSpid AS NVARCHAR);
                
                BEGIN TRY
                    EXEC sp_executesql @KillCmd;
                    SET @ActionTaken = 'Killed blocking SPID ' + CAST(@BlockerSpid AS NVARCHAR) 
                        + ' (blocking for ' + CAST(CAST(@CurrentValue AS INT) AS NVARCHAR) + 's)';
                END TRY
                BEGIN CATCH
                    SET @ActionTaken = 'Failed to kill SPID ' + CAST(@BlockerSpid AS NVARCHAR) 
                        + ': ' + ERROR_MESSAGE();
                END CATCH;
            END
            ELSE IF @DebugMode = 1
            BEGIN
                SET @ActionTaken = '[DEBUG] Would kill SPID ' + ISNULL(CAST(@BlockerSpid AS NVARCHAR), 'NULL');
            END;
        END;
    END;

    -- ============================================================
    -- ACTION: Capture diagnostic snapshot on critical CPU
    -- ============================================================
    IF @MetricName = 'CPU_SqlPct' AND @Severity = 'Critical'
    BEGIN
        -- Capture top CPU queries at the moment of alert
        INSERT INTO [monitor].[TopQueriesHistory] (DatabaseName, QueryHash, TotalCpuMs, TotalReads, TotalWrites, ExecutionCount, AvgDurationMs, QueryText)
        SELECT TOP 5
            DB_NAME(r.database_id),
            qs.query_hash,
            qs.total_worker_time / 1000,
            qs.total_logical_reads,
            qs.total_logical_writes,
            qs.execution_count,
            (qs.total_elapsed_time / NULLIF(qs.execution_count, 0)) / 1000,
            SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1,
                CASE WHEN qs.statement_end_offset = -1 THEN LEN(st.text)
                     ELSE (qs.statement_end_offset - qs.statement_start_offset) / 2 + 1 END)
        FROM sys.dm_exec_requests r
        INNER JOIN sys.dm_exec_query_stats qs ON r.sql_handle = qs.sql_handle
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
        WHERE r.session_id > 50
        ORDER BY r.cpu_time DESC;

        SET @ActionTaken = ISNULL(@ActionTaken + ' | ', '') + 'Captured CPU diagnostic snapshot (top 5 queries)';
    END;

    -- ============================================================
    -- ACTION: Log TempDB consumers on critical TempDB usage
    -- ============================================================
    IF @MetricName = 'TempDB_UsedPct' AND @Severity = 'Critical'
    BEGIN
        -- Log top TempDB consumers to error log for investigation
        DECLARE @TempMsg NVARCHAR(500);
        SELECT TOP 1 @TempMsg = 'Top TempDB consumer: Session ' + CAST(session_id AS NVARCHAR) 
            + ' using ' + CAST(CAST((user_objects_alloc_page_count + internal_objects_alloc_page_count) * 8 / 1024.0 AS DECIMAL(10,1)) AS NVARCHAR) + ' MB'
        FROM sys.dm_db_session_space_usage
        WHERE session_id > 50
        ORDER BY (user_objects_alloc_page_count + internal_objects_alloc_page_count) DESC;

        IF @TempMsg IS NOT NULL
        BEGIN
            INSERT INTO [monitor].[ErrorLogHistory] (LogDate, ProcessInfo, ErrorMessage, Severity)
            VALUES (SYSUTCDATETIME(), 'Alert Action', @TempMsg, 'Warning');
            SET @ActionTaken = ISNULL(@ActionTaken + ' | ', '') + @TempMsg;
        END;
    END;

    -- ============================================================
    -- ACTION: Log AG failover risk on critical lag
    -- ============================================================
    IF @MetricName = 'AG_SecondsBehind' AND @Severity = 'Critical'
    BEGIN
        INSERT INTO [monitor].[ErrorLogHistory] (LogDate, ProcessInfo, ErrorMessage, Severity)
        VALUES (SYSUTCDATETIME(), 'Alert Action', 
            'AG replica ' + ISNULL(@Context, 'unknown') + ' is ' + CAST(CAST(@CurrentValue AS INT) AS NVARCHAR) 
            + 's behind primary. Data loss risk on failover.', 'Critical');
        SET @ActionTaken = ISNULL(@ActionTaken + ' | ', '') + 'Logged AG failover risk warning';
    END;

    -- Log action taken
    IF @ActionTaken IS NOT NULL
    BEGIN
        INSERT INTO [monitor].[ErrorLogHistory] (LogDate, ProcessInfo, ErrorMessage, Severity)
        VALUES (SYSUTCDATETIME(), 'Alert Action', 
            'Action for [' + @MetricName + '/' + @Severity + ']: ' + @ActionTaken, 'Info');
    END;

    IF @DebugMode = 1 AND @ActionTaken IS NOT NULL
        PRINT 'Action taken: ' + @ActionTaken;
END;
GO

PRINT '✓ Alert actions [monitor].[usp_AlertAction_Execute] created.';
GO
