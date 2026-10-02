# Configuration Guide

All configuration is stored in the `[monitor].[Settings]` table. Changes take effect immediately on the next collection/report cycle.

## Settings Categories

### General

| Setting | Default | Description |
|---------|---------|-------------|
| `Language` | `en` | Report language: `en` or `ptbr` |
| `ServerName` | `@@SERVERNAME` | Server identifier shown in reports |
| `MonitoringEnabled` | `1` | Master switch. Set to `0` to pause all collection. |

### Email

| Setting | Default | Description |
|---------|---------|-------------|
| `Recipients` | `dba@company.com` | Comma-separated email recipients |
| `CcRecipients` | _(empty)_ | CC recipients |
| `ProfileName` | `DBA_Mail` | Database Mail profile name |
| `SubjectPrefix` | `[SQL Health]` | Prefix for all email subjects |

### Schedule

| Setting | Default | Description |
|---------|---------|-------------|
| `DailyReportTime` | `07:00` | Time for daily report (HH:mm) |
| `WeeklyReportDay` | `Monday` | Day for weekly deep dive |
| `WeeklyReportTime` | `08:00` | Time for weekly report (HH:mm) |

> **Note:** Changing schedule settings here does NOT update SQL Agent jobs automatically. Modify the jobs in SQL Agent or re-run `04-create-jobs.sql`.

### Retention

| Setting | Default | Description |
|---------|---------|-------------|
| `DataRetentionDays` | `90` | Days to keep metric data |
| `AlertRetentionDays` | `365` | Days to keep alert history |
| `ReportRetentionDays` | `90` | Days to keep report log |

### Features (Enable/Disable Collectors)

| Setting | Default | Description |
|---------|---------|-------------|
| `CollectCPU` | `1` | CPU utilization |
| `CollectMemory` | `1` | Memory metrics |
| `CollectDisk` | `1` | Disk space & I/O |
| `CollectWaits` | `1` | Wait statistics |
| `CollectBlocking` | `1` | Blocking detection |
| `CollectAG` | `1` | Availability Groups |
| `CollectCDC` | `1` | CDC health |
| `CollectTopQueries` | `1` | Top queries by CPU |
| `CollectIndexHealth` | `1` | Index fragmentation |
| `CollectBackups` | `1` | Backup status |
| `CollectJobs` | `1` | SQL Agent job history |
| `CollectTempDB` | `1` | TempDB usage |
| `CollectFileGrowth` | `1` | Database file growth |
| `CollectErrorLog` | `1` | Error log entries |

Set to `0` to disable a collector. Useful for servers without AG, CDC, etc.

```sql
-- Example: Disable AG and CDC collectors on a standalone server
UPDATE [monitor].[Settings] SET SettingValue = '0' WHERE SettingName = 'CollectAG';
UPDATE [monitor].[Settings] SET SettingValue = '0' WHERE SettingName = 'CollectCDC';
```

## Thresholds

Thresholds are stored in `[monitor].[Thresholds]` and control when alerts fire.

| MetricName | Warning | Critical | Operator | Description |
|-----------|---------|----------|----------|-------------|
| `CPU_SqlPct` | 80 | 95 | >= | SQL CPU % |
| `CPU_SystemPct` | 90 | 98 | >= | Total system CPU % |
| `Memory_PLE` | 300 | 100 | <= | Page Life Expectancy (s) |
| `Memory_GrantsPending` | 1 | 5 | >= | Memory grants pending |
| `Memory_BufferHitRatio` | 95 | 90 | <= | Buffer cache hit ratio % |
| `Disk_UsedPct` | 85 | 95 | >= | Disk space used % |
| `Disk_ReadLatencyMs` | 20 | 50 | >= | Read latency (ms) |
| `Disk_WriteLatencyMs` | 20 | 50 | >= | Write latency (ms) |
| `AG_SecondsBehind` | 30 | 120 | >= | Seconds behind primary |
| `AG_LogSendQueueMB` | 500 | 2000 | >= | Log send queue (MB) |
| `AG_RedoQueueMB` | 500 | 2000 | >= | Redo queue (MB) |
| `CDC_LatencySeconds` | 300 | 900 | >= | CDC capture latency (s) |
| `Blocking_DurationSec` | 30 | 120 | >= | Blocking duration (s) |
| `Backup_FullHours` | 25 | 48 | >= | Hours since full backup |
| `Backup_LogHours` | 1 | 4 | >= | Hours since log backup |
| `TempDB_UsedPct` | 70 | 90 | >= | TempDB used % |
| `Jobs_FailedCount` | 1 | 3 | >= | Failed jobs count |

### Modifying Thresholds

```sql
-- Adjust CPU warning to 70%
UPDATE [monitor].[Thresholds] SET WarningValue = 70 WHERE MetricName = 'CPU_SqlPct';

-- Disable a specific threshold
UPDATE [monitor].[Thresholds] SET IsEnabled = 0 WHERE MetricName = 'CDC_LatencySeconds';
```

## Alert Cooldown

The alert engine uses a cooldown period (default: 30 minutes) to prevent spam. The same alert won't fire again within the cooldown window.

```sql
-- Change cooldown to 60 minutes (modify the job step command)
EXEC [monitor].[usp_RunAlertEngine] @CooldownMinutes = 60;
```

## Language Support

Reports support English (`en`) and Portuguese-BR (`ptbr`). Language strings are in `[monitor].[Languages]`.

```sql
-- Switch to Portuguese
UPDATE [monitor].[Settings] SET SettingValue = 'ptbr' 
WHERE Category = 'General' AND SettingName = 'Language';

-- Override language for a single report execution
EXEC [monitor].[usp_GenerateDailyReport] @OverrideLanguage = 'ptbr';
```

## SQL Agent Job Schedules

| Job | Schedule | Purpose |
|-----|----------|---------|
| Collectors | Every 5 min | Gather all metrics |
| Alert Engine | Every 5 min | Check thresholds, fire alerts |
| Daily Report | 7:00 AM | Send daily health summary |
| Weekly Report | Monday 8:00 AM | Send weekly deep dive |
| Purge Old Data | 3:00 AM daily | Retention cleanup |
| Update Baselines | Sunday 2:00 AM | Recalculate baselines |
