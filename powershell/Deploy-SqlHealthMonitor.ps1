<#
.SYNOPSIS
    Deploys SQL Health Monitor to one or more SQL Server instances.

.DESCRIPTION
    Reads a server list (or accepts pipeline input) and deploys all SQL scripts
    in the correct order. Supports credential passing and validation.

.PARAMETER ServerList
    Path to a text file with one server name per line, or comma-separated server names.

.PARAMETER Credential
    SQL credential for authentication. If omitted, uses Windows Authentication.

.PARAMETER DatabaseName
    Target database name. Default: SQLHealthMonitor

.PARAMETER CreateDatabase
    If specified, creates the SQLHealthMonitor database if it doesn't exist.

.PARAMETER ScriptPath
    Path to the sql-health-monitor folder. Default: script's parent directory.

.PARAMETER WhatIf
    Shows what would be deployed without executing.

.EXAMPLE
    .\Deploy-SqlHealthMonitor.ps1 -ServerList "Server1,Server2"
    .\Deploy-SqlHealthMonitor.ps1 -ServerList .\servers.txt -Credential (Get-Credential)
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [string]$ServerList,

    [Parameter()]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter()]
    [string]$DatabaseName = "SQLHealthMonitor",

    [Parameter()]
    [switch]$CreateDatabase,

    [Parameter()]
    [string]$ScriptPath
)

