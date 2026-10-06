/*
    SQL Health Monitor - Uninstall
    Removes all SQL Agent Jobs created by this tool, then drops the database.

    WARNING: This is irreversible. All collected metrics, alert history, and configuration
    will be permanently deleted.

    Run from master or any other database (NOT from SQLHealthMonitor itself).

    Usage:
        sqlcmd -S <server> -E -i Uninstall.sql
        or via deploy\Uninstall.ps1
*/

:setvar DatabaseName "SQLHealthMonitor"

USE [master];
GO

PRINT 'SQL Health Monitor - Uninstall';
PRINT '-------------------------------';

-- ============================================================
-- REMOVE SQL AGENT JOBS
-- ============================================================
DECLARE @Jobs TABLE (JobName NVARCHAR(128));
INSERT @Jobs VALUES
    ('SQL Health Monitor - Collectors'),
    ('SQL Health Monitor - Alert Engine'),
    ('SQL Health Monitor - Daily Report'),
    ('SQL Health Monitor - Weekly Report'),
    ('SQL Health Monitor - Purge Old Data'),
    ('SQL Health Monitor - Update Baselines');

DECLARE @JobName NVARCHAR(128);
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT JobName FROM @Jobs;
OPEN cur;
FETCH NEXT FROM cur INTO @JobName;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
    BEGIN
        EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;
        PRINT '  Dropped job: ' + @JobName;
    END
    ELSE
        PRINT '  Skipped (not found): ' + @JobName;

    FETCH NEXT FROM cur INTO @JobName;
END;
CLOSE cur; DEALLOCATE cur;

-- ============================================================
-- DROP DATABASE
-- ============================================================
IF DB_ID('$(DatabaseName)') IS NOT NULL
BEGIN
    ALTER DATABASE [$(DatabaseName)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$(DatabaseName)];
    PRINT '  Dropped database: $(DatabaseName)';
END
ELSE
    PRINT '  Skipped (not found): database $(DatabaseName)';

PRINT '';
PRINT 'Uninstall complete.';
GO
