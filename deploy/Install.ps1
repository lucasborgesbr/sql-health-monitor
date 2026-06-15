#Requires -Version 5.1
<#
.SYNOPSIS
    Deploys SQL Health Monitor to a SQL Server instance.

.DESCRIPTION
    Runs the T-SQL install scripts in order using sqlcmd.
    All monitoring logic, scheduling, and email delivery run entirely inside SQL Server.

.PARAMETER ServerInstance
    SQL Server instance (e.g. "localhost", "SERVER\INSTANCE", "SERVER,1433").

.PARAMETER Database
    Target database name. Default: SQLHealthMonitor.

.PARAMETER SqlAuth
    Switch: use SQL authentication instead of Windows authentication.

.PARAMETER Login
    SQL login (only used when -SqlAuth is specified).

.PARAMETER Password
    SQL password (only used when -SqlAuth is specified).

.EXAMPLE
    # Windows auth
    .\Install.ps1 -ServerInstance "SQLSERVER01"

    # SQL auth
    .\Install.ps1 -ServerInstance "SQLSERVER01" -SqlAuth -Login "sa" -Password "P@ssw0rd"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ServerInstance,

    [string]$Database = "SQLHealthMonitor",

    [switch]$SqlAuth,

    [string]$Login,

    [string]$Password
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---- locate sqlcmd ----
$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
if (-not $sqlcmd) {
    Write-Error "sqlcmd not found. Install SQL Server Command Line Utilities: https://aka.ms/sqlcmdinstall"
    exit 1
}

# ---- build common sqlcmd args ----
$authArgs = if ($SqlAuth) { @("-U", $Login, "-P", $Password) } else { @("-E") }
$baseArgs  = @("-S", $ServerInstance) + $authArgs + @("-b", "-V", "1")

# Scripts to run in order — all paths relative to this file's directory
$repoRoot = Split-Path $PSScriptRoot -Parent
$scripts  = @(
    "install\00-create-schema.sql",
    "install\01-create-collectors.sql",
    "install\02-create-reports.sql",
    "install\03-create-alerts.sql",
    "install\04-create-jobs.sql",
    "install\05-configure.sql",
    "install\06-alert-history.sql",
    "install\07-baselines.sql",
    "install\08-extended-schema.sql",
    "install\09-uptime-tracker.sql",
    "collectors\collect_cpu.sql",
    "collectors\collect_memory.sql",
    "collectors\collect_disk.sql",
    "collectors\collect_waits.sql",
    "collectors\collect_blocking.sql",
    "collectors\collect_deadlocks.sql",
    "collectors\collect_ag_health.sql",
    "collectors\collect_cdc_health.sql",
    "collectors\collect_top_queries.sql",
    "collectors\collect_index_health.sql",
    "collectors\collect_backup_status.sql",
    "collectors\collect_job_history.sql",
    "collectors\collect_tempdb.sql",
    "collectors\collect_log_growth.sql",
    "collectors\collect_database_growth.sql",
    "collectors\collect_errorlog.sql",
    "collectors\collect_uptime_tracker.sql",
    "reports\html_builder_daily.sql",
    "reports\html_builder_weekly.sql",
    "reports\daily_health_check.sql",
    "reports\weekly_deep_dive.sql",
    "reports\enhanced_analytics.sql",
    "reports\recommendations_engine.sql",
    "alerts\alert_engine.sql",
    "alerts\alert_actions.sql",
    "baselines\capture_baseline.sql",
    "baselines\detect_anomalies.sql",
    "maintenance\purge_old_data.sql",
    "views\vw_CurrentHealth.sql",
    "views\vw_UptimeTracker.sql"
)

Write-Host ""
Write-Host "SQL Health Monitor - Deployment" -ForegroundColor Cyan
Write-Host "  Server  : $ServerInstance"
Write-Host "  Database: $Database"
Write-Host "  Auth    : $(if ($SqlAuth) { 'SQL (' + $Login + ')' } else { 'Windows' })"
Write-Host ""

$total   = $scripts.Count
$current = 0
$errors  = 0

foreach ($rel in $scripts) {
    $current++
    $path = Join-Path $repoRoot $rel

    if (-not (Test-Path $path)) {
        Write-Warning "  [$current/$total] SKIP (not found): $rel"
        continue
    }

    Write-Host "  [$current/$total] $rel" -NoNewline

    $cmdArgs = $baseArgs + @("-d", $Database, "-i", $path)
    $output  = & sqlcmd @cmdArgs 2>&1
    $rc      = $LASTEXITCODE

    if ($rc -ne 0) {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host ($output | Out-String) -ForegroundColor Red
        $errors++
    } else {
        Write-Host " OK" -ForegroundColor Green
    }
}

Write-Host ""
if ($errors -eq 0) {
    Write-Host "Deployment complete. $total scripts executed, 0 errors." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Configure Database Mail in SQL Server (if not already done)"
    Write-Host "  2. Update Email.ProfileName and Email.Recipients in [SQLHealthMonitor].[monitor].[Settings]"
    Write-Host "  3. SQL Agent Jobs are already scheduled. Verify in SSMS > SQL Server Agent > Jobs."
    Write-Host "  4. Test: EXEC [SQLHealthMonitor].[monitor].[usp_RunReport] @ReportType='Daily', @DebugMode=1"
} else {
    Write-Host "Deployment finished with $errors error(s). Review output above." -ForegroundColor Red
    exit 1
}
