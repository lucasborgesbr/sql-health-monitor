<#
.SYNOPSIS
    SQL Server Health Monitor - Main orchestrator script.

.DESCRIPTION
    Executes health collectors, triggers alerts, and generates reports for SQL Server instances.
    Connects to the SQLHealthMonitor database and runs T-SQL collectors in proper sequence,
    evaluates alert thresholds, and optionally generates/sends health reports.

.PARAMETER ServerInstance
    SQL Server instance name (e.g., 'SERVER\INSTANCE' or 'server,port').

.PARAMETER Database
    Monitor database name. Default: 'SQLHealthMonitor'.

.PARAMETER ConfigProfile
    Configuration profile to load from the database. Default: 'DEFAULT'.

.PARAMETER RunType
    Type of execution: Collection, DailyReport, WeeklyReport, or Alert.

.PARAMETER Language
    Report language: EN or PTBR. Default: EN.

.PARAMETER ConfigPath
    Path to JSON config file. Default: module's config/default.json.

.EXAMPLE
    Invoke-SQLHealthMonitor -ServerInstance 'DBPRD' -RunType Collection

.EXAMPLE
    Invoke-SQLHealthMonitor -ServerInstance 'DBPRD' -RunType DailyReport -Language PTBR

.EXAMPLE
    Invoke-SQLHealthMonitor -ServerInstance 'DBPRD' -RunType Alert -Verbose

.NOTES
    Author: Lucas Allan Borges
    Version: 1.0.0
    Requires: dbatools module, SQL Server 2016+
#>

function Invoke-SQLHealthMonitor {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServerInstance,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Database = 'SQLHealthMonitor',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ConfigProfile = 'DEFAULT',

        [Parameter(Mandatory = $true)]
        [ValidateSet('Collection', 'DailyReport', 'WeeklyReport', 'Alert')]
        [string]$RunType,

        [Parameter()]
        [ValidateSet('EN', 'PTBR')]
        [string]$Language = 'EN',

        [Parameter()]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$ConfigPath
    )

    begin {
        # --- Initialize logging ---
        $scriptStart = Get-Date
        $modulePath = Split-Path -Parent $PSScriptRoot
        if (-not $ConfigPath) {
            $ConfigPath = Join-Path $PSScriptRoot 'config\default.json'
        }

        # Load configuration
        try {
            $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
            Write-Verbose "Configuration loaded from: $ConfigPath"
        }
        catch {
            throw "Failed to load configuration from '$ConfigPath': $_"
        }

        # Setup log directory
        $logPath = $config.Logging.Path
        if (-not (Test-Path $logPath)) {
            New-Item -Path $logPath -ItemType Directory -Force | Out-Null
        }
        $logFile = Join-Path $logPath "SQLHealthMonitor_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

        # Internal logging function
        function Write-Log {
            param(
                [string]$Message,
                [ValidateSet('Information', 'Warning', 'Error')]
                [string]$Level = 'Information'
            )
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            $entry = "[$timestamp] [$Level] $Message"
            Add-Content -Path $logFile -Value $entry -ErrorAction SilentlyContinue

            switch ($Level) {
                'Warning' { Write-Warning $Message }
                'Error'   { Write-Error $Message }
                default   { Write-Verbose $Message }
            }
        }

        Write-Log "=== SQL Health Monitor started ==="
        Write-Log "ServerInstance: $ServerInstance | Database: $Database | RunType: $RunType | Language: $Language"
    }

    process {
        try {
            # --- Establish connection ---
            Write-Log "Connecting to $ServerInstance..."
            if ($PSCmdlet.ShouldProcess($ServerInstance, "Connect to SQL Server")) {
                $sqlInstance = Connect-DbaInstance -SqlInstance $ServerInstance -Database $Database
                Write-Log "Connected successfully to $ServerInstance"
            }
            else {
                Write-Log "WhatIf: Would connect to $ServerInstance" -Level Warning
                return
            }

            # --- Execute based on RunType ---
            switch ($RunType) {
                'Collection' {
                    Invoke-HealthCollection -SqlInstance $sqlInstance -Database $Database -Config $config
                }
                'DailyReport' {
                    Invoke-HealthCollection -SqlInstance $sqlInstance -Database $Database -Config $config
                    $reportData = Get-ReportData -SqlInstance $sqlInstance -Database $Database -ReportType 'Daily'
                    Send-HealthReport -ServerInstance $ServerInstance -Database $Database `
                        -ReportType 'Daily' -Language $Language -ReportData $reportData -Config $config
                }
                'WeeklyReport' {
                    Invoke-HealthCollection -SqlInstance $sqlInstance -Database $Database -Config $config
                    $reportData = Get-ReportData -SqlInstance $sqlInstance -Database $Database -ReportType 'Weekly'
                    Send-HealthReport -ServerInstance $ServerInstance -Database $Database `
                        -ReportType 'Weekly' -Language $Language -ReportData $reportData -Config $config
                }
                'Alert' {
                    Invoke-HealthCollection -SqlInstance $sqlInstance -Database $Database -Config $config
                    $alerts = Invoke-AlertEvaluation -SqlInstance $sqlInstance -Database $Database
                    if ($alerts.Count -gt 0) {
                        Write-Log "ALERT: $($alerts.Count) threshold(s) breached!"
                        Send-HealthReport -ServerInstance $ServerInstance -Database $Database `
                            -ReportType 'Alert' -Language $Language -ReportData $alerts -Config $config
                    }
                    else {
                        Write-Log "No alert thresholds breached."
                    }
                }
            }
        }
        catch {
            Write-Log "FATAL: $($_.Exception.Message)" -Level Error
            Write-Log "Stack: $($_.ScriptStackTrace)" -Level Error
            throw
        }
    }

    end {
        $duration = (Get-Date) - $scriptStart
        Write-Log "=== SQL Health Monitor completed in $($duration.TotalSeconds.ToString('F1'))s ==="
    }
}

#region Private Functions

function Invoke-HealthCollection {
    <#
    .SYNOPSIS
        Executes all enabled T-SQL collectors in sequence.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]$SqlInstance,
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)]$Config
    )

    # Collector execution order matters: base metrics first, then dependent ones
    $collectorSequence = @(
        @{ Name = 'CPU';                Script = 'collect_cpu.sql' }
        @{ Name = 'Memory';             Script = 'collect_memory.sql' }
        @{ Name = 'Disk';               Script = 'collect_disk.sql' }
        @{ Name = 'TempDB';             Script = 'collect_tempdb.sql' }
        @{ Name = 'WaitStats';          Script = 'collect_waits.sql' }
        @{ Name = 'Blocking';           Script = 'collect_blocking.sql' }
        @{ Name = 'Deadlocks';          Script = 'collect_deadlocks.sql' }
        @{ Name = 'AvailabilityGroups'; Script = 'collect_ag.sql' }
        @{ Name = 'CDC';                Script = 'collect_cdc.sql' }
        @{ Name = 'TopQueries';         Script = 'collect_top_queries.sql' }
        @{ Name = 'IndexHealth';        Script = 'collect_index_health.sql' }
        @{ Name = 'BackupStatus';       Script = 'collect_backup_status.sql' }
        @{ Name = 'Jobs';               Script = 'collect_jobs.sql' }
        @{ Name = 'ErrorLog';           Script = 'collect_error_log.sql' }
        @{ Name = 'LogGrowth';          Script = 'collect_log_growth.sql' }
        @{ Name = 'DatabaseGrowth';     Script = 'collect_database_growth.sql' }
    )

    $enabledCollectors = $Config.Collectors.Enabled
    $collectorsPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'collectors'

    $successCount = 0
    $failCount = 0

    foreach ($collector in $collectorSequence) {
        # Skip disabled collectors
        if ($collector.Name -notin $enabledCollectors) {
            Write-Verbose "Skipping disabled collector: $($collector.Name)"
            continue
        }

        $scriptFile = Join-Path $collectorsPath $collector.Script
        if (-not (Test-Path $scriptFile)) {
            Write-Log "Collector script not found: $scriptFile" -Level Warning
            $failCount++
            continue
        }

        if ($PSCmdlet.ShouldProcess($collector.Name, "Execute collector")) {
            try {
                Write-Verbose "Running collector: $($collector.Name)..."
                $collectorStart = Get-Date
                $sql = Get-Content -Path $scriptFile -Raw
                Invoke-DbaQuery -SqlInstance $SqlInstance -Database $Database -Query $sql -QueryTimeout $Config.Connection.CommandTimeout
                $elapsed = ((Get-Date) - $collectorStart).TotalMilliseconds
                Write-Log "Collector [$($collector.Name)] completed in $($elapsed.ToString('F0'))ms"
                $successCount++
            }
            catch {
                Write-Log "Collector [$($collector.Name)] FAILED: $($_.Exception.Message)" -Level Warning
                $failCount++
                # Continue with remaining collectors - don't abort the whole run
            }
        }
    }

    Write-Log "Collection complete: $successCount succeeded, $failCount failed"
}

function Invoke-AlertEvaluation {
    <#
    .SYNOPSIS
        Runs the alert engine and returns any breached thresholds.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$SqlInstance,
        [Parameter(Mandatory)][string]$Database
    )

    $alertScriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'alerts\alert_engine.sql'

    if (-not (Test-Path $alertScriptPath)) {
        Write-Log "Alert engine script not found: $alertScriptPath" -Level Warning
        return @()
    }

    $sql = Get-Content -Path $alertScriptPath -Raw
    $results = Invoke-DbaQuery -SqlInstance $SqlInstance -Database $Database -Query $sql -QueryTimeout 120

    if ($results) {
        return @($results)
    }
    return @()
}

function Get-ReportData {
    <#
    .SYNOPSIS
        Retrieves aggregated data for report generation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$SqlInstance,
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][ValidateSet('Daily', 'Weekly')][string]$ReportType
    )

    # Use the current health view as base data
    $viewQuery = "SELECT * FROM dbo.vw_CurrentHealth"
    $currentHealth = Invoke-DbaQuery -SqlInstance $SqlInstance -Database $Database -Query $viewQuery

    # Get recommendations
    $recsPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'reports\recommendations_engine.sql'
    $recommendations = @()
    if (Test-Path $recsPath) {
        $recsSql = Get-Content -Path $recsPath -Raw
        $recommendations = Invoke-DbaQuery -SqlInstance $SqlInstance -Database $Database -Query $recsSql
    }

    # Build report data object
    $reportData = [PSCustomObject]@{
        ReportType      = $ReportType
        GeneratedAt     = Get-Date
        ServerInstance  = $SqlInstance.Name
        CurrentHealth   = $currentHealth
        Recommendations = $recommendations
    }

    if ($ReportType -eq 'Weekly') {
        # Weekly includes trend data
        $trendQuery = @"
SELECT MetricName, CollectedAt, MetricValue
FROM dbo.HealthMetrics
WHERE CollectedAt >= DATEADD(DAY, -7, GETDATE())
ORDER BY MetricName, CollectedAt
"@
        $reportData | Add-Member -NotePropertyName 'TrendData' -NotePropertyValue (
            Invoke-DbaQuery -SqlInstance $SqlInstance -Database $Database -Query $trendQuery
        )
    }

    return $reportData
}

#endregion

# Export the main function
Export-ModuleMember -Function Invoke-SQLHealthMonitor
