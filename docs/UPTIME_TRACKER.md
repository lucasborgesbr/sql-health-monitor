# SQL Health Monitor - Uptime Tracker Documentation

## Overview

The SQL Health Monitor includes a comprehensive uptime tracking system that monitors service availability and calculates SLA compliance. This feature is designed for enterprise environments that need to track uptime percentages and incident trends for business reporting and compliance purposes.

## Features

- **Automatic Incident Detection** - Identifies unplanned downtime, planned maintenance, and critical failures
- **SLA Compliance Tracking** - Monitors uptime percentage against business targets
- **Monthly Reports** - Detailed monthly uptime summaries with trend analysis
- **Incident Classification** - Categorizes incidents by type, severity, and business impact
- **Real-time Dashboard** - Current uptime status and active incidents

## Installation

```sql
-- Install uptime tracking components
:r install/09-uptime-tracker.sql

-- Validate installation
:r validate_uptime_tracker.sql
```

## Usage

### Basic Operations

```sql
-- Run hourly uptime tracking
EXEC monitor.usp_Collect_UptimeTracker;

-- Generate monthly uptime report
EXEC monitor.usp_Generate_MonthlyUptimeReport @ReportMonth = '2026-06-01';

-- View current uptime status
SELECT * FROM monitor.vw_CurrentUptimeStatus;

-- View monthly summary
SELECT * FROM monitor.vw_MonthlyUptimeSummary;

-- View active incidents
SELECT * FROM monitor.vw_ActiveIncidents;
```

### Advanced Queries

```sql
-- View incident trends
SELECT * FROM monitor.vw_IncidentTrends 
ORDER BY MonthStart DESC, IncidentCount DESC;

-- View SLA compliance history
SELECT * FROM monitor.vw_SLAComplianceHistory
ORDER BY MonthStart DESC;

-- View uptime dashboard
SELECT * FROM monitor.vw_UptimeDashboard;
```

## Incident Classification

### Incident Types

| Type | Description | Examples |
|------|-------------|----------|
| **Planned** | Scheduled maintenance | Upgrades, patches, migrations |
| **Unplanned** | Unexpected failures | Hardware crashes, software bugs |
| **Emergency** | Critical failures requiring immediate action | Complete service interruption |

### Severity Levels

| Level | Impact | Response Time |
|-------|--------|---------------|
| **Critical** | Complete service interruption | < 15 minutes |
| **High** | Severe degradation | < 1 hour |
| **Medium** | Noticeable impact | < 4 hours |
| **Low** | Minimal impact | < 24 hours |

### Categories

| Category | Description |
|----------|-------------|
| **Database** | Failures within SQL Server itself |
| **Server** | OS/hardware failures |
| **Network** | Connectivity issues |
| **Application** | Application-level failures |

## SLA Configuration

### Setting SLA Targets

```sql
-- Configure SLA targets
INSERT INTO monitor.Settings (Category, SettingName, SettingValue, Description)
VALUES ('SLA', 'TargetUptime', '99.9', 'Target uptime percentage');

-- Set incident response times
INSERT INTO monitor.Settings (Category, SettingName, SettingValue, Description)
VALUES ('SLA', 'IncidentResponseTime', '60', 'Critical incident response time (minutes)');

-- Configure monthly report generation
INSERT INTO monitor.Settings (Category, SettingName, SettingValue, Description)
VALUES ('SLA', 'UptimeReportDay', '1', 'Day of month to generate uptime report');
```

### SLA Thresholds

```sql
-- Add SLA thresholds to alert system
INSERT INTO monitor.Thresholds (MetricName, WarningValue, CriticalValue, Operator, Description)
VALUES 
('SLA_UptimePercentage', 99.5, 99.0, '<', 'Uptime percentage threshold'),
('SLA_DowntimeMinutes', 60, 1440, '>=', 'Downtime threshold (minutes)'),
('SLA_IncidentResponseTime', 60, 240, '>=', 'Incident response time threshold (minutes)');
```

## Data Collection

### Hourly Collection

The uptime tracker runs automatically every hour and performs the following operations:

1. **Incident Detection** - Scans alerts, error logs, job failures, and system events
2. **Uptime Calculation** - Calculates uptime percentage for the hour
3. **SLA Tracking** - Compares actual uptime against target SLA
4. **Incident Logging** - Records detected incidents with classification
5. **Period Storage** - Stores hourly, daily, and monthly periods

### Data Sources

The uptime tracker collects data from multiple sources:

- **Alert System** - Critical and warning alerts
- **Error Log** - SQL Server error messages
- **Job History** - SQL Agent job failures
- **Availability Groups** - AlwaysOn replica states
- **System Events** - Service availability and deadlock traces
- **Custom Sources** - Manual incident entry

## Reporting

### Monthly Reports

The monthly uptime report includes:

- **Executive Summary** - Overall uptime and SLA compliance
- **Incident Breakdown** - By type, category, and severity
- **SLA Analysis** - Compliance and violation tracking
- **Recommendations** - Actionable improvement suggestions
- **Trend Analysis** - Historical performance and forecasting

### Report Generation

```sql
-- Generate report for specific month
EXEC monitor.usp_Generate_MonthlyUptimeReport 
    @ReportMonth = '2026-06-01',
    @ServerName = 'SQL-PROD-01',
    @Environment = 'PRODUCTION';
```

