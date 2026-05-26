# SQL Health Monitor

Proactive SQL Server health monitoring, alerting, and reporting solution. Designed for production environments running SQL Server 2016+.

## Features

- **16 Health Collectors** — CPU, memory, disk, waits, blocking, deadlocks, AG, CDC, top queries, index health, backup status, jobs, error log, tempdb, log growth, database growth
- **Alert Engine** — Configurable thresholds with real-time notifications and cooldown
- **Baseline Engine** — Statistical baselines with anomaly detection (σ-based deviation alerts)
- **HTML Reports** — Daily summaries, weekly deep dives, and alert notifications
- **Daily Report** — Health score, traffic light status, top issues, baseline anomalies, recommendations
- **Weekly Deep Dive** — Week-over-week trends, capacity planning, degraded queries, "What Changed"
- **Multi-Language** — English and Portuguese (BR) support
- **Recommendations Engine** — Actionable suggestions with priority levels (P1/P2/P3)
- **Multi-Instance (CMS)** — Central management of multiple SQL Server instances with drift detection
- **Housekeeping** — Configurable retention per data type with batched purge and activity logging
- **Traffic Light Status** — 🟢🟡🔴 visual indicators for quick assessment

## Architecture

```
sql-health-monitor/
├── powershell/              # PowerShell orchestration layer
│   ├── Invoke-SQLHealthMonitor.ps1   # Main orchestrator (single + multi-instance)
│   ├── Send-HealthReport.ps1         # Report generator/sender
│   ├── Install-SQLHealthMonitor.ps1  # Automated installer
│   ├── Deploy-SqlHealthMonitor.ps1   # Deployment helper
│   ├── Test-Installation.ps1         # Post-install validation
│   ├── SQLHealthMonitor.psd1         # Module manifest
│   └── config/
│       └── default.json              # Default configuration
├── collectors/              # T-SQL collection scripts (16 collectors)
├── alerts/                  # Alert engine, thresholds, and actions
├── baselines/               # Baseline engine
│   ├── baseline_tables.sql           # DDL for baseline storage
│   ├── capture_baseline.sql          # Weekly baseline capture procedure
│   └── detect_anomalies.sql          # Real-time anomaly detection
├── reports/
│   ├── daily_health_check.sql        # usp_GenerateDailyReport
│   ├── weekly_deep_dive.sql          # usp_GenerateWeeklyReport
│   ├── recommendations_engine.sql    # Actionable recommendations
│   └── templates/                    # HTML email templates (EN + PT-BR)
├── maintenance/             # Housekeeping procedures
│   ├── purge_old_data.sql            # usp_PurgeHistoricalData (batched)
│   ├── retention_config.sql          # Default retention settings
│   └── update_baselines.sql          # Legacy baseline update
├── multi-instance/          # CMS multi-instance support
│   ├── cms_tables.sql                # RegisteredServers + health snapshot tables
│   ├── register_databank.sql         # DataBank environment registration
│   ├── collect_all_instances.sql     # Cross-instance collection wrapper
│   └── compare_instances.sql         # Health comparison + drift detection
├── config/                  # Database configuration scripts
├── views/                   # SQL views for reporting
├── docs/                    # Documentation
│   ├── CONFIGURATION.md
│   ├── CUSTOMIZATION.md
│   └── INSTALL.md
└── install/                 # Database install scripts (ordered)
    ├── 00-create-schema.sql          # Schema + all tables
    ├── 01-create-collectors.sql      # Master collector procedure
    ├── 02-create-reports.sql         # Report procedures
    ├── 03-create-alerts.sql          # Alert engine
    ├── 04-create-jobs.sql            # SQL Agent jobs
    ├── 05-configure.sql              # Default configuration
    ├── 06-alert-history.sql          # Alert history + cooldown
    └── 07-baselines.sql              # Baseline engine tables + procedures
```

## Requirements

