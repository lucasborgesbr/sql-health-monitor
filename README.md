# SQL Health Monitor

Proactive SQL Server health monitoring, alerting, and reporting solution. Designed for production environments running SQL Server 2016+.

## Features

- **16 Health Collectors** — CPU, memory, disk, waits, blocking, deadlocks, AG, CDC, top queries, index health, backup status, jobs, error log, tempdb, log growth, database growth
- **Alert Engine** — Configurable thresholds with real-time notifications
- **HTML Reports** — Daily summaries, weekly deep dives, and alert notifications
- **Multi-Language** — English and Portuguese (BR) support
- **Recommendations Engine** — Actionable suggestions with priority levels
- **Traffic Light Status** — 🟢🟡🔴 visual indicators for quick assessment

## Architecture

```
sql-health-monitor/
├── powershell/              # PowerShell orchestration layer
│   ├── Invoke-SQLHealthMonitor.ps1   # Main orchestrator
│   ├── Send-HealthReport.ps1         # Report generator/sender
│   ├── Install-SQLHealthMonitor.ps1  # Automated installer
│   ├── SQLHealthMonitor.psd1         # Module manifest
│   └── config/
│       └── default.json              # Default configuration
├── collectors/              # T-SQL collection scripts
├── alerts/                  # Alert engine and thresholds
├── reports/
│   ├── templates/           # HTML email templates (EN + PT-BR)
│   └── recommendations_engine.sql
├── config/                  # Database configuration scripts
├── views/                   # SQL views for reporting
└── install/                 # Database install scripts (ordered)
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

### 4. Test with WhatIf

```powershell
# Preview what would happen without executing
Invoke-SQLHealthMonitor -ServerInstance 'YOUR_SERVER' -RunType Collection -WhatIf
```

## PowerShell Module Usage

### Invoke-SQLHealthMonitor

Main orchestrator that ties collectors, alerts, and reports together.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| ServerInstance | string | (required) | SQL Server instance |
| Database | string | SQLHealthMonitor | Monitor database name |
| ConfigProfile | string | DEFAULT | Config profile in database |
| RunType | string | (required) | Collection, DailyReport, WeeklyReport, Alert |
| Language | string | EN | EN or PTBR |
| ConfigPath | string | config/default.json | Path to JSON config |

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

## Configuration

Edit `powershell/config/default.json` to customize:

- **Connection** — Server, database, timeouts
- **Schedule** — Collection intervals, report times
- **Email** — Method (DatabaseMail/SMTP), recipients per report type
- **Collectors** — Enable/disable specific collectors
- **Retention** — Data retention periods
- **Logging** — Log path and verbosity

## SQL Agent Jobs Created

| Job | Schedule | Description |
|-----|----------|-------------|
| SQLHealthMonitor - Collection | Every 15 min (or hourly) | Collects all health metrics |
| SQLHealthMonitor - Daily Report | Daily 7:00 AM | Sends daily health summary |
| SQLHealthMonitor - Weekly Report | Monday 8:00 AM | Sends weekly deep dive |
| SQLHealthMonitor - Alert Check | Every 5 min | Evaluates thresholds, sends alerts |

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
$servers = @('DBPRD', 'DBSTG', 'DBAPP')
$servers | ForEach-Object {
    Install-SQLHealthMonitor -ServerInstance $_ -EmailProfile 'DBA Mail' -Recipients 'team@company.com'
}
```

## Customization

### Adding a New Collector

1. Create `collectors/collect_your_metric.sql`
2. Add the collector name to `powershell/config/default.json` → `Collectors.Enabled`
3. Add the mapping in `Invoke-SQLHealthMonitor.ps1` → `$collectorSequence`

### Custom Thresholds

Edit `alerts/thresholds_default.sql` or insert directly into the `AlertThresholds` table.

### Custom Report Templates

Create new templates in `reports/templates/` following the naming convention: `{type}_{language}.html`

## License

MIT

## Author

Lucas Allan Borges — Senior DBA / Database Engineer
