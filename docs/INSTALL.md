# Installation Guide

## Prerequisites

- SQL Server 2016 or later
- `sysadmin` or `db_owner` on target instance
- Database Mail configured (for email alerts/reports)
- SQL Server Agent running (for scheduled jobs)
- PowerShell 5.1+ with `SqlServer` module (for automated deployment)

## Quick Start

### Option 1: PowerShell Deployment (Recommended)

```powershell
# Single server
.\powershell\Deploy-SqlHealthMonitor.ps1 -ServerList "MyServer" -CreateDatabase

# Multiple servers
.\powershell\Deploy-SqlHealthMonitor.ps1 -ServerList "Server1,Server2,Server3" -CreateDatabase

# From file with SQL auth
.\powershell\Deploy-SqlHealthMonitor.ps1 -ServerList .\servers.txt -Credential (Get-Credential) -CreateDatabase
```

### Option 2: Manual Deployment

Execute scripts in this order on each target server:

```sql
-- 1. Create the database (if not exists)
CREATE DATABASE [DBA_Monitor];
GO
USE [DBA_Monitor];
GO

-- 2. Run install scripts in order
-- install/00-create-schema.sql      (tables & schema)
-- install/05-configure.sql          (settings, thresholds, languages)

-- 3. Deploy collectors (all files in collectors/ folder)
-- collectors/collect_cpu.sql
-- collectors/collect_memory.sql
-- collectors/collect_disk.sql
-- collectors/collect_waits.sql
-- collectors/collect_blocking.sql
-- collectors/collect_ag_health.sql
-- collectors/collect_cdc_health.sql
-- collectors/collect_top_queries.sql
-- collectors/collect_index_health.sql
-- collectors/collect_backup_status.sql
-- collectors/collect_job_history.sql
-- collectors/collect_tempdb.sql
-- collectors/collect_log_growth.sql
-- collectors/collect_errorlog.sql

-- 4. Deploy orchestration & reports
-- install/01-create-collectors.sql  (master collector proc)
-- install/02-create-reports.sql     (report runner)
-- reports/daily_health_check.sql    (daily report)
-- reports/weekly_deep_dive.sql      (weekly report)

-- 5. Deploy alerts
-- alerts/alert_engine.sql           (alert engine)
-- alerts/alert_actions.sql          (automated actions)
-- install/03-create-alerts.sql      (alert registration)

-- 6. Deploy maintenance
-- maintenance/purge_old_data.sql    (data retention)
-- maintenance/update_baselines.sql  (performance baselines)

-- 7. Create SQL Agent jobs (run on msdb)
-- install/04-create-jobs.sql
```

## Post-Installation

### 1. Configure Email Settings

```sql
USE [DBA_Monitor];
UPDATE [monitor].[Settings] SET SettingValue = 'your-team@company.com' 
WHERE Category = 'Email' AND SettingName = 'Recipients';

UPDATE [monitor].[Settings] SET SettingValue = 'YourMailProfile' 
WHERE Category = 'Email' AND SettingName = 'ProfileName';
```

### 2. Verify Database Mail

```sql
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = 'YourMailProfile',
    @recipients = 'your-email@company.com',
    @subject = 'SQL Health Monitor - Test',
    @body = 'Installation successful!';
```

### 3. Test Collectors

```sql
-- Run all collectors once
EXEC [monitor].[usp_RunAllCollectors] @ForceRun = 1;

-- Check data was collected
SELECT 'CPU' AS Source, COUNT(*) AS Rows FROM [monitor].[CpuHistory]
UNION ALL SELECT 'Memory', COUNT(*) FROM [monitor].[MemoryHistory]
UNION ALL SELECT 'Disk', COUNT(*) FROM [monitor].[DiskHistory];
```

### 4. Test Reports

```sql
-- Preview daily report (debug mode = shows HTML, doesn't send email)
EXEC [monitor].[usp_Report_DailyHealth] @DebugMode = 1;

-- Preview weekly report
EXEC [monitor].[usp_Report_WeeklyDeepDive] @DebugMode = 1;
```

### 5. Validate Installation

```powershell
.\powershell\Test-Installation.ps1 -ServerInstance "MyServer"
```

## Upgrading

Re-run the deployment scripts. All procedures use `CREATE OR ALTER`, and tables use `IF NOT EXISTS`. Safe to re-run on existing installations.

## Uninstalling

```sql
-- Remove jobs
USE [msdb];
EXEC sp_delete_job @job_name = 'SQL Health Monitor - Collectors';
EXEC sp_delete_job @job_name = 'SQL Health Monitor - Alert Engine';
EXEC sp_delete_job @job_name = 'SQL Health Monitor - Daily Report';
EXEC sp_delete_job @job_name = 'SQL Health Monitor - Weekly Report';
EXEC sp_delete_job @job_name = 'SQL Health Monitor - Purge Old Data';
EXEC sp_delete_job @job_name = 'SQL Health Monitor - Update Baselines';

-- Drop database (WARNING: destroys all historical data)
-- DROP DATABASE [DBA_Monitor];
```
