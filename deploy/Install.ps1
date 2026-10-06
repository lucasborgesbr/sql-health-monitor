#Requires -Version 5.1
<#
.SYNOPSIS
    Installs or upgrades SQL Health Monitor on a SQL Server instance.

.DESCRIPTION
    All monitoring logic, scheduling and email delivery run inside SQL Server.

    -Mode Status   Read-only. Reports the installed version against the repo's
                   VERSION file, lists Agent jobs and schedules, pending
                   migrations and row counts. Writes nothing.
    -Mode Upgrade  Default. Runs the idempotent install chain plus any pending
                   migrations. Preserves collected data, operator configuration
                   and job schedules.
    -Mode Fresh    Stops the Agent jobs, drops the database, and installs from
                   scratch. Requires -Force.

    An upgrade preserves:
      - every collected metric and every alert
      - [monitor].[Settings] and [monitor].[Thresholds] values you changed
      - SQL Agent schedules you adjusted
    Procedures and views are updated in place; new columns are added; new
    defaults are inserted without overwriting yours.

.PARAMETER ServerInstance
    SQL Server instance (e.g. "localhost", "SERVER\INSTANCE", "SERVER,1433").
    Defaults to $env:SQLCMDSERVER, then localhost,1433.

.PARAMETER Database
    Target database name. Default: SQLHealthMonitor.

    33 of the 35 SQL files hardcode that name, so a custom name is NOT
    supported. Upgrade and Status will refuse rather than half-apply.

.PARAMETER Mode
    Status, Upgrade (default) or Fresh.

.PARAMETER Force
    Required by -Mode Fresh. Also permits a downgrade, which otherwise
    reverts procedure fixes silently.

.PARAMETER ResetSchedules
    Let the repository own the Agent job schedules again, discarding any
    schedule you adjusted by hand.

.PARAMETER SkipJobs
    Do not run install\04-create-jobs.sql. For instances without SQL Agent
    (Azure SQL Managed Instance) and for faster runs.

.PARAMETER AssumeVersion
    Version to record for an installation predating version tracking.
    Default: 1.0.0, the last release before this feature.

.PARAMETER BackupPath
    Directory for a BACKUP DATABASE taken before anything changes. If not
    supplied, row counts are still reported so a lost row is visible.

.PARAMETER SqlAuth
    Use SQL authentication explicitly. Without it, credentials are read from
    the SQLCMDUSER / SQLCMDPASSWORD environment variables when present.

.EXAMPLE
    .\Install.ps1 -ServerInstance "SQLSERVER01" -Mode Status
.EXAMPLE
    .\Install.ps1 -ServerInstance "SQLSERVER01"
.EXAMPLE
    .\Install.ps1 -ServerInstance "SQLSERVER01" -Mode Fresh -Force
