# SQL Health Monitor - Linux Implementation Guide

## Overview

This guide provides step-by-step instructions for implementing SQL Health Monitor on Linux environments. The implementation includes adapting collectors for Linux compatibility, setting up monitoring infrastructure, and ensuring proper scheduling and alerting.

## Prerequisites

### System Requirements
- **SQL Server**: 2017+ (Linux)
- **Operating System**: Ubuntu 18.04+, RHEL 7+, CentOS 7+
- **Memory**: Minimum 2GB RAM (recommended 4GB+)
- **Storage**: Minimum 10GB free space (recommended 50GB+)
- **Network**: TCP/IP access to SQL Server

### Software Dependencies
- **sqlcmd**: Microsoft ODBC Driver for SQL Server
- **jq**: JSON processor for configuration
- **cron**: For job scheduling
- **systemd**: For service management
- **Postfix** (optional): For email notifications

## Installation Steps

### Step 1: Install Dependencies

#### Ubuntu/Debian
```bash
# Update package list
sudo apt-get update

# Install required packages
sudo apt-get install -y mssql-tools jq cron systemd postfix

# Add sqlcmd to PATH
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
source ~/.bashrc
```

#### RHEL/CentOS
```bash
# Install required packages
sudo yum install -y mssql-tools jq cron systemd postfix

# Add sqlcmd to PATH
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
source ~/.bashrc
```

### Step 2: Download SQL Health Monitor

```bash
# Clone the repository
git clone https://github.com/your-repo/sql-health-monitor.git
cd sql-health-monitor

# Navigate to Linux adaptation directory
cd linux-adaptation

# Make scripts executable
chmod +x install-linux.sh run-collector.sh validate-installation.sh
```

### Step 3: Configure Connection Settings

Edit the configuration file:
```bash
nano ../config/linux-config.json
```

Update the connection settings:
```json
{
  "InstallMode": "Linux",
  "Connection": {
    "ServerInstance": "localhost",
    "Port": 1433,
    "AuthMethod": "Sql",
    "Database": "SQLHealthMonitor"
  },
  "Collectors": {
    "EnableAll": true,
    "LinuxAdaptations": {
      "CollectCPU": true,
      "CollectDisk": true,
      "CollectErrorLog": true,
      "CollectJobHistory": true
    }
  },
  "Alerts": {
    "Enabled": true,
    "UseDefaults": true,
    "Recipients": ["dba@company.com"]
  },
  "Scheduling": {
    "UseCron": true,
    "CollectionInterval": "2min",
    "AlertInterval": "5min",
    "DailyReportTime": "07:00",
    "WeeklyReportDay": "Monday",
    "WeeklyReportTime": "08:00",
    "MaintenanceTime": "03:00"
  }
}
```

### Step 4: Run Installation

```bash
# Run the installation script
./install-linux.sh localhost 1433 SQLHealthMonitor sa your_password
```

The script will:
1. Check prerequisites
2. Create the database and schema
3. Install Linux-adapted collectors
4. Install core components
5. Set up cron jobs
6. Create systemd service
7. Test the installation

### Step 5: Validate Installation

```bash
# Run validation script
./validate-installation.sh --server localhost --database SQLHealthMonitor --user sa --password your_password
```

The validation script will test:
- Database connectivity
- Schema and tables
- Stored procedures
- Collectors
- Alert engine
- Data collection
- Cron jobs
- Systemd service
- File permissions
- Log files

## Configuration

### Step 1: Configure Email Notifications (Optional)

If you want email notifications, configure Postfix:

```bash
# Install Postfix
sudo apt-get install postfix

# Configure Postfix
sudo dpkg-reconfigure postfix

# Test email functionality
echo "Test email" | mail -s "Test Subject" dba@company.com
```

### Step 2: Customize Alert Thresholds

```sql
-- Connect to SQL Server
sqlcmd -S localhost,1433 -U sa -P your_password -d SQLHealthMonitor

-- Update thresholds
UPDATE [monitor].[Thresholds] 
SET WarningValue = 80, CriticalValue = 95 
WHERE MetricName = 'CPU_SqlPct';

UPDATE [monitor].[Thresholds] 
SET WarningValue = 85, CriticalValue = 95 
WHERE MetricName = 'Disk_UsedPct';

UPDATE [monitor].[Thresholds] 
SET WarningValue = 300, CriticalValue = 100 
WHERE MetricName = 'PLE_Minutes';
```

