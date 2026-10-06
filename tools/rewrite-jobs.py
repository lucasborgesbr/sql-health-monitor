#!/usr/bin/env python3
"""
Rewrite install/04-create-jobs.sql so an upgrade refreshes job steps without
discarding schedules.

Today every run deletes all six Agent jobs and recreates them, so a schedule an
operator adjusted by hand is silently reset. The rule the rewrite applies:

    job absent  -> create it with the repository's step and schedule
    job present -> update the step only, never the schedule

Steps belong to the release: a fix to a procedure call has to reach the job.
Schedules belong to the operator: an adjusted run time has to survive.

Schedule deletion stays available behind -ResetSchedules, which arrives as the
sqlcmd variable $(ResetSchedules).
"""
import re

PATH = "install/04-create-jobs.sql"
src = open(PATH, encoding="utf-8-sig").read()


def grab(pattern, text):
    m = re.search(pattern, text, re.S)
    return m.group(1) if m else None


def indent(block):
    return "\n".join("    " + ln if ln.strip() else ln for ln in block.split("\n"))


# -- 1. gate the delete cursor behind -ResetSchedules ------------------------------

old_del = """DECLARE @JobName NVARCHAR(128);

-- Clean up existing jobs for re-runs
DECLARE @JobsToCreate TABLE (JobName NVARCHAR(128));"""

new_del = """DECLARE @JobName NVARCHAR(128);

-- Delete-and-recreate only when the operator asked for the repository's
-- schedules back (-ResetSchedules). An ordinary upgrade must never discard a
-- schedule someone adjusted.
DECLARE @ResetSchedules INT = TRY_CONVERT(INT, '$(ResetSchedules)');

DECLARE @JobsToCreate TABLE (JobName NVARCHAR(128));"""

if old_del in src:
    src = src.replace(old_del, new_del, 1)
else:
    print("delete-cursor header: already rewritten, skipping")

# wrap the cursor body
old_open = """OPEN job_cursor;
FETCH NEXT FROM job_cursor INTO @JobName;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
        EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;
    FETCH NEXT FROM job_cursor INTO @JobName;
END;
CLOSE job_cursor;
DEALLOCATE job_cursor;
GO"""

new_open = """IF @ResetSchedules = 1
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
GO"""

if old_open in src:
    src = src.replace(old_open, new_open, 1)
else:
    print("cursor body: already rewritten, skipping")

# -- 2. rewrite each job ------------------------------------------------------------

JOB_RX = re.compile(
    r"(DECLARE @JobId UNIQUEIDENTIFIER;\s*\n"
    r"(?:DECLARE @ScheduleId INT;\s*\n)?"
    r"DECLARE @Owner NVARCHAR\(128\) = SUSER_SNAME\(\);\s*\n\n"
    r"EXEC msdb\.dbo\.sp_add_job\s*@job_name = N'(?P<name>[^']+)'.*?"
    r"EXEC msdb\.dbo\.sp_add_jobstep.*?EXEC msdb\.dbo\.sp_add_jobschedule.*?"
    r"EXEC msdb\.dbo\.sp_add_jobserver @job_id = @JobId, @server_name = N'\(local\)';\s*\nGO)",
    re.S)

count = 0


def rewrite_job(m):
    global count
    block = m.group(0)
    name = m.group("name")
    count += 1

    add_job = grab(r"(EXEC msdb\.dbo\.sp_add_job\s*@job_name.*?@job_id = @JobId OUTPUT;)", block)
    add_step = grab(r"(EXEC msdb\.dbo\.sp_add_jobstep.*?@on_fail_action = \d+;)", block)
    add_sched = grab(r"(EXEC msdb\.dbo\.sp_add_jobschedule.*?@active_start_time = \d+[^;]*;)", block)
    step_name = grab(r"@step_name = N'([^']+)'", add_step)

    assert add_job and add_step and add_sched and step_name, "could not parse a job block"

    return f"""DECLARE @JobId UNIQUEIDENTIFIER;
DECLARE @Owner NVARCHAR(128) = SUSER_SNAME();

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'{name}')
BEGIN
{indent(add_job)}

{indent(add_step)}

{indent(add_sched)}

    EXEC msdb.dbo.sp_add_jobserver @job_id = @JobId, @server_name = N'(local)';
    PRINT '+ Created job: {name}';
END
ELSE
BEGIN
    SELECT @JobId = job_id FROM msdb.dbo.sysjobs WHERE name = N'{name}';

    -- Steps belong to the release, so a fix to a procedure call reaches the
    -- job. Schedules belong to the operator, so the schedule is left alone.
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobsteps WHERE job_id = @JobId AND step_id = 1)
    BEGIN
{indent(add_step.replace('sp_add_jobstep', 'sp_update_jobstep'))}
    END
    ELSE
    BEGIN
{indent(add_step)}
    END;

    PRINT '  Updated step on existing job: {name} (schedule untouched)';
END
GO"""


src = JOB_RX.sub(rewrite_job, src)
open(PATH, "w", encoding="utf-8", newline="").write(src)
print("rewrote %d job blocks" % count)