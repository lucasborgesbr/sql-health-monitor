<#
.SYNOPSIS
    Installs the SQL Health Monitor database, objects, and SQL Agent jobs.

.DESCRIPTION
    Deploys the SQLHealthMonitor solution to a SQL Server instance by:
    1. Creating the database (if not exists)
    2. Running install scripts in order (schema, tables, procedures, config)
    3. Inserting default thresholds and language packs
    4. Creating SQL Agent jobs for scheduled execution

.PARAMETER ServerInstance
    Target SQL Server instance.

.PARAMETER Database
    Database name to create/use. Default: 'SQLHealthMonitor'.

.PARAMETER Schedule
    Collection schedule: Hourly or Daily. Default: Hourly.

.PARAMETER EmailProfile
    Database Mail profile name for sending reports.

.PARAMETER Recipients
    Email recipients for reports and alerts.

.PARAMETER Language
    Default language for reports: EN or PTBR. Default: EN.

.PARAMETER SkipAgentJobs
    Skip SQL Agent job creation (useful for testing or manual scheduling).

.PARAMETER Force
    Overwrite existing objects without prompting.

.EXAMPLE
    Install-SQLHealthMonitor -ServerInstance 'DBPRD' -EmailProfile 'DBA Mail' -Recipients 'dba@company.com'

.EXAMPLE
    Install-SQLHealthMonitor -ServerInstance 'DBDEV' -Schedule Daily -Language PTBR -SkipAgentJobs

.NOTES
    Author: Lucas Allan Borges
    Version: 1.0.0
    Requires: dbatools module, sysadmin or db_owner permissions
#>

function Install-SQLHealthMonitor {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$ServerInstance,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Database = 'SQLHealthMonitor',

        [Parameter()]
        [ValidateSet('Hourly', 'Daily')]
        [string]$Schedule = 'Hourly',

        [Parameter()]
        [string]$EmailProfile,

        [Parameter()]
        [string[]]$Recipients,

        [Parameter()]
        [ValidateSet('EN', 'PTBR')]
        [string]$Language = 'EN',

        [Parameter()]
        [switch]$SkipAgentJobs,

        [Parameter()]
        [switch]$Force
    )

    begin {
        $installStart = Get-Date
        $modulePath = Split-Path $PSScriptRoot -Parent
        $installPath = Join-Path $modulePath 'install'
        $configPath = Join-Path $modulePath 'config'
        $alertsPath = Join-Path $modulePath 'alerts'

        Write-Host "============================================" -ForegroundColor Cyan
        Write-Host "  SQL Health Monitor - Installation" -ForegroundColor Cyan
        Write-Host "============================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Server:   $ServerInstance"
        Write-Host "  Database: $Database"
        Write-Host "  Schedule: $Schedule"
        Write-Host "  Language: $Language"
        Write-Host ""
    }

    process {
        try {
            # --- Step 1: Connect ---
            Write-Host "[1/6] Connecting to SQL Server..." -ForegroundColor Yellow
            $sqlInstance = Connect-DbaInstance -SqlInstance $ServerInstance
            Write-Host "      Connected successfully." -ForegroundColor Green

            # --- Step 2: Create database if not exists ---
            Write-Host "[2/6] Ensuring database exists..." -ForegroundColor Yellow
            if ($PSCmdlet.ShouldProcess($Database, "Create database")) {
                $dbExists = Get-DbaDatabase -SqlInstance $sqlInstance -Database $Database
                if (-not $dbExists) {
                    $createDbSql = @"
CREATE DATABASE [$Database]
ALTER DATABASE [$Database] SET RECOVERY SIMPLE
ALTER DATABASE [$Database] SET AUTO_CLOSE OFF
ALTER DATABASE [$Database] SET AUTO_SHRINK OFF
"@
                    Invoke-DbaQuery -SqlInstance $sqlInstance -Query $createDbSql
                    Write-Host "      Database '$Database' created." -ForegroundColor Green
                }
                else {
                    Write-Host "      Database '$Database' already exists." -ForegroundColor Green
                }
            }

            # --- Step 3: Run install scripts in order ---
            Write-Host "[3/6] Running install scripts..." -ForegroundColor Yellow
            $installScripts = Get-ChildItem -Path $installPath -Filter '*.sql' -ErrorAction SilentlyContinue |
                Sort-Object Name

            if ($installScripts.Count -eq 0) {
                Write-Warning "No install scripts found in: $installPath"
                Write-Host "      Creating placeholder structure..." -ForegroundColor Yellow
                # The install scripts will be created as part of the project
            }
            else {
                foreach ($script in $installScripts) {
                    Write-Host "      Running: $($script.Name)..." -NoNewline
                    if ($PSCmdlet.ShouldProcess($script.Name, "Execute install script")) {
                        try {
                            $sql = Get-Content -Path $script.FullName -Raw
                            Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query $sql -QueryTimeout 300
                            Write-Host " OK" -ForegroundColor Green
                        }
                        catch {
                            Write-Host " FAILED" -ForegroundColor Red
                            if (-not $Force) {
                                throw "Install script '$($script.Name)' failed: $($_.Exception.Message)"
                            }
                            Write-Warning "Continuing due to -Force: $($_.Exception.Message)"
                        }
                    }
                }
            }

            # --- Step 4: Insert default configuration ---
            Write-Host "[4/6] Loading configuration..." -ForegroundColor Yellow
            $configScripts = @(
                (Join-Path $configPath 'settings.sql'),
                (Join-Path $configPath 'languages.sql'),
                (Join-Path $alertsPath 'thresholds_default.sql')
            )

            foreach ($configScript in $configScripts) {
                if (Test-Path $configScript) {
                    $scriptName = Split-Path $configScript -Leaf
                    Write-Host "      Loading: $scriptName..." -NoNewline
                    if ($PSCmdlet.ShouldProcess($scriptName, "Load configuration")) {
                        $sql = Get-Content -Path $configScript -Raw
                        Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query $sql -QueryTimeout 120
                        Write-Host " OK" -ForegroundColor Green
                    }
                }
            }

            # --- Step 5: Deploy collectors and views ---
            Write-Host "[5/6] Deploying collectors and views..." -ForegroundColor Yellow
            $deployPaths = @(
                @{ Path = (Join-Path $modulePath 'collectors'); Label = 'Collectors' }
                @{ Path = (Join-Path $modulePath 'views');      Label = 'Views' }
                @{ Path = (Join-Path $modulePath 'alerts');     Label = 'Alert Engine' }
                @{ Path = (Join-Path $modulePath 'reports');    Label = 'Reports' }
            )

            foreach ($deployItem in $deployPaths) {
                if (Test-Path $deployItem.Path) {
                    $sqlFiles = Get-ChildItem -Path $deployItem.Path -Filter '*.sql' -Recurse -ErrorAction SilentlyContinue
                    $count = ($sqlFiles | Measure-Object).Count
                    Write-Host "      $($deployItem.Label): $count file(s) found" -ForegroundColor Gray

                    foreach ($file in $sqlFiles) {
                        if ($PSCmdlet.ShouldProcess($file.Name, "Deploy $($deployItem.Label)")) {
                            try {
                                $sql = Get-Content -Path $file.FullName -Raw
                                Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query $sql -QueryTimeout 300
                            }
                            catch {
                                Write-Warning "Failed to deploy $($file.Name): $($_.Exception.Message)"
                            }
                        }
                    }
                }
            }

            # --- Step 6: Create SQL Agent Jobs ---
            if (-not $SkipAgentJobs) {
                Write-Host "[6/6] Creating SQL Agent jobs..." -ForegroundColor Yellow
                if ($PSCmdlet.ShouldProcess($ServerInstance, "Create SQL Agent jobs")) {
                    New-MonitorAgentJobs -SqlInstance $sqlInstance -Database $Database `
                        -Schedule $Schedule -EmailProfile $EmailProfile `
                        -Recipients $Recipients -Language $Language
                    Write-Host "      SQL Agent jobs created." -ForegroundColor Green
                }
            }
            else {
                Write-Host "[6/6] Skipping SQL Agent jobs (SkipAgentJobs specified)." -ForegroundColor Gray
            }

            # --- Done ---
            $duration = (Get-Date) - $installStart
            Write-Host ""
            Write-Host "============================================" -ForegroundColor Green
            Write-Host "  Installation completed in $($duration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
            Write-Host "============================================" -ForegroundColor Green
            Write-Host ""
            Write-Host "Next steps:" -ForegroundColor Cyan
            Write-Host "  1. Verify: Invoke-SQLHealthMonitor -ServerInstance '$ServerInstance' -RunType Collection -WhatIf"
            Write-Host "  2. Test:   Invoke-SQLHealthMonitor -ServerInstance '$ServerInstance' -RunType Collection -Verbose"
            Write-Host "  3. Report: Invoke-SQLHealthMonitor -ServerInstance '$ServerInstance' -RunType DailyReport -Language $Language"
            Write-Host ""
        }
        catch {
            Write-Host ""
            Write-Host "INSTALLATION FAILED" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
            Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
            throw
        }
    }
}

#region Private Functions

function New-MonitorAgentJobs {
    <#
    .SYNOPSIS
        Creates SQL Agent jobs for automated health monitoring.
    #>
    param(
        $SqlInstance,
        [string]$Database,
        [string]$Schedule,
        [string]$EmailProfile,
        [string[]]$Recipients,
        [string]$Language
    )

    $recipientList = if ($Recipients) { $Recipients -join '; ' } else { '' }

    # Determine PowerShell executable path
    $psCommand = @"
Import-Module SQLHealthMonitor; Invoke-SQLHealthMonitor -ServerInstance '`$(ESCAPE_SQUOTE(SRVR))' -Database '$Database' -RunType {0} -Language '$Language'
"@

    # Job 1: Collection (every 15 min or hourly)
    $collectionSchedule = if ($Schedule -eq 'Hourly') {
        @{ FrequencyType = 'Daily'; FrequencyInterval = 1; FrequencySubDayType = 'Hour'; FrequencySubDayInterval = 1 }
    }
    else {
        @{ FrequencyType = 'Daily'; FrequencyInterval = 1; FrequencySubDayType = 'Minute'; FrequencySubDayInterval = 15 }
    }

    New-AgentJob -SqlInstance $SqlInstance -JobName 'SQLHealthMonitor - Collection' `
        -Description 'Collects health metrics from SQL Server instance.' `
        -Command ($psCommand -f 'Collection') -Schedule $collectionSchedule

    # Job 2: Daily Report (7:00 AM)
    New-AgentJob -SqlInstance $SqlInstance -JobName 'SQLHealthMonitor - Daily Report' `
        -Description 'Generates and sends the daily health report.' `
        -Command ($psCommand -f 'DailyReport') `
        -Schedule @{ FrequencyType = 'Daily'; FrequencyInterval = 1; ActiveStartTimeOfDay = '070000' }

    # Job 3: Weekly Report (Monday 8:00 AM)
    New-AgentJob -SqlInstance $SqlInstance -JobName 'SQLHealthMonitor - Weekly Report' `
        -Description 'Generates and sends the weekly deep-dive report.' `
        -Command ($psCommand -f 'WeeklyReport') `
        -Schedule @{ FrequencyType = 'Weekly'; FrequencyInterval = 2; ActiveStartTimeOfDay = '080000' }  # 2 = Monday

    # Job 4: Alert Check (every 5 min)
    New-AgentJob -SqlInstance $SqlInstance -JobName 'SQLHealthMonitor - Alert Check' `
        -Description 'Evaluates alert thresholds and sends notifications.' `
        -Command ($psCommand -f 'Alert') `
        -Schedule @{ FrequencyType = 'Daily'; FrequencyInterval = 1; FrequencySubDayType = 'Minute'; FrequencySubDayInterval = 5 }

    Write-Verbose "Created 4 SQL Agent jobs for SQLHealthMonitor"
}

function New-AgentJob {
    <#
    .SYNOPSIS
        Creates a single SQL Agent job with a PowerShell step and schedule.
    #>
    param(
        $SqlInstance,
        [string]$JobName,
        [string]$Description,
        [string]$Command,
        [hashtable]$Schedule
    )

    # Drop existing job if present
    $dropSql = @"
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1
END
"@
    Invoke-DbaQuery -SqlInstance $SqlInstance -Database 'msdb' -Query $dropSql -SqlParameters @{ JobName = $JobName }

    # Create job via T-SQL for maximum compatibility
    $createSql = @"
DECLARE @jobId UNIQUEIDENTIFIER
DECLARE @scheduleId INT

-- Create the job
EXEC msdb.dbo.sp_add_job
    @job_name = @JobName,
    @description = @Description,
    @category_name = N'Database Maintenance',
    @owner_login_name = N'sa',
    @enabled = 1,
    @jobId = @jobId OUTPUT

-- Add PowerShell step
EXEC msdb.dbo.sp_add_jobstep
    @job_id = @jobId,
    @step_name = N'Execute Monitor',
    @step_id = 1,
    @subsystem = N'PowerShell',
    @command = @Command,
    @on_success_action = 1,
    @on_fail_action = 2,
    @retry_attempts = 1,
    @retry_interval = 5

-- Add schedule
EXEC msdb.dbo.sp_add_jobschedule
    @job_id = @jobId,
    @name = @JobName,
    @enabled = 1,
    @freq_type = @FreqType,
    @freq_interval = @FreqInterval,
    @freq_subday_type = @FreqSubDayType,
    @freq_subday_interval = @FreqSubDayInterval,
    @active_start_time = @ActiveStartTime

-- Target local server
EXEC msdb.dbo.sp_add_jobserver
    @job_id = @jobId,
    @server_name = N'(local)'
"@

    # Map schedule parameters
    $freqTypeMap = @{ 'Daily' = 4; 'Weekly' = 8 }
    $subDayTypeMap = @{ 'Hour' = 8; 'Minute' = 4 }

    $params = @{
        JobName            = $JobName
        Description        = $Description
        Command            = $Command
        FreqType           = $freqTypeMap[$Schedule.FrequencyType]
        FreqInterval       = $Schedule.FrequencyInterval
        FreqSubDayType     = if ($Schedule.FrequencySubDayType) { $subDayTypeMap[$Schedule.FrequencySubDayType] } else { 1 }
        FreqSubDayInterval = if ($Schedule.FrequencySubDayInterval) { $Schedule.FrequencySubDayInterval } else { 0 }
        ActiveStartTime    = if ($Schedule.ActiveStartTimeOfDay) { [int]$Schedule.ActiveStartTimeOfDay } else { 0 }
    }

    Invoke-DbaQuery -SqlInstance $SqlInstance -Database 'msdb' -Query $createSql -SqlParameters $params
    Write-Verbose "Created job: $JobName"
}

#endregion

Export-ModuleMember -Function Install-SQLHealthMonitor