### Step 3: Configure Alert Recipients

```sql
-- Add email recipients
INSERT INTO [monitor].[AlertRecipients] (Email, IsActive, AlertTypes)
VALUES ('dba@company.com', 1, 'All');

INSERT INTO [monitor].[AlertRecipients] (Email, IsActive, AlertTypes)
VALUES ('manager@company.com', 1, 'Critical,Warning');
```

## Monitoring and Management

### Step 1: Manual Execution

Run collectors manually:
```bash
# Run all collectors
./run-collector.sh collect --server localhost --database SQLHealthMonitor --user sa --password your_password

# Run specific collector
./run-collector.sh cpu --server localhost --database SQLHealthMonitor --user sa --password your_password

# Generate daily report
./run-collector.sh report daily --server localhost --database SQLHealthMonitor --user sa --password your_password

# Check system status
./run-collector.sh status --server localhost --database SQLHealthMonitor --user sa --password your_password
```

### Step 2: Monitor Services

Check service status:
```bash
# Check cron service
sudo systemctl status cron

# Check systemd service
sudo systemctl status sql_health_monitor

# View logs
sudo journalctl -u sql_health_monitor -f
```

### Step 3: Review Logs

Monitor log files:
```bash
# View collector logs
tail -f /var/log/sql_health_monitor_collect.log

# View alert logs
tail -f /var/log/sql_health_monitor_alerts.log

# View daily report logs
tail -f /var/log/sql_health_monitor_daily.log

# View maintenance logs
tail -f /var/log/sql_health_monitor_maintenance.log
```

## Scheduling

### Step 1: Cron Job Configuration

The installation script creates cron jobs in `/etc/cron.d/sql_health_monitor`. You can customize them:

```bash
# Edit cron jobs
sudo nano /etc/cron.d/sql_health_monitor
```

Example cron configuration:
```
# Run every 2 minutes
*/2 * * * * mssql-cli -S localhost,1433 -U sa -P "your_password" -d SQLHealthMonitor -Q "EXEC [monitor].[usp_RunAllCollectors];" > /var/log/sql_health_monitor_collect.log 2>&1

# Run alert engine every 5 minutes
*/5 * * * * mssql-cli -S localhost,1433 -U sa -P "your_password" -d SQLHealthMonitor -Q "EXEC [monitor].[usp_RunAlertEngine];" > /var/log/sql_health_monitor_alerts.log 2>&1

# Daily report at 7:00 AM
0 7 * * * mssql-cli -S localhost,1433 -U sa -P "your_password" -d SQLHealthMonitor -Q "EXEC [monitor].[usp_RunReport] @ReportType = 'Daily';" > /var/log/sql_health_monitor_daily.log 2>&1

# Weekly report on Monday at 8:00 AM
0 8 * * 1 mssql-cli -S localhost,1433 -U sa -P "your_password" -d SQLHealthMonitor -Q "EXEC [monitor].[usp_RunReport] @ReportType = 'Weekly';" > /var/log/sql_health_monitor_weekly.log 2>&1

# Maintenance job daily at 3:00 AM
0 3 * * * mssql-cli -S localhost,1433 -U sa -P "your_password" -d SQLHealthMonitor -Q "EXEC [monitor].[usp_Maintenance_PurgeOldData];" > /var/log/sql_health_monitor_maintenance.log 2>&1
```

### Step 2: Systemd Service Management

Manage the systemd service:
```bash
# Enable service
sudo systemctl enable sql_health_monitor.service

# Start service
sudo systemctl start sql_health_monitor.service

# Stop service
sudo systemctl stop sql_health_monitor.service

# Restart service
sudo systemctl restart sql_health_monitor.service

# Check service status
sudo systemctl status sql_health_monitor

# View service logs
sudo journalctl -u sql_health_monitor -f
```

## Performance Tuning

### Step 1: Adjust Collection Intervals

Modify cron intervals based on system load:
```bash
# For high-load systems, increase intervals
# Change */2 to */5 for 5-minute intervals
# Change */5 to */10 for 10-minute intervals
```

### Step 2: Optimize Query Performance

Monitor collector execution time:
```sql
-- Check collector performance
SELECT 
    CollectionDate,
    'CPU' as Collector,
    TotalCPUms,
    SystemCPUms
FROM [monitor].[CPUHistory]
ORDER BY CollectionDate DESC;
```

### Step 3: Manage Data Retention

