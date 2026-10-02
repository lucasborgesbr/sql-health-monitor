#!/bin/bash

# SQL Health Monitor - Linux Manual Execution Script
# Allows manual execution of collectors and reports on Linux
# Author: Lucas Allan Borges
# Version: 1.0.0

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/linux-config.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
SERVER_HOST="localhost"
SERVER_PORT="1433"
DATABASE_NAME="SQLHealthMonitor"
USERNAME="sa"
PASSWORD=""
USE_WINDOWS_AUTH="false"

# Load configuration if it exists
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${BLUE}[INFO]${NC} Loading configuration from $CONFIG_FILE"
    SERVER_HOST=$(jq -r '.Connection.ServerInstance' "$CONFIG_FILE")
    SERVER_PORT=$(jq -r '.Connection.Port' "$CONFIG_FILE")
    DATABASE_NAME=$(jq -r '.Connection.Database' "$CONFIG_FILE")
    USERNAME=$(jq -r '.Connection.AuthMethod' "$CONFIG_FILE")
    PASSWORD=$(jq -r '.Connection.Password // ""' "$CONFIG_FILE")
    USE_WINDOWS_AUTH=$(jq -r '.Connection.AuthMethod' "$CONFIG_FILE")
fi

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

# Show usage
show_usage() {
    echo "SQL Health Monitor - Linux Manual Execution Script"
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  collect          Run all collectors"
    echo "  cpu             Run CPU collector only"
    echo "  memory          Run memory collector only"
    echo "  disk            Run disk collector only"
    echo "  errorlog        Run error log collector only"
    echo "  blocking        Run blocking collector only"
    echo "  deadlocks       Run deadlock collector only"
    echo "  ag-health       Run AG health collector only"
    echo "  job-history     Run job history collector only"
    echo "  waits           Run waits collector only"
    echo "  alerts          Run alert engine"
    echo "  report [daily|weekly] Generate report"
    echo "  maintenance     Run maintenance tasks"
    echo "  status          Show system status"
    echo "  test            Test connectivity"
    echo ""
    echo "Options:"
    echo "  --server HOST   SQL Server host (default: localhost)"
    echo "  --port PORT     SQL Server port (default: 1433)"
    echo "  --database DB   Database name (default: SQLHealthMonitor)"
    echo "  --user USER     Username (default: sa)"
    echo "  --password PWD  Password"
    echo "  --windows-auth  Use Windows authentication"
    echo "  --verbose       Show detailed output"
    echo "  --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 collect --server my-sql-server --user sa --password mypass"
    echo "  $0 report daily --database MyMonitorDB"
    echo "  $0 status --verbose"
}

# Test connectivity
test_connectivity() {
    log "Testing connectivity to SQL Server..."
    
    if [ -z "$PASSWORD" ]; then
        error "Password is required for connection"
        exit 1
    fi
    
    if sqlcmd -S "${SERVER_HOST},${SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -Q "SELECT 1" -l 10 > /dev/null 2>&1; then
        log "Connectivity test passed"
    else
        error "Cannot connect to SQL Server at ${SERVER_HOST}:${SERVER_PORT}"
        exit 1
    fi
}

# Execute SQL command
execute_sql() {
    local command="$1"
    local options="$2"
    
    if [ -z "$PASSWORD" ]; then
        error "Password is required for connection"
        exit 1
    fi
    
    if [ "$USE_WINDOWS_AUTH" = "true" ]; then
        sqlcmd -S "${SERVER_HOST},${SERVER_PORT}" -E -d "${DATABASE_NAME}" -Q "${command}" ${options}
    else
        sqlcmd -S "${SERVER_HOST},${SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -Q "${command}" ${options}
    fi
}

# Run all collectors
run_collectors() {
    log "Running all collectors..."
    execute_sql "EXEC [monitor].[usp_RunAllCollectors];" "-l 300"
    log "All collectors completed"
}

# Run specific collector
run_collector() {
    local collector_name="$1"
    log "Running ${collector_name} collector..."
    
    case "$collector_name" in
        "cpu")
            execute_sql "EXEC [monitor].[usp_Collect_CPU];" "-l 60"
            ;;
        "memory")
            execute_sql "EXEC [monitor].[usp_Collect_Memory];" "-l 60"
            ;;
        "disk")
            execute_sql "EXEC [monitor].[usp_Collect_Disk];" "-l 60"
            ;;
        "errorlog")
            execute_sql "EXEC [monitor].[usp_Collect_ErrorLog];" "-l 60"
            ;;
        "blocking")
            execute_sql "EXEC [monitor].[usp_Collect_Blocking];" "-l 60"
            ;;
        "deadlocks")
            execute_sql "EXEC [monitor].[usp_Collect_Deadlocks];" "-l 60"
            ;;
        "ag-health")
            execute_sql "EXEC [monitor].[usp_Collect_AG_Health];" "-l 60"
            ;;
        "job-history")
            execute_sql "EXEC [monitor].[usp_Collect_JobHistory];" "-l 60"
            ;;
        "waits")
            execute_sql "EXEC [monitor].[usp_Collect_Waits];" "-l 60"
            ;;
        *)
            error "Unknown collector: $collector_name"
            exit 1
            ;;
    esac
    
    log "${collector_name} collector completed"
}

