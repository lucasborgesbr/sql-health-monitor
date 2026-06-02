# SQL Health Monitor - Database Name Standardization

## Overview
Standardized the database name across all files in the SQL Health Monitor project to use `SQLHealthMonitor` as the canonical name.

## Changes Made

### 1. README.md
- Updated manual installation examples to use `SQLHealthMonitor`
- Updated example configurations to use `SQLHealthMonitor` instead of `SQLHealthMonitor`
- Fixed all inline SQL examples in troubleshooting section

### 2. Install Scripts (install/)
- `00-create-schema.sql`: Updated target database and USE statement
- `01-create-collectors.sql`: Updated USE statement
- `02-create-reports.sql`: Updated USE statement
- `03-create-alerts.sql`: Updated USE statement
- `04-create-jobs.sql`: Updated all 6 job creation references
- `05-configure.sql`: Updated USE statement
- `06-alert-history.sql`: Updated USE statement
- `07-baselines.sql`: Updated USE statement

### 3. Maintenance Scripts (maintenance/)
- `purge_old_data.sql`: Updated USE statement
- `update_baselines.sql`: Updated USE statement
- `retention_config.sql`: Updated USE statement

### 4. Multi-Instance Scripts (multi-instance/)
- `cms_tables.sql`: Updated default database name in table definition
- `register_sample.sql`: Updated all 6 sample instance registrations
- `collect_all_instances.sql`: Updated USE statement
- `compare_instances.sql`: Updated USE statement

### 5. Alert Scripts (alerts/)
- `alert_engine.sql`: Updated USE statement
- `alert_actions.sql`: Updated USE statement
- `thresholds_default.sql`: Updated USE statement

### 6. Baseline Scripts (baselines/)
- `baseline_tables.sql`: Updated target database and USE statement
- `capture_baseline.sql`: Updated USE statement
- `detect_anomalies.sql`: Updated USE statement

### 7. Report Scripts (reports/)
- `enhanced_analytics.sql`: Updated USE statement
- `daily_health_check.sql`: Updated USE statement
- `weekly_deep_dive.sql`: Updated USE statement

### 8. PowerShell Scripts (powershell/)
- `Deploy-SqlHealthMonitor.ps1`: Updated default database name and documentation
- `Start-SQLHealthMonitorSetup.ps1`: Updated default database name in wizard
- `Test-Installation.ps1`: Updated default database name

### 9. PowerShell Scripts (scripts/)
- `Configure-SQLHealthMonitor.ps1`: Updated all example commands
- `Deploy-SQLHealthMonitorJobs.ps1`: Updated all example commands
- `Install-SQLHealthMonitor.ps1`: Updated all example commands
- `Setup-SQLHealthMonitorDatabase.ps1`: Updated replacement pattern and example commands
- `Test-SQLHealthMonitorInstallation.ps1`: Updated default database name
- `Validate-SQLHealthMonitorSetup.ps1`: Updated example commands

## Default Configuration
The default configuration file (`powershell/config/default.json`) already used `SQLHealthMonitor` as the database name, which is now consistent across all documentation and scripts.

## Backward Compatibility
**Important:** This change is **not backward compatible**. Existing installations using the `SQLHealthMonitor` database name will need to:
1. Create a new database named `SQLHealthMonitor`
2. Re-run the installation scripts
3. Migrate data if needed

## Migration Path
For existing installations with `SQLHealthMonitor`:

```sql
-- Option 1: Rename the database
ALTER DATABASE [SQLHealthMonitor] MODIFY NAME = [SQLHealthMonitor];

-- Option 2: Create new database and migrate data
CREATE DATABASE [SQLHealthMonitor];
USE [SQLHealthMonitor];

-- Copy tables from SQLHealthMonitor
SELECT * INTO [monitor] FROM [SQLHealthMonitor].[monitor];
SELECT * INTO [monitor].[RegisteredServers] FROM [SQLHealthMonitor].[monitor].[RegisteredServers];
-- Continue with other tables...

-- Drop old database when migration is complete
USE master;
DROP DATABASE [SQLHealthMonitor];
```

## Files Updated
- 1 README.md
- 8 install/*.sql scripts
- 3 maintenance/*.sql scripts
- 4 multi-instance/*.sql scripts
- 3 alerts/*.sql scripts
- 3 baselines/*.sql scripts
- 3 reports/*.sql scripts
- 3 powershell/*.ps1 scripts
- 6 scripts/*.ps1 scripts

**Total:** 38 files updated

## Verification
All references to `SQLHealthMonitor` have been removed from:
- All .ps1 scripts (PowerShell)
- All .sql scripts (T-SQL)
- Documentation (README.md)

All references now consistently use `SQLHealthMonitor` as the database name.
