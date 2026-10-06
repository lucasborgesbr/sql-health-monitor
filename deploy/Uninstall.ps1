#Requires -Version 5.1
<#
.SYNOPSIS
    Removes SQL Health Monitor: drops all SQL Agent Jobs and the SQLHealthMonitor database.

.DESCRIPTION
    WARNING: This is irreversible. All collected metrics, alert history, and configuration
    will be permanently deleted.

.PARAMETER ServerInstance
    SQL Server instance (e.g. "localhost", "SERVER\INSTANCE").

.PARAMETER SqlAuth
    Switch: use SQL authentication instead of Windows authentication.

.PARAMETER Login
    SQL login (only used when -SqlAuth is specified).

.PARAMETER Password
    SQL password (only used when -SqlAuth is specified).

.EXAMPLE
    .\Uninstall.ps1 -ServerInstance "SQLSERVER01"
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ServerInstance,
    [string]$Database       = "SQLHealthMonitor",

    [switch]$SqlAuth,
    [string]$Login,
    [string]$Password
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $ServerInstance) {
    if ($env:SQLCMDSERVER) { $ServerInstance = $env:SQLCMDSERVER }
    else { $ServerInstance = 'localhost,1433' }
}

if ($SqlAuth) {
    $env:SQLCMDSERVER   = $ServerInstance
    $env:SQLCMDUSER     = $Login
    $env:SQLCMDPASSWORD = $Password
} elseif (-not $env:SQLCMDUSER) {
    Write-Error @"
No SQL credentials available.

Set them once for the machine:
  setx SQLCMDSERVER   "localhost,1433"
  setx SQLCMDUSER     "sa"
  setx SQLCMDPASSWORD "<password>"

or pass -SqlAuth -Login <user> -Password <password>.
"@
    exit 1
}

$sqlcmd = (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
if (-not $sqlcmd) {
    Write-Error "sqlcmd not found. Install SQL Server Command Line Utilities."
    exit 1
}

$baseArgs = @('-S', $ServerInstance, '-b', '-V', '1', '-C', '-d', 'master')

# Say what is about to be destroyed, and which version. An operator should not
# have to guess whether they are pointed at the right server.
$installed = $null
try {
    $q = @"
IF DB_ID(N'$Database') IS NOT NULL
   AND OBJECT_ID('[monitor].[SchemaVersion]','U') IS NOT NULL
    SELECT [monitor].[fn_GetInstalledVersion]();
"@
    $v = & $sqlcmd @baseArgs -d $Database -h -1 -W -Q "SET NOCOUNT ON; $q" 2>&1
    if ($LASTEXITCODE -eq 0) {
        $installed = (@($v | ForEach-Object { $_.ToString().Trim() }) |
                      Where-Object { $_ -and $_ -ne 'NULL' } | Select-Object -First 1)
    }
} catch {
    $installed = $null
}

Write-Host ""
Write-Host "SQL Health Monitor - Uninstall" -ForegroundColor Yellow
Write-Host "  Server  : $ServerInstance"
Write-Host "  Database: $Database"
if ($installed) { Write-Host "  Version : $installed" }
Write-Host ""
Write-Warning "This permanently deletes all SQL Agent Jobs and the '$Database' database, including every collected metric and your configuration."
Write-Warning "To keep the data, run '\Install.ps1 -Mode Fresh -BackupPath <dir>' instead."
$confirm = Read-Host "Type YES to continue"
if ($confirm -ne 'YES') { Write-Host "Cancelled."; exit 0 }

$script = Join-Path $PSScriptRoot "..\install\Uninstall.sql"

$output = & $sqlcmd @baseArgs -v "DatabaseName=$Database" -i $script 2>&1
$rc     = $LASTEXITCODE

Write-Host ($output | Out-String)

if ($rc -ne 0) {
    Write-Host "Uninstall failed (exit $rc)." -ForegroundColor Red
    exit 1
}
Write-Host "Uninstall complete." -ForegroundColor Green
