#Requires -Version 5.1
<#
.SYNOPSIS
    Scenario tests for SQL Health Monitor installation and upgrade.

.DESCRIPTION
    Runs against a real SQL Server instance with SQL Agent. Credentials come
    from the SQLCMDUSER / SQLCMDPASSWORD environment variables, or from
    -SqlAuth / -Login / -Password. Nothing is hardcoded and no password ever
    appears on a command line.

    Isolation is not possible at the database level: 33 of the 35 SQL files
    hardcode the name SQLHealthMonitor, so every scenario operates on that one
    database and DROPs it between scenarios. Point this at a throwaway
    instance, not a monitored one.

    Requires the SQL Agent to be running -- install\04-create-jobs.sql calls
    sp_add_job. Use -SkipJobs to run the suite against an instance without it.

.EXAMPLE
    # Uses SQLCMDUSER / SQLCMDPASSWORD from the environment
    .\tests\Test-Install.ps1 -ServerInstance "localhost,1433"

.EXAMPLE
    # Instance without SQL Agent (Azure SQL Managed Instance, for example)
    .\tests\Test-Install.ps1 -ServerInstance "myserver.database.windows.net" -SkipJobs
#>
[CmdletBinding()]
param(
    [string]$ServerInstance = "",
    [string]$Database       = "SQLHealthMonitor",
    [switch]$SkipJobs,
    [switch]$SqlAuth,
    [string]$Login,
    [string]$Password
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path $PSScriptRoot -Parent

# ---- connection ---------------------------------------------------------------

$Sqlcmd = (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
if (-not $Sqlcmd) { throw "sqlcmd not found. Install SQL Server Command Line Utilities." }

if (-not $ServerInstance) {
    if ($env:SQLCMDSERVER) {
        $ServerInstance = $env:SQLCMDSERVER
    } else {
        $ServerInstance = "localhost,1433"
    }
}

if ($SqlAuth) {
    $env:SQLCMDSERVER = $ServerInstance
    $env:SQLCMDUSER   = $Login
    $env:SQLCMDPASSWORD = $Password
} elseif (-not $env:SQLCMDUSER) {
    throw @"
No SQL credentials available.

Set them once for the machine:
  setx SQLCMDSERVER "localhost,1433"
  setx SQLCMDUSER "sa"
  setx SQLCMDPASSWORD "<password>"

or pass -SqlAuth -Login <user> -Password <password>.
"@
}

# Never pass -E when SQLCMDUSER is set: it would override the variables and
# silently fail on a SQL-auth instance. -C is mandatory on sqlcmd 18.
$BaseArgs = @("-S", $ServerInstance, "-b", "-V", "1", "-C")

# ---- assertions ---------------------------------------------------------------

$script:Pass = 0
$script:Fail = 0
$script:Skip = 0
$script:Failures = @()

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ("$Expected" -eq "$Actual") {
        Write-Host "      PASS  $Message" -ForegroundColor DarkGreen
        $script:Pass++
    } else {
        Write-Host "      FAIL  $Message" -ForegroundColor Red
        Write-Host "            expected: [$Expected]" -ForegroundColor Red
        Write-Host "            actual  : [$Actual]" -ForegroundColor Red
        $script:Fail++
        $script:Failures += $Message
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    Assert-Equal -Expected $true -Actual $Condition -Message $Message
}

function Skip-Scenario {
    param([string]$Reason)
    Write-Host "      SKIP  $Reason" -ForegroundColor Yellow
    $script:Skip++
}

# ---- SQL execution ------------------------------------------------------------

function Invoke-Sql {
    <#
    .SYNOPSIS
        Runs a query or script file and returns trimmed output lines.
    .PARAMETER File
        Path to a .sql file, relative to the repo root. Mutually exclusive
        with -Query.
    .PARAMETER Vars
        sqlcmd -v variables, as name=value strings.
    #>
    param(
        [string]$Query,
        [string]$File,
        [string]$Db = 'master',
        [string[]]$Vars = @()
    )

    if (-not $Db) { $Db = $Database }

    $args = @($BaseArgs) + @('-h', '-1', '-W', '-d', $Db)
    foreach ($v in $Vars) { $args += @('-v', $v) }

    if ($File) { $args += @('-i', $File) } else { $args += @('-Q', $Query) }

    # sqlcmd resolves :r relative to the working directory, and several install
    # scripts use :r. Always run from the repo root.
    Push-Location $RepoRoot
    try {
        $out  = & $Sqlcmd @args 2>&1
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    if ($code -ne 0) {
        throw "sqlcmd failed (exit $code) on '$Db'.`n$($out | Out-String)"
    }

    # The leading comma stops PowerShell unrolling a single-row result into a
    # scalar string, where $rows[0] would then be the first *character*.
    return ,@($out | ForEach-Object { $_.ToString().Trim() } |
              Where-Object { $_ -ne '' -and $_ -notmatch '^\(\d+ rows? affected\)$' })
}

function Reset-TestDatabase {
    <#
    Drops the database so a scenario starts from nothing. The Agent jobs are
    dropped too: they outlive the database they point at, and a job whose
    database is gone errors on every schedule tick.
    #>
    param()

    if (-not $SkipJobs) {
        $jobs = Invoke-Sql -Db 'msdb' -Query "SELECT name FROM msdb.dbo.sysjobs WHERE name LIKE N'SQL Health Monitor%';"
        foreach ($j in $jobs) {
            # sp_delete_job is slow on this kind of instance -- do not parallelise.
            Invoke-Sql -Db 'msdb' -Query "EXEC msdb.dbo.sp_delete_job @job_name = N'$j', @delete_unused_schedule = 1;" | Out-Null
        }
    }

    Invoke-Sql -Query @"
IF DB_ID(N'$Database') IS NOT NULL
BEGIN
    ALTER DATABASE [$Database] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$Database];
END
"@ | Out-Null
}

function Invoke-Install {
    <#
    Runs deploy\Install.ps1 as a child process and captures its exit code.
    #>
    param([string[]]$ExtraArgs = @())

    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                (Join-Path $RepoRoot 'deploy\Install.ps1'),
                '-ServerInstance', $ServerInstance,
                '-Database', $Database)
    if ($SkipJobs)   { $psArgs += '-SkipJobs' }
    if ($SqlAuth)    { $psArgs += @('-SqlAuth', '-Login', $Login, '-Password', $Password) }
    $psArgs += $ExtraArgs

    $out = & powershell @psArgs 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($out | Out-String) }
}