#>
[CmdletBinding()]
param(
    [string]$ServerInstance,
    [string]$Database       = "SQLHealthMonitor",
    [ValidateSet('Status', 'Upgrade', 'Fresh')]
    [string]$Mode           = 'Upgrade',
    [switch]$Force,
    [switch]$ResetSchedules,
    [switch]$SkipJobs,
    [string]$AssumeVersion  = '1.0.0',
    [string]$BackupPath,
    [switch]$SqlAuth,
    [string]$Login,
    [string]$Password
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---- resolve connection --------------------------------------------------------

$Sqlcmd = (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
if (-not $Sqlcmd) {
    Write-Error "sqlcmd not found. Install SQL Server Command Line Utilities: https://aka.ms/sqlcmdinstall"
    exit 1
}

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

# No -E when SQLCMDUSER is set: it overrides the environment variables and
# fails on any SQL-auth instance. -C is mandatory on sqlcmd 18.
$BaseArgs = @('-S', $ServerInstance, '-b', '-V', '1', '-C')

$RepoRoot = Split-Path $PSScriptRoot -Parent

# ---- version helpers -----------------------------------------------------------

$VersionFile = Join-Path $RepoRoot 'VERSION'
if (-not (Test-Path $VersionFile)) {
    Write-Error "VERSION not found at $VersionFile. The repository is incomplete."
    exit 1
}
$RepoVersion = (Get-Content $VersionFile -Raw).Trim()

function Get-GitCommit {
    # $null outside a checkout, so a ZIP download still installs.
    try {
        if (-not (Test-Path (Join-Path $RepoRoot '.git'))) { return $null }
        $hash = & git -C $RepoRoot rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $hash) { return $null }
        return $hash.Trim()
    } catch { return $null }
}
$GitCommit = Get-GitCommit

function Compare-SemVer {
    # Returns -1 / 0 / 1 and never throws: an unparseable version falls back
    # to ordinal string comparison rather than crashing the install.
    param([string]$Left, [string]$Right)

    $rx = '^(\d+)\.(\d+)\.(\d+)(?:-(.+))?$'
    $l = [regex]::Match($Left, $rx); $r = [regex]::Match($Right, $rx)

    if (-not $l.Success -or -not $r.Success) {
        return [Math]::Sign([string]::Compare($Left, $Right, [System.StringComparison]::OrdinalIgnoreCase))
    }
    foreach ($i in 1..3) {
        $d = [int]$l.Groups[$i].Value - [int]$r.Groups[$i].Value
        if ($d -ne 0) { return [Math]::Sign($d) }
    }
    $lp = $l.Groups[4].Success; $rp = $r.Groups[4].Success
    if ($lp -and -not $rp) { return -1 }   # 1.2.0-rc1 sorts below 1.2.0
    if ($rp -and -not $lp) { return 1 }
    if ($lp -and $rp) {
        return [Math]::Sign([string]::Compare($l.Groups[4].Value, $r.Groups[4].Value, [System.StringComparison]::OrdinalIgnoreCase))
    }
    return 0
}

# ---- SQL helpers ---------------------------------------------------------------

function Invoke-Sql {
    param([string]$Query, [string]$Db = 'master')
    $out = & $Sqlcmd @BaseArgs -d $Db -h -1 -W -Q "SET NOCOUNT ON; $Query" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd failed on '$Db':`n$($out | Out-String)" }
    return ,@($out | ForEach-Object { $_.ToString().Trim() } |
              Where-Object { $_ -ne '' -and $_ -notmatch '^\(\d+ rows? affected\)$' })
}

function Test-DatabaseExists {
    $r = Invoke-Sql -Query "SELECT CAST(CASE WHEN DB_ID(N'$Database') IS NULL THEN 0 ELSE 1 END AS VARCHAR(1));"
    return ($r[0] -eq '1')
}

function Get-InstalledVersion {
    # $null when nothing is recorded: either no install yet, or one predating
    # version tracking. The two are told apart by the caller.
    if (-not (Test-DatabaseExists)) { return $null }
    $q = @"
IF OBJECT_ID('[monitor].[SchemaVersion]','U') IS NULL
    SELECT CAST(NULL AS VARCHAR(20));
ELSE
    SELECT [monitor].[fn_GetInstalledVersion]();
"@
    $r = Invoke-Sql -Query $q -Db $Database
    if (-not $r -or $r[0] -eq 'NULL' -or [string]::IsNullOrEmpty($r[0])) { return $null }
    return $r[0]
}

function Get-RowCounts {
    $result = @{}
    foreach ($t in 'CpuHistory','MemoryHistory','DiskHistory','AlertHistory','ErrorLogHistory','Incidents') {
        $exists = Invoke-Sql -Db $Database -Query "SELECT CAST(CASE WHEN OBJECT_ID('[monitor].[$t]','U') IS NULL THEN 0 ELSE 1 END AS VARCHAR(1));"
        if ($exists[0] -eq '1') {
            $c = Invoke-Sql -Db $Database -Query "SELECT CAST(COUNT_BIG(*) AS VARCHAR(20)) FROM [monitor].[$t];"
            $result[$t] = $c[0]
        }
    }
    return $result
}

function Get-PendingMigrations {
    param([string]$InstalledVersion)
    $dir = Join-Path $RepoRoot 'install\migrations'
    if (-not (Test-DatabaseExists)) { return @() }
    if (-not (Test-Path $dir)) { return @() }

    $pending = @()
    foreach ($f in Get-ChildItem $dir -Filter '*.sql' | Sort-Object Name) {
        $m = [regex]::Match($f.Name, '^V(\d+)_(\d+)_(\d+)__(.+)\.sql$')
        if (-not $m.Success) {
            Write-Warning "  Ignoring migration with unrecognised name: $($f.Name)"
            continue
        }
        $v = "$($m.Groups[1].Value).$($m.Groups[2].Value).$($m.Groups[3].Value)"
        if (-not $InstalledVersion) { continue }
        if ((Compare-SemVer $v $InstalledVersion) -le 0) { continue }

        $applied = Invoke-Sql -Db $Database -Query "SELECT CAST(COUNT(*) AS VARCHAR(10)) FROM [monitor].[AppliedMigrations] WHERE FileName = N'$($f.Name)';"
        if ($applied[0] -eq '0') {
            $pending += [pscustomobject]@{ File = $f.Name; Version = $v }
        }
    }
    return $pending
}

# ---- install chain --------------------------------------------------------------

$JobScript = 'install\04-create-jobs.sql'

$scripts = @(
    "install\00-create-schema.sql",
    "install\01-create-collectors.sql",
    "install\02-create-reports.sql",
    "install\03-create-alerts.sql",
    $JobScript,
    "install\05-configure.sql",
    "install\06-alert-history.sql",
    "install\07-baselines.sql",
    "install\08-extended-schema.sql",
    "install\09-uptime-tracker.sql",
    "install\10-phase1-3-schema.sql",
    "collectors\collect_cpu.sql",
    "collectors\collect_memory.sql",
    "collectors\collect_disk.sql",
    "collectors\collect_waits.sql",
    "collectors\collect_blocking.sql",
    "collectors\collect_deadlocks.sql",
    "collectors\collect_ag_health.sql",
    "collectors\collect_cdc_health.sql",
    "collectors\collect_top_queries.sql",
    "collectors\collect_index_health.sql",
    "collectors\collect_backup_status.sql",
    "collectors\collect_job_history.sql",
    "collectors\collect_tempdb.sql",
    "collectors\collect_log_growth.sql",
    "collectors\collect_database_growth.sql",
    "collectors\collect_errorlog.sql",
    "collectors\collect_uptime_tracker.sql",
    "collectors\collect_live_sessions.sql",
    "collectors\collect_query_store.sql",
    "collectors\collect_index_recommendations.sql",
    "reports\html_builder_daily.sql",
    "reports\html_builder_weekly.sql",
    "reports\daily_health_check.sql",
    "reports\weekly_deep_dive.sql",
    "reports\recommendations_engine.sql",
    "alerts\alert_engine.sql",
    "alerts\alert_actions.sql",
    "baselines\capture_baseline.sql",
    "baselines\detect_anomalies.sql",
    "maintenance\purge_old_data.sql",
    "maintenance\update_baselines.sql",
    "views\vw_CurrentHealth.sql",
    "views\vw_UptimeTracker.sql",
    "install\99-record-version.sql"
)

if ($SkipJobs) { $scripts = $scripts | Where-Object { $_ -ne $JobScript } }

# ---- header ----------------------------------------------------------------------

$commitText = if ($GitCommit) { "$RepoVersion ($GitCommit)" } else { "$RepoVersion (no git)" }
Write-Host ""
Write-Host "SQL Health Monitor - $Mode" -ForegroundColor Cyan
Write-Host "  Instance : $ServerInstance"
Write-Host "  Database : $Database"
Write-Host "  Release  : $commitText"
Write-Host "  Jobs     : $(if ($SkipJobs) { 'skipped' } else { 'included' })"
Write-Host ""

# ---- Status -----------------------------------------------------------------------

$dbExists = Test-DatabaseExists
$installedVersion = Get-InstalledVersion

if ($Mode -eq 'Status') {
    if (-not $dbExists) {
        Write-Host "  Installed: nothing -- database '$Database' does not exist." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  To install it:"
        Write-Host "    .\Install.ps1 -Mode Fresh -Force"
        exit 0
    }

    $shown = if ($installedVersion) { $installedVersion }
             else { 'unknown (predates version tracking)' }
    Write-Host "  Installed: $shown" -ForegroundColor Cyan
    Write-Host "  Release  : $commitText"
    $cmp = if ($installedVersion) { Compare-SemVer $RepoVersion $installedVersion } else { 0 }
    if ($cmp -gt 0) { Write-Host "  Upgrade available: $installedVersion -> $RepoVersion" -ForegroundColor Yellow }
    elseif ($cmp -eq 0 -and $installedVersion) { Write-Host "  Up to date." -ForegroundColor Green }
    elseif ($cmp -lt 0) { Write-Host "  This checkout is OLDER than what is installed." -ForegroundColor Red }

    Write-Host ""
    Write-Host "  Collected rows:" -ForegroundColor Cyan
    $rows = Get-RowCounts
    if ($rows.Count -eq 0) { Write-Host "    (no monitoring tables found)" }
    foreach ($k in ($rows.Keys | Sort-Object)) { Write-Host ("    {0,-18} {1}" -f $k, $rows[$k]) }

    $pending = @(Get-PendingMigrations -InstalledVersion $installedVersion)
    Write-Host ""
    if ($pending.Count -gt 0) {
        Write-Host "  Pending migrations:" -ForegroundColor Yellow
        foreach ($p in $pending) { Write-Host "    $($p.Version)  $($p.File)" }
    } else {
        Write-Host "  Pending migrations: none"
    }

    if (-not $SkipJobs) {
        Write-Host ""
        Write-Host "  Agent jobs:" -ForegroundColor Cyan
        try {
            $jobs = @(Invoke-Sql -Db 'msdb' -Query @"
SELECT j.name, j.enabled
FROM msdb.dbo.sysjobs j
WHERE j.name LIKE N'SQL Health Monitor%'
ORDER BY j.name;
"@)
            if ($jobs.Count -eq 0) { Write-Host "    (none)" }
            foreach ($j in $jobs) { Write-Host "    $j" }
        } catch {
            Write-Host "    could not read msdb: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    if ($Database -ne 'SQLHealthMonitor') {
        Write-Warning "Most SQL files hardcode 'SQLHealthMonitor'. A custom database name is not supported."
    }
    Write-Host ""
    exit 0
}

# ---- Fresh -------------------------------------------------------------------------

if ($Mode -eq 'Fresh') {
    if (-not $Force) {
        Write-Error "-Mode Fresh deletes all collected data, configuration and Agent jobs, and requires -Force. Nothing was changed."
        exit 1
    }

    # Stop the jobs BEFORE dropping the database. Left running, they fire
    # against a database that is being recreated and fill ErrorLogHistory with
    # "could not find stored procedure" for every collector.
    if (-not $SkipJobs -and (Test-DatabaseExists)) {
        Write-Host "  Stopping Agent jobs..." -ForegroundColor Yellow
        foreach ($j in @(Invoke-Sql -Db 'msdb' -Query "SELECT name FROM msdb.dbo.sysjobs WHERE name LIKE N'SQL Health Monitor%';")) {
            Invoke-Sql -Db 'msdb' -Query "EXEC msdb.dbo.sp_update_job @job_name = N'$j', @enabled = 0;" | Out-Null
        }
    }
    if (-not $SkipJobs) {
        foreach ($j in (Invoke-Sql -Db 'msdb' -Query "SELECT name FROM msdb.dbo.sysjobs WHERE name LIKE N'SQL Health Monitor%';")) {
            Invoke-Sql -Db 'msdb' -Query "EXEC msdb.dbo.sp_delete_job @job_name = N'$j', @delete_unused_schedule = 1;" | Out-Null
        }
    }

    if (Test-DatabaseExists) {
        Write-Host "  Dropping database $Database..." -ForegroundColor Yellow
        Invoke-Sql -Query @"
ALTER DATABASE [$Database] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE [$Database];
"@ | Out-Null
    }
    $installedVersion = $null
    $dbExists = $false
}

# ---- Upgrade preconditions -----------------------------------------------------------

if ($Mode -eq 'Upgrade') {
    if (-not (Test-DatabaseExists)) {
        # One call, not two: under $ErrorActionPreference = 'Stop' the first
        # Write-Error terminates the script and the guidance never reaches the
        # operator.
        Write-Error "Database '$Database' does not exist. Run: .\Install.ps1 -Mode Fresh -Force"
        exit 1
    }

    if (-not $installedVersion) {
        Write-Warning "No version recorded. This installation predates version tracking."
        Write-Warning "Recording it as $AssumeVersion. Override with -AssumeVersion if that is not what is installed."
        $installedVersion = $AssumeVersion
    }

    $cmp = Compare-SemVer $RepoVersion $installedVersion
    if ($cmp -lt 0) {
        if (-not $Force) {
            Write-Error "This checkout is version $RepoVersion but the database has $installedVersion. Downgrading reverts procedure fixes without warning -- switch to the matching tag (git checkout v$installedVersion), or pass -Force."
            exit 1
        }
        Write-Warning "Downgrading $installedVersion -> $RepoVersion because -Force was supplied."
    } elseif ($cmp -eq 0) {
        Write-Host "  Already at $RepoVersion; re-running for idempotency." -ForegroundColor DarkGray
    } else {
        Write-Host "  Upgrading $installedVersion -> $RepoVersion" -ForegroundColor Green
    }

    if ($Database -ne 'SQLHealthMonitor') {
        Write-Warning "Most SQL files hardcode 'SQLHealthMonitor'. A custom database name is not supported in Upgrade mode."
    }
}

# ---- optional backup ------------------------------------------------------------------

if ($Mode -ne 'Fresh' -and $BackupPath) {
    if (-not (Test-Path $BackupPath)) {
        Write-Error "BackupPath '$BackupPath' does not exist. Nothing was changed."
        exit 1
    }
    $bak = Join-Path $BackupPath ("{0}_pre{1}_{2}.bak" -f $Database, $RepoVersion, (Get-Date -Format yyyyMMddHHmmss))
    Write-Host "  Backing up $Database to $bak ..." -ForegroundColor Yellow
    try {
        Invoke-Sql -Query "BACKUP DATABASE [$Database] TO DISK = N'$bak' WITH INIT, COMPRESSION;" | Out-Null
    } catch {
        Write-Error "Backup failed, so nothing was changed. Fix the backup and retry. $($_.Exception.Message)"
        exit 1
    }
}

# In Fresh the database was just dropped, so there is nothing to count yet.
$before = if (Test-DatabaseExists) { Get-RowCounts } else { @{} }

# ---- run the chain ----------------------------------------------------------------------

$total   = $scripts.Count
$current = 0

# sqlcmd resolves :r paths relative to the working directory and several
# install scripts use :r, so always run from the repo root.
Push-Location $RepoRoot
try {
    foreach ($rel in $scripts) {
        $current++
        $path = Join-Path $RepoRoot $rel

        if (-not (Test-Path $path)) {
            Write-Warning "  [$current/$total] SKIP (not found): $rel"
            continue
        }

        Write-Host "  [$current/$total] $rel" -NoNewline

        # 00-create-schema.sql creates the database, so it must run against master.
        $dbArg = if ($rel -eq 'install\00-create-schema.sql') { 'master' } else { $Database }

        $args = @($BaseArgs) + @('-d', $dbArg)
        foreach ($v in @(
            "ResetSchedules=$(if ($ResetSchedules) { 1 } else { 0 })",
            "Version=$RepoVersion",
            "Mode=$Mode",
            "Commit=$GitCommit"
        )) { $args += @('-v', $v) }
        $args += @('-i', $path)

        $out = & $Sqlcmd @args 2>&1
        $rc  = $LASTEXITCODE

        if ($rc -ne 0) {
            Write-Host " FAILED" -ForegroundColor Red
            Write-Host ($out | Out-String) -ForegroundColor Red
            Write-Host ""
            Write-Host "Deployment stopped at script $current of ${total}: $rel" -ForegroundColor Red
            Write-Host "The scripts after this one did NOT run, so anything they create is missing." -ForegroundColor Red
            Write-Host "Fix the cause above and re-run; the chain is idempotent." -ForegroundColor Red
            Pop-Location
            exit 1
        }
        Write-Host " OK" -ForegroundColor Green
    }
}
finally {
    Pop-Location
}

# ---- migrations --------------------------------------------------------------------

$pending = @(Get-PendingMigrations -InstalledVersion $installedVersion)
if ($pending.Count -gt 0) {
    Write-Host ""
    Write-Host "  Applying $($pending.Count) migration(s):" -ForegroundColor Cyan
    Push-Location $RepoRoot
    try {
        foreach ($p in $pending) {
            Write-Host "  $($p.File)" -NoNewline
            $out = & $Sqlcmd @BaseArgs -d $Database -v "Version=$($p.Version)" `
                            -i (Join-Path $RepoRoot "install\migrations\$($p.File)") 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host " FAILED" -ForegroundColor Red
                Write-Host ($out | Out-String) -ForegroundColor Red
                Pop-Location
                Write-Host ""
                Write-Host "Migration '$($p.File)' failed. The installed version was NOT advanced." -ForegroundColor Red
                exit 1
            }
            Write-Host " OK" -ForegroundColor Green
            Invoke-Sql -Db $Database -Query "INSERT INTO [monitor].[AppliedMigrations] (FileName, Version) VALUES (N'$($p.File)', N'$($p.Version)');" | Out-Null
        }
    }
    finally { Pop-Location }
}

