<#
.SYNOPSIS
    SQL Server Health Monitor - Main orchestrator script.

.DESCRIPTION
    Executes health collectors, triggers alerts, and generates reports for SQL Server instances.
    Connects to the SQLHealthMonitor database and runs T-SQL collectors in proper sequence,
    evaluates alert thresholds, and optionally generates/sends health reports.

    Supports multi-instance mode via -AllInstances switch, which reads from the
    RegisteredServers table and loops collection across all active instances.

.PARAMETER ServerInstance
    SQL Server instance name (e.g., 'SERVER\INSTANCE' or 'server,port').
    Not required when using -AllInstances.

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

.PARAMETER AllInstances
    When specified, reads from [monitor].[RegisteredServers] and runs the
    specified RunType against all active instances. Requires a CMS server
    specified via -ServerInstance (the instance hosting the RegisteredServers table).

.PARAMETER Environment
    Filter instances by environment when using -AllInstances (DEV, STG, PRD).

.PARAMETER ParallelDegree
    Max parallel instance collections when using -AllInstances. Default: 4.

.EXAMPLE
    Invoke-SQLHealthMonitor -ServerInstance 'DBPRD' -RunType Collection

.EXAMPLE
    Invoke-SQLHealthMonitor -ServerInstance 'DBPRD' -RunType DailyReport -Language PTBR

.EXAMPLE
    Invoke-SQLHealthMonitor -ServerInstance 'DBPRD' -RunType Alert -Verbose

.EXAMPLE
    # Multi-instance: collect from all registered production servers
    Invoke-SQLHealthMonitor -ServerInstance 'DBPRD' -RunType Collection -AllInstances -Environment PRD

.EXAMPLE
    # Multi-instance: collect from ALL registered servers
    Invoke-SQLHealthMonitor -ServerInstance 'DBPRD' -RunType Collection -AllInstances

.NOTES
    Author: Lucas Allan Borges
    Version: 2.0.0
    Requires: dbatools module, SQL Server 2016+
#>

function Invoke-SQLHealthMonitor {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
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
        [string]$ConfigPath,

        [Parameter()]
        [switch]$AllInstances,

        [Parameter()]
        [ValidateSet('DEV', 'STG', 'PRD', 'DR')]
        [string]$Environment,

        [Parameter()]
        [ValidateRange(1, 16)]
        [int]$ParallelDegree = 4
    )

    begin {
        # --- Validate parameters ---
        if (-not $AllInstances -and -not $ServerInstance) {
            throw "ServerInstance is required unless -AllInstances is specified."
        }

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
        Write-Log "RunType: $RunType | Language: $Language | AllInstances: $AllInstances"
    }

    process {
        try {
            # ============================================================
            # MULTI-INSTANCE MODE
            # ============================================================
            if ($AllInstances) {
                if (-not $ServerInstance) {
                    throw "ServerInstance (CMS host) is required with -AllInstances to read RegisteredServers."
                }

                Write-Log "Multi-instance mode: connecting to CMS host $ServerInstance..."
                $cmsInstance = Connect-DbaInstance -SqlInstance $ServerInstance -Database $Database

                # Read registered servers
                $envFilter = if ($Environment) { "AND Environment = '$Environment'" } else { "" }
                $registeredQuery = @"
SELECT InstanceName, MonitorDatabase, Environment, AgRole, ServerRole
FROM [monitor].[RegisteredServers]
WHERE IsActive = 1 $envFilter
ORDER BY Environment, InstanceName
"@
                $registeredServers = Invoke-DbaQuery -SqlInstance $cmsInstance -Database $Database -Query $registeredQuery

                if (-not $registeredServers -or $registeredServers.Count -eq 0) {
                    Write-Log "No active registered servers found matching criteria." -Level Warning
                    return
                }

                Write-Log "Found $($registeredServers.Count) registered instance(s). Starting $RunType..."

                # Track results
                $results = [System.Collections.ArrayList]::new()

                # Process instances (sequential or parallel based on PS version)
                foreach ($server in $registeredServers) {
                    $instanceName = $server.InstanceName
                    $instanceDb = $server.MonitorDatabase
                    $instanceStart = Get-Date

                    Write-Log "Processing [$instanceName] ($($server.Environment) / $($server.ServerRole))..."

                    try {
                        if ($PSCmdlet.ShouldProcess($instanceName, "$RunType")) {
                            $instanceConn = Connect-DbaInstance -SqlInstance $instanceName -Database $instanceDb

                            switch ($RunType) {
                                'Collection' {
                                    Invoke-HealthCollection -SqlInstance $instanceConn -Database $instanceDb -Config $config
                                    
                                    # Also collect health snapshot for CMS comparison
                                    $snapshotQuery = @"
INSERT INTO [$Database].[monitor].[InstanceHealthSnapshot]
    (InstanceName, HealthScore, CpuAvg, CpuMax, PleAvg, DiskMaxUsedPct, AgMaxLagSec, BlockingCount, AlertCount, OverallStatus)
SELECT 
    '$instanceName',
    100 
        - CASE WHEN MAX(c.SqlCpuPct) >= 95 THEN 25 WHEN MAX(c.SqlCpuPct) >= 80 THEN 10 ELSE 0 END
        - CASE WHEN MIN(m.PageLifeExpectancy) <= 100 THEN 25 WHEN MIN(m.PageLifeExpectancy) <= 300 THEN 10 ELSE 0 END
        - CASE WHEN MAX(d.UsedPct) >= 95 THEN 20 WHEN MAX(d.UsedPct) >= 85 THEN 8 ELSE 0 END,
    AVG(c.SqlCpuPct), MAX(c.SqlCpuPct),
    AVG(m.PageLifeExpectancy),
    MAX(d.UsedPct),
    ISNULL(MAX(ag.SecondsBehindPrimary), 0),
    (SELECT COUNT(*) FROM [monitor].[BlockingHistory] WHERE DetectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())),
    (SELECT COUNT(*) FROM [monitor].[AlertHistory] WHERE FiredAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())),
    CASE 
        WHEN MAX(c.SqlCpuPct) >= 95 OR MIN(m.PageLifeExpectancy) <= 100 OR MAX(d.UsedPct) >= 95 THEN 'critical'
        WHEN MAX(c.SqlCpuPct) >= 80 OR MIN(m.PageLifeExpectancy) <= 300 OR MAX(d.UsedPct) >= 85 THEN 'warning'
        ELSE 'healthy'
    END
FROM [monitor].[CpuHistory] c
CROSS JOIN [monitor].[MemoryHistory] m
CROSS JOIN [monitor].[DiskHistory] d
LEFT JOIN [monitor].[AgHealthHistory] ag ON ag.CollectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
WHERE c.CollectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
    AND m.CollectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
    AND d.CollectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME());
"@
                                    # Run snapshot on remote, insert into CMS
                                    try {
                                        Invoke-DbaQuery -SqlInstance $instanceConn -Database $instanceDb -Query $snapshotQuery -QueryTimeout 30
                                    }
                                    catch {
                                        Write-Log "  Snapshot collection failed for [$instanceName]: $($_.Exception.Message)" -Level Warning
                                    }
                                }
                                'DailyReport' {
                                    Invoke-HealthCollection -SqlInstance $instanceConn -Database $instanceDb -Config $config
                                    $reportData = Get-ReportData -SqlInstance $instanceConn -Database $instanceDb -ReportType 'Daily'
                                    Send-HealthReport -ServerInstance $instanceName -Database $instanceDb `
                                        -ReportType 'Daily' -Language $Language -ReportData $reportData -Config $config
                                }
                                'WeeklyReport' {
                                    Invoke-HealthCollection -SqlInstance $instanceConn -Database $instanceDb -Config $config
                                    $reportData = Get-ReportData -SqlInstance $instanceConn -Database $instanceDb -ReportType 'Weekly'
                                    Send-HealthReport -ServerInstance $instanceName -Database $instanceDb `
                                        -ReportType 'Weekly' -Language $Language -ReportData $reportData -Config $config
                                }
                                'Alert' {
                                    Invoke-HealthCollection -SqlInstance $instanceConn -Database $instanceDb -Config $config
                                    $alerts = Invoke-AlertEvaluation -SqlInstance $instanceConn -Database $instanceDb
                                    if ($alerts.Count -gt 0) {
                                        Write-Log "  ALERT on [$instanceName]: $($alerts.Count) threshold(s) breached!"
                                        Send-HealthReport -ServerInstance $instanceName -Database $instanceDb `
                                            -ReportType 'Alert' -Language $Language -ReportData $alerts -Config $config
                                    }
                                }
                            }

                            $elapsed = ((Get-Date) - $instanceStart).TotalSeconds
                            [void]$results.Add([PSCustomObject]@{
                                Instance    = $instanceName
                                Environment = $server.Environment
                                Status      = 'Success'
                                Duration    = [math]::Round($elapsed, 1)
                                Error       = $null
                            })

                            # Update registration status
                            $updateQuery = "UPDATE [monitor].[RegisteredServers] SET LastCollectedAt = SYSUTCDATETIME(), LastCollectionStatus = 'Success' WHERE InstanceName = '$instanceName'"
                            Invoke-DbaQuery -SqlInstance $cmsInstance -Database $Database -Query $updateQuery -QueryTimeout 10
                        }
                    }
                    catch {
                        $elapsed = ((Get-Date) - $instanceStart).TotalSeconds
                        Write-Log "  FAILED [$instanceName]: $($_.Exception.Message)" -Level Warning
                        [void]$results.Add([PSCustomObject]@{
                            Instance    = $instanceName
                            Environment = $server.Environment
                            Status      = 'Failed'
                            Duration    = [math]::Round($elapsed, 1)
                            Error       = $_.Exception.Message
                        })

                        # Update registration status
                        $updateQuery = "UPDATE [monitor].[RegisteredServers] SET LastCollectedAt = SYSUTCDATETIME(), LastCollectionStatus = 'Failed' WHERE InstanceName = '$instanceName'"
                        try { Invoke-DbaQuery -SqlInstance $cmsInstance -Database $Database -Query $updateQuery -QueryTimeout 10 } catch {}
                    }
                }

                # Summary output
                $successCount = ($results | Where-Object Status -eq 'Success').Count
                $failCount = ($results | Where-Object Status -eq 'Failed').Count
                Write-Log "Multi-instance $RunType complete: $successCount succeeded, $failCount failed."

                # Output results
                $results | Format-Table -AutoSize
                return
            }

            # ============================================================
            # SINGLE-INSTANCE MODE (original behavior)
            # ============================================================
            Write-Log "Single-instance mode: $ServerInstance | Database: $Database"

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
        Calls usp_GenerateDailyReport or usp_GenerateWeeklyReport for structured output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$SqlInstance,
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][ValidateSet('Daily', 'Weekly')][string]$ReportType
    )

    # Use the new structured report procedures
    $reportProc = switch ($ReportType) {
        'Daily'  { '[monitor].[usp_GenerateDailyReport] @DebugMode = 1' }
        'Weekly' { '[monitor].[usp_GenerateWeeklyReport] @DebugMode = 1' }
    }

    try {
        $reportData = Invoke-DbaQuery -SqlInstance $SqlInstance -Database $Database -Query "EXEC $reportProc" -QueryTimeout 300
    }
    catch {
        Write-Log "Report procedure failed, falling back to view-based data: $($_.Exception.Message)" -Level Warning
        # Fallback to basic view
        $viewQuery = "SELECT * FROM [monitor].[vw_CurrentHealth]"
        $reportData = Invoke-DbaQuery -SqlInstance $SqlInstance -Database $Database -Query $viewQuery
    }

    # Get recommendations
    $recsPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'reports\recommendations_engine.sql'
    $recommendations = @()
    if (Test-Path $recsPath) {
        $recsSql = Get-Content -Path $recsPath -Raw
        $recommendations = Invoke-DbaQuery -SqlInstance $SqlInstance -Database $Database -Query $recsSql
    }

    # Build report data object
    $result = [PSCustomObject]@{
        ReportType      = $ReportType
        GeneratedAt     = Get-Date
        ServerInstance  = $SqlInstance.Name
        ReportData      = $reportData
        Recommendations = $recommendations
    }

    return $result
}

#endregion

# Export the main function
Export-ModuleMember -Function Invoke-SQLHealthMonitor
