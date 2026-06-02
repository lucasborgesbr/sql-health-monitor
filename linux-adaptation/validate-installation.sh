#!/bin/bash

# SQL Health Monitor - Linux Validation Script
# Validates Linux adaptation and tests all components
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

# Load configuration if it exists
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${BLUE}[INFO]${NC} Loading configuration from $CONFIG_FILE"
    SERVER_HOST=$(jq -r '.Connection.ServerInstance' "$CONFIG_FILE")
    SERVER_PORT=$(jq -r '.Connection.Port' "$CONFIG_FILE")
    DATABASE_NAME=$(jq -r '.Connection.Database' "$CONFIG_FILE")
    USERNAME=$(jq -r '.Connection.AuthMethod' "$CONFIG_FILE")
    PASSWORD=$(jq -r '.Connection.Password // ""' "$CONFIG_FILE")
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

# Test connectivity
test_connectivity() {
    log "Testing connectivity to SQL Server..."
    
    if [ -z "$PASSWORD" ]; then
        error "Password is required for connection"
        return 1
    fi
    
    if sqlcmd -S "${SERVER_HOST},${SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -Q "SELECT 1" -l 10 > /dev/null 2>&1; then
        log "✓ Connectivity test passed"
        return 0
    else
        error "✗ Cannot connect to SQL Server at ${SERVER_HOST}:${SERVER_PORT}"
        return 1
    fi
}

# Test database existence
test_database() {
    log "Testing database existence..."
    
    if sqlcmd -S "${SERVER_HOST},${SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -Q "IF DB_ID('${DATABASE_NAME}') IS NOT NULL SELECT 1 ELSE SELECT 0" -l 10 | grep -q "1"; then
        log "✓ Database '${DATABASE_NAME}' exists"
        return 0
    else
        error "✗ Database '${DATABASE_NAME}' does not exist"
        return 1
    fi
}

# test schema and tables
test_schema() {
    log "Testing schema and tables..."
    
    # Test monitor schema
    if sqlcmd -S "${SERVER_HOST},${SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -Q "IF SCHEMA_ID('monitor') IS NOT NULL SELECT 1 ELSE SELECT 0" -l 10 | grep -q "1"; then
        log "✓ Monitor schema exists"
    else
        error "✗ Monitor schema does not exist"
        return 1
    fi
    
    # Test key tables
    local tables=("CPUHistory" "MemoryHistory" "DiskHistory" "ErrorLogHistory" "BlockingHistory" "DeadlockHistory" "AgHealthHistory" "JobHistory")
    for table in "${tables[@]}"; do
        if sqlcmd -S "${SERVER_HOST},${SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -Q "IF OBJECT_ID('monitor.$table') IS NOT NULL SELECT 1 ELSE SELECT 0" -l 10 | grep -q "1"; then
            log "✓ Table monitor.$table exists"
        else
            warn "✗ Table monitor.$table does not exist"
        fi
    done
}

# test stored procedures
test_procedures() {
    log "Testing stored procedures..."
    
    local procedures=("usp_RunAllCollectors" "usp_Collect_CPU" "usp_Collect_Memory" "usp_Collect_Disk" "usp_Collect_ErrorLog" "usp_Collect_Blocking" "usp_Collect_Deadlocks" "usp_Collect_AG_Health" "usp_Collect_JobHistory" "usp_Collect_Waits" "usp_RunAlertEngine" "usp_RunReport")
    for proc in "${procedures[@]}"; do
        if sqlcmd -S "${SERVER_HOST},${SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -Q "IF OBJECT_ID('monitor.$proc') IS NOT NULL SELECT 1 ELSE SELECT 0" -l 10 | grep -q "1"; then
            log "✓ Procedure monitor.$proc exists"
        else
            warn "✗ Procedure monitor.$proc does not exist"
        fi
    done
}

# test collectors
test_collectors() {
    log "Testing collectors..."
    
    # Test CPU collector
    if sqlcmd -S "${SERVER_HOST},${SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -Q "EXEC monitor.usp_Collect_CPU;" -l 60 > /dev/null 2>&1; then
        log "✓ CPU collector test passed"
    else
        warn "✗ CPU collector test failed"
    fi
    
    # Test memory collector
    if sqlcmd -S "${SERVER_HOST},${SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -Q "EXEC monitor.usp_Collect_Memory;" -l 60 > /dev/null 2>&1; then
        log "✓ Memory collector test passed"
    else
        warn "✗ Memory collector test failed"
    fi
    
    # Test disk collector
    if sqlcmd -S "${SERVER_HOST},${SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -Q "EXEC monitor.usp_Collect_Disk;" -l 60 > /dev/null 2>&1; then
        log "✓ Disk collector test passed"
    else
        warn "✗ Disk collector test failed"
    fi
    
    # Test error log collector
    if sqlcmd -S "${SERVER_HOST},${SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -Q "EXEC monitor.usp_Collect_ErrorLog;" -l 60 > /dev/null 2>&1; then
        log "✓ Error log collector test passed"
    else
        warn "✗ Error log collector test failed"
    fi
}

# test alert engine
test_alerts() {
    log "Testing alert engine..."
    
    if sqlcmd -S "${SERVER_HOST},${SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -Q "EXEC monitor.usp_RunAlertEngine;" -l 60 > /dev/null 2>&1; then
        log "✓ Alert engine test passed"
    else
        warn "✗ Alert engine test failed"
    fi
}

# test data collection
test_data_collection() {
    log "Testing data collection..."
    
    # Check if data was collected
    local cpu_count=$(sqlcmd -S "${SERVER_HOST},${SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -Q "SELECT COUNT(*) FROM monitor.CPUHistory WHERE CollectionDate >= DATEADD(MINUTE, -10, GETDATE())" -h-1 -W | tr -d ' ')
    if [ "$cpu_count" -gt 0 ]; then
        log "✓ CPU data collected ($cpu_count records)"
    else
        warn "✗ No CPU data collected in last 10 minutes"
    fi
    
    local memory_count=$(sqlcmd -S "${SERVER_HOST},${SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -Q "SELECT COUNT(*) FROM monitor.MemoryHistory WHERE CollectionDate >= DATEADD(MINUTE, -10, GETDATE())" -h-1 -W | tr -d ' ')
    if [ "$memory_count" -gt 0 ]; then
        log "✓ Memory data collected ($memory_count records)"
    else
        warn "✗ No memory data collected in last 10 minutes"
    fi
    
    local disk_count=$(sqlcmd -S "${SERVER_HOST},${SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -Q "SELECT COUNT(*) FROM monitor.DiskHistory WHERE CollectionDate >= DATEADD(MINUTE, -10, GETDATE())" -h-1 -W | tr -d ' ')
    if [ "$disk_count" -gt 0 ]; then
        log "✓ Disk data collected ($disk_count records)"
    else
        warn "✗ No disk data collected in last 10 minutes"
    fi
}

# test alerts configuration
test_alerts_config() {
    log "Testing alerts configuration..."
    
    # Check if thresholds are configured
    local threshold_count=$(sqlcmd -S "${SERVER_HOST},${SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -Q "SELECT COUNT(*) FROM monitor.Thresholds" -h-1 -W | tr -d ' ')
    if [ "$threshold_count" -gt 0 ]; then
        log "✓ Thresholds configured ($threshold_count rules)"
    else
        warn "✗ No thresholds configured"
    fi
    
    # Check if alert history exists
    local alert_count=$(sqlcmd -S "${SERVER_HOST},${SERVER_PORT}" -U "${USERNAME}" -P "${PASSWORD}" -d "${DATABASE_NAME}" -Q "SELECT COUNT(*) FROM monitor.AlertHistory WHERE AlertDate >= DATEADD(DAY, -1, GETDATE())" -h-1 -W | tr -d ' ')
    if [ "$alert_count" -gt 0 ]; then
        log "✓ Alert history exists ($alert_count alerts in last 24 hours)"
    else
        log "ℹ No alerts in last 24 hours (normal for healthy system)"
    fi
}

# test cron jobs
test_cron_jobs() {
    log "Testing cron jobs..."
    
    if [ -f "/etc/cron.d/sql_health_monitor" ]; then
        log "✓ Cron job file exists"
        # Check if cron service is running
        if systemctl is-active --quiet cron; then
            log "✓ Cron service is running"
        else
            warn "✗ Cron service is not running"
        fi
    else
        warn "✗ Cron job file does not exist"
    fi
}

# test systemd service
test_systemd_service() {
    log "Testing systemd service..."
    
    if [ -f "/etc/systemd/system/sql_health_monitor.service" ]; then
        log "✓ Systemd service file exists"
        # Check if service is enabled
        if systemctl is-enabled --quiet sql_health_monitor.service; then
            log "✓ Systemd service is enabled"
        else
            warn "✗ Systemd service is not enabled"
        fi
        # Check if service is running
        if systemctl is-active --quiet sql_health_monitor.service; then
            log "✓ Systemd service is running"
        else
            warn "✗ Systemd service is not running"
        fi
    else
        warn "✗ Systemd service file does not exist"
    fi
}

# test file permissions
test_permissions() {
    log "Testing file permissions..."
    
    # Check script permissions
    if [ -x "${SCRIPT_DIR}/install-linux.sh" ]; then
        log "✓ Install script is executable"
    else
        warn "✗ Install script is not executable"
    fi
    
    if [ -x "${SCRIPT_DIR}/run-collector.sh" ]; then
        log "✓ Run collector script is executable"
    else
        warn "✗ Run collector script is not executable"
    fi
    
    # Check configuration file permissions
    if [ -r "${CONFIG_FILE}" ]; then
        log "✓ Configuration file is readable"
    else
        warn "✗ Configuration file is not readable"
    fi
}

# test log files
test_logs() {
    log "Testing log files..."
    
    local log_files=("/var/log/sql_health_monitor_collect.log" "/var/log/sql_health_monitor_alerts.log" "/var/log/sql_health_monitor_daily.log" "/var/log/sql_health_monitor_weekly.log" "/var/log/sql_health_monitor_maintenance.log")
    
    for log_file in "${log_files[@]}"; do
        if [ -f "$log_file" ]; then
            log "✓ Log file exists: $log_file"
            # Check if log file has recent entries
            if [ -s "$log_file" ]; then
                log "✓ Log file has content"
            else
                warn "✗ Log file is empty"
            fi
        else
            warn "✗ Log file does not exist: $log_file"
        fi
    done
}

# generate validation report
generate_report() {
    log "Generating validation report..."
    
    local report_file="${SCRIPT_DIR}/validation-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$report_file" << EOF
SQL Health Monitor - Linux Validation Report
===========================================
Generated: $(date)
Server: ${SERVER_HOST}:${SERVER_PORT}
Database: ${DATABASE_NAME}

Validation Results:
==================

Database Connectivity: $(test_connectivity && echo "PASS" || echo "FAIL")
Database Existence: $(test_database && echo "PASS" || echo "FAIL")
Schema and Tables: $(test_schema && echo "PASS" || echo "FAIL")
Stored Procedures: $(test_procedures && echo "PASS" || echo "FAIL")
Collectors: $(test_collectors && echo "PASS" || echo "FAIL")
Alert Engine: $(test_alerts && echo "PASS" || echo "FAIL")
Data Collection: $(test_data_collection && echo "PASS" || echo "FAIL")
Alerts Configuration: $(test_alerts_config && echo "PASS" || echo "FAIL")
Cron Jobs: $(test_cron_jobs && echo "PASS" || echo "FAIL")
Systemd Service: $(test_systemd_service && echo "PASS" || echo "FAIL")
File Permissions: $(test_permissions && echo "PASS" || echo "FAIL")
Log Files: $(test_logs && echo "PASS" || echo "FAIL")

Recommendations:
================
EOF
    
    # Add recommendations based on test results
    if ! test_connectivity; then
        echo "- Check SQL Server connectivity and credentials" >> "$report_file"
    fi
    
    if ! test_database; then
        echo "- Run installation script to create database" >> "$report_file"
    fi
    
    if ! test_schema; then
        echo "- Run schema installation script" >> "$report_file"
    fi
    
    if ! test_collectors; then
        echo "- Check collector procedures and permissions" >> "$report_file"
    fi
    
    if ! test_cron_jobs; then
        echo "- Setup cron jobs manually" >> "$report_file"
    fi
    
    if ! test_systemd_service; then
        echo "- Setup systemd service manually" >> "$report_file"
    fi
    
    log "✓ Validation report generated: $report_file"
}

# main validation function
main() {
    echo "SQL Health Monitor - Linux Validation"
    echo "===================================="
    echo "Server: ${SERVER_HOST}:${SERVER_PORT}"
    echo "Database: ${DATABASE_NAME}"
    echo ""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
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
            --help|-h)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --server HOST     SQL Server host (default: localhost)"
                echo "  --port PORT       SQL Server port (default: 1433)"
                echo "  --database DB     Database name (default: SQLHealthMonitor)"
                echo "  --user USER       Username (default: sa)"
                echo "  --password PWD    Password"
                echo "  --help           Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0 --server my-sql --user sa --password mypass"
                echo "  $0 --database MyMonitorDB"
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Check if password is provided
    if [ -z "$PASSWORD" ]; then
        error "Password is required for validation"
        echo "Use --password option to provide password"
        exit 1
    fi
    
    # Run all tests
    echo "Starting validation..."
    echo ""
    
    local tests=(
        "test_connectivity"
        "test_database"
        "test_schema"
        "test_procedures"
        "test_collectors"
        "test_alerts"
        "test_data_collection"
        "test_alerts_config"
        "test_cron_jobs"
        "test_systemd_service"
        "test_permissions"
        "test_logs"
    )
    
    local passed=0
    local failed=0
    
    for test in "${tests[@]}"; do
        if $test; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
        fi
        echo ""
    done
    
    # Generate summary
    echo "Validation Summary:"
    echo "=================="
    echo "Tests Passed: $passed"
    echo "Tests Failed: $failed"
    echo "Total Tests: $((passed + failed))"
    
    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        generate_report
        exit 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        generate_report
        exit 1
    fi
}

# Run main function
main "$@"