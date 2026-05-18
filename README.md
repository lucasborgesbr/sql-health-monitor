# SQL Health Monitor

**Proactive SQL Server monitoring and daily health reporting via Database Mail.**

Inspired by [First Responder Kit](https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit) and [Power Alerts](https://poweralerts.com.br/), but customized for your environment — not a generic tool.

## Philosophy

> "If a tree falls in the forest and no one is there to hear, did it make a sound?"

This toolkit makes your DBA work **visible**. It doesn't just alert when things break — it proactively reports health, trends, and recommendations so leadership sees the value you deliver every day.

## Features

### Daily Health Check (Email)
- CPU, Memory, Disk utilization summary
- Wait stats analysis (top waits, deltas)
- AG synchronization status & latency
- CDC health & retention
- Backup status (last full/diff/log per DB)
- Job failures in last 24h
- Blocking events summary
- Top resource-intensive queries
- Index health (fragmentation, missing, unused)
- TempDB utilization
- Log file growth trends
- Error log highlights

### Weekly Deep Dive (Email)
- Capacity planning trends
- Performance baselines & deviations
- Growth projections (data, log, tempdb)
- Recommendations with priority
- Week-over-week comparisons

### Real-time Alerts
- Configurable thresholds
- Critical: Log full, disk space, corruption, AG unhealthy
- Warning: CPU sustained, blocking > N seconds, CDC latency
- Info: Job completed, failover detected, config change

### Output
- Beautiful HTML emails via Database Mail
- Traffic light system (🟢🟡🔴) for quick scanning
- Multi-language support (EN / PT-BR)
- Configurable detail level and recipients

## Architecture

```
sql-health-monitor/
├── README.md
├── install/
│   ├── 00-create-schema.sql        -- Monitoring schema & tables
│   ├── 01-create-collectors.sql    -- Data collection procedures
│   ├── 02-create-reports.sql       -- Report generation procedures
│   ├── 03-create-alerts.sql        -- Alert threshold procedures
│   ├── 04-create-jobs.sql          -- SQL Agent job creation
│   └── 05-configure.sql            -- Initial configuration
├── collectors/
│   ├── collect_cpu.sql
│   ├── collect_memory.sql
│   ├── collect_disk.sql
│   ├── collect_waits.sql
│   ├── collect_blocking.sql
│   ├── collect_ag_health.sql
│   ├── collect_cdc_health.sql
│   ├── collect_top_queries.sql
│   ├── collect_index_health.sql
│   ├── collect_backup_status.sql
│   ├── collect_job_history.sql
│   ├── collect_tempdb.sql
│   ├── collect_log_growth.sql
│   └── collect_errorlog.sql
├── reports/
│   ├── daily_health_check.sql
│   ├── weekly_deep_dive.sql
│   └── templates/
│       ├── email_daily_en.html
│       ├── email_daily_ptbr.html
│       ├── email_weekly_en.html
│       └── email_weekly_ptbr.html
├── alerts/
│   ├── alert_engine.sql
│   ├── thresholds_default.sql
│   └── alert_actions.sql
├── config/
│   ├── settings.sql                -- Central config table
│   └── languages.sql               -- i18n strings
├── maintenance/
│   ├── purge_old_data.sql          -- Retention cleanup
│   └── update_baselines.sql        -- Baseline recalculation
├── powershell/
│   ├── Deploy-SqlHealthMonitor.ps1 -- Multi-server deployment
│   └── Test-Installation.ps1       -- Validation script
└── docs/
    ├── INSTALL.md
    ├── CONFIGURATION.md
    └── CUSTOMIZATION.md
```

## Requirements

- SQL Server 2016+ (2019/2022 recommended)
- Database Mail configured
- SQL Agent running
- `sysadmin` or equivalent for installation
- Dedicated monitoring database (recommended: `DBA_Monitor`)

## Quick Start

```sql
-- 1. Create monitoring database
CREATE DATABASE [DBA_Monitor];
GO

-- 2. Run install scripts in order
-- 00-create-schema.sql
-- 01-create-collectors.sql
-- ...

-- 3. Configure
EXEC [monitor].[usp_Configure]
    @EmailRecipients = 'your@email.com',
    @Language = 'en',  -- 'en' or 'ptbr'
    @DailyReportTime = '07:00',
    @WeeklyReportDay = 'Monday';
```

## Configuration

All settings stored in `[monitor].[Settings]` table:

| Setting | Default | Description |
|---------|---------|-------------|
| Language | en | Report language (en/ptbr) |
| DailyReportTime | 07:00 | When to send daily report |
| WeeklyReportDay | Monday | Day for weekly deep dive |
| RetentionDays | 90 | How long to keep collected data |
| CPUWarningThreshold | 80 | CPU % to trigger warning |
| CPUCriticalThreshold | 95 | CPU % to trigger critical |
| BlockingThresholdSec | 30 | Seconds before blocking alert |
| DiskWarningPct | 85 | Disk usage % warning |
| DiskCriticalPct | 95 | Disk usage % critical |

## Multi-Language

Reports support EN and PT-BR out of the box. Language strings are stored in `[monitor].[Languages]` table — add your own or customize existing ones.

## Compatibility

- ✅ SQL Server 2016, 2017, 2019, 2022
- ✅ Standard & Enterprise Edition
- ✅ AlwaysOn AG environments
- ✅ Standalone instances
- ✅ Multi-instance servers
- ⚠️ Azure SQL MI (partial — no SQL Agent, use external scheduler)
- ❌ Azure SQL DB (not supported)

## License

MIT

## Author

Lucas Borges — Senior DBA / Database Engineer
