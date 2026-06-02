# SQL Health Monitor

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/powershell/scripting/overview)
[![SQL Server](https://img.shields.io/badge/SQL%20Server-2016%2B-green.svg)](https://www.microsoft.com/sql-server/)

> **Note:** Portuguese (Brazil) version available at [README-PTBR.md](README-PTBR.md)

## 📋 Overview

The SQL Health Monitor is a comprehensive proactive monitoring solution for SQL Server environments. It provides real-time health monitoring, intelligent alerting, and detailed reporting capabilities designed for production environments running SQL Server 2016 and later.

### 🎯 Key Benefits

- **16 Health Collectors** - Monitor CPU, memory, disk, waits, blocking, deadlocks, Availability Groups, CDC, top queries, index health, backup status, jobs, error log, tempdb, and database growth
- **Intelligent Alert Engine** - Configurable thresholds with real-time notifications and intelligent cooldown periods
- **Statistical Baseline Engine** - Automatic anomaly detection using standard deviation-based alerts
- **Comprehensive Reporting** - Daily health summaries, weekly deep dives, and alert notifications
- **Multi-Instance Support** - Centralized management of multiple SQL Server instances with drift detection
- **Multi-Language Support** - Built-in English and Portuguese (BR) language support
- **Automated Maintenance** - Configurable data retention with batched cleanup and activity logging
- **Visual Status Indicators** - Traffic light status (🟢🟡🔴) for quick health assessment

## 📋 Table of Contents

1. [Prerequisites & Compatibility](#prerequisites--compatibility)
2. [Installation Guide](#installation-guide)
3. [Configuration & Alert Setup](#configuration--alert-setup)
4. [Project Structure & Components](#project-structure--components)
5. [Usage Examples & Reports](#usage-examples--reports)
6. [Multi-Environment Customization](#multi-environment-customization)
7. [Troubleshooting Guide](#troubleshooting-guide)
8. [Contributing & License](#contributing--license)
9. [Support & Contact](#support--contact)

## 🔧 Prerequisites & Compatibility

### System Requirements

| Component | Minimum Version | Notes |
|-----------|----------------|-------|
| **SQL Server** | 2016+ | Optimized for SQL Server 2022 |
| **Windows Server** | 2012 R2+ | For PowerShell execution |
| **PowerShell** | 5.1+ | PowerShell 7+ recommended |
| **SQL Server Agent** | Required | For scheduled jobs |
| **Database Mail** | Required | For email notifications |

### Software Dependencies

- **dbatools** module (v22.0.0+) - PowerShell module for SQL Server management
- **SqlServer** module (v21.1.0+) - PowerShell module for SQL Server cmdlets
- **Microsoft.PowerShell.Management** - Core PowerShell management cmdlets

### Database Permissions

Required permissions for installation:
- `sysadmin` server role (recommended for full functionality)
- `db_owner` role on target database (minimum requirement)

### Network Requirements

- TCP port 1433 (default SQL Server port) accessible from execution server
- SMTP port 587 (or 25) accessible for email notifications
- Database Mail configured with valid mail profile

## 🚀 Installation Guide

### Option 1: Interactive Setup Wizard (Recommended)

The easiest way to get started with guided configuration:

```powershell
# 1. Install dbatools module (if not already installed)
Install-Module dbatools -Scope CurrentUser -Force

# 2. Run the interactive setup wizard
.\powershell\Start-SQLHealthMonitorSetup.ps1
```

The wizard guides you through:
- Connection setup with live validation
- Single or multi-instance mode selection
- Collector configuration (auto-detects AG/CDC capabilities)
- Alert thresholds and recipient configuration
- Report scheduling and language preferences
- Email configuration (Database Mail or SMTP)
- SQL Agent job creation
- Baseline engine setup
- Data retention policies

**Export your configuration** for replication:
```powershell
# Export answers for non-interactive setup
.\powershell\Start-SQLHealthMonitorSetup.ps1 -ExportAnswers .\my-config.json

# Non-interactive setup using exported configuration
.\powershell\Start-SQLHealthMonitorSetup.ps1 -NonInteractive -AnswerFile .\my-config.json
```

### Option 2: Automated Installation

For scripted deployments across multiple servers:

```powershell
# Install on single server with Agent jobs
Install-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' `
    -EmailProfile 'DBA Mail' `
    -Recipients 'dba-team@company.com' `
    -Language EN

# Install without Agent jobs (manual scheduling)
Install-SQLHealthMonitor -ServerInstance 'SQL-DEV-01' -SkipAgentJobs -Language EN

# Install with custom database name
Install-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor_Production'
```

### Option 3: Manual Installation

For environments requiring granular control:

```sql
-- 1. Create the database (if not exists)
CREATE DATABASE [SQLHealthMonitor];
GO
USE [SQLHealthMonitor];
GO

-- 2. Execute install scripts in order
-- install/00-create-schema.sql      (tables & schema)
-- install/01-create-collectors.sql  (master collector procedure)
-- install/02-create-reports.sql     (report procedures)
-- install/03-create-alerts.sql      (alert engine)
-- install/04-create-jobs.sql        (SQL Agent jobs)
-- install/05-configure.sql          (settings, thresholds, languages)
-- install/06-alert-history.sql      (alert history + cooldown)
-- install/07-baselines.sql          (baseline engine)

-- 3. Deploy all collector scripts
-- Execute all files in collectors/ folder

-- 4. Deploy maintenance procedures
-- maintenance/purge_old_data.sql
-- maintenance/update_baselines.sql
```

### Post-Installation Verification

```powershell
# Test installation
.\powershell\Test-Installation.ps1 -ServerInstance 'SQL-PRD-01'

# Run manual collection
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType Collection -Verbose

# Test daily report generation
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType DailyReport -Language EN -DebugMode
```

## ⚙️ Configuration & Alert Setup

### Core Configuration

Edit the configuration file at `powershell\config\default.json`:

```json
{
    "Connection": {
        "ServerInstance": "localhost",
        "Database": "SQLHealthMonitor",
        "TrustedConnection": true,
        "ConnectTimeout": 30,
        "CommandTimeout": 300
    },
    "Schedule": {
        "CollectionIntervalMinutes": 15,
        "DailyReportTime": "07:00",
        "WeeklyReportDay": "Monday",
        "WeeklyReportTime": "08:00",
        "AlertCheckIntervalMinutes": 5
    },
    "Email": {
        "Method": "DatabaseMail",
        "DatabaseMailProfile": "SQLHealthMonitor",
        "Recipients": {
            "Daily": ["dba-team@company.com"],
            "Weekly": ["dba-team@company.com", "it-management@company.com"],
            "Alert": ["dba-team@company.com"]
        }
    },
    "Language": "EN"
}
```

### Alert Threshold Configuration

Alert thresholds are stored in the `[monitor].[Thresholds]` table:

```sql
-- View current thresholds
SELECT MetricName, WarningValue, CriticalValue, Operator, Description
FROM [monitor].[Thresholds]
ORDER BY MetricName;

-- Modify CPU thresholds
UPDATE [monitor].[Thresholds] 
SET WarningValue = 70, CriticalValue = 90 
WHERE MetricName = 'CPU_SqlPct';

-- Disable specific alert
UPDATE [monitor].[Thresholds] 
SET IsEnabled = 0 
WHERE MetricName = 'CDC_LatencySeconds';
```

### Default Thresholds

| Metric | Warning | Critical | Direction | Description |
|--------|---------|----------|-----------|-------------|
| CPU_SqlPct | 80% | 95% | >= | SQL Server CPU utilization |
| CPU_SystemPct | 90% | 98% | >= | Total system CPU utilization |
| Memory_PLE | 300s | 100s | <= | Page Life Expectancy |
| Memory_GrantsPending | 1 | 5 | >= | Memory grants pending |
| Disk_UsedPct | 85% | 95% | >= | Disk space used percentage |
| Disk_ReadLatencyMs | 20ms | 50ms | >= | Disk read latency |
| Disk_WriteLatencyMs | 20ms | 50ms | >= | Disk write latency |
| AG_SecondsBehind | 30s | 120s | >= | AG replication lag |
| AG_LogSendQueueMB | 500MB | 2000MB | >= | AG log send queue |
| Blocking_DurationSec | 30s | 120s | >= | Blocking duration |
| Backup_FullHours | 25h | 48h | >= | Hours since full backup |
| Jobs_FailedCount | 1 | 3 | >= | Failed job count |

### Email Configuration

#### Database Mail Setup

```sql
-- Configure Database Mail
USE msdb;
GO

EXEC msdb.dbo.sysmail_add_account_sp
    @account_name = 'SQLHealthMonitor',
    @description = 'SQL Health Monitor notifications',
    @email_address = 'sqlhealthmonitor@company.com',
    @reply_to_address = 'dba-team@company.com',
    @display_name = 'SQL Health Monitor';

EXEC msdb.dbo.sysmail_add_profile_sp
    @profile_name = 'SQLHealthMonitor',
    @description = 'Profile for SQL Health Monitor notifications';

EXEC msdb.dbo.sysmail_add_profileaccount_sp
    @profile_name = 'SQLHealthMonitor',
    @account_name = 'SQLHealthMonitor',
    @sequence_number = 1;
```

#### SMTP Configuration

```json
{
    "Email": {
        "Method": "SMTP",
        "SmtpServer": "smtp.company.com",
        "SmtpPort": 587,
        "SmtpUseSsl": true,
        "SmtpCredential": {
            "Username": "sqlhealthmonitor@company.com",
            "Password": "securepassword"
        }
    }
}
```

## 📁 Project Structure & Components

```
sql-health-monitor/
├── powershell/                     # PowerShell orchestration layer
│   ├── Start-SQLHealthMonitorSetup.ps1    # Interactive setup wizard
│   ├── Invoke-SQLHealthMonitor.ps1       # Main orchestrator
│   ├── Send-HealthReport.ps1             # Report generator/sender
│   ├── Install-SQLHealthMonitor.ps1      # Automated installer
│   ├── Deploy-SqlHealthMonitor.ps1       # Deployment helper
│   ├── Test-Installation.ps1             # Post-install validation
│   ├── SQLHealthMonitor.psd1            # Module manifest
│   └── config/
│       ├── default.json                 # Default configuration
│       └── answer-file-sample.json      # Sample answers
├── collectors/                      # T-SQL collection scripts (16 collectors)
│   ├── collect_cpu.sql                  # CPU utilization
│   ├── collect_memory.sql               # Memory metrics
│   ├── collect_disk.sql                 # Disk space & I/O
│   ├── collect_waits.sql                # Wait statistics
│   ├── collect_blocking.sql             # Blocking detection
│   ├── collect_deadlocks.sql            # Deadlock analysis
│   ├── collect_ag_health.sql            # Availability Groups
│   ├── collect_cdc_health.sql           # CDC health monitoring
│   ├── collect_top_queries.sql          # Top resource queries
│   ├── collect_index_health.sql        # Index fragmentation
│   ├── collect_backup_status.sql        # Backup verification
│   ├── collect_job_history.sql          # SQL Agent jobs
│   ├── collect_tempdb.sql               # TempDB usage
│   ├── collect_errorlog.sql             # Error log analysis
│   ├── collect_log_growth.sql           # Transaction log growth
│   └── collect_database_growth.sql     # Database file growth
├── alerts/                         # Alert engine
│   ├── alert_engine.sql                # Alert evaluation logic
│   ├── alert_actions.sql               # Automated response actions
│   └── thresholds_default.sql          # Default thresholds
├── baselines/                      # Statistical baselines
│   ├── baseline_tables.sql            # DDL for baseline storage
│   ├── capture_baseline.sql           # Weekly baseline capture
│   └── detect_anomalies.sql           # Real-time anomaly detection
├── reports/                        # Report generation
│   ├── daily_health_check.sql         # Daily health report
│   ├── weekly_deep_dive.sql           # Weekly analysis report
│   ├── recommendations_engine.sql     # Actionable recommendations
│   └── templates/                    # HTML email templates
│       ├── daily_en.html              # Daily report template (EN)
│       ├── daily_ptbr.html            # Daily report template (PT-BR)
│       ├── weekly_en.html             # Weekly report template (EN)
│       ├── weekly_ptbr.html           # Weekly report template (PT-BR)
│       ├── alert_en.html              # Alert template (EN)
│       └── alert_ptbr.html            # Alert template (PT-BR)
├── maintenance/                    # Housekeeping procedures
│   ├── purge_old_data.sql            # Data retention cleanup
│   ├── retention_config.sql          # Default retention settings
│   └── update_baselines.sql          # Legacy baseline updates
├── multi-instance/                 # Central management support
│   ├── cms_tables.sql                # CMS tables for multi-instance
│   ├── register_sample.sql           # Sample instance registration
│   ├── compare_instances.sql           # Instance comparison
│   └── compare_instances.sql         # Health comparison
├── config/                         # Database configuration
├── views/                          # SQL views for reporting
├── docs/                          # Documentation
│   ├── INSTALL.md                   # Installation guide
│   ├── CONFIGURATION.md            # Configuration reference
│   └── CUSTOMIZATION.md            # Customization guide
└── install/                       # Installation scripts (ordered execution)
    ├── 00-create-schema.sql        # Database schema & tables
    ├── 01-create-collectors.sql    # Master collector procedure
    ├── 02-create-reports.sql       # Report procedures
    ├── 03-create-alerts.sql        # Alert engine setup
    ├── 04-create-jobs.sql          # SQL Agent jobs
    ├── 05-configure.sql           # Default configuration
    ├── 06-alert-history.sql       # Alert history & cooldown
    └── 07-baselines.sql           # Baseline engine setup
```

### Key Components

#### PowerShell Module
- **Start-SQLHealthMonitorSetup.ps1**: Interactive setup wizard
- **Invoke-SQLHealthMonitor.ps1**: Main orchestration engine
- **Send-HealthReport.ps1**: HTML report generator and email sender
- **Install-SQLHealthMonitor.ps1**: Automated deployment script

#### Collectors
16 specialized collectors gather comprehensive metrics:
- **System Metrics**: CPU, Memory, Disk I/O
- **SQL Server Metrics**: Waits, Blocking, Deadlocks
- **High Availability**: Availability Groups, CDC
- **Performance**: Top Queries, Index Health
- **Operations**: Backup Status, Job History, Error Log
- **Capacity**: TempDB, Database Growth, Log Growth

#### Alert Engine
- Real-time threshold evaluation
- Configurable cooldown periods
- Automated response actions
- Alert history tracking

#### Reporting Engine
- **Daily Health Check**: Executive summary with traffic light status
- **Weekly Deep Dive**: Trend analysis and capacity planning
- **Alert Notifications**: Detailed alert information with context
- **Multi-language Support**: English and Portuguese (BR)

## 💡 Usage Examples & Reports

### Basic Usage

```powershell
# Import the module
Import-Module .\powershell\SQLHealthMonitor.psd1

# Collect all health metrics
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType Collection -Verbose

# Generate daily health report
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType DailyReport -Language EN

# Generate weekly deep dive report
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType WeeklyReport -Language PTBR

# Check for alerts
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType Alert
```

### Advanced Usage

```powershell
# Multi-instance collection from central CMS
Invoke-SQLHealthMonitor -ServerInstance 'SQL-CMS-01' -RunType Collection -AllInstances

# Production instances only
Invoke-SQLHealthMonitor -ServerInstance 'SQL-CMS-01' -RunType Collection -AllInstances -Environment PRD

# Generate reports for all instances
Invoke-SQLHealthMonitor -ServerInstance 'SQL-CMS-01' -RunType DailyReport -AllInstances -Language EN

# Test configuration changes without execution
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType Collection -WhatIf
```

### Direct SQL Usage

```sql
-- Run specific collectors
EXEC [monitor].[usp_Collect_CPU];
EXEC [monitor].[usp_Collect_Memory];
EXEC [monitor].[usp_Collect_Disk];

-- Generate reports directly
EXEC [monitor].[usp_Report_DailyHealth] @DebugMode = 1;
EXEC [monitor].[usp_Report_WeeklyDeepDive] @DebugMode = 1;

-- Manage baselines
EXEC [monitor].[usp_Baseline_Capture] @LookbackDays = 7;
EXEC [monitor].[usp_Baseline_DetectAnomalies] @LookbackMinutes = 60;

-- Purge old data
EXEC [monitor].[usp_PurgeHistoricalData] @BatchSize = 10000;
```

### Report Examples

#### Daily Health Report Features:
- Health score (0-100) with traffic light status
- Top 5 issues requiring attention
- Baseline anomalies detection
- Actionable recommendations with priority levels
- Executive summary table
- Detailed metric breakdowns

#### Weekly Deep Dive Features:
- Week-over-week trend analysis
- Capacity planning projections
- Query performance degradation detection
- "What Changed" analysis
- Historical performance charts
- Strategic recommendations

### Email Notifications

```powershell
# Send custom report
Send-HealthReport -ServerInstance 'SQL-PRD-01' -ReportType Daily -Language EN -OutputPath '.\Reports\daily.html'

# Send alert notification
Send-HealthReport -ServerInstance 'SQL-PRD-01' -ReportType Alert -Language PTBR -Recipients 'emergency-team@company.com'

### PowerShell Module Reference

#### Invoke-SQLHealthMonitor

Main orchestrator that ties collectors, alerts, and reports together.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| ServerInstance | string | (required*) | SQL Server instance (* not required with -AllInstances if CMS host specified) |
| Database | string | SQLHealthMonitor | Monitor database name |
| ConfigProfile | string | DEFAULT | Config profile in database |
| RunType | string | (required) | Collection, DailyReport, WeeklyReport, Alert |
| Language | string | EN | EN or PTBR |
| ConfigPath | string | .\powershell\config\default.json | Path to JSON config |
| AllInstances | switch | false | Loop through RegisteredServers table |
| Environment | string | (all) | Filter: DEV, STG, PRD, DR |
| ParallelDegree | int | 4 | Max parallel collections (multi-instance) |

#### Send-HealthReport

Generates HTML reports and sends via Database Mail or SMTP.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| ServerInstance | string | (required) | SQL Server instance |
| ReportType | string | (required) | Daily, Weekly, Alert |
| Recipients | string[] | from config | Email recipients |
| Language | string | EN | EN or PTBR |
| OutputPath | string | (none) | Save HTML locally |

#### Install-SQLHealthMonitor

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

## 🌍 Multi-Environment Customization

### Development Environment

```json
{
    "Connection": {
        "ServerInstance": "SQL-DEV-01",
        "Database": "SQLHealthMonitor_DEV"
    },
    "Schedule": {
        "CollectionIntervalMinutes": 30,
        "DailyReportTime": "18:00"
    },
    "Email": {
        "Recipients": {
            "Daily": ["dev-team@company.com"],
            "Weekly": ["dev-team@company.com"],
            "Alert": ["dev-team@company.com"]
        }
    },
    "Collectors": {
        "Enabled": ["CPU", "Memory", "Disk", "Waits", "Blocking", "Jobs"]
    }
}
```

### Staging Environment

```json
{
    "Connection": {
        "ServerInstance": "SQL-STG-01",
        "Database": "SQLHealthMonitor_STG"
    },
    "Schedule": {
        "CollectionIntervalMinutes": 15,
        "DailyReportTime": "08:00"
    },
    "Email": {
        "Recipients": {
            "Daily": ["stg-team@company.com", "dba-team@company.com"],
            "Weekly": ["stg-team@company.com", "dba-team@company.com", "it-management@company.com"],
            "Alert": ["stg-team@company.com", "dba-team@company.com"]
        }
    },
    "Collectors": {
        "Enabled": ["CPU", "Memory", "Disk", "Waits", "Blocking", "AG", "TopQueries", "IndexHealth", "BackupStatus", "Jobs"]
    }
}
```

### Production Environment

```json
{
    "Connection": {
        "ServerInstance": "SQL-PRD-01",
        "Database": "SQLHealthMonitor_PRD"
    },
    "Schedule": {
        "CollectionIntervalMinutes": 5,
        "DailyReportTime": "07:00",
        "WeeklyReportDay": "Monday",
        "WeeklyReportTime": "08:00"
    },
    "Email": {
        "Recipients": {
            "Daily": ["dba-team@company.com", "it-management@company.com"],
            "Weekly": ["dba-team@company.com", "it-management@company.com", "executive@company.com"],
            "Alert": ["dba-team@company.com", "emergency-team@company.com"]
        }
    },
    "Collectors": {
        "Enabled": ["CPU", "Memory", "Disk", "Waits", "Blocking", "Deadlocks", "AG", "CDC", "TopQueries", "IndexHealth", "BackupStatus", "Jobs", "ErrorLog", "TempDB", "LogGrowth", "DatabaseGrowth"]
    },
    "Retention": {
        "DetailedDataDays": 90,
        "AggregatedDataDays": 365,
        "ReportHistoryDays": 180
    }
}
```

### Environment-Specific Thresholds

```sql
-- Production thresholds (stricter)
UPDATE [monitor].[Thresholds] SET 
    WarningValue = 70, CriticalValue = 85 
WHERE MetricName = 'CPU_SqlPct' AND Environment = 'PRD';

-- Development thresholds (more lenient)
UPDATE [monitor].[Thresholds] SET 
    WarningValue = 85, CriticalValue = 95 
WHERE MetricName = 'CPU_SqlPct' AND Environment = 'DEV';
```

### Multi-Instance Management

```sql
-- Register multiple instances
INSERT INTO [monitor].[RegisteredServers] (ServerName, Environment, Description)
VALUES 
    ('SQL-PRD-01', 'PRD', 'Production Primary'),
    ('SQL-PRD-02', 'PRD', 'Production Secondary'),
    ('SQL-STG-01', 'STG', 'Staging Environment'),
    ('SQL-DEV-01', 'DEV', 'Development Environment');

-- Collect from all production instances
EXEC [monitor].[usp_CollectAllInstances] @Environment = 'PRD';

-- Compare health across instances
EXEC [monitor].[usp_CompareInstances] @Environment = 'PRD';
```

## 🚨 Troubleshooting Guide

### Common Installation Issues

#### 1. Permission Errors

```powershell
# Run with elevated privileges
Start-Process powershell -Verb RunAs

# Or use explicit credentials
$credential = Get-Credential
Install-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -Credential $credential
```

#### 2. Connection Timeouts

```json
{
    "Connection": {
        "ConnectTimeout": 60,
        "CommandTimeout": 600
    }
}
```

#### 3. Database Mail Configuration

```sql
-- Test Database Mail
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = 'SQLHealthMonitor',
    @recipients = 'dba@company.com',
    @subject = 'Test Message',
    @body = 'Database Mail test successful';

-- Check Database Mail log
SELECT * FROM msdb.dbo.sysmail_eventlog WHERE event_type = 'error';
```

### Common Runtime Issues

#### 1. Collection Failures

```sql
-- Check collection history
SELECT * FROM [monitor].[CollectionHistory] ORDER BY CollectedAt DESC;

-- Check specific collector errors
SELECT * FROM [monitor].[CollectionErrors] ORDER BY ErrorTime DESC;

-- Test individual collector
EXEC [monitor].[usp_Collect_CPU] @DebugMode = 1;
```

#### 2. Alert Engine Issues

```sql
-- Check alert history
SELECT * FROM [monitor].[AlertHistory] ORDER BY TriggeredAt DESC;

-- Check cooldown status
SELECT * FROM [monitor].[AlertCooldown] ORDER BY LastTriggered DESC;

-- Test alert engine manually
EXEC [monitor].[usp_RunAlertEngine] @DebugMode = 1;
```

#### 3. Report Generation Issues

```sql
-- Check report history
SELECT * FROM [monitor].[ReportHistory] ORDER BY GeneratedAt DESC;

-- Test report generation with debug mode
EXEC [monitor].[usp_Report_DailyHealth] @DebugMode = 1;

-- Check HTML output directly
SELECT HTMLContent FROM [monitor].[ReportHistory] WHERE ReportType = 'Daily' ORDER BY GeneratedAt DESC;
```

#### 4. Performance Issues

```sql
-- Check long-running collections
SELECT * FROM [monitor].[CollectionHistory] WHERE DurationSeconds > 60 ORDER BY CollectedAt DESC;

-- Check table sizes
SELECT 
    t.NAME AS TableName,
    s.Name AS SchemaName,
    p.rows AS RowCounts,
    SUM(a.total_pages) * 8 / 1024 AS TotalSpaceMB
FROM sys.tables t
INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
LEFT OUTER JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE t.NAME LIKE 'monitor%'
GROUP BY t.Name, s.Name, p.rows;

-- Optimize purge operations
EXEC [monitor].[usp_PurgeHistoricalData] @BatchSize = 5000, @MaxDurationMin = 15;
```

### Debug Mode Operations

```powershell
# Enable debug logging
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType Collection -Verbose

# Test with WhatIf
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType Collection -WhatIf

# Generate debug reports
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType DailyReport -DebugMode
```

### Log File Analysis

```powershell
# View recent log entries
Get-Content ".\SQLHealthMonitor\Logs\SQLHealthMonitor.log" | Select-Object -Last 50

# Filter error logs
Get-Content ".\SQLHealthMonitor\Logs\SQLHealthMonitor.log" | Where-Object { $_ -match "ERROR" }

# Monitor real-time logs
Get-Content ".\SQLHealthMonitor\Logs\SQLHealthMonitor.log" -Wait
```

## 🤝 Contributing & License

### Contributing Guidelines

We welcome contributions! Please follow these guidelines:

1. **Fork the repository** and create a feature branch
2. **Follow the existing code style** and naming conventions
3. **Test your changes** thoroughly
4. **Update documentation** for new features
5. **Submit a pull request** with a clear description of changes

### Development Setup

```powershell
# Clone the repository
git clone https://github.com/lucasborgesbr/sql-health-monitor.git
cd sql-health-monitor

# Install development dependencies
Install-Module dbatools -Scope CurrentUser -Force
Install-Module Pester -Scope CurrentUser -Force

# Run tests (when available)
# Invoke-Pester -Path tests/
```

### Code Style Guidelines

- **PowerShell**: Follow [PowerShell Scripting Best Practices](https://docs.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-logging)
- **T-SQL**: Follow [T-SQL Coding Conventions](https://docs.microsoft.com/sql/t-sql/development-recommendations)
- **Comments**: Use clear, concise comments explaining complex logic
- **Error Handling**: Implement comprehensive error handling and logging

### Adding New Features

1. **Create a new collector** in the `collectors/` directory
2. **Update the main orchestrator** in `Invoke-SQLHealthMonitor.ps1`
3. **Add configuration options** to `powershell/config/default.json`
4. **Create unit tests** for the new functionality
5. **Update documentation** with usage examples

### Reporting Issues

When reporting issues, please include:

- Environment details (SQL Server version, OS, PowerShell version)
- Steps to reproduce the issue
- Expected vs actual behavior
- Error messages and stack traces
- Relevant log entries
- Configuration file (redact sensitive information)

### License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Third-Party Dependencies

This project uses the following third-party components:

- **dbatools** - PowerShell module for SQL Server management
- **SqlServer** - PowerShell module for SQL Server cmdlets
- **Pester** - PowerShell testing framework

All third-party components are subject to their respective licenses.

## 📞 Support & Contact

### Documentation

- **Main Documentation**: [README.md](README.md)
- **Installation Guide**: [docs/INSTALL.md](docs/INSTALL.md)
- **Configuration Reference**: [docs/CONFIGURATION.md](docs/CONFIGURATION.md)
- **Customization Guide**: [docs/CUSTOMIZATION.md](docs/CUSTOMIZATION.md)

### Community Support

- **GitHub Issues**: [Report bugs or request features](https://github.com/lucasborgesbr/sql-health-monitor/issues)
- **Discussions**: [Join community discussions](https://github.com/lucasborgesbr/sql-health-monitor/discussions)
- **Wiki**: [Contribute to documentation](https://github.com/lucasborgesbr/sql-health-monitor/wiki)

### Professional Support

For professional support and consulting services:

- **Email**: lucasborgesbr@gmail.com
- **LinkedIn**: [Lucas Allan Borges](https://linkedin.com/in/lucasallanborges)
- **Repository**: [https://github.com/lucasborgesbr/sql-health-monitor](https://github.com/lucasborgesbr/sql-health-monitor)

### Release Notes

#### Version 1.0.0 (Current)

**New Features:**
- 16 health collectors covering all major SQL Server metrics
- Intelligent alert engine with configurable thresholds
- Statistical baseline engine with anomaly detection
- Comprehensive reporting (daily and weekly)
- Multi-instance support with central management
- Multi-language support (English and Portuguese-BR)
- Automated maintenance and data retention
- Interactive setup wizard

**Improvements:**
- Enhanced error handling and logging
- Optimized performance for large environments
- Improved report templates and formatting
- Better multi-instance management

**Bug Fixes:**
- Fixed memory leak in long-running collections
- Resolved timezone issues in report generation
- Improved alert cooldown mechanism
- Enhanced database connection handling

### Future Roadmap

- **Machine Learning Integration**: Predictive analytics for capacity planning
- **Mobile App**: Mobile-friendly dashboards and notifications
- **API Access**: REST API for integration with other tools
- **Enhanced Reporting**: Custom report builder and visualization
- **Cloud Support**: Azure SQL and AWS RDS support
- **Automated Remediation**: Self-healing capabilities for common issues

---

**SQL Health Monitor** - Proactive monitoring for SQL Server environments

*Created with ❤️ by Lucas Allan Borges - Senior DBA / Database Engineer*