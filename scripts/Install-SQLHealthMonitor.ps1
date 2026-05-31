<#
.SYNOPSIS
    SQL Health Monitor - Complete Installation Wrapper
    Orchestrates the complete installation process with a single command.

.DESCRIPTION
    This script provides a simplified interface for installing the SQL Health Monitor
    by coordinating all the individual installation scripts in the correct sequence.

.PARAMETER ServerInstance
    Target SQL Server instance (e.g., 'localhost', 'SQL-PRD-01')

.PARAMETER Database
    Database name. Default: 'SQLHealthMonitor'

.PARAMETER ConfigFile
    Path to JSON configuration file with all settings

.PARAMETER EmailProfile
    Database Mail profile name for email notifications

.PARAMETER EmailRecipients
    Email recipients for alerts and reports (comma-separated string or array)

.PARAMETER Language
    Report language: 'EN' or 'PTBR'. Default: 'EN'

.PARAMETER ScheduleType
    Collection schedule: 'Hourly' or 'Daily'. Default: 'Hourly'

.PARAMETER AuthMethod
    Authentication method: 'Windows' (default) or 'Sql'

.PARAMETER SqlCredential
    SQL credential object for SQL authentication

.PARAMETER Force
    Overwrite existing database without prompting

.PARAMETER SkipJobs
    Skip SQL Agent job creation

.PARAMETER SkipValidation
    Skip validation steps

.PARAMETER WhatIf
    Preview installation steps without executing

.EXAMPLE
    # Complete installation with minimal parameters
    .\Install-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -Database 'DBA_Monitor'

.EXAMPLE
    # Installation with configuration file
    .\Install-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -Database 'DBA_Monitor' -ConfigFile '.\config\example-config.json'

.EXAMPLE
    # Installation with custom parameters
    .\Install-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -Database 'DBA_Monitor' -EmailProfile 'DBA Mail' -EmailRecipients 'dba@company.com' -Language 'EN'

.EXAMPLE
    # SQL authentication
    $cred = Get-Credential
    .\Install-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -Database 'DBA_Monitor' -AuthMethod 'Sql' -SqlCredential $cred

.NOTES
    Author: Lucas Allan Borges
    Version: 1.0.0
    Generic version - no hardcoded environment dependencies
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$ServerInstance,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Database = 'SQLHealthMonitor',

    [Parameter()]
    [ValidateScript({ Test-Path $_ })]
    [string]$ConfigFile,

    [Parameter()]
    [string]$EmailProfile,

    [Parameter()]
    [string[]]$EmailRecipients,

    [Parameter()]
    [ValidateSet('EN', 'PTBR')]
    [string]$Language = 'EN',

    [Parameter()]
    [ValidateSet('Hourly', 'Daily')]
    [string]$ScheduleType = 'Hourly',

    [Parameter()]
    [ValidateSet('Windows', 'Sql')]
    [string]$AuthMethod = 'Windows',

    [Parameter()]
    [System.Management.Automation.PSCredential]$SqlCredential,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$SkipJobs,

    [Parameter()]
    [switch]$SkipValidation,

    [Parameter()]
    [switch]$WhatIf
)

begin {
    $scriptStart = Get-Date
    $modulePath = $PSScriptRoot
    $scriptsPath = Join-Path $modulePath 'scripts'
    
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  SQL Health Monitor - Complete Installation" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Server:      $ServerInstance"
    Write-Host "  Database:    $Database"
    Write-Host "  Language:    $Language"
    Write-Host "  Schedule:    $ScheduleType"
    Write-Host "  Auth Method: $AuthMethod"
    Write-Host ""
    
    # Load configuration if provided
    $config = $null
    if ($ConfigFile) {
        Write-Host "Loading configuration from: $ConfigFile" -ForegroundColor Yellow
        $config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
        
        # Override with command line parameters
        if ($EmailProfile) { $config.Email.ProfileName = $EmailProfile }
        if ($EmailRecipients) { 
            $config.Email.Recipients = $EmailRecipients
            $config.Alerts.Recipients = $EmailRecipients
        }
        if ($Language) { $config.Language = $Language }
        if ($ScheduleType) { $config.Scheduling.CollectionInterval = $ScheduleType }
        if ($Database) { $config.Connection.Database = $Database }
    }
}