Configure data retention:
```sql
-- Update retention settings
UPDATE [monitor].[Settings] 
SET SettingValue = '30' 
WHERE Category = 'Retention' AND SettingName = 'RawDataRetentionDays';

UPDATE [monitor].[Settings] 
SET SettingValue = '90' 
WHERE Category = 'Retention' AND SettingName = 'DailySummaryRetentionDays';
```

## Backup and Recovery

### Step 1: Database Backup

Create backup script:
```bash
#!/bin/bash
# backup-script.sh

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backup/sql_health_monitor"
mkdir -p $BACKUP_DIR

# Create backup
sqlcmd -S localhost,1433 -U sa -P your_password -Q "BACKUP DATABASE SQLHealthMonitor TO DISK = '$BACKUP_DIR/backup_$DATE.bak'"

# Keep only last 7 days
find $BACKUP_DIR -name "*.bak" -mtime +7 -delete

echo "Backup completed: $BACKUP_DIR/backup_$DATE.bak"
```

Make backup script executable and schedule it:
```bash
chmod +x backup-script.sh
echo "0 2 * * * /path/to/backup-script.sh" | sudo tee -a /etc/cron.d/sql_health_monitor_backup
```

### Step 2: Configuration Backup

Backup configuration files:
```bash
# Copy configuration to backup location
cp -r /path/to/sql-health-monitor /backup/sql_health_monitor_config_$(date +%Y%m%d)
```

## Troubleshooting

### Step 1: Common Issues

#### Connection Problems
```bash
# Test connectivity
sqlcmd -S localhost,1433 -U sa -P your_password -Q "SELECT 1"

# Check SQL Server service
sudo systemctl status mssql-server
```

#### Collector Failures
```bash
# Check collector logs
tail -f /var/log/sql_health_monitor_collect.log

# Run individual collector manually
./run-collector.sh cpu --server localhost --database SQLHealthMonitor --user sa --password your_password
```

#### Cron Job Issues
```bash
# Check cron service
sudo systemctl status cron

# Test cron syntax
sudo crontab -l

# Check cron logs
sudo tail -f /var/log/syslog | grep CRON
```

#### Permission Issues
```bash
# Check file permissions
ls -la /etc/cron.d/sql_health_monitor
sudo chmod 644 /etc/cron.d/sql_health_monitor

# Check service permissions
sudo systemctl status sql_health_monitor
```

### Step 2: Debug Mode

Enable debug mode for detailed logging:
```bash
# Run collector with debug output
./run-collector.sh collect --server localhost --database SQLHealthMonitor --user sa --password your_password --verbose
```

### Step 3: System Health Check

Perform comprehensive health check:
```bash
# Run validation script
./validate-installation.sh --server localhost --database SQLHealthMonitor --user sa -- password your_password

# Check system resources
htop
df -h
free -h
```

## Security Considerations

### Step 1: Secure Configuration

#### Secure SQL Server Connection
```bash
# Enable SSL encryption
sqlcmd -S localhost,1433 -U sa -P your_password -C -Q "SELECT 1"
```

#### File Permissions
```bash
# Secure configuration files
sudo chmod 600 /etc/cron.d/sql_health_monitor
sudo chmod 600 /path/to/sql-health-monitor/config/linux-config.json
```

### Step 2: Network Security

#### Firewall Configuration
```bash
# Allow SQL Server port
sudo ufw allow 1433/tcp

# Allow local cron jobs
sudo ufw allow from 127.0.0.1 to any port 1433
```

### Step 3: User Management

#### Create Dedicated User
```bash
# Create dedicated user for monitoring
sudo useradd -m -s /bin/bash sqlmonitor
sudo usermod -aG mssql sqlmonitor
```

## Advanced Configuration

### Step 1: External Monitoring Integration

#### Prometheus Integration
```bash
# Install Prometheus
sudo apt-get install prometheus

# Configure Prometheus to collect SQL metrics
# Create prometheus.yml with SQL Health Monitor scrape configuration
```

#### Grafana Dashboard
```bash
# Install Grafana
sudo apt-get install grafana

# Configure data source
# Create dashboard with SQL Health Monitor metrics
```

### Step 2: High Availability

#### Multi-Instance Setup
```bash
# Configure monitoring for multiple instances
# Create separate configuration files for each instance
# Use cron jobs to monitor all instances
```

#### Load Balancing
```bash
# Configure load balancer for multiple SQL instances
# Use health checks to monitor instance availability
# Update configuration to use load balancer endpoint
```

### Step 3: Custom Alerts

#### Create Custom Alert Rules
```sql
-- Add custom alert for specific conditions
INSERT INTO [monitor].[Thresholds] 
(MetricName, WarningValue, CriticalValue, Description)
VALUES ('Custom_Metric', 80, 95, 'Custom metric description');
```

#### Custom Alert Actions
```sql
-- Create custom alert action procedure
CREATE OR ALTER PROCEDURE [monitor].[usp_CustomAlertAction]
    @MetricName NVARCHAR(100),
    @Severity NVARCHAR(20),
    @CurrentValue DECIMAL(18,2),
    @Context NVARCHAR(500)
AS
BEGIN
    -- Custom alert logic here
    INSERT INTO [monitor].[ErrorLogHistory] 
    (LogDate, ProcessInfo, ErrorMessage, Severity)
    VALUES (SYSUTCDATETIME(), 'Custom Alert', 
            'Custom alert triggered: ' + @MetricName, @Severity);
END;
```

## Maintenance

### Step 1: Regular Maintenance Tasks

#### Daily Tasks
```bash
# Check log files
ls -la /var/log/sql_health_monitor_*.log

# Check service status
sudo systemctl status sql_health_monitor

# Verify data collection
./run-collector.sh status --server localhost --database SQLHealthMonitor --user sa --password your_password
```

#### Weekly Tasks
```bash
# Review alert history
sqlcmd -S localhost,1433 -U sa -P your_password -d SQLHealthMonitor -Q "SELECT * FROM [monitor].[AlertHistory] WHERE AlertDate >= DATEADD(DAY, -7, GETDATE()) ORDER BY AlertDate DESC;"

# Check performance metrics
sqlcmd -S localhost,1433 -U sa -P your_password -d SQLHealthMonitor -Q "SELECT * FROM [monitor].[CPUHistory] WHERE CollectionDate >= DATEADD(DAY, -7, GETDATE()) ORDER BY CollectionDate DESC;"

# Update baselines
sqlcmd -S localhost,1433 -U sa -P your_password -d SQLHealthMonitor -Q "EXEC [monitor].[usp_Maintenance_UpdateBaselines];"
```

#### Monthly Tasks
```bash
# Review configuration
cat /path/to/sql-health-monitor/config/linux-config.json

# Update thresholds if needed
sqlcmd -S localhost,1433 -U sa -P your_password -d SQLHealthMonitor -Q "UPDATE [monitor].[Thresholds] SET WarningValue = 85, CriticalValue = 95 WHERE MetricName = 'CPU_SqlPct';"

# Backup database
./backup-script.sh
```

### Step 2: Performance Monitoring

#### Monitor Collector Performance
```sql
-- Check collector execution time
SELECT 
    CollectionDate,
    'CPU' as Collector,
    TotalCPUms,
    SystemCPUms
FROM [monitor].[CPUHistory]
WHERE CollectionDate >= DATEADD(HOUR, -1, GETDATE())
ORDER BY CollectionDate DESC;
```

#### Monitor System Resources
```bash
# Check CPU usage
top -c

# Check memory usage
free -h

# Check disk usage
df -h

# Check network usage
netstat -i
```

## Support and Updates

### Step 1: Update SQL Health Monitor

```bash
# Pull latest changes
cd /path/to/sql-health-monitor
git pull origin main

# Update Linux adaptation
cd linux-adaptation
git pull origin main

# Reinstall if needed
./install-linux.sh localhost 1433 SQLHealthMonitor sa your_password
```

### Step 2: Get Help

#### Check Documentation
```bash
# View documentation
cat /path/to/sql-health-monitor/docs/Linux-Compatibility-Report.md
cat /path/to/sql-health-monitor/linux-adaptation/Linux-Compatibility-Report.md
```

#### Contact Support
- Email: support@sqlhealthmonitor.com
- GitHub: https://github.com/your-repo/sql-health-monitor
- Issues: https://github.com/your-repo/sql-health-monitor/issues

## Conclusion

This implementation guide provides comprehensive instructions for deploying SQL Health Monitor on Linux environments. By following these steps, you can establish robust monitoring for your SQL Server instances running on Linux with proper scheduling, alerting, and maintenance procedures.

For additional support and troubleshooting, refer to the full documentation or contact the development team.

---

*Last Updated: 2026-06-02*  
*Version: 1.0.0*  
*Author: Lucas Allan Borges*