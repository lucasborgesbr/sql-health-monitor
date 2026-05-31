<#
.SYNOPSIS
    SQL Health Monitor - Generic SQL Agent Job Deployment Script
    Creates SQL Agent jobs for scheduled monitoring, alerting, and reporting.

.DESCRIPTION
    This script deploys SQL Agent jobs for automated health monitoring.
    It creates jobs for collection, reporting, alert checking, and data maintenance.
    Works with any environment without hardcoded values.

.PARAMETER ServerInstance
    Target SQL Server instance (e.g., 'localhost', 'SQL-PRD-01')

.PARAMETER Database
    Database name. Default: 'SQLHealthMonitor'

.PARAMETER AuthMethod
    Authentication method: 'Windows' (default) or 'Sql'

.PARAMETER SqlCredential
    SQL credential object for SQL authentication

.PARAMETER ScheduleType
    Collection schedule: 'Hourly' or 'Daily'. Default: 'Hourly'

.PARAMETER EmailProfile
    Database Mail profile name for email notifications

.PARAMETER Language
    Report language: 'EN' or 'PTBR'. Default: 'EN'

.PARAMETER SkipCollectionJob
    Skip creating the collection job (for manual testing)

.PARAMETER SkipReportJobs
    Skip creating report jobs (for manual testing)

.PARAMETER SkipAlertJob
    Skip creating the alert checking job (for manual testing)

.PARAMETER SkipMaintenanceJob
    Skip creating the maintenance job (for manual testing)

.EXAMPLE
    # Standard deployment with all jobs
    .\Deploy-SQLHealthMonitorJobs.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -EmailProfile 'DBA Mail'

.EXAMPLE
    # Daily schedule with selective job creation
    .\Deploy-SQLHealthMonitorJobs.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -ScheduleType 'Daily' -SkipCollectionJob

.EXAMPLE
    # SQL authentication
    $cred = Get-Credential
    .\Deploy-SQLHealthMonitorJobs.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -AuthMethod 'Sql' -SqlCredential $cred

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
    [ValidateSet('Windows', 'Sql')]
    [string]$AuthMethod = 'Windows',

    [Parameter()]
    [System.Management.Automation.PSCredential]$SqlCredential,

    [Parameter()]
    [ValidateSet('Hourly', 'Daily')]
    [string]$ScheduleType = 'Hourly',

    [Parameter()]
    [string]$EmailProfile,

    [Parameter()]
    [ValidateSet('EN', 'PTBR')]
    [string]$Language = 'EN',

    [Parameter()]
    [switch]$SkipCollectionJob,

    [Parameter()]
    [switch]$SkipReportJobs,

    [Parameter()]
    [switch]$SkipAlertJob,

    [Parameter()]
    [switch]$SkipMaintenanceJob
)

begin {
    $scriptStart = Get-Date
    
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  SQL Health Monitor - Job Deployment" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Server:      $ServerInstance"
    Write-Host "  Database:    $Database"
    Write-Host "  Schedule:    $ScheduleType"
    Write-Host "  Language:    $Language"
    Write-Host ""
}