process {
    try {
        # --- Step 1: Database Setup ---
        if (-not $SkipValidation -or $WhatIf) {
            Write-Host "[1/4] Database Setup..." -ForegroundColor Yellow
            
            if ($PSCmdlet.ShouldProcess($Database, "Setup database")) {
                $setupParams = @{
                    ServerInstance = $ServerInstance
                    Database = $Database
                    AuthMethod = $AuthMethod
                    SqlCredential = $SqlCredential
                    Force = $Force
                }
                
                if ($WhatIf) {
                    Write-Host "  WhatIf: Would execute Setup-SQLHealthMonitorDatabase.ps1 with parameters:" -ForegroundColor Gray
                    Write-Host "    ServerInstance: $ServerInstance" -ForegroundColor Gray
                    Write-Host "    Database: $Database" -ForegroundColor Gray
                    Write-Host "    AuthMethod: $AuthMethod" -ForegroundColor Gray
                    Write-Host "    Force: $Force" -ForegroundColor Gray
                }
                else {
                    & "$scriptsPath\Setup-SQLHealthMonitorDatabase.ps1" @setupParams
                }
            }
        }

        # --- Step 2: Configuration ---
        if (-not $SkipValidation -or $WhatIf) {
            Write-Host "[2/4] Configuration..." -ForegroundColor Yellow
            
            if ($PSCmdlet.ShouldProcess($Database, "Configure system")) {
                $configParams = @{
                    ServerInstance = $ServerInstance
                    Database = $Database
                    AuthMethod = $AuthMethod
                    SqlCredential = $SqlCredential
                    Language = $Language
                }
                
                # Add email parameters if available
                if ($EmailProfile) { $configParams.EmailProfile = $EmailProfile }
                if ($EmailRecipients) { $configParams.EmailRecipients = $EmailRecipients }
                
                # Add custom thresholds from config file
                if ($config -and $config.Alerts.CustomThresholds) {
                    $configParams.CustomThresholds = $config.Alerts.CustomThresholds
                }
                
                if ($WhatIf) {
                    Write-Host "  WhatIf: Would execute Configure-SQLHealthMonitor.ps1 with parameters:" -ForegroundColor Gray
                    Write-Host "    ServerInstance: $ServerInstance" -ForegroundColor Gray
                    Write-Host "    Database: $Database" -ForegroundColor Gray
                    Write-Host "    Language: $Language" -ForegroundColor Gray
                    if ($EmailProfile) { Write-Host "    EmailProfile: $EmailProfile" -ForegroundColor Gray }
                    if ($EmailRecipients) { Write-Host "    EmailRecipients: $($EmailRecipients -join ', ')" -ForegroundColor Gray }
                }
                else {
                    & "$scriptsPath\Configure-SQLHealthMonitor.ps1" @configParams
                }
            }
        }

        # --- Step 3: Job Deployment ---
        if (-not $SkipJobs -and (-not $SkipValidation -or $WhatIf)) {
            Write-Host "[3/4] Job Deployment..." -ForegroundColor Yellow
            
            if ($PSCmdlet.ShouldProcess($ServerInstance, "Deploy jobs")) {
                $jobParams = @{
                    ServerInstance = $ServerInstance
                    Database = $Database
                    AuthMethod = $AuthMethod
                    SqlCredential = $SqlCredential
                    ScheduleType = $ScheduleType
                    Language = $Language
                }
                
                # Add email parameters if available
                if ($EmailProfile) { $jobParams.EmailProfile = $EmailProfile }
                
                if ($WhatIf) {
                    Write-Host "  WhatIf: Would execute Deploy-SQLHealthMonitorJobs.ps1 with parameters:" -ForegroundColor Gray
                    Write-Host "    ServerInstance: $ServerInstance" -ForegroundColor Gray
                    Write-Host "    Database: $Database" -ForegroundColor Gray
                    Write-Host "    ScheduleType: $ScheduleType" -ForegroundColor Gray
                    Write-Host "    Language: $Language" -ForegroundColor Gray
                    if ($EmailProfile) { Write-Host "    EmailProfile: $EmailProfile" -ForegroundColor Gray }
                }
                else {
                    & "$scriptsPath\Deploy-SQLHealthMonitorJobs.ps1" @jobParams
                }
            }
        }

        # --- Step 4: Validation ---
        if (-not $SkipValidation -or $WhatIf) {
            Write-Host "[4/4] Validation..." -ForegroundColor Yellow
            
            if ($PSCmdlet.ShouldProcess($Database, "Validate installation")) {
                $validationParams = @{
                    ServerInstance = $ServerInstance
                    Database = $Database
                    AuthMethod = $AuthMethod
                    SqlCredential = $SqlCredential
                }
                
                if ($WhatIf) {
                    Write-Host "  WhatIf: Would execute Validate-SQLHealthMonitorSetup.ps1 with parameters:" -ForegroundColor Gray
                    Write-Host "    ServerInstance: $ServerInstance" -ForegroundColor Gray
                    Write-Host "    Database: $Database" -ForegroundColor Gray
                }
                else {
                    & "$scriptsPath\Validate-SQLHealthMonitorSetup.ps1" @validationParams
                }
            }
        }

        # --- Installation Complete ---
        $duration = (Get-Date) - $scriptStart
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Green
        Write-Host "  Installation Complete!" -ForegroundColor Green
        Write-Host "============================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Server:      $ServerInstance"
    Write-Host "  Database:    $Database"
    Write-Host "  Duration:    $($duration.TotalSeconds.ToString('F1'))s"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Monitor SQL Agent jobs in SSMS"
    Write-Host "  2. Check email reports for confirmation"
    Write-Host "  3. Review initial health data"
    Write-Host "  4. Adjust thresholds as needed"
    Write-Host ""
    
    # Return installation summary for pipeline
    [PSCustomObject]@{
        ServerInstance = $ServerInstance
        Database = $Database
        Language = $Language
        ScheduleType = $ScheduleType
        EmailProfile = $EmailProfile
        EmailRecipients = $EmailRecipients
        Status = 'Completed'
        Duration = $duration
        ConfigFile = $ConfigFile
    }
}
catch {
    Write-Host ""
    Write-Host "INSTALLATION FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($_.ScriptStackTrace) {
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    }
    throw
}
}

end {
    # Clean up
    if ($config) {
        Remove-Variable config -ErrorAction SilentlyContinue
    }
}