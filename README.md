# SQL Health Monitor

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![SQL Server](https://img.shields.io/badge/SQL%20Server-2012%2B-green.svg)](https://www.microsoft.com/sql-server/)

> **Versão em Português:** [README-PTBR.md](README-PTBR.md)

## Overview

SQL Health Monitor is a proactive monitoring solution for SQL Server built entirely in T-SQL. All collection, alerting, reporting, and email delivery run inside SQL Server via SQL Agent Jobs and Database Mail — no external scripts, no server-side files, no PowerShell dependencies at runtime.

PowerShell is used **only** for deployment (`deploy/Install.ps1` runs the `.sql` files via `sqlcmd`).

### Key Features

- **24+ Health Collectors** including live sessions, Query Store, and index recommendations
- **Real-Time Visibility** — live session capture with blocking chain detection
- **Query Store Integration** — multi-dimensional query analysis (CPU, Duration, I/O)
- **Index Recommendations** — DMV-based suggestions with CREATE INDEX scripts
- **Alert Engine** — configurable thresholds with cooldown periods and alert history
- **Statistical Baseline Engine** — anomaly detection using standard deviation
- **HTML Reports via Database Mail** — daily health check and weekly deep dive; HTML built inside T-SQL procedures, sent via `sp_send_dbmail`
- **Uptime / SLA Tracking** — incident classification, SLA compliance, monthly reports
- **Multi-Instance Support** — centralized management with drift detection
- **Multi-Language** — English and Portuguese (BR)

## Prerequisites

| Component | Requirement |
|-----------|-------------|
| SQL Server | 2012+ (optimized for 2022) |
| SQL Server Agent | Required for scheduled jobs |
| Database Mail | Required for email reports and alerts |
| Permissions | `sysadmin` recommended; `db_owner` minimum |

> **PowerShell** (5.1+) and **sqlcmd** are needed only during deployment. No PowerShell modules (`dbatools`, `SqlServer`) are required.

## Installation

### Option 1 — Deploy script (recommended)

```powershell
# Windows auth
.\deploy\Install.ps1 -ServerInstance "SQLSERVER01"

# SQL auth
.\deploy\Install.ps1 -ServerInstance "SQLSERVER01" -SqlAuth -Login "sa" -Password "P@ss"
```

The script runs each `.sql` file in order via `sqlcmd` and reports success/failure per file.

### Option 2 — Manual (sqlcmd)

> **Important:** Run all `sqlcmd` commands from the **repo root directory**. Install scripts use `:r` includes that resolve relative to the current working directory.

```bash
cd C:\path\to\sql-health-monitor

sqlcmd -S SQLSERVER01 -E -b -i install\00-create-schema.sql
sqlcmd -S SQLSERVER01 -E -b -i install\01-create-collectors.sql
sqlcmd -S SQLSERVER01 -E -b -i install\02-create-reports.sql
sqlcmd -S SQLSERVER01 -E -b -i install\03-create-alerts.sql
sqlcmd -S SQLSERVER01 -E -b -i install\04-create-jobs.sql
sqlcmd -S SQLSERVER01 -E -b -i install\05-configure.sql
sqlcmd -S SQLSERVER01 -E -b -i install\06-alert-history.sql
sqlcmd -S SQLSERVER01 -E -b -i install\07-baselines.sql
sqlcmd -S SQLSERVER01 -E -b -i install\08-extended-schema.sql
sqlcmd -S SQLSERVER01 -E -b -i install\09-uptime-tracker.sql

-- Collectors
sqlcmd -S SQLSERVER01 -E -b -i collectors\collect_cpu.sql
-- ... (repeat for each file in collectors/)

-- Reports (HTML builders first, then report procedures)
sqlcmd -S SQLSERVER01 -E -b -i reports\html_builder_daily.sql
sqlcmd -S SQLSERVER01 -E -b -i reports\html_builder_weekly.sql
sqlcmd -S SQLSERVER01 -E -b -i reports\daily_health_check.sql
sqlcmd -S SQLSERVER01 -E -b -i reports\weekly_deep_dive.sql
```

### Post-installation: configure email

```sql
USE [SQLHealthMonitor];

-- Set your Database Mail profile name
UPDATE monitor.Settings SET SettingValue = 'YourMailProfile'
WHERE Category = 'Email' AND SettingName = 'ProfileName';

-- Set recipients
UPDATE monitor.Settings SET SettingValue = 'dba@company.com'
WHERE Category = 'Email' AND SettingName = 'Recipients';

-- Optional: per-report-type recipient lists
UPDATE monitor.Settings SET SettingValue = 'dba@company.com'
WHERE Category = 'Email' AND SettingName = 'Recipients_Daily';

UPDATE monitor.Settings SET SettingValue = 'dba@company.com;manager@company.com'
WHERE Category = 'Email' AND SettingName = 'Recipients_Weekly';
```

Test the report before the first scheduled run:
```sql
-- Preview HTML without sending email
EXEC [SQLHealthMonitor].[monitor].[usp_RunReport] @ReportType = 'Daily', @DebugMode = 1;
```

## Uninstall

```powershell
.\deploy\Uninstall.ps1 -ServerInstance "SQLSERVER01"
```

This removes all 6 SQL Agent Jobs and drops the `SQLHealthMonitor` database. Prompts for confirmation.

## Configuration

All configuration is stored in `[monitor].[Settings]`. No JSON or config files needed.

```sql
-- View all settings
SELECT Category, SettingName, SettingValue, Description
FROM [monitor].[Settings]
ORDER BY Category, SettingName;
```

### Key settings

| Category | SettingName | Default | Description |
|----------|-------------|---------|-------------|
| General | Language | en | Report language: `en` or `ptbr` |
| General | ServerName | @@SERVERNAME | Server label used in emails |
| General | MonitoringEnabled | 1 | Master switch |
| Email | ProfileName | DBA_Mail | Database Mail profile name |
| Email | Recipients | dba@company.com | Default recipients (all reports) |
| Email | Recipients_Daily | *(empty)* | Override for daily report |
| Email | Recipients_Weekly | *(empty)* | Override for weekly report |
| Email | Recipients_Alert | *(empty)* | Override for alert emails |
| Retention | DataRetentionDays | 90 | Days to keep collected metrics |
| Features | CollectCPU | 1 | Enable/disable individual collectors |

### Alert thresholds

```sql
-- View thresholds
SELECT MetricName, WarningValue, CriticalValue, Operator, Description
FROM [monitor].[Thresholds] ORDER BY MetricName;

-- Adjust CPU threshold
UPDATE [monitor].[Thresholds]
SET WarningValue = 70, CriticalValue = 90
WHERE MetricName = 'CPU_SqlPct';

-- Disable a specific alert
UPDATE [monitor].[Thresholds] SET IsEnabled = 0 WHERE MetricName = 'CDC_LatencySeconds';
```

### Default thresholds

| Metric | Warning | Critical | Direction |
|--------|---------|----------|-----------|
| CPU_SqlPct | 80% | 95% | >= |
| CPU_SystemPct | 90% | 98% | >= |
| Memory_PLE | 300s | 100s | <= |
| Memory_GrantsPending | 1 | 5 | >= |
| Disk_UsedPct | 85% | 95% | >= |
| Disk_ReadLatencyMs | 20ms | 50ms | >= |
| Disk_WriteLatencyMs | 20ms | 50ms | >= |
| AG_SecondsBehind | 30s | 120s | >= |
| Blocking_DurationSec | 30s | 120s | >= |
| Backup_FullHours | 25h | 48h | >= |
| Jobs_FailedCount | 1 | 3 | >= |

### Database Mail setup (if not already configured)

```sql
USE msdb;

EXEC sysmail_add_account_sp
    @account_name  = 'DBA_Mail',
    @email_address = 'sqlmonitor@company.com',
    @display_name  = 'SQL Health Monitor',
    @mailserver_name = 'smtp.company.com';

EXEC sysmail_add_profile_sp   @profile_name = 'DBA_Mail';
EXEC sysmail_add_profileaccount_sp @profile_name = 'DBA_Mail', @account_name = 'DBA_Mail', @sequence_number = 1;

-- Test
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = 'DBA_Mail',
    @recipients   = 'dba@company.com',
    @subject      = 'Test',
    @body         = 'Database Mail works.';
```

## Project Structure

```
sql-health-monitor/
├── deploy/                          # Deployment scripts (PowerShell wrapping sqlcmd)
│   ├── Install.ps1                  # Deploy all .sql files in order
│   └── Uninstall.ps1                # Remove jobs and drop database
│
├── install/                         # Ordered T-SQL installation scripts
│   ├── 00-create-schema.sql         # Database, schema, tables, indexes
│   ├── 01-create-collectors.sql     # Master collector dispatcher
│   ├── 02-create-reports.sql        # Report runner (usp_RunReport)
│   ├── 03-create-alerts.sql         # Alert engine setup
│   ├── 04-create-jobs.sql           # SQL Agent Jobs (6 jobs)
│   ├── 05-configure.sql             # Default settings and thresholds
│   ├── 06-alert-history.sql         # Alert history + cooldown tables
│   ├── 07-baselines.sql             # Baseline engine
│   ├── 08-extended-schema.sql       # Extended monitoring schema
│   ├── 09-uptime-tracker.sql        # Uptime SLA tracking
│   └── Uninstall.sql                # Drop jobs + drop database
│
├── collectors/                      # 18 T-SQL collection procedures
│
├── reports/                         # Report procedures
│   ├── html_builder_daily.sql       # usp_BuildDailyHtml  — pure HTML renderer (no DB queries)
│   ├── html_builder_weekly.sql      # usp_BuildWeeklyHtml — pure HTML renderer (no DB queries)
│   ├── daily_health_check.sql       # usp_GenerateDailyReport  — collects data + calls builder + sends email
│   ├── weekly_deep_dive.sql         # usp_GenerateWeeklyReport — collects data + calls builder + sends email
│   ├── monthly_uptime_report.sql
│   ├── enhanced_analytics.sql
│   └── recommendations_engine.sql
│
├── alerts/                          # Alert engine
│   ├── alert_engine.sql
│   ├── alert_actions.sql
│   └── thresholds_default.sql
│
├── baselines/                       # Statistical baseline engine
│   ├── baseline_tables.sql
│   ├── capture_baseline.sql
│   └── detect_anomalies.sql
│
├── maintenance/                     # Data retention + housekeeping
│   ├── purge_old_data.sql
│   ├── retention_config.sql
│   └── update_baselines.sql
│
├── multi-instance/                  # Centralized multi-server management
│   ├── cms_tables.sql                # Registered servers + CMS linkage
│   ├── collect_all_instances.sql    # Cross-instance collection
│   ├── compare_instances.sql        # Drift detection
│   └── register_sample.sql
│
├── linux-adaptation/                # Linux SQL Server: collectors + shell helpers
│   ├── collect_cpu_linux.sql
│   ├── collect_disk_linux.sql
│   ├── collect_errorlog_linux.sql
│   ├── collect_job_history_linux.sql
│   ├── install-linux.sh              # Linux deployment helper
│   ├── run-collector.sh              # Per-collector runner for Linux
│   ├── validate-installation.sh
│   ├── ADAPTATION-SUMMARY.md
│   ├── Linux-Compatibility-Report.md
│   └── Linux-Implementation-Guide.md
│
├── views/                           # SQL views for direct querying
│   ├── vw_CurrentHealth.sql
│   └── vw_UptimeTracker.sql
│
├── config/                           # Static configuration
│   ├── settings.sql                  # Settings metadata (runtime config lives in [monitor].[Settings])
│   ├── languages.sql                  # UI strings: en, ptbr
│   └── default.json                  # Legacy PS-era reference; superseded by Settings table
│
└── validate_installation.sql         # Pre-install validation
    validate_uptime_tracker.sql        # Post-install uptime validation
```

### Report architecture

```
SQL Agent Job
    └─> usp_RunReport @ReportType='Daily'
            └─> usp_GenerateDailyReport
                    ├─ queries metric tables → scalar variables
                    ├─ populates temp tables (#ReportRecommendations, #ReportTopWaits, #ReportAnomalies)
                    ├─ EXEC usp_BuildDailyHtml (reads temp tables, returns @HtmlBody OUTPUT)
                    └─ msdb.dbo.sp_send_dbmail → email delivered
```

`usp_BuildDailyHtml` / `usp_BuildWeeklyHtml` contain only HTML string building — no queries to permanent tables. This separates layout from data collection and makes templates easy to modify.

## SQL Agent Jobs

Six jobs are created by `install/04-create-jobs.sql`:

| Job | Schedule | Procedure |
|-----|----------|-----------|
| SQL Health Monitor - Collectors | Every 5 min | `usp_RunAllCollectors` |
| SQL Health Monitor - Alert Engine | Every 5 min | `usp_RunAlertEngine` |
| SQL Health Monitor - Daily Report | Daily 07:00 | `usp_RunReport @ReportType='Daily'` |
| SQL Health Monitor - Weekly Report | Monday 08:00 | `usp_RunReport @ReportType='Weekly'` |
| SQL Health Monitor - Purge Old Data | Daily 03:00 | `usp_PurgeHistoricalData` |
| SQL Health Monitor - Update Baselines | Sunday 02:00 | `usp_Maintenance_UpdateBaselines` |

Schedules can be adjusted via SSMS > SQL Server Agent > Jobs.

## Usage

### Run collectors manually

```sql
-- All collectors
EXEC [SQLHealthMonitor].[monitor].[usp_RunAllCollectors];

-- Individual collector
EXEC [SQLHealthMonitor].[monitor].[usp_Collect_CPU];
EXEC [SQLHealthMonitor].[monitor].[usp_Collect_Memory];
EXEC [SQLHealthMonitor].[monitor].[usp_Collect_Disk];
```

### Generate reports

```sql
-- Preview HTML in SSMS (no email sent)
EXEC [monitor].[usp_RunReport] @ReportType = 'Daily',  @DebugMode = 1;
EXEC [monitor].[usp_RunReport] @ReportType = 'Weekly', @DebugMode = 1;

-- Send to a specific address without changing settings
EXEC [monitor].[usp_RunReport]
    @ReportType         = 'Daily',
    @OverrideRecipients = 'oncall@company.com';

-- Force a different language
EXEC [monitor].[usp_RunReport]
    @ReportType       = 'Daily',
    @OverrideLanguage = 'ptbr',
    @DebugMode        = 1;
```

### Query collected data

```sql
-- Current health overview
SELECT * FROM [monitor].[vw_CurrentHealth];

-- Last 24h CPU
SELECT CollectedAt, SqlCpuPct, SystemCpuPct
FROM [monitor].[CpuHistory]
WHERE CollectedAt >= DATEADD(HOUR, -24, SYSUTCDATETIME())
ORDER BY CollectedAt DESC;

-- Alert history
SELECT * FROM [monitor].[AlertHistory]
ORDER BY FiredAt DESC;

-- Report send history
SELECT * FROM [monitor].[ReportHistory]
ORDER BY GeneratedAt DESC;
```

### Uptime / SLA tracking

```sql
-- Monthly uptime report
EXEC [monitor].[usp_Generate_MonthlyUptimeReport] @ReportMonth = '2026-06-01';

-- Current uptime status
SELECT * FROM [monitor].[vw_UptimeDashboard];

-- SLA compliance history
SELECT * FROM [monitor].[vw_SLAComplianceHistory];
```

## Troubleshooting

### Email not sending

```sql
-- Check Database Mail profile is set correctly
SELECT SettingValue FROM monitor.Settings
WHERE Category = 'Email' AND SettingName = 'ProfileName';

-- Check Database Mail send log
SELECT * FROM msdb.dbo.sysmail_eventlog WHERE event_type = 'error' ORDER BY log_date DESC;
SELECT * FROM msdb.dbo.sysmail_allitems ORDER BY send_request_date DESC;
```

### Report failures

```sql
-- Check report history for errors
SELECT ReportType, Success, ErrorMessage, GeneratedAt
FROM [monitor].[ReportHistory]
ORDER BY GeneratedAt DESC;

-- Run in debug mode to see HTML output and error details
EXEC [monitor].[usp_RunReport] @ReportType = 'Daily', @DebugMode = 1;
```

### Collector failures

```sql
-- Check collection history
SELECT * FROM [monitor].[CollectionHistory] ORDER BY CollectedAt DESC;

-- Test individual collector
EXEC [monitor].[usp_Collect_CPU];
```

### Check table sizes

```sql
SELECT
    t.name AS TableName,
    p.rows AS Rows,
    SUM(a.total_pages) * 8 / 1024 AS TotalMB
FROM sys.tables t
JOIN sys.indexes i ON t.object_id = i.object_id
JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
JOIN sys.allocation_units a ON p.partition_id = a.container_id
JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE s.name = 'monitor'
GROUP BY t.name, p.rows
ORDER BY TotalMB DESC;
```

## Multi-Instance Support

```sql
-- Register instances
INSERT INTO [monitor].[RegisteredServers] (ServerName, Environment, Description)
VALUES
    ('SQL-PRD-01', 'PRD', 'Production Primary'),
    ('SQL-PRD-02', 'PRD', 'Production Secondary'),
    ('SQL-STG-01', 'STG', 'Staging');

-- Collect from all registered instances
EXEC [monitor].[usp_CollectAllInstances] @Environment = 'PRD';

-- Compare health across instances
EXEC [monitor].[usp_CompareInstances] @Environment = 'PRD';
```

## Contributing

1. Fork the repository and create a feature branch
2. Add new collectors in `collectors/` following the existing naming convention
3. Update `install/01-create-collectors.sql` to register the new procedure
4. Test with `@DebugMode = 1` before submitting
5. Open a pull request with a description of what is monitored and why

When adding features: keep all logic in T-SQL. If OS-level data collection is needed, adapt it in `linux-adaptation/` following the existing pattern.

## License

MIT License — see [LICENSE](LICENSE).

## Contact

- **Author**: Lucas Allan Borges
- **Email**: lucasborgesbr@gmail.com
- **GitHub**: https://github.com/lucasborgesbr/sql-health-monitor
- **LinkedIn**: https://linkedin.com/in/lucasallanborges

---

*SQL Health Monitor — T-SQL native monitoring for SQL Server.*