- SQL Server 2016+ (optimized for 2022)
- Windows PowerShell 5.1 or PowerShell 7+
- [dbatools](https://dbatools.io/) module
- Database Mail configured (or SMTP access)
- sysadmin or db_owner permissions for installation

## Quick Start

### 1. Install dbatools (if not already installed)

```powershell
Install-Module dbatools -Scope CurrentUser -Force
```

### 2. Deploy the solution

```powershell
Import-Module .\powershell\SQLHealthMonitor.psd1

# Full installation with SQL Agent jobs
Install-SQLHealthMonitor -ServerInstance 'YOUR_SERVER' `
    -EmailProfile 'DBA Mail' `
    -Recipients 'dba-team@company.com' `
    -Language EN

# Installation without Agent jobs (manual scheduling)
Install-SQLHealthMonitor -ServerInstance 'YOUR_SERVER' -SkipAgentJobs
```

### 3. Run manually

```powershell
# Collect metrics
Invoke-SQLHealthMonitor -ServerInstance 'YOUR_SERVER' -RunType Collection -Verbose

# Generate daily report
Invoke-SQLHealthMonitor -ServerInstance 'YOUR_SERVER' -RunType DailyReport -Language EN

# Generate weekly deep dive
Invoke-SQLHealthMonitor -ServerInstance 'YOUR_SERVER' -RunType WeeklyReport -Language PTBR

# Check alerts
Invoke-SQLHealthMonitor -ServerInstance 'YOUR_SERVER' -RunType Alert
```

### 4. Multi-Instance Mode

```powershell
# Collect from all registered production instances
Invoke-SQLHealthMonitor -ServerInstance 'DBPRD' -RunType Collection -AllInstances -Environment PRD

# Collect from ALL registered instances
Invoke-SQLHealthMonitor -ServerInstance 'DBPRD' -RunType Collection -AllInstances

# Daily report for all instances
Invoke-SQLHealthMonitor -ServerInstance 'DBPRD' -RunType DailyReport -AllInstances -Language EN
```

### 5. Baseline Management

```sql
-- Capture baseline (run weekly or after stable period)
EXEC [monitor].[usp_Baseline_Capture] @LookbackDays = 7;

-- Detect anomalies (run with alert checks)
EXEC [monitor].[usp_Baseline_DetectAnomalies] @LookbackMinutes = 60;

-- Debug: see all metric comparisons
EXEC [monitor].[usp_Baseline_DetectAnomalies] @DebugMode = 1;
```

### 6. Test with WhatIf

```powershell
# Preview what would happen without executing
Invoke-SQLHealthMonitor -ServerInstance 'YOUR_SERVER' -RunType Collection -WhatIf
```

## PowerShell Module Usage

### Invoke-SQLHealthMonitor

Main orchestrator that ties collectors, alerts, and reports together.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| ServerInstance | string | (required*) | SQL Server instance (* not required with -AllInstances if CMS host specified) |
| Database | string | SQLHealthMonitor | Monitor database name |
| ConfigProfile | string | DEFAULT | Config profile in database |
| RunType | string | (required) | Collection, DailyReport, WeeklyReport, Alert |
| Language | string | EN | EN or PTBR |
| ConfigPath | string | config/default.json | Path to JSON config |
| AllInstances | switch | false | Loop through RegisteredServers table |
| Environment | string | (all) | Filter: DEV, STG, PRD, DR |
| ParallelDegree | int | 4 | Max parallel collections (multi-instance) |

### Send-HealthReport

Generates HTML reports and sends via Database Mail or SMTP.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| ServerInstance | string | (required) | SQL Server instance |
| ReportType | string | (required) | Daily, Weekly, Alert |
| Recipients | string[] | from config | Email recipients |
| Language | string | EN | EN or PTBR |
| OutputPath | string | (none) | Save HTML locally |

### Install-SQLHealthMonitor

Deploys database objects and creates SQL Agent jobs.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| ServerInstance | string | (required) | Target SQL Server |
| Database | string | SQLHealthMonitor | Database name |
| Schedule | string | Hourly | Hourly or Daily collection |
| EmailProfile | string | (none) | Database Mail profile |
| Recipients | string[] | (none) | Report recipients |
| SkipAgentJobs | switch | false | Skip Agent job creation |
| Force | switch | false | Overwrite without prompting |

## Baseline Engine

The baseline engine provides statistical anomaly detection by comparing current metrics against historical baselines.

### How It Works

1. **Capture** (`usp_Baseline_Capture`): Runs weekly, calculates avg + stddev for each metric over a configurable lookback window
2. **Detect** (`usp_Baseline_DetectAnomalies`): Runs with alert checks, compares current values against baselines
3. **Alert**: Flags when `current_value > baseline_avg + (N × stddev)` where N is configurable per metric

### Configuration

Each metric has independent thresholds in `[monitor].[BaselineConfig]`:

| Metric | Warning (σ) | Critical (σ) | Direction |
|--------|-------------|--------------|-----------|
| CPU_Avg | 2.0 | 3.0 | ABOVE |
| PLE_Avg | 2.0 | 3.0 | BELOW |
| Disk_UsedPct_Max | 1.5 | 2.0 | ABOVE |
| Blocking_Count | 2.0 | 3.0 | ABOVE |
| AG_Lag_Max | 2.0 | 3.0 | ABOVE |

Direction controls which deviations trigger alerts:
- `ABOVE`: Only alert when current > baseline (e.g., CPU going up is bad)
- `BELOW`: Only alert when current < baseline (e.g., PLE going down is bad)
- `BOTH`: Alert on any significant deviation

## Housekeeping / Retention

Data retention is configurable per data type via the Settings table:

| Data Type | Default Retention | Setting Name |
|-----------|-------------------|--------------|
| Raw collector data | 30 days | RawDataRetentionDays |
| Daily summaries | 90 days | DailySummaryRetentionDays |
| Weekly summaries | 365 days | WeeklySummaryRetentionDays |
| Alert history | 365 days | AlertRetentionDays |
| Report history | 90 days | ReportRetentionDays |
| Baseline anomalies | 90 days | AnomalyRetentionDays |
| **Baselines** | **Forever** | *(never purged)* |

```sql
-- Run purge manually
EXEC [monitor].[usp_PurgeHistoricalData];

-- Preview what would be purged
EXEC [monitor].[usp_PurgeHistoricalData] @DebugMode = 1;

-- Smaller batches for busy systems
EXEC [monitor].[usp_PurgeHistoricalData] @BatchSize = 5000, @MaxDurationMin = 15;
```

Safety features:
- Batched deletes (TOP 10000) to avoid transaction log bloat
- Configurable max runtime (default 30 min) to prevent runaway operations
- Activity logging (rows deleted per table, duration)

## Multi-Instance (CMS) Support

Monitor multiple SQL Server instances from a central management server.

### Setup

```sql
-- 1. Create CMS tables on your primary instance
-- Run: multi-instance/cms_tables.sql

-- 2. Register your instances
-- Run: multi-instance/register_databank.sql (or add your own)

-- 3. Collect from all instances (T-SQL via linked servers)
EXEC [monitor].[usp_CollectAllInstances] @Environment = 'PRD';

-- 4. Compare health across instances
EXEC [monitor].[usp_CompareInstances] @Environment = 'PRD';
```

### PowerShell Multi-Instance

```powershell
# Collect from all registered servers (no linked servers needed)
Invoke-SQLHealthMonitor -ServerInstance 'DBPRD' -RunType Collection -AllInstances

# Production only
Invoke-SQLHealthMonitor -ServerInstance 'DBPRD' -RunType Collection -AllInstances -Environment PRD
```

### Drift Detection

The `usp_CompareInstances` procedure identifies instances that deviate from the cluster average:
- Compares CPU, PLE, disk usage across all instances
- Flags deviations beyond configurable threshold (default: 25%)
- Persists drift history for trend analysis

## SQL Agent Jobs Created

| Job | Schedule | Description |
|-----|----------|-------------|
| SQLHealthMonitor - Collection | Every 15 min | Collects all health metrics |
| SQLHealthMonitor - Daily Report | Daily 7:00 AM | Sends daily health summary |
| SQLHealthMonitor - Weekly Report | Monday 8:00 AM | Sends weekly deep dive |
| SQLHealthMonitor - Alert Check | Every 5 min | Evaluates thresholds, sends alerts |
| SQLHealthMonitor - Baseline Capture | Sunday 2:00 AM | Captures weekly baselines |
| SQLHealthMonitor - Purge Old Data | Daily 3:00 AM | Retention cleanup |

## Configuration

Edit `powershell/config/default.json` to customize:

- **Connection** — Server, database, timeouts
- **Schedule** — Collection intervals, report times
- **Email** — Method (DatabaseMail/SMTP), recipients per report type
- **Collectors** — Enable/disable specific collectors
- **Retention** — Data retention periods
- **Logging** — Log path and verbosity

## Deployment Notes

### DataBank Environment

```powershell
# Production deployment
Install-SQLHealthMonitor -ServerInstance 'DFW3PRDBCSSQL03' `
    -Schedule Hourly `
    -EmailProfile 'DataBank DBA' `
    -Recipients 'dba-team@databank.com','travis@databank.com' `
    -Language EN

# Dev/staging (no agent jobs, manual testing)
Install-SQLHealthMonitor -ServerInstance 'DBDEV' -SkipAgentJobs -Language EN
```

### Multi-Instance Deployment

```powershell
# Deploy to all registered instances
$servers = @('DBPRD', 'DBSTG', 'DBAPP', 'DFW3PRDBCSSQL01', 'DFW3PRDBCSSQL03', 'DFW3PRDBCSSQL04', 'DFW3PRDBCSSQL05')
$servers | ForEach-Object {
    Install-SQLHealthMonitor -ServerInstance $_ -EmailProfile 'DBA Mail' -Recipients 'team@company.com'
}

# Or use multi-instance collection from CMS
Invoke-SQLHealthMonitor -ServerInstance 'DBPRD' -RunType Collection -AllInstances
```

## Customization

### Adding a New Collector

1. Create `collectors/collect_your_metric.sql`
2. Add the collector name to `powershell/config/default.json` → `Collectors.Enabled`
3. Add the mapping in `Invoke-SQLHealthMonitor.ps1` → `$collectorSequence`

### Custom Thresholds

Edit `alerts/thresholds_default.sql` or insert directly into the `Thresholds` table.

### Custom Baseline Metrics

```sql
-- Add a new metric to baseline tracking
INSERT INTO [monitor].[BaselineConfig] (MetricName, WarningMultiplier, CriticalMultiplier, Direction, Description)
VALUES ('YourMetric', 2.0, 3.0, 'ABOVE', 'Description of your metric');
```

### Custom Report Templates

Create new templates in `reports/templates/` following the naming convention: `{type}_{language}.html`

### Adjusting Retention

```sql
-- Change raw data retention to 60 days
UPDATE [monitor].[Settings] 
SET SettingValue = '60' 
WHERE Category = 'Retention' AND SettingName = 'RawDataRetentionDays';
```

## License

MIT

## Author

Lucas Allan Borges — Senior DBA / Database Engineer