# Run alert engine
run_alerts() {
    log "Running alert engine..."
    execute_sql "EXEC [monitor].[usp_RunAlertEngine];" "-l 60"
    log "Alert engine completed"
}

# Generate report
generate_report() {
    local report_type="$1"
    log "Generating ${report_type} report..."
    
    case "$report_type" in
        "daily")
            execute_sql "EXEC [monitor].[usp_RunReport] @ReportType = 'Daily';" "-l 120"
            ;;
        "weekly")
            execute_sql "EXEC [monitor].[usp_RunReport] @ReportType = 'Weekly';" "-l 180"
            ;;
        *)
            error "Unknown report type: $report_type"
            exit 1
            ;;
    esac
    
    log "${report_type} report generated"
}

# Run maintenance
run_maintenance() {
    log "Running maintenance tasks..."
    execute_sql "EXEC [monitor].[usp_PurgeHistoricalData];" "-l 120"
    execute_sql "EXEC [monitor].[usp_Maintenance_UpdateBaselines];" "-l 120"
    log "Maintenance completed"
}

# Show status
show_status() {
    log "Showing system status..."
    
    # Show database status
    echo -e "${BLUE}Database Status:${NC}"
    execute_sql "
    SELECT 
        name as DatabaseName,
        create_date as CreatedDate,
        state_desc as State,
        collation_name as Collation
    FROM sys.databases 
    WHERE name = '${DATABASE_NAME}';" "-h-1 -w 200"
    
    # Show collector status
    echo -e "\n${BLUE}Collector Status:${NC}"
    execute_sql "
    SELECT TOP 10
        CollectionDate,
        'CPU' as CollectorType,
        TotalCPUms,
        SystemCPUms
    FROM [monitor].[CPUHistory]
    ORDER BY CollectionDate DESC;
    
    SELECT TOP 10
        CollectionDate,
        'Memory' as CollectorType,
        TotalMemoryMB,
        BufferPoolMB
    FROM [monitor].[MemoryHistory]
    ORDER BY CollectionDate DESC;
    
    SELECT TOP 10
        CollectionDate,
        'Disk' as CollectorType,
        DriveLetter,
        UsedPct
    FROM [monitor].[DiskHistory]
    ORDER BY CollectionDate DESC;" "-h-1 -w 200"
    
    # Show alert status
    echo -e "\n${BLUE}Alert Status:${NC}"
    execute_sql "
    SELECT TOP 10
        AlertDate,
        MetricName,
        Severity,
        CurrentValue,
        ThresholdValue
    FROM [monitor].[AlertHistory]
    ORDER BY AlertDate DESC;" "-h-1 -w 200"
    
    # Show job status
    echo -e "\n${BLUE}Job Status:${NC}"
    execute_sql "
    SELECT TOP 10
        JobName,
        LastRunDate,
        LastRunStatus,
        LastRunDuration
    FROM [monitor].[JobHistory]
    ORDER BY LastRunDate DESC;" "-h-1 -w 200"
}

# Parse command line arguments
VERBOSE=false
COMMAND=""
COLLECTOR=""
REPORT_TYPE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        collect|cpu|memory|disk|errorlog|blocking|deadlocks|ag-health|job-history|waits|alerts|maintenance|status|test)
            COMMAND="$1"
            shift
            ;;
        daily|weekly)
            REPORT_TYPE="$1"
            shift
            ;;
        --server)
            SERVER_HOST="$2"
            shift 2
            ;;
        --port)
            SERVER_PORT="$2"
            shift 2
            ;;
        --database)
            DATABASE_NAME="$2"
            shift 2
            ;;
        --user)
            USERNAME="$2"
            shift 2
            ;;
        --password)
            PASSWORD="$2"
            shift 2
            ;;
        --windows-auth)
            USE_WINDOWS_AUTH="true"
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Execute command based on input
case "$COMMAND" in
    "collect")
        test_connectivity
        run_collectors
        ;;
    "cpu"|"memory"|"disk"|"errorlog"|"blocking"|"deadlocks"|"ag-health"|"job-history"|"waits")
        test_connectivity
        run_collector "$COMMAND"
        ;;
    "alerts")
        test_connectivity
        run_alerts
        ;;
    "report")
        test_connectivity
        if [ -z "$REPORT_TYPE" ]; then
            error "Report type is required (daily or weekly)"
            exit 1
        fi
        generate_report "$REPORT_TYPE"
        ;;
    "maintenance")
        test_connectivity
        run_maintenance
        ;;
    "status")
        test_connectivity
        show_status
        ;;
    "test")
        test_connectivity
        ;;
    *)
        error "No command specified"
        show_usage
        exit 1
        ;;
esac