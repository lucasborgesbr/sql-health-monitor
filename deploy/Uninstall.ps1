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
    [Parameter(Mandatory)]
    [string]$ServerInstance,

    [switch]$SqlAuth,
    [string]$Login,
    [string]$Password
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
if (-not $sqlcmd) {
    Write-Error "sqlcmd not found. Install SQL Server Command Line Utilities."
    exit 1
}

Write-Host ""
Write-Host "SQL Health Monitor - Uninstall" -ForegroundColor Yellow
Write-Host "  Server: $ServerInstance"
Write-Host ""
Write-Warning "This will permanently delete all SQL Agent Jobs and the SQLHealthMonitor database."
$confirm = Read-Host "Type YES to continue"
if ($confirm -ne 'YES') { Write-Host "Cancelled."; exit 0 }

$authArgs = if ($SqlAuth) { @("-U", $Login, "-P", $Password) } elseif ($env:SQLCMDUSER) { @() } else { @("-E") }
$script   = Join-Path $PSScriptRoot "..\install\Uninstall.sql"

$output = & sqlcmd -S $ServerInstance @authArgs -d master -b -V 1 -C -i $script 2>&1
$rc     = $LASTEXITCODE

Write-Host ($output | Out-String)

if ($rc -ne 0) {
    Write-Host "Uninstall failed (exit $rc)." -ForegroundColor Red
    exit 1
}
Write-Host "Uninstall complete." -ForegroundColor Green