process {
    try {
        # --- Step 1: Connect to SQL Server ---
        Write-Host "[1/5] Connecting to SQL Server..." -ForegroundColor Yellow
        
        $sqlParams = @{
            SqlInstance = $ServerInstance
            ErrorAction = 'Stop'
        }
        
        if ($AuthMethod -eq 'Sql' -and $SqlCredential) {
            $sqlParams.SqlCredential = $SqlCredential
        }
        
        $sqlInstance = Connect-DbaInstance @sqlParams
        Write-Host "      Connected successfully to $ServerInstance" -ForegroundColor Green

        # --- Step 2: Generate PowerShell command for jobs ---
        Write-Host "[2/5] Preparing PowerShell commands..." -ForegroundColor Yellow
        
        # Escape single quotes for SQL
        $escapedServer = $ServerInstance -replace "'", "''"
        $escapedDatabase = $Database -replace "'", "''"
        
        $psCommand = @"
Import-Module SQLHealthMonitor; Invoke-SQLHealthMonitor -ServerInstance '$escapedServer' -Database '$escapedDatabase' -RunType {0} -Language '$Language'
"@

        # --- Step 3: Create collection job ---
        if (-not $SkipCollectionJob) {
            Write-Host "[3/5] Creating collection job..." -ForegroundColor Yellow
            if ($PSCmdlet.ShouldProcess($ServerInstance, "Create collection job")) {
                $collectionJob = New-SQLAgentJob -SqlInstance $sqlInstance `
                    -JobName 'SQLHealthMonitor - Collection' `
                    -Description 'Collects health metrics from SQL Server instance.' `
                    -Command ($psCommand -f 'Collection') `
                    -Schedule $ScheduleType `
                    -Enabled $true
                
                if ($collectionJob) {
                    Write-Host "      Collection job created successfully." -ForegroundColor Green
                }
            }
        }

        # --- Step 4: Create report jobs ---
        if (-not $SkipReportJobs) {
            Write-Host "[4/5] Creating report jobs..." -ForegroundColor Yellow
            
            # Daily Report job
            if ($PSCmdlet.ShouldProcess($ServerInstance, "Create daily report job")) {
                $dailyJob = New-SQLAgentJob -SqlInstance $sqlInstance `
                    -JobName 'SQLHealthMonitor - Daily Report' `
                    -Description 'Generates and sends the daily health report.' `
                    -Command ($psCommand -f 'DailyReport') `
                    -Schedule 'Daily' `
                    -StartTime '070000' `
                    -Enabled $true
                
                if ($dailyJob) {
                    Write-Host "      Daily report job created successfully." -ForegroundColor Green
                }
            }

            # Weekly Report job
            if ($PSCmdlet.ShouldProcess($ServerInstance, "Create weekly report job")) {
                $weeklyJob = New-SQLAgentJob -SqlInstance $sqlInstance `
                    -JobName 'SQLHealthMonitor - Weekly Report' `
                    -Description 'Generates and sends the weekly deep-dive report.' `
                    -Command ($psCommand -f 'WeeklyReport') `
                    -Schedule 'Weekly' `
                    -Day 'Monday' `
                    -StartTime '080000' `
                    -Enabled $true
                
                if ($weeklyJob) {
                    Write-Host "      Weekly report job created successfully." -ForegroundColor Green
                }
            }
        }

        # --- Step 5: Create alert and maintenance jobs ---
        if (-not $SkipAlertJob) {
            Write-Host "[5/5] Creating alert job..." -ForegroundColor Yellow
            if ($PSCmdlet.ShouldProcess($ServerInstance, "Create alert job")) {
                $alertJob = New-SQLAgentJob -SqlInstance $sqlInstance `
                    -JobName 'SQLHealthMonitor - Alert Check' `
                    -Description 'Evaluates alert thresholds and sends notifications.' `
                    -Command ($psCommand -f 'Alert') `
                    -Schedule 'Frequent' `
                    -Interval 5 `
                    -Enabled $true
                
                if ($alertJob) {
                    Write-Host "      Alert job created successfully." -ForegroundColor Green
                }
            }
        }

        if (-not $SkipMaintenanceJob) {
            if ($PSCmdlet.ShouldProcess($ServerInstance, "Create maintenance job")) {
                $maintenanceJob = New-SQLAgentJob -SqlInstance $sqlInstance `
                    -JobName 'SQLHealthMonitor - Maintenance' `
                    -Description 'Purges old data and performs maintenance tasks.' `
                    -Command ($psCommand -f 'Maintenance') `
                    -Schedule 'Daily' `
                    -StartTime '030000' `
                    -Enabled $true
                
                if ($maintenanceJob) {
                    Write-Host "      Maintenance job created successfully." -ForegroundColor Green
                }
            }
        }

        # --- Done ---
        $duration = (Get-Date) - $scriptStart
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Green
        Write-Host "  Job deployment completed in $($duration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
        Write-Host "============================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "  1. Test:      .\Test-SQLHealthMonitorInstallation.ps1 -ServerInstance '$ServerInstance' -Database '$Database'"
        Write-Host "  2. Validate:  .\Validate-SQLHealthMonitorSetup.ps1 -ServerInstance '$ServerInstance' -Database '$Database'"
        Write-Host "  3. Monitor:   Check SQL Agent job status in SSMS"
        Write-Host ""
        
        # Return job deployment summary for pipeline
        [PSCustomObject]@{
            ServerInstance = $ServerInstance
            Database = $Database
            ScheduleType = $ScheduleType
            Language = $Language
            JobsCreated = @{
                Collection = (-not $SkipCollectionJob)
                DailyReport = (-not $SkipReportJobs)
                WeeklyReport = (-not $SkipReportJobs)
                AlertCheck = (-not $SkipAlertJob)
                Maintenance = (-not $SkipMaintenanceJob)
            }
            Status = 'Completed'
            Duration = $duration
        }
    }
    catch {
        Write-Host ""
        Write-Host "JOB DEPLOYMENT FAILED" -ForegroundColor Red
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

#region Helper Functions

function New-SQLAgentJob {
    <#
    .SYNOPSIS
        Creates a SQL Agent job with PowerShell step and schedule.
    #>
    param(
        $SqlInstance,
        [string]$JobName,
        [string]$Description,
        [string]$Command,
        [string]$Schedule = 'Hourly',
        [string]$StartTime = '000000',
        [string]$Day = 'Monday',
        [int]$Interval = 15,
        [bool]$Enabled = $true
    )

    # Drop existing job if present
    $dropSql = @"
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    DECLARE @jobId UNIQUEIDENTIFIER
    SELECT @jobId = job_id FROM msdb.dbo.sysjobs WHERE name = @JobName
    EXEC msdb.dbo.sp_delete_job @job_id = @jobId
END
"@

    $dropParams = @{ JobName = $JobName }
    Invoke-DbaQuery -SqlInstance $SqlInstance -Database 'msdb' -Query $dropSql -SqlParameters $dropParams

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
    @enabled = @Enabled,
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
    @enabled = @Enabled,
    @freq_type = @FreqType,
    @freq_interval = @FreqInterval,
    @freq_subday_type = @FreqSubDayType,
    @freq_subday_interval = @Interval,
    @active_start_time = @StartTime,
    @active_start_date = NULL,
    @active_end_date = 99991231,
    @active_end_time = 235959

-- Target local server
EXEC msdb.dbo.sp_add_jobserver
    @job_id = @jobId,
    @server_name = N'(local)'

SELECT @jobId AS JobId
"@

    # Map schedule parameters
    $freqTypeMap = @{
        'Hourly' = 4      # Daily
        'Daily' = 4      # Daily
        'Weekly' = 8     # Weekly
        'Frequent' = 4   # Daily with subday interval
    }

    $freqIntervalMap = @{
        'Hourly' = 1     # Every day
        'Daily' = 1     # Every day
        'Weekly' = 2     # Monday
        'Frequent' = 1   # Every day
    }

    $subDayTypeMap = @{
        'Hourly' = 8     # Hours
        'Daily' = 1     # Once
        'Weekly' = 1     # Once
        'Frequent' = 4   # Minutes
    }

    $params = @{
        JobName = $JobName
        Description = $Description
        Command = $Command
        FreqType = $freqTypeMap[$Schedule]
        FreqInterval = $freqIntervalMap[$Schedule]
        FreqSubDayType = $subDayTypeMap[$Schedule]
        StartTime = [int]$StartTime
        Enabled = $Enabled
    }

    $result = Invoke-DbaQuery -SqlInstance $sqlInstance -Database 'msdb' -Query $createSql -SqlParameters $params
    return $result
}

#endregion