begin {
    $ErrorActionPreference = "Stop"

    # Resolve script path
    if (-not $ScriptPath) {
        $ScriptPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        if (-not $ScriptPath) { $ScriptPath = Split-Path -Parent $PSCommandPath }
    }

    # Deployment order
    $DeploymentOrder = @(
        @{ Path = "install/00-create-schema.sql";      Description = "Schema & Tables" },
        @{ Path = "install/05-configure.sql";          Description = "Default Configuration" },
        @{ Path = "collectors/collect_cpu.sql";         Description = "CPU Collector" },
        @{ Path = "collectors/collect_memory.sql";      Description = "Memory Collector" },
        @{ Path = "collectors/collect_disk.sql";        Description = "Disk Collector" },
        @{ Path = "collectors/collect_waits.sql";       Description = "Wait Stats Collector" },
        @{ Path = "collectors/collect_blocking.sql";    Description = "Blocking Collector" },
        @{ Path = "collectors/collect_ag_health.sql";   Description = "AG Health Collector" },
        @{ Path = "collectors/collect_cdc_health.sql";  Description = "CDC Health Collector" },
        @{ Path = "collectors/collect_top_queries.sql"; Description = "Top Queries Collector" },
        @{ Path = "collectors/collect_index_health.sql";Description = "Index Health Collector" },
        @{ Path = "collectors/collect_backup_status.sql";Description = "Backup Status Collector" },
        @{ Path = "collectors/collect_job_history.sql"; Description = "Job History Collector" },
        @{ Path = "collectors/collect_tempdb.sql";      Description = "TempDB Collector" },
        @{ Path = "collectors/collect_log_growth.sql";  Description = "File Growth Collector" },
        @{ Path = "collectors/collect_errorlog.sql";    Description = "Error Log Collector" },
        @{ Path = "install/01-create-collectors.sql";   Description = "Master Collector Procedure" },
        @{ Path = "install/02-create-reports.sql";      Description = "Report Runner" },
        @{ Path = "reports/daily_health_check.sql";     Description = "Daily Report" },
        @{ Path = "reports/weekly_deep_dive.sql";       Description = "Weekly Deep Dive Report" },
        @{ Path = "alerts/alert_engine.sql";            Description = "Alert Engine" },
        @{ Path = "alerts/alert_actions.sql";           Description = "Alert Actions" },
        @{ Path = "install/03-create-alerts.sql";       Description = "Alert Registration" },
        @{ Path = "maintenance/purge_old_data.sql";     Description = "Purge Old Data" },
        @{ Path = "maintenance/update_baselines.sql";   Description = "Update Baselines" },
        @{ Path = "install/04-create-jobs.sql";         Description = "SQL Agent Jobs" }
    )

    # Validate all scripts exist
    foreach ($script in $DeploymentOrder) {
        $fullPath = Join-Path $ScriptPath $script.Path
        if (-not (Test-Path $fullPath)) {
            Write-Warning "Script not found: $fullPath"
        }
    }

    function Invoke-SqlScript {
        param(
            [string]$ServerInstance,
            [string]$Database,
            [string]$FilePath,
            [System.Management.Automation.PSCredential]$SqlCredential
        )

        $params = @{
            ServerInstance = $ServerInstance
            Database       = $Database
            InputFile      = $FilePath
            ErrorAction    = "Stop"
            QueryTimeout   = 120
        }

        if ($SqlCredential) {
            $params.Credential = $SqlCredential
        }

        Invoke-Sqlcmd @params
    }

    function Test-SqlConnection {
        param(
            [string]$ServerInstance,
            [System.Management.Automation.PSCredential]$SqlCredential
        )

        try {
            $params = @{
                ServerInstance = $ServerInstance
                Query          = "SELECT @@VERSION AS Version, @@SERVERNAME AS ServerName"
                ErrorAction    = "Stop"
                QueryTimeout   = 10
            }
            if ($SqlCredential) { $params.Credential = $SqlCredential }
            
            $result = Invoke-Sqlcmd @params
            return $result
        }
        catch {
            return $null
        }
    }

    # Parse server list
    $Servers = @()
    if (Test-Path $ServerList -ErrorAction SilentlyContinue) {
        $Servers = Get-Content $ServerList | Where-Object { $_ -and $_ -notmatch '^\s*#' }
    }
    else {
        $Servers = $ServerList -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host " SQL Health Monitor - Deployment" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "Servers: $($Servers.Count)"
    Write-Host "Database: $DatabaseName"
    Write-Host "Scripts: $($DeploymentOrder.Count)"
    Write-Host ""
}

process {
    foreach ($Server in $Servers) {
        Write-Host "─────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "Deploying to: $Server" -ForegroundColor Yellow
        Write-Host ""

        # Test connection
        $connTest = Test-SqlConnection -ServerInstance $Server -SqlCredential $Credential
        if (-not $connTest) {
            Write-Error "Cannot connect to $Server. Skipping."
            continue
        }
        Write-Host "  ✓ Connected: $($connTest.ServerName)" -ForegroundColor Green

        # Create database if needed
        if ($CreateDatabase) {
            if ($PSCmdlet.ShouldProcess($Server, "Create database $DatabaseName")) {
                try {
                    $createDbSql = @"
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = '$DatabaseName')
BEGIN
    CREATE DATABASE [$DatabaseName];
    ALTER DATABASE [$DatabaseName] SET RECOVERY SIMPLE;
END
"@
                    $params = @{ ServerInstance = $Server; Query = $createDbSql; ErrorAction = "Stop" }
                    if ($Credential) { $params.Credential = $Credential }
                    Invoke-Sqlcmd @params
                    Write-Host "  ✓ Database ensured" -ForegroundColor Green
                }
                catch {
                    Write-Error "  ✗ Failed to create database: $_"
                    continue
                }
            }
        }

        # Deploy scripts in order
        $successCount = 0
        $failCount = 0

        foreach ($script in $DeploymentOrder) {
            $fullPath = Join-Path $ScriptPath $script.Path
            if (-not (Test-Path $fullPath)) {
                Write-Warning "  ⚠ Skipping (not found): $($script.Path)"
                continue
            }

            if ($PSCmdlet.ShouldProcess($Server, "Deploy $($script.Description)")) {
                try {
                    Invoke-SqlScript -ServerInstance $Server -Database $DatabaseName `
                        -FilePath $fullPath -SqlCredential $Credential
                    Write-Host "  ✓ $($script.Description)" -ForegroundColor Green
                    $successCount++
                }
                catch {
                    Write-Host "  ✗ $($script.Description): $_" -ForegroundColor Red
                    $failCount++
                }
            }
        }

        Write-Host ""
        Write-Host "  Results: $successCount succeeded, $failCount failed" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })
    }
}

end {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host " Deployment Complete" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
}