# ---- report ---------------------------------------------------------------------------

Write-Host ""
Write-Host "  Data check:" -ForegroundColor Cyan
if (-not $before -or $before.Count -eq 0) {
    Write-Host "    (nothing to compare -- this was a fresh install)"
} else {
    $after = Get-RowCounts
    foreach ($k in ($before.Keys | Sort-Object)) {
        $b = $before[$k]
        $a = if ($after.ContainsKey($k)) { $after[$k] } else { '0' }
        $lost = ([long]$a -lt [long]$b)
        $mark = if ($lost) { ' <-- rows lost' } else { '' }
        Write-Host ("    {0,-18} {1,10} -> {2,10}{3}" -f $k, $b, $a, $mark)
        if ($lost) {
            Write-Error "Row count dropped for $k. Investigate before trusting this deployment."
        }
    }
}

Write-Host ""
if ($Mode -eq 'Fresh') {
    Write-Host "Installation complete at $RepoVersion." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Configure Database Mail if not already done (deploy\Configure-Mail.ps1)"
    Write-Host "  2. Point the report at your profile:"
    Write-Host "       UPDATE [monitor].[Settings] SET SettingValue = '<profile>'"
    Write-Host "       WHERE Category = 'Email' AND SettingName = 'ProfileName';"
    Write-Host "  3. Test: EXEC [monitor].[usp_RunReport] @ReportType = 'Daily', @DebugMode = 1;"
} else {
    Write-Host "Upgrade complete at $RepoVersion." -ForegroundColor Green
    Write-Host "  Check any time with: .\Install.ps1 -Mode Status"
}
Write-Host ""