## Views and Queries

### Current Status

```sql
-- Real-time uptime status
SELECT 
    CurrentUptimePercentage,
    CurrentStatusIcon,
    MinutesSinceLastUpdate,
    ActiveIncidents,
    ActiveCriticalIncidents,
    CurrentSLAStatus
FROM monitor.vw_UptimeDashboard;
```

### Historical Analysis

```sql
-- Monthly uptime trends
SELECT 
    MonthStart,
    MonthlyUptimePercentage,
    TotalIncidents,
    CriticalIncidents,
    SLAStatus
FROM monitor.vw_MonthlyUptimeSummary
ORDER BY MonthStart DESC;

-- Incident classification trends
SELECT 
    MonthStart,
    IncidentType,
    Category,
    Severity,
    IncidentCount,
    TotalDowntimeMinutes
FROM monitor.vw_IncidentTrends
ORDER BY MonthStart DESC, IncidentCount DESC;
```

## Monitoring and Alerting

### Alert Integration

The uptime tracker integrates with the existing alert system:

- **Uptime Alerts** - Triggered when uptime drops below thresholds
- **Incident Alerts** - Critical incidents generate immediate alerts
- **SLA Violations** - SLA compliance violations are tracked and reported
- **Escalation** - Automatic escalation for critical incidents

### Alert Configuration

```sql
-- Enable uptime alerts
UPDATE monitor.Settings 
SET SettingValue = '1' 
WHERE Category = 'Features' AND SettingName = 'CollectUptimeTracker';

-- Configure alert thresholds
UPDATE monitor.Thresholds 
SET CriticalValue = 99.0 
WHERE MetricName = 'SLA_UptimePercentage';
```

## Troubleshooting

### Common Issues

#### 1. No Uptime Data

```sql
-- Check if uptime tracker is enabled
SELECT * FROM monitor.Settings 
WHERE Category = 'Features' AND SettingName = 'CollectUptimeTracker';

-- Run manual collection
EXEC monitor.usp_Collect_UptimeTracker;

-- Check for recent data
SELECT TOP 10 * FROM monitor.UptimePeriods 
ORDER BY PeriodEnd DESC;
```

#### 2. Incorrect Incident Detection

```sql
-- Check incident sources
SELECT * FROM monitor.IncidentSources 
WHERE DetectedAt >= DATEADD(DAY, -1, GETDATE());

-- View incident details
SELECT * FROM monitor.Incidents 
WHERE DetectedAt >= DATEADD(DAY, -1, GETDATE());

-- Check alert history for recent events
SELECT TOP 10 * FROM monitor.AlertHistory 
ORDER BY FiredAt DESC;
```

#### 3. SLA Violations

```sql
-- Check SLA compliance
SELECT * FROM monitor.SLATracking 
WHERE PeriodStart >= DATEADD(MONTH, -1, GETDATE());

-- Review SLA settings
SELECT * FROM monitor.Settings 
WHERE Category = 'SLA';

-- Check uptime periods for violations
SELECT * FROM monitor.UptimePeriods 
WHERE UptimePercentage < 99.0 
ORDER BY PeriodEnd DESC;
```

### Performance Tuning

#### Index Maintenance

```sql
-- Rebuild indexes for large tables
ALTER INDEX IX_Incidents_Date ON monitor.Incidents REBUILD;
ALTER INDEX IX_UptimePeriods_Date ON monitor.UptimePeriods REBUILD;
ALTER INDEX IX_SLATracking_Date ON monitor.SLATracking REBUILD;
```

#### Data Retention

```sql
-- Clean old data (older than 12 months)
DELETE FROM monitor.UptimePeriods 
WHERE PeriodStart < DATEADD(MONTH, -12, GETDATE());

DELETE FROM monitor.SLATracking 
WHERE PeriodStart < DATEADD(MONTH, -12, GETDATE());

DELETE FROM monitor.Incidents 
WHERE ResolvedAt < DATEADD(MONTH, -6, GETDATE());
```

## Best Practices

### 1. Regular Maintenance

- Schedule monthly index maintenance
- Implement data retention policies
- Regular review of SLA targets
- Update incident classification as needed

### 2. Monitoring

- Monitor collection success rates
- Track alert generation effectiveness
- Review incident response times
- Analyze uptime trends for patterns

### 3. Reporting

- Generate monthly reports for management
- Track SLA compliance over time
- Document major incidents and root causes
- Use trends for capacity planning

### 4. Integration

- Integrate with existing monitoring tools
- Export data for business intelligence
- Set up automated notifications
- Create custom dashboards

## Security

### Access Control

- Limit access to uptime data based on role
- Implement audit logging for changes
- Use encrypted connections for remote access
- Regular security reviews

### Data Protection

- Backup uptime data regularly
- Implement disaster recovery procedures
- Monitor for unauthorized access
- Use secure storage for sensitive data

## Version History

### Version 1.0.0
- Initial release with uptime tracking
- Incident classification system
- SLA compliance tracking
- Monthly reporting capabilities
- Real-time dashboard views

## Support

For issues or questions regarding the uptime tracker:

1. Check the troubleshooting section
2. Review the SQL Health Monitor documentation
3. Open an issue on GitHub
4. Contact the development team

---

*This documentation is part of the SQL Health Monitor project by Lucas Allan Borges*