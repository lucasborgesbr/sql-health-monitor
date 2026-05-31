<#
.SYNOPSIS
    SQL Health Monitor - Generic Configuration Script
    Configures alert thresholds, recipients, and parameters for any environment.

.DESCRIPTION
    This script configures the SQL Health Monitor with customizable settings
    for alerts, email recipients, thresholds, and monitoring parameters.
    It works with any environment without hardcoded values.

.PARAMETER ServerInstance
    Target SQL Server instance (e.g., 'localhost', 'SQL-PRD-01')

.PARAMETER Database
    Database name. Default: 'SQLHealthMonitor'

.PARAMETER AuthMethod
    Authentication method: 'Windows' (default) or 'Sql'

.PARAMETER SqlCredential
    SQL credential object for SQL authentication

.PARAMETER ConfigFile
    Path to JSON configuration file with all settings

.PARAMETER EmailProfile
    Database Mail profile name for email notifications

.PARAMETER EmailRecipients
    Email recipients for alerts and reports (comma-separated string or array)

.PARAMETER Language
    Report language: 'EN' or 'PTBR'. Default: 'EN'

.PARAMETER EnableAllCollectors
    Enable all monitoring collectors. Default: $true

.PARAMETER CustomThresholds
    Hashtable with custom threshold values

.PARAMETER RetentionSettings
    Hashtable with data retention settings

.EXAMPLE
    # Basic configuration
    .\Configure-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -EmailProfile 'DBA Mail' -EmailRecipients 'dba@company.com'

.EXAMPLE
    # Custom thresholds
    $thresholds = @{
        CPU_Warning = 80
        CPU_Critical = 95
        Disk_Warning = 85
        Disk_Critical = 95
        PLE_Warning = 300
        PLE_Critical = 100
    }
    .\Configure-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -CustomThresholds $thresholds

.EXAMPLE
    # Using configuration file
    .\Configure-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -ConfigFile '.\config\my-settings.json'

.EXAMPLE
    # Complete configuration with custom retention
    $retention = @{
        RawDataDays = 30
        DailySummaryDays = 90
        WeeklySummaryDays = 365
        AlertHistoryDays = 365
        AnomalyDays = 90
    }
    .\Configure-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -EmailRecipients 'dba@company.com,manager@company.com' -RetentionSettings $retention

.NOTES
    Author: Lucas Allan Borges
    Version: 1.0.0
    Generic version - no hardcoded environment dependencies
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$ServerInstance,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Database = 'SQLHealthMonitor',

    [Parameter()]
    [ValidateSet('Windows', 'Sql')]
    [string]$AuthMethod = 'Windows',

    [Parameter()]
    [System.Management.Automation.PSCredential]$SqlCredential,

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
    [bool]$EnableAllCollectors = $true,

    [Parameter()]
    [hashtable]$CustomThresholds,

    [Parameter()]
    [hashtable]$RetentionSettings
)

begin {
    $scriptStart = Get-Date
    $modulePath = $PSScriptRoot
    $configPath = Join-Path $modulePath 'config'
    
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  SQL Health Monitor - Configuration" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Server:    $ServerInstance"
    Write-Host "  Database:  $Database"
    Write-Host "  Language:  $Language"
    Write-Host ""
}

process {
    try {
        # --- Step 1: Connect to SQL Server ---
        Write-Host "[1/6] Connecting to SQL Server..." -ForegroundColor Yellow
        
        $sqlParams = @{
            SqlInstance = $ServerInstance
            Database = $Database
            ErrorAction = 'Stop'
        }
        
        if ($AuthMethod -eq 'Sql' -and $SqlCredential) {
            $sqlParams.SqlCredential = $SqlCredential
        }
        
        $sqlInstance = Connect-DbaInstance @sqlParams
        Write-Host "      Connected successfully to $ServerInstance" -ForegroundColor Green

        # --- Step 2: Load configuration ---
        Write-Host "[2/6] Loading configuration..." -ForegroundColor Yellow
        
        $config = @{
            Email = @{
                Method = 'DatabaseMail'
                Profile = $EmailProfile
                Recipients = @()
                CcRecipients = @()
                SubjectPrefix = '[SQL Health]'
            }
            Language = $Language
            Collectors = @{
                Enabled = @()
                Disabled = @()
                TopQueriesCount = 25
                IndexFragmentationThreshold = 30
                ErrorLogHoursBack = 24
            }
            Retention = @{
                DetailedDataDays = 90
                AggregatedDataDays = 365
                ReportHistoryDays = 180
                AlertHistoryDays = 365
                AnomalyDays = 90
            }
            Alerts = @{
                Enabled = $true
                CooldownMinutes = 60
                NotificationMethod = 'Email'
            }
        }
        
        # Load from config file if provided
        if ($ConfigFile) {
            $fileConfig = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
            if ($fileConfig.Email) { $config.Email += $fileConfig.Email }
            if ($fileConfig.Language) { $config.Language = $fileConfig.Language }
            if ($fileConfig.Collectors) { $config.Collectors += $fileConfig.Collectors }
            if ($fileConfig.Retention) { $config.Retention += $fileConfig.Retention }
            if ($fileConfig.Alerts) { $config.Alerts += $fileConfig.Alerts }
        }
        
        # Override with command line parameters
        if ($EmailRecipients) {
            $config.Email.Recipients = $EmailRecipients
        }
        if ($CustomThresholds) {
            $config.Thresholds = $CustomThresholds
        }
        if ($RetentionSettings) {
            $config.Retention += $RetentionSettings
        }
        
        Write-Host "      Configuration loaded successfully." -ForegroundColor Green

        # --- Step 3: Configure general settings ---
        Write-Host "[3/6] Configuring general settings..." -ForegroundColor Yellow
        if ($PSCmdlet.ShouldProcess($Database, "Configure general settings")) {
            $generalSettings = @"
-- General settings
DELETE FROM [monitor].[Settings] WHERE Category = 'General';
INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType) VALUES
('General', 'Language', '$($config.Language)', 'Report language: en or ptbr', 'string'),
('General', 'ServerName', @@SERVERNAME, 'Server identifier for reports', 'string'),
('General', 'MonitoringEnabled', '1', 'Master switch for all monitoring', 'bool'),
('General', 'ConfigProfile', 'CUSTOM', 'Configuration profile name', 'string'),
('General', 'LastConfigured', '$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))', 'Last configuration timestamp', 'string');
"@
            
            Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query $generalSettings
            Write-Host "      General settings configured." -ForegroundColor Green
        }

        # --- Step 4: Configure email settings ---
        Write-Host "[4/6] Configuring email settings..." -ForegroundColor Yellow
        if ($PSCmdlet.ShouldProcess($Database, "Configure email settings")) {
            $emailSettings = @"
-- Email settings
DELETE FROM [monitor].[Settings] WHERE Category = 'Email';
"@

            if ($config.Email.Recipients -and $config.Email.Profile) {
                $recipients = $config.Email.Recipients -join ', '
                $emailSettings += @"
INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType) VALUES
('Email', 'Recipients', '$recipients', 'Comma-separated email recipients', 'string'),
('Email', 'ProfileName', '$($config.Email.Profile)', 'Database Mail profile name', 'string'),
('Email', 'SubjectPrefix', '$($config.Email.SubjectPrefix)', 'Email subject prefix', 'string');
"@
            }
            elseif ($config.Email.Recipients) {
                # Fallback to SMTP if no profile specified
                $recipients = $config.Email.Recipients -join ', '
                $emailSettings += @"
INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType) VALUES
('Email', 'Recipients', '$recipients', 'Comma-separated email recipients', 'string'),
('Email', 'Method', 'SMTP', 'Email method: DatabaseMail or SMTP', 'string'),
('Email', 'SubjectPrefix', '$($config.Email.SubjectPrefix)', 'Email subject prefix', 'string');
"@
            }
            
            Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query $emailSettings
            Write-Host "      Email settings configured." -ForegroundColor Green
        }

        # --- Step 5: Configure collectors ---
        Write-Host "[5/6] Configuring collectors..." -ForegroundColor Yellow
        if ($PSCmdlet.ShouldProcess($Database, "Configure collectors")) {
            $collectorSettings = @"
-- Collector settings
DELETE FROM [monitor].[Settings] WHERE Category = 'Collectors';
"@

            if ($EnableAllCollectors) {
                $collectors = @('CPU', 'Memory', 'Disk', 'WaitStats', 'Blocking', 'Deadlocks', 
                              'AvailabilityGroups', 'CDC', 'TopQueries', 'IndexHealth', 
                              'BackupStatus', 'Jobs', 'ErrorLog', 'TempDB', 'LogGrowth', 'DatabaseGrowth')
                $enabledList = $collectors -join "','"
                $collectorSettings += @"
INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType) VALUES
('Collectors', 'Enabled', '$enabledList', 'Enabled collectors list', 'string'),
('Collectors', 'TopQueriesCount', '$($config.Collectors.TopQueriesCount)', 'Number of top queries to collect', 'int'),
('Collectors', 'IndexFragmentationThreshold', '$($config.Collectors.IndexFragmentationThreshold)', 'Index fragmentation threshold (%)', 'int'),
('Collectors', 'ErrorLogHoursBack', '$($config.Collectors.ErrorLogHoursBack)', 'Hours back to check error log', 'int');
"@
            }
            else {
                $collectorSettings += @"
INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType) VALUES
('Collectors', 'Enabled', '', 'Enabled collectors list', 'string'),
('Collectors', 'TopQueriesCount', '$($config.Collectors.TopQueriesCount)', 'Number of top queries to collect', 'int'),
('Collectors', 'IndexFragmentationThreshold', '$($config.Collectors.IndexFragmentationThreshold)', 'Index fragmentation threshold (%)', 'int'),
('Collectors', 'ErrorLogHoursBack', '$($config.Collectors.ErrorLogHoursBack)', 'Hours back to check error log', 'int');
"@
            }
            
            Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query $collectorSettings
            Write-Host "      Collectors configured." -ForegroundColor Green
        }

        # --- Step 6: Configure retention and alerts ---
        Write-Host "[6/6] Configuring retention and alerts..." -ForegroundColor Yellow
        if ($PSCmdlet.ShouldProcess($Database, "Configure retention and alerts")) {
            $retentionAlertSettings = @"
-- Retention settings
DELETE FROM [monitor].[Settings] WHERE Category = 'Retention';
INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType) VALUES
('Retention', 'RawDataRetentionDays', '$($config.Retention.DetailedDataDays)', 'Raw data retention in days', 'int'),
('Retention', 'DailySummaryRetentionDays', '$($config.Retention.AggregatedDataDays)', 'Daily summary retention in days', 'int'),
('Retention', 'WeeklySummaryRetentionDays', '$($config.Retention.ReportHistoryDays)', 'Weekly summary retention in days', 'int'),
('Retention', 'AlertRetentionDays', '$($config.Retention.AlertHistoryDays)', 'Alert history retention in days', 'int'),
('Retention', 'AnomalyRetentionDays', '$($config.Retention.AnomalyDays)', 'Anomaly retention in days', 'int');

-- Alert settings
DELETE FROM [monitor].[Settings] WHERE Category = 'Alerts';
INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType) VALUES
('Alerts', 'Enabled', '$($config.Alerts.Enabled)', 'Alert engine enabled', 'bool'),
('Alerts', 'CooldownMinutes', '$($config.Alerts.CooldownMinutes)', 'Alert cooldown period in minutes', 'int'),
('Alerts', 'NotificationMethod', '$($config.Alerts.NotificationMethod)', 'Alert notification method', 'string');
"@
            
            Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query $retentionAlertSettings
            Write-Host "      Retention and alerts configured." -ForegroundColor Green
        }

        # --- Done ---
        $duration = (Get-Date) - $scriptStart
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Green
        Write-Host "  Configuration completed in $($duration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
        Write-Host "============================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "  1. Test:      .\Test-SQLHealthMonitorInstallation.ps1 -ServerInstance '$ServerInstance' -Database '$Database'"
        Write-Host "  2. Deploy:   .\Deploy-SQLHealthMonitorJobs.ps1 -ServerInstance '$ServerInstance' -Database '$Database'"
        Write-Host "  3. Validate: .\Validate-SQLHealthMonitorSetup.ps1 -ServerInstance '$ServerInstance' -Database '$Database'"
        Write-Host ""
        
        # Return configuration summary for pipeline
        [PSCustomObject]@{
            ServerInstance = $ServerInstance
            Database = $Database
            Language = $config.Language
            EmailRecipients = $config.Email.Recipients
            CollectorsEnabled = $EnableAllCollectors
            Status = 'Completed'
            Duration = $duration
        }
    }
    catch {
        Write-Host ""
        Write-Host "CONFIGURATION FAILED" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        if ($_.ScriptStackTrace) {
            Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
        }
        throw
    }
}

end {
    # Clean up
    if ($sqlInstance) {
        $sqlInstance.ConnectionContext.Disconnect()
    }
}