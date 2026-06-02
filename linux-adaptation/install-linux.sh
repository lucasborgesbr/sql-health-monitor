#!/bin/bash

# SQL Health Monitor - Linux Installation Script
# Adapted for Linux environments with SQL Server
# Author: Lucas Allan Borges
# Version: 1.0.0

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_SERVER_HOST="${1:-localhost}"
SQL_SERVER_PORT="${2:-1433}"
DATABASE_NAME="${3:-SQLHealthMonitor}"
USERNAME="${4:-sa}"
PASSWORD="${5:-}"
USE_WINDOWS_AUTH="${6:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if sqlcmd is available
    if ! command -v sqlcmd &> /dev/null; then
        error "sqlcmd is not installed. Please install Microsoft ODBC Driver for SQL Server and unixodbc."
        exit 1
    fi
    
    # Check if SQL Server is accessible
    if ! sqlcmd -S "${SQL_SERVER_HOST},${SQL_SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -Q "SELECT 1" -l 10 > /dev/null 2>&1; then
        error "Cannot connect to SQL Server at ${SQL_SERVER_HOST}:${SQL_SERVER_PORT}"
        exit 1
    fi
    
    log "Prerequisites check passed"
}

# Create database and schema
create_database() {
    log "Creating database and schema..."
    
    # Create database if it doesn't exist
    sqlcmd -S "${SQL_SERVER_HOST},${SQL_SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -Q "
    IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = '${DATABASE_NAME}')
    BEGIN
        CREATE DATABASE [${DATABASE_NAME}];
        PRINT 'Database ${DATABASE_NAME} created successfully';
    END
    ELSE
    BEGIN
        PRINT 'Database ${DATABASE_NAME} already exists';
    END
    " -l 30
    
    # Create schema
    sqlcmd -S "${SQL_SERVER_HOST},${SQL_SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -i "${SCRIPT_DIR}/../install/00-create-schema.sql" -l 30
    
    log "Database and schema created successfully"
}

# Install Linux-adapted collectors
install_collectors() {
    log "Installing Linux-adapted collectors..."
    
    # Install Linux-specific collectors
    for collector in "${SCRIPT_DIR}/linux-adaptation/collect_*.sql"; do
        if [ -f "$collector" ]; then
            filename=$(basename "$collector")
            log "Installing $filename..."
            sqlcmd -S "${SQL_SERVER_HOST},${SQL_SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -i "$collector" -l 30
        fi
    done
    
    # Install standard collectors that work on Linux
    for collector in "${SCRIPT_DIR}/../collectors/collect_*.sql"; do
        filename=$(basename "$collector")
        # Skip collectors that have Linux-specific versions
        if [[ ! "$filename" =~ collect_cpu\.sql|collect_disk\.sql|collect_errorlog\.sql|collect_job_history\.sql ]]; then
            log "Installing $filename..."
            sqlcmd -S "${SQL_SERVER_HOST},${SQL_SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -i "$collector" -l 30
        fi
    done
    
    log "Collectors installed successfully"
}

# Install core components
install_core() {
    log "Installing core components..."
    
    # Install core tables and procedures
    sqlcmd -S "${SQL_SERVER_HOST},${SQL_SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -i "${SCRIPT_DIR}/../install/01-create-collectors.sql" -l 30
    sqlcmd -S "${SQL_SERVER_HOST},${SQL_SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -i "${SCRIPT_DIR}/../install/02-create-reports.sql" -l 30
    sqlcmd -S "${SQL_SERVER_HOST},${SQL_SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -i "${SCRIPT_DIR}/../install/03-create-alerts.sql" -l 30
    sqlcmd -S "${SQL_SERVER_HOST},${SQL_SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -i "${SCRIPT_DIR}/../install/05-configure.sql" -l 30
    sqlcmd -S "${SQL_SERVER_HOST},${SQL_SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -i "${SCRIPT_DIR}/../install/06-alert-history.sql" -l 30
    sqlcmd -S "${SQL_SERVER_HOST},${SQL_SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -i "${SCRIPT_DIR}/../install/07-baselines.sql" -l 30
    
    log "Core components installed successfully"
}

# Create Linux-specific cron jobs
setup_cron_jobs() {
    log "Setting up cron jobs for Linux..."
    
    # Create cron job file
    cat > /tmp/sql_health_monitor_cron << 'EOF'
# SQL Health Monitor - Linux Cron Jobs
# Run every 2 minutes
*/2 * * * * /usr/bin/sqlcmd -S localhost,1433 -U sa -P "your_password" -d SQLHealthMonitor -Q "EXEC [monitor].[usp_RunAllCollectors];" > /var/log/sql_health_monitor_collect.log 2>&1

# Run alert engine every 5 minutes
*/5 * * * * /usr/bin/sqlcmd -S localhost,1433 -U sa -P "your_password" -d SQLHealthMonitor -Q "EXEC [monitor].[usp_RunAlertEngine];" > /var/log/sql_health_monitor_alerts.log 2>&1

# Daily report at 7:00 AM
0 7 * * * /usr/bin/sqlcmd -S localhost,1433 -U sa -P "your_password" -d SQLHealthMonitor -Q "EXEC [monitor].[usp_RunReport] @ReportType = 'Daily';" > /var/log/sql_health_monitor_daily.log 2>&1

# Weekly report on Monday at 8:00 AM
0 8 * * 1 /usr/bin/sqlcmd -S localhost,1433 -U sa -P "your_password" -d SQLHealthMonitor -Q "EXEC [monitor].[usp_RunReport] @ReportType = 'Weekly';" > /var/log/sql_health_monitor_weekly.log 2>&1

# Maintenance job daily at 3:00 AM
0 3 * * * /usr/bin/sqlcmd -S localhost,1433 -U sa -P "your_password" -d SQLHealthMonitor -Q "EXEC [monitor].[usp_Maintenance_PurgeOldData];" > /var/log/sql_health_monitor_maintenance.log 2>&1
EOF

    # Install cron job
    sudo cp /tmp/sql_health_monitor_cron /etc/cron.d/sql_health_monitor
    sudo chmod 644 /etc/cron.d/sql_health_monitor
    
    log "Cron jobs installed successfully"
}

# Create systemd service for manual execution
create_systemd_service() {
    log "Creating systemd service..."
    
    # Create systemd service file
    cat > /tmp/sql_health_monitor.service << EOF
[Unit]
Description=SQL Health Monitor Collection Service
After=mssql.service
Requires=mssql.service

[Service]
Type=simple
User=mssql
ExecStart=/usr/bin/sqlcmd -S localhost,1433 -U sa -P "your_password" -d SQLHealthMonitor -Q "EXEC [monitor].[usp_RunAllCollectors];"
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

    # Install systemd service
    sudo cp /tmp/sql_health_monitor.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable sql_health_monitor.service
    
    log "Systemd service created successfully"
}

# Create configuration file
create_config() {
    log "Creating configuration file..."
    
    cat > "${SCRIPT_DIR}/../config/linux-config.json" << EOF
{
  "InstallMode": "Linux",
  "Connection": {
    "ServerInstance": "${SQL_SERVER_HOST}",
    "Port": ${SQL_SERVER_PORT},
    "AuthMethod": "${USE_WINDOWS_AUTH}",
    "Database": "${DATABASE_NAME}"
  },
  "Collectors": {
    "EnableAll": true,
    "Disabled": [],
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
    "Recipients": ["dba@company.com"],
    "CustomThresholds": {
      "CPU_Warning": 80,
      "CPU_Critical": 95,
      "Disk_Warning": 85,
      "Disk_Critical": 95,
      "PLE_Warning": 300,
      "PLE_Critical": 100
    }
  },
  "Scheduling": {
    "UseCron": true,
    "CollectionInterval": "2min",
    "AlertInterval": "5min",
    "DailyReportTime": "07:00",
    "WeeklyReportDay": "Monday",
    "WeeklyReportTime": "08:00",
    "MaintenanceTime": "03:00"
  },
  "Retention": {
    "UseDefaults": true,
    "RawDataDays": 30,
    "DailySummaryDays": 90,
    "WeeklySummaryDays": 365,
    "AlertHistoryDays": 365,
    "AnomalyDays": 90
  }
}
EOF
    
    log "Configuration file created successfully"
}

# Test installation
test_installation() {
    log "Testing installation..."
    
    # Test database connection
    if sqlcmd -S "${SQL_SERVER_HOST},${SQL_SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -Q "SELECT 1" -l 10 > /dev/null 2>&1; then
        log "Database connection test passed"
    else
        error "Database connection test failed"
        exit 1
    fi
    
    # Test collector execution
    if sqlcmd -S "${SQL_SERVER_HOST},${SQL_SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -Q "EXEC [monitor].[usp_RunAllCollectors];" -l 60 > /dev/null 2>&1; then
        log "Collector execution test passed"
    else
        error "Collector execution test failed"
        exit 1
    fi
    
    log "Installation test passed"
}

# Main installation process
main() {
    log "Starting SQL Health Monitor installation for Linux..."
    log "Target server: ${SQL_SERVER_HOST}:${SQL_SERVER_PORT}"
    log "Database: ${DATABASE_NAME}"
    
    check_prerequisites
    create_database
    install_core
    install_collectors
    create_config
    
    # Optional: Setup cron jobs (requires sudo)
    if [ "$EUID" -eq 0 ]; then
        setup_cron_jobs
        create_systemd_service
    else
        warn "Skipping cron setup - run as root or setup manually"
        warn "To setup cron jobs, run: sudo ./install-linux.sh --setup-cron"
    fi
    
    test_installation
    
    log "SQL Health Monitor installation completed successfully!"
    log "Next steps:"
    log "1. Update configuration in config/linux-config.json"
    log "2. Set up email notifications if needed"
    log "3. Review and customize alert thresholds"
    log "4. Start manual collection: sqlcmd -S ${SQL_SERVER_HOST},${SQL_SERVER_PORT} -U ${USERNAME} -P ${PASSWORD} -d ${DATABASE_NAME} -Q \"EXEC [monitor].[usp_RunAllCollectors];\""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --setup-cron)
            setup_cron_jobs
            create_systemd_service
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [server_host] [server_port] [database_name] [username] [password] [use_windows_auth]"
            echo "Example: $0 localhost 1433 SQLHealthMonitor sa false"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Run main function
main "$@"