<#
.SYNOPSIS
    Validates SQL Health Monitor installation on a SQL Server instance.

.DESCRIPTION
    Checks that all required objects exist: schema, tables, procedures,
    SQL Agent jobs, and Database Mail profile.

.PARAMETER ServerInstance
    SQL Server instance to validate.

.PARAMETER Credential
    SQL credential. If omitted, uses Windows Authentication.

.PARAMETER DatabaseName
    Target database. Default: SQLHealthMonitor

.EXAMPLE
    .\Test-Installation.ps1 -ServerInstance "MyServer"
    .\Test-Installation.ps1 -ServerInstance "MyServer\Instance" -Credential (Get-Credential)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerInstance,

    [Parameter()]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter()]
    [string]$DatabaseName = "SQLHealthMonitor"
)

$ErrorActionPreference = "Continue"
$totalChecks = 0
$passedChecks = 0
$failedChecks = 0
$warnings = 0

function Test-SqlObject {
    param(
        [string]$Query,
        [string]$Description,
        [string]$Database = $DatabaseName,
        [switch]$IsWarning
    )

    $script:totalChecks++
    try {
        $params = @{
            ServerInstance = $ServerInstance
            Database       = $Database
            Query          = $Query
            ErrorAction    = "Stop"
            QueryTimeout   = 10
        }
        if ($Credential) { $params.Credential = $Credential }

        $result = Invoke-Sqlcmd @params
        if ($result -and $result.Exists -eq 1) {
            Write-Host "  ✓ $Description" -ForegroundColor Green
            $script:passedChecks++
            return $true
        }
        else {
            if ($IsWarning) {
                Write-Host "  ⚠ $Description (optional)" -ForegroundColor Yellow
                $script:warnings++
            }
            else {
                Write-Host "  ✗ $Description" -ForegroundColor Red
                $script:failedChecks++
            }
            return $false
        }
    }
    catch {
        Write-Host "  ✗ $Description - Error: $_" -ForegroundColor Red
        $script:failedChecks++
        return $false
    }
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " SQL Health Monitor - Installation Validator" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Server: $ServerInstance"
Write-Host "Database: $DatabaseName"
Write-Host ""

# ─────────────────────────────────────────
# 1. Database & Schema
# ─────────────────────────────────────────
Write-Host "── Database & Schema ──" -ForegroundColor White

Test-SqlObject -Database "master" `
    -Query "SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM sys.databases WHERE name = '$DatabaseName') THEN 1 ELSE 0 END AS BIT) AS Exists" `
    -Description "Database [$DatabaseName] exists" | Out-Null

Test-SqlObject `
    -Query "SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'monitor') THEN 1 ELSE 0 END AS BIT) AS Exists" `
    -Description "Schema [monitor] exists" | Out-Null

# ─────────────────────────────────────────
# 2. Tables
# ─────────────────────────────────────────
Write-Host ""
Write-Host "── Tables ──" -ForegroundColor White

$tables = @(
    "Settings", "Languages", "Thresholds",
    "CpuHistory", "MemoryHistory", "DiskHistory", "WaitStatsHistory",
    "BlockingHistory", "AgHealthHistory", "CdcHealthHistory",
    "TopQueriesHistory", "IndexHealthHistory", "BackupHistory",
    "JobHistory", "TempDbHistory", "FileGrowthHistory", "ErrorLogHistory",
    "AlertHistory", "ReportHistory", "AlertCooldown", "PerformanceBaselines"
)

foreach ($table in $tables) {
    Test-SqlObject `
        -Query "SELECT CAST(CASE WHEN OBJECT_ID('monitor.$table', 'U') IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS Exists" `
        -Description "Table [monitor].[$table]" | Out-Null
}

# ─────────────────────────────────────────
# 3. Procedures
# ─────────────────────────────────────────
Write-Host ""
Write-Host "── Procedures ──" -ForegroundColor White

$procedures = @(
    "usp_Collect_CPU", "usp_Collect_Memory", "usp_Collect_Disk",
    "usp_Collect_Waits", "usp_Collect_Blocking", "usp_Collect_AG_Health",
    "usp_Collect_CDC_Health", "usp_Collect_TopQueries", "usp_Collect_IndexHealth",
    "usp_Collect_BackupStatus", "usp_Collect_JobHistory", "usp_Collect_TempDB",
    "usp_Collect_DatabaseGrowth", "usp_Collect_ErrorLog",
    "usp_RunAllCollectors", "usp_RunReport",
    "usp_Report_DailyHealth", "usp_Report_WeeklyDeepDive",
    "usp_AlertEngine_Check", "usp_RunAlertEngine",
    "usp_AlertAction_Execute",
    "usp_Maintenance_PurgeOldData", "usp_Maintenance_UpdateBaselines"
)

foreach ($proc in $procedures) {
    Test-SqlObject `
        -Query "SELECT CAST(CASE WHEN OBJECT_ID('monitor.$proc', 'P') IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS Exists" `
        -Description "Procedure [monitor].[$proc]" | Out-Null
}

# ─────────────────────────────────────────
# 4. SQL Agent Jobs
# ─────────────────────────────────────────
Write-Host ""
Write-Host "── SQL Agent Jobs ──" -ForegroundColor White

$jobs = @(
    "SQL Health Monitor - Collectors",
    "SQL Health Monitor - Alert Engine",
    "SQL Health Monitor - Daily Report",
    "SQL Health Monitor - Weekly Report",
    "SQL Health Monitor - Purge Old Data",
    "SQL Health Monitor - Update Baselines"
)

foreach ($job in $jobs) {
    Test-SqlObject -Database "msdb" `
        -Query "SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = '$job') THEN 1 ELSE 0 END AS BIT) AS Exists" `
        -Description "Job: $job" | Out-Null
}

# ─────────────────────────────────────────
# 5. Database Mail Profile
# ─────────────────────────────────────────
Write-Host ""
Write-Host "── Database Mail ──" -ForegroundColor White

$mailProfile = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $DatabaseName `
    -Query "SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'Email' AND SettingName = 'ProfileName'" `
    -ErrorAction SilentlyContinue

if ($mailProfile) {
    $profileName = $mailProfile.SettingValue
    Test-SqlObject -Database "msdb" -IsWarning `
        -Query "SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM msdb.dbo.sysmail_profile WHERE name = '$profileName') THEN 1 ELSE 0 END AS BIT) AS Exists" `
        -Description "Mail Profile: $profileName" | Out-Null
}

# ─────────────────────────────────────────
# 6. Configuration Data
# ─────────────────────────────────────────
Write-Host ""
Write-Host "── Configuration ──" -ForegroundColor White

Test-SqlObject `
    -Query "SELECT CAST(CASE WHEN (SELECT COUNT(*) FROM [monitor].[Settings]) > 0 THEN 1 ELSE 0 END AS BIT) AS Exists" `
    -Description "Settings populated" | Out-Null

Test-SqlObject `
    -Query "SELECT CAST(CASE WHEN (SELECT COUNT(*) FROM [monitor].[Thresholds]) > 0 THEN 1 ELSE 0 END AS BIT) AS Exists" `
    -Description "Thresholds populated" | Out-Null

Test-SqlObject `
    -Query "SELECT CAST(CASE WHEN (SELECT COUNT(*) FROM [monitor].[Languages]) > 0 THEN 1 ELSE 0 END AS BIT) AS Exists" `
    -Description "Language strings populated" | Out-Null

# ─────────────────────────────────────────
# Summary
# ─────────────────────────────────────────
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Validation Summary" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Total checks:  $totalChecks"
Write-Host "  Passed:        $passedChecks" -ForegroundColor Green
Write-Host "  Failed:        $failedChecks" -ForegroundColor $(if ($failedChecks -eq 0) { "Green" } else { "Red" })
Write-Host "  Warnings:      $warnings" -ForegroundColor $(if ($warnings -eq 0) { "Green" } else { "Yellow" })
Write-Host ""

if ($failedChecks -eq 0) {
    Write-Host "  ✓ Installation is COMPLETE" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "  ✗ Installation has ISSUES - review failed checks above" -ForegroundColor Red
    exit 1
}