# ---- runner -------------------------------------------------------------------

function Invoke-Scenario {
    param([string]$Name, [scriptblock]$Body)
    Write-Host ""
    Write-Host "  [$Name]" -ForegroundColor Cyan
    try { & $Body } catch {
        Write-Host "      ERROR $($_.Exception.Message)" -ForegroundColor Red
        $script:Fail++
        $script:Failures += "$Name threw"
    }
}

$repoVersion = (Get-Content (Join-Path $RepoRoot 'VERSION') -Raw).Trim()

try {
    Write-Host ""
    Write-Host "SQL Health Monitor - Install Tests" -ForegroundColor Cyan
    Write-Host "  Instance : $ServerInstance" -ForegroundColor Cyan
    Write-Host "  Database : $Database   (will be DROPPED between scenarios)" -ForegroundColor Cyan
    Write-Host "  VERSION  : $repoVersion" -ForegroundColor Cyan
    Write-Host "  Jobs     : $(if ($SkipJobs) { 'skipped' } else { 'included -- needs SQL Agent' })"

    Invoke-Scenario 'Harness self-check' {
        Reset-TestDatabase
        $r = Invoke-Sql -Query "SELECT 42"
        Assert-Equal -Expected '42' -Actual $r[0] -Message 'Invoke-Sql returns query output'
    }

    Invoke-Scenario '00-create-schema provides the version tracking objects' {
        Reset-TestDatabase
        Invoke-Sql -File 'install\00-create-schema.sql' | Out-Null

        $t = Invoke-Sql -Query @"
SELECT COUNT(*) FROM $Database.sys.objects
WHERE name IN ('SchemaVersion','AppliedMigrations','fn_GetInstalledVersion');
"@
        Assert-Equal -Expected '3' -Actual $t[0] -Message 'SchemaVersion, AppliedMigrations and fn_GetInstalledVersion all created'

        # ISNULL makes the result unambiguous: sqlcmd renders a bare NULL as
        # the literal text "NULL", which is indistinguishable from a real
        # version string of that value.
        $v = Invoke-Sql -Db $Database -Query @"
SELECT ISNULL([$Database].[monitor].[fn_GetInstalledVersion](), 'NOT_SET');
"@
        Assert-Equal -Expected 'NOT_SET' -Actual $v[0] -Message 'fn_GetInstalledVersion is NULL before any install'
    }

    # Scenarios for -Mode, upgrades, migrations and job schedules are added by
    # the tasks that implement them. A scenario that cannot pass yet is worse
    # than no scenario: it trains you to ignore red.
}
finally {
    Write-Host ""
    $colour = if ($script:Fail -eq 0) { 'Green' } else { 'Red' }
    Write-Host "Results: $($script:Pass) passed, $($script:Fail) failed, $($script:Skip) skipped" -ForegroundColor $colour
    if ($script:Fail -gt 0) {
        Write-Host ""
        foreach ($f in $script:Failures) { Write-Host "  - $f" -ForegroundColor Red }
        exit 1
    }
}