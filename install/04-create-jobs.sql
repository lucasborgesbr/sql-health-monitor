/*
    SQL Health Monitor - SQL Agent Jobs Creation
    Creates all scheduled jobs for collectors, reports, and alerts.
    
    Run after: 03-create-alerts.sql
    Compatibility: SQL Server 2016+
    
    Jobs created:
      - SQL Health Monitor - Collectors (every 5 min)
      - SQL Health Monitor - Alert Engine (every 5 min)
      - SQL Health Monitor - Daily Report (7:00 AM)
      - SQL Health Monitor - Weekly Report (Monday 8:00 AM)
      - SQL Health Monitor - Purge Old Data (daily 3:00 AM)
      - SQL Health Monitor - Update Baselines (Sunday 2:00 AM)
*/

USE [msdb];
GO

----------------------------------------------------------------------
-- HELPER: Delete job if exists
----------------------------------------------------------------------
DECLARE @JobName NVARCHAR(128);

-- Delete-and-recreate only when the operator asked for the repository's
-- schedules back (-ResetSchedules). An ordinary upgrade must never discard a
-- schedule someone adjusted.
DECLARE @ResetSchedules INT = TRY_CONVERT(INT, '$(ResetSchedules)');

DECLARE @JobsToCreate TABLE (JobName NVARCHAR(128));
INSERT INTO @JobsToCreate VALUES
    (N'SQL Health Monitor - Collectors'),
    (N'SQL Health Monitor - Alert Engine'),
    (N'SQL Health Monitor - Daily Report'),
    (N'SQL Health Monitor - Weekly Report'),
    (N'SQL Health Monitor - Purge Old Data'),
    (N'SQL Health Monitor - Update Baselines');

DECLARE job_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT JobName FROM @JobsToCreate;

IF @ResetSchedules = 1
BEGIN
    OPEN job_cursor;
    FETCH NEXT FROM job_cursor INTO @JobName;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
            EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;
        FETCH NEXT FROM job_cursor INTO @JobName;
    END;
    CLOSE job_cursor;
    DEALLOCATE job_cursor;
    PRINT '  Schedules reset to the repository defaults.';
END;
GO

----------------------------------------------------------------------
-- JOB 1: Collectors (every 5 minutes)
----------------------------------------------------------------------
DECLARE @JobId UNIQUEIDENTIFIER;
DECLARE @Owner NVARCHAR(128) = SUSER_SNAME();

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'SQL Health Monitor - Collectors')
BEGIN
    EXEC msdb.dbo.sp_add_job
        @job_name = N'SQL Health Monitor - Collectors',
        @enabled = 1,
        @description = N'Runs all SQL Health Monitor collectors every 5 minutes.',
        @category_name = N'Database Maintenance',
        @owner_login_name = @Owner,
        @job_id = @JobId OUTPUT;

    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobId,
        @step_name = N'Run All Collectors',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_RunAllCollectors];',
        @database_name = N'SQLHealthMonitor',
        @on_success_action = 1,
        @on_fail_action = 2;

    EXEC msdb.dbo.sp_add_jobschedule
        @job_id = @JobId,
        @name = N'Every 5 Minutes',
        @freq_type = 4,           -- Daily
        @freq_interval = 1,
        @freq_subday_type = 4,    -- Minutes
        @freq_subday_interval = 5,
        @active_start_time = 0;

    EXEC msdb.dbo.sp_add_jobserver @job_id = @JobId, @server_name = N'(local)';
    PRINT '+ Created job: SQL Health Monitor - Collectors';
END
ELSE
BEGIN
    SELECT @JobId = job_id FROM msdb.dbo.sysjobs WHERE name = N'SQL Health Monitor - Collectors';

    -- Steps belong to the release, so a fix to a procedure call reaches the
    -- job. Schedules belong to the operator, so the schedule is left alone.
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobsteps WHERE job_id = @JobId AND step_id = 1)
    BEGIN
    EXEC msdb.dbo.sp_update_jobstep
        @job_id = @JobId,
        @step_name = N'Run All Collectors',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_RunAllCollectors];',
        @database_name = N'SQLHealthMonitor',
        @on_success_action = 1,
        @on_fail_action = 2;
    END
    ELSE
    BEGIN
    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobId,
        @step_name = N'Run All Collectors',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_RunAllCollectors];',
        @database_name = N'SQLHealthMonitor',
        @on_success_action = 1,
        @on_fail_action = 2;
    END;

    PRINT '  Updated step on existing job: SQL Health Monitor - Collectors (schedule untouched)';
END
GO

----------------------------------------------------------------------
-- JOB 2: Alert Engine (every 5 minutes)
----------------------------------------------------------------------
DECLARE @JobId UNIQUEIDENTIFIER;
DECLARE @Owner NVARCHAR(128) = SUSER_SNAME();

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'SQL Health Monitor - Alert Engine')
BEGIN
    EXEC msdb.dbo.sp_add_job
        @job_name = N'SQL Health Monitor - Alert Engine',
        @enabled = 1,
        @description = N'Checks metrics against thresholds and fires alerts.',
        @category_name = N'Database Maintenance',
        @owner_login_name = @Owner,
        @job_id = @JobId OUTPUT;

    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobId,
        @step_name = N'Run Alert Engine',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_RunAlertEngine];',
        @database_name = N'SQLHealthMonitor',
        @on_success_action = 1,
        @on_fail_action = 2;

    EXEC msdb.dbo.sp_add_jobschedule
        @job_id = @JobId,
        @name = N'Every 5 Minutes',
        @freq_type = 4,
        @freq_interval = 1,
        @freq_subday_type = 4,
        @freq_subday_interval = 5,
        @active_start_time = 0;

    EXEC msdb.dbo.sp_add_jobserver @job_id = @JobId, @server_name = N'(local)';
    PRINT '+ Created job: SQL Health Monitor - Alert Engine';
END
ELSE
BEGIN
    SELECT @JobId = job_id FROM msdb.dbo.sysjobs WHERE name = N'SQL Health Monitor - Alert Engine';

    -- Steps belong to the release, so a fix to a procedure call reaches the
    -- job. Schedules belong to the operator, so the schedule is left alone.
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobsteps WHERE job_id = @JobId AND step_id = 1)
    BEGIN
    EXEC msdb.dbo.sp_update_jobstep
        @job_id = @JobId,
        @step_name = N'Run Alert Engine',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_RunAlertEngine];',
        @database_name = N'SQLHealthMonitor',
        @on_success_action = 1,
        @on_fail_action = 2;
    END
    ELSE
    BEGIN
    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobId,
        @step_name = N'Run Alert Engine',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_RunAlertEngine];',
        @database_name = N'SQLHealthMonitor',
        @on_success_action = 1,
        @on_fail_action = 2;
    END;

    PRINT '  Updated step on existing job: SQL Health Monitor - Alert Engine (schedule untouched)';
END
GO

----------------------------------------------------------------------
-- JOB 3: Daily Report (7:00 AM)
----------------------------------------------------------------------
DECLARE @JobId UNIQUEIDENTIFIER;
DECLARE @Owner NVARCHAR(128) = SUSER_SNAME();

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'SQL Health Monitor - Daily Report')
BEGIN
    EXEC msdb.dbo.sp_add_job
        @job_name = N'SQL Health Monitor - Daily Report',
        @enabled = 1,
        @description = N'Generates and sends the daily health report.',
        @category_name = N'Database Maintenance',
        @owner_login_name = @Owner,
        @job_id = @JobId OUTPUT;

    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobId,
        @step_name = N'Generate Daily Report',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_RunReport] @ReportType = ''Daily'';',
        @database_name = N'SQLHealthMonitor',
        @on_success_action = 1,
        @on_fail_action = 2;

    EXEC msdb.dbo.sp_add_jobschedule
        @job_id = @JobId,
        @name = N'Daily at 7AM',
        @freq_type = 4,           -- Daily
        @freq_interval = 1,
        @active_start_time = 70000;

    EXEC msdb.dbo.sp_add_jobserver @job_id = @JobId, @server_name = N'(local)';
    PRINT '+ Created job: SQL Health Monitor - Daily Report';
END
ELSE
BEGIN
    SELECT @JobId = job_id FROM msdb.dbo.sysjobs WHERE name = N'SQL Health Monitor - Daily Report';

    -- Steps belong to the release, so a fix to a procedure call reaches the
    -- job. Schedules belong to the operator, so the schedule is left alone.
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobsteps WHERE job_id = @JobId AND step_id = 1)
    BEGIN
    EXEC msdb.dbo.sp_update_jobstep
        @job_id = @JobId,
        @step_name = N'Generate Daily Report',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_RunReport] @ReportType = ''Daily'';',
        @database_name = N'SQLHealthMonitor',
        @on_success_action = 1,
        @on_fail_action = 2;
    END
    ELSE
    BEGIN
    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobId,
        @step_name = N'Generate Daily Report',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_RunReport] @ReportType = ''Daily'';',
        @database_name = N'SQLHealthMonitor',
        @on_success_action = 1,
        @on_fail_action = 2;
    END;

    PRINT '  Updated step on existing job: SQL Health Monitor - Daily Report (schedule untouched)';
END
GO

----------------------------------------------------------------------
-- JOB 4: Weekly Report (Monday 8:00 AM)
----------------------------------------------------------------------
DECLARE @JobId UNIQUEIDENTIFIER;
DECLARE @Owner NVARCHAR(128) = SUSER_SNAME();

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'SQL Health Monitor - Weekly Report')
BEGIN
    EXEC msdb.dbo.sp_add_job
        @job_name = N'SQL Health Monitor - Weekly Report',
        @enabled = 1,
        @description = N'Generates and sends the weekly deep dive report.',
        @category_name = N'Database Maintenance',
        @owner_login_name = @Owner,
        @job_id = @JobId OUTPUT;

    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobId,
        @step_name = N'Generate Weekly Report',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_RunReport] @ReportType = ''Weekly'';',
        @database_name = N'SQLHealthMonitor',
        @on_success_action = 1,
        @on_fail_action = 2;

    EXEC msdb.dbo.sp_add_jobschedule
        @job_id = @JobId,
        @name = N'Monday at 8AM',
        @freq_type = 8,           -- Weekly
        @freq_interval = 2,       -- Monday
        @freq_recurrence_factor = 1,
        @active_start_time = 80000;

    EXEC msdb.dbo.sp_add_jobserver @job_id = @JobId, @server_name = N'(local)';
    PRINT '+ Created job: SQL Health Monitor - Weekly Report';
END
ELSE
BEGIN
    SELECT @JobId = job_id FROM msdb.dbo.sysjobs WHERE name = N'SQL Health Monitor - Weekly Report';

    -- Steps belong to the release, so a fix to a procedure call reaches the
    -- job. Schedules belong to the operator, so the schedule is left alone.
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobsteps WHERE job_id = @JobId AND step_id = 1)
    BEGIN
    EXEC msdb.dbo.sp_update_jobstep
        @job_id = @JobId,
        @step_name = N'Generate Weekly Report',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_RunReport] @ReportType = ''Weekly'';',
        @database_name = N'SQLHealthMonitor',
        @on_success_action = 1,
        @on_fail_action = 2;
    END
    ELSE
    BEGIN
    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobId,
        @step_name = N'Generate Weekly Report',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_RunReport] @ReportType = ''Weekly'';',
        @database_name = N'SQLHealthMonitor',
        @on_success_action = 1,
        @on_fail_action = 2;
    END;

    PRINT '  Updated step on existing job: SQL Health Monitor - Weekly Report (schedule untouched)';
END
GO

----------------------------------------------------------------------
-- JOB 5: Purge Old Data (daily 3:00 AM)
----------------------------------------------------------------------
DECLARE @JobId UNIQUEIDENTIFIER;
DECLARE @Owner NVARCHAR(128) = SUSER_SNAME();

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'SQL Health Monitor - Purge Old Data')
BEGIN
    EXEC msdb.dbo.sp_add_job
        @job_name = N'SQL Health Monitor - Purge Old Data',
        @enabled = 1,
        @description = N'Removes data older than retention period.',
        @category_name = N'Database Maintenance',
        @owner_login_name = @Owner,
        @job_id = @JobId OUTPUT;

    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobId,
        @step_name = N'Purge Old Data',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_PurgeHistoricalData];',
        @database_name = N'SQLHealthMonitor',
        @on_success_action = 1,
        @on_fail_action = 2;

    EXEC msdb.dbo.sp_add_jobschedule
        @job_id = @JobId,
        @name = N'Daily at 3AM',
        @freq_type = 4,
        @freq_interval = 1,
        @active_start_time = 30000;

    EXEC msdb.dbo.sp_add_jobserver @job_id = @JobId, @server_name = N'(local)';
    PRINT '+ Created job: SQL Health Monitor - Purge Old Data';
END
ELSE
BEGIN
    SELECT @JobId = job_id FROM msdb.dbo.sysjobs WHERE name = N'SQL Health Monitor - Purge Old Data';

    -- Steps belong to the release, so a fix to a procedure call reaches the
    -- job. Schedules belong to the operator, so the schedule is left alone.
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobsteps WHERE job_id = @JobId AND step_id = 1)
    BEGIN
    EXEC msdb.dbo.sp_update_jobstep
        @job_id = @JobId,
        @step_name = N'Purge Old Data',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_PurgeHistoricalData];',
        @database_name = N'SQLHealthMonitor',
        @on_success_action = 1,
        @on_fail_action = 2;
    END
    ELSE
    BEGIN
    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobId,
        @step_name = N'Purge Old Data',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_PurgeHistoricalData];',
        @database_name = N'SQLHealthMonitor',
        @on_success_action = 1,
        @on_fail_action = 2;
    END;

    PRINT '  Updated step on existing job: SQL Health Monitor - Purge Old Data (schedule untouched)';
END
GO

----------------------------------------------------------------------
-- JOB 6: Update Baselines (Sunday 2:00 AM)
----------------------------------------------------------------------
DECLARE @JobId UNIQUEIDENTIFIER;
DECLARE @Owner NVARCHAR(128) = SUSER_SNAME();

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'SQL Health Monitor - Update Baselines')
BEGIN
    EXEC msdb.dbo.sp_add_job
        @job_name = N'SQL Health Monitor - Update Baselines',
        @enabled = 1,
        @description = N'Recalculates performance baselines weekly.',
        @category_name = N'Database Maintenance',
        @owner_login_name = @Owner,
        @job_id = @JobId OUTPUT;

    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobId,
        @step_name = N'Update Baselines',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_Maintenance_UpdateBaselines];',
        @database_name = N'SQLHealthMonitor',
        @on_success_action = 1,
        @on_fail_action = 2;

    EXEC msdb.dbo.sp_add_jobschedule
        @job_id = @JobId,
        @name = N'Sunday at 2AM',
        @freq_type = 8,           -- Weekly
        @freq_interval = 1,       -- Sunday
        @freq_recurrence_factor = 1,
        @active_start_time = 20000;

    EXEC msdb.dbo.sp_add_jobserver @job_id = @JobId, @server_name = N'(local)';
    PRINT '+ Created job: SQL Health Monitor - Update Baselines';
END
ELSE
BEGIN
    SELECT @JobId = job_id FROM msdb.dbo.sysjobs WHERE name = N'SQL Health Monitor - Update Baselines';

    -- Steps belong to the release, so a fix to a procedure call reaches the
    -- job. Schedules belong to the operator, so the schedule is left alone.
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobsteps WHERE job_id = @JobId AND step_id = 1)
    BEGIN
    EXEC msdb.dbo.sp_update_jobstep
        @job_id = @JobId,
        @step_name = N'Update Baselines',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_Maintenance_UpdateBaselines];',
        @database_name = N'SQLHealthMonitor',
        @on_success_action = 1,
        @on_fail_action = 2;
    END
    ELSE
    BEGIN
    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobId,
        @step_name = N'Update Baselines',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_Maintenance_UpdateBaselines];',
        @database_name = N'SQLHealthMonitor',
        @on_success_action = 1,
        @on_fail_action = 2;
    END;

    PRINT '  Updated step on existing job: SQL Health Monitor - Update Baselines (schedule untouched)';
END
GO

PRINT '✓ All SQL Agent jobs created successfully.';
PRINT '  - SQL Health Monitor - Collectors (every 5 min)';
PRINT '  - SQL Health Monitor - Alert Engine (every 5 min)';
PRINT '  - SQL Health Monitor - Daily Report (7:00 AM)';
PRINT '  - SQL Health Monitor - Weekly Report (Monday 8:00 AM)';
PRINT '  - SQL Health Monitor - Purge Old Data (daily 3:00 AM)';
PRINT '  - SQL Health Monitor - Update Baselines (Sunday 2:00 AM)';
GO
