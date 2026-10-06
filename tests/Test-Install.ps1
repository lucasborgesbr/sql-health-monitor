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

function Remove-Column {
    <#
    Drops a column the way an older installation would not have it.

    A default constraint blocks DROP COLUMN outright, so any constraint the
    column carries is removed first. Doing it here rather than by choosing a
    column that happens to have no DEFAULT keeps the test from breaking the
    next time someone adds one.
    #>
    param([string]$Table, [string]$Column)

    Invoke-Sql -Db $Database -Query @"
DECLARE @df NVARCHAR(400) = (
    SELECT QUOTENAME(dc.name)
    FROM sys.default_constraints dc
    JOIN sys.columns c ON c.object_id = dc.parent_object_id
                     AND c.column_id  = dc.parent_column_id
    WHERE dc.parent_object_id = OBJECT_ID(N'[monitor].[$Table]')
      AND c.name = N'$Column');
IF @df IS NOT NULL
    EXEC(N'ALTER TABLE [monitor].[$Table] DROP CONSTRAINT ' + @df);
ALTER TABLE [monitor].[$Table] DROP COLUMN [$Column];
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

    # Several scenarios assert that Install.ps1 *refuses* something, and it
    # reports refusals with Write-Error -- which goes to stderr. Under
    # $ErrorActionPreference = 'Stop' a native command's stderr would abort
    # this script before the assertion could run, so relax it for the call and
    # judge the outcome by the exit code instead.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out  = & powershell @psArgs 2>&1 | ForEach-Object { $_.ToString() }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }

    return [pscustomobject]@{ ExitCode = $code; Output = ($out -join "`n") }
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

    Invoke-Scenario '99-record-version is idempotent and refreshes LastVerifiedAt' {
        Invoke-Sql -File 'install\00-create-schema.sql' | Out-Null

        Invoke-Sql -Db $Database -File 'install\99-record-version.sql' `
                   -Vars @('Version=1.1.0', 'Mode=Fresh', 'Commit=abc1234') | Out-Null

        $v = Invoke-Sql -Db $Database -Query "SELECT [$Database].[monitor].[fn_GetInstalledVersion]();"
        Assert-Equal -Expected '1.1.0' -Actual $v[0] -Message 'version recorded'

        $n = Invoke-Sql -Db $Database -Query "SELECT CAST(COUNT(*) AS VARCHAR(10)) FROM [$Database].[monitor].[SchemaVersion];"
        Assert-Equal -Expected '1' -Actual $n[0] -Message 'exactly one row after first record'

        $c = Invoke-Sql -Db $Database -Query "SELECT CommitHash FROM [$Database].[monitor].[SchemaVersion] WHERE Version = '1.1.0';"
        Assert-Equal -Expected 'abc1234' -Actual $c[0] -Message 'CommitHash stored'

        # Re-running the same version must not add a row, but must refresh
        # LastVerifiedAt -- that is how Status answers "did my upgrade apply?".
        Invoke-Sql -Db $Database -Query "UPDATE [$Database].[monitor].[SchemaVersion] SET LastVerifiedAt = NULL;" | Out-Null
        Invoke-Sql -Db $Database -File 'install\99-record-version.sql' `
                   -Vars @('Version=1.1.0', 'Mode=Upgrade', 'Commit=abc1234') | Out-Null

        $n2 = Invoke-Sql -Db $Database -Query "SELECT CAST(COUNT(*) AS VARCHAR(10)) FROM [$Database].[monitor].[SchemaVersion];"
        Assert-Equal -Expected '1' -Actual $n2[0] -Message 're-running the same version adds no row'

        $lv = Invoke-Sql -Db $Database -Query @"
SELECT CASE WHEN LastVerifiedAt IS NULL THEN 'NULL' ELSE 'SET' END
FROM [$Database].[monitor].[SchemaVersion] WHERE Version = '1.1.0';
"@
        Assert-Equal -Expected 'SET' -Actual $lv[0] -Message 'LastVerifiedAt refreshed on re-run'
    }

    Invoke-Scenario 'Recording a new version carries PreviousVersion' {
        Invoke-Sql -Db $Database -File 'install\99-record-version.sql' `
                   -Vars @('Version=1.2.0', 'Mode=Upgrade', 'Commit=deadbee') | Out-Null

        $p = Invoke-Sql -Db $Database -Query "SELECT PreviousVersion FROM [$Database].[monitor].[SchemaVersion] WHERE Version = '1.2.0';"
        Assert-Equal -Expected '1.1.0' -Actual $p[0] -Message 'PreviousVersion records where the upgrade came from'
    }

    Invoke-Scenario 'Upgrade records the repo version' {
        Reset-TestDatabase
        $f = Invoke-Install @('-Mode', 'Fresh', '-Force')
        Assert-Equal -Expected 0 -Actual $f.ExitCode -Message "Fresh install succeeds. Output:`n$($f.Output)"

        $v = Invoke-Sql -Db $Database -Query "SELECT [$Database].[monitor].[fn_GetInstalledVersion]();"
        Assert-Equal -Expected $repoVersion -Actual $v[0] -Message 'installed version matches the VERSION file'

        $mode = Invoke-Sql -Db $Database -Query "SELECT TOP 1 InstallMode FROM [$Database].[monitor].[SchemaVersion];"
        Assert-Equal -Expected 'Fresh' -Actual $mode[0] -Message 'recorded as a Fresh install'
    }

    Invoke-Scenario 'Upgrade preserves operator configuration' {
        Invoke-Sql -Db $Database -Query @"
UPDATE [$Database].[monitor].[Settings] SET SettingValue = 'sentinel@corp.example'
WHERE Category = 'Email' AND SettingName = 'Recipients';
UPDATE [$Database].[monitor].[Settings] SET SettingValue = 'ptbr'
WHERE Category = 'General' AND SettingName = 'Language';
UPDATE [$Database].[monitor].[Thresholds] SET WarningValue = 42
WHERE MetricName = 'CPU_SqlPct';
"@ | Out-Null

        $u = Invoke-Install @('-Mode', 'Upgrade')
        Assert-Equal -Expected 0 -Actual $u.ExitCode -Message "Upgrade succeeds. Output:`n$($u.Output)"

        $r = Invoke-Sql -Db $Database -Query "SELECT SettingValue FROM [$Database].[monitor].[Settings] WHERE Category='Email' AND SettingName='Recipients';"
        Assert-Equal -Expected 'sentinel@corp.example' -Actual $r[0] -Message 'Email.Recipients survived the upgrade'

        $l = Invoke-Sql -Db $Database -Query "SELECT SettingValue FROM [$Database].[monitor].[Settings] WHERE Category='General' AND SettingName='Language';"
        Assert-Equal -Expected 'ptbr' -Actual $l[0] -Message 'General.Language survived the upgrade'

        $t = Invoke-Sql -Db $Database -Query "SELECT WarningValue FROM [$Database].[monitor].[Thresholds] WHERE MetricName='CPU_SqlPct';"
        Assert-Equal -Expected '42.00' -Actual $t[0] -Message 'tuned threshold survived the upgrade'
    }

    Invoke-Scenario 'Upgrade inserts missing defaults but leaves present ones alone' {
        Invoke-Sql -Db $Database -Query "DELETE FROM [$Database].[monitor].[Settings] WHERE Category='General' AND SettingName='ServerName';" | Out-Null

        $u = Invoke-Install @('-Mode', 'Upgrade')
        Assert-Equal -Expected 0 -Actual $u.ExitCode -Message "Upgrade succeeds. Output:`n$($u.Output)"

        $s = Invoke-Sql -Db $Database -Query "SELECT CAST(COUNT(*) AS VARCHAR(10)) FROM [$Database].[monitor].[Settings] WHERE Category='General' AND SettingName='ServerName';"
        Assert-Equal -Expected '1' -Actual $s[0] -Message 'a missing default is re-inserted'

        # Languages are repo-owned: a stale translation must be corrected.
        Invoke-Sql -Db $Database -Query @"
UPDATE [$Database].[monitor].[Languages] SET StringValue = 'stale text'
WHERE LanguageCode='en' AND StringKey='report.daily.title';
"@ | Out-Null
        $null = Invoke-Install @('-Mode', 'Upgrade')

        $g = Invoke-Sql -Db $Database -Query "SELECT StringValue FROM [$Database].[monitor].[Languages] WHERE LanguageCode='en' AND StringKey='report.daily.title';"
        Assert-Equal -Expected 'Daily SQL Health Report' -Actual $g[0] -Message 'stale translation corrected on upgrade'
    }

    Invoke-Scenario 'Upgrade refuses a downgrade unless -Force is given' {
        Invoke-Sql -Db $Database -Query "DELETE FROM [$Database].[monitor].[SchemaVersion];" | Out-Null
        Invoke-Sql -Db $Database -File 'install\99-record-version.sql' `
                   -Vars @('Version=99.0.0', 'Mode=Fresh', 'Commit=x') | Out-Null

        $d = Invoke-Install @('-Mode', 'Upgrade')
        Assert-Equal -Expected 1 -Actual $d.ExitCode -Message 'downgrade refused, exit 1'
        Assert-True -Condition ($d.Output -match '99\.0\.0') -Message 'refusal names the installed version'

        $v = Invoke-Sql -Db $Database -Query "SELECT [$Database].[monitor].[fn_GetInstalledVersion]();"
        Assert-Equal -Expected '99.0.0' -Actual $v[0] -Message 'installed version untouched by the refusal'
    }

    Invoke-Scenario 'Upgrade refuses to run against a database that does not exist' {
        Reset-TestDatabase
        $u = Invoke-Install @('-Mode', 'Upgrade')
        Assert-Equal -Expected 1 -Actual $u.ExitCode -Message 'no silent fallback to Fresh'
        Assert-True -Condition ($u.Output -match 'Fresh') -Message 'points the operator at -Mode Fresh'
    }

    Invoke-Scenario 'Fresh requires -Force' {
        Reset-TestDatabase
        $null = Invoke-Install @('-Mode', 'Fresh', '-Force')
        $f = Invoke-Install @('-Mode', 'Fresh')
        Assert-Equal -Expected 1 -Actual $f.ExitCode -Message 'Fresh without -Force is refused'
        Assert-True -Condition ($f.Output -match 'Force') -Message 'the message names -Force'
    }

    Invoke-Scenario 'Re-running 00 restores a column an older install would not have' {
        Reset-TestDatabase
        Invoke-Sql -File 'install\00-create-schema.sql' | Out-Null

        # The exact situation the IF OBJECT_ID guard creates: the table exists,
        # so the whole CREATE TABLE is skipped and its shape never changes.
        Remove-Column -Table 'MemoryHistory' -Column 'MemoryGrantsPending'
        # sqlcmd renders a bare NULL as the literal text "NULL", so ISNULL makes
        # the result unambiguous instead of comparing against emptiness.
        $before = Invoke-Sql -Db $Database -Query "SELECT ISNULL(CAST(COL_LENGTH('monitor.MemoryHistory','MemoryGrantsPending') AS VARCHAR(10)), 'ABSENT');"
        Assert-Equal -Expected 'ABSENT' -Actual $before[0] -Message 'column absent before the re-run'

        Invoke-Sql -File 'install\00-create-schema.sql' | Out-Null

        $after = Invoke-Sql -Db $Database -Query "SELECT COL_LENGTH('monitor.MemoryHistory','MemoryGrantsPending');"
        Assert-True -Condition (-not [string]::IsNullOrEmpty($after[0])) -Message 'column restored on re-run'
    }

    Invoke-Scenario 'Re-running 00 restores a computed column' {
        # HoursSinceLastBackup is AS DATEDIFF(...) -- COL_LENGTH does not probe
        # computed columns, so this needs sys.computed_columns.
        Remove-Column -Table 'BackupHistory' -Column 'HoursSinceLastBackup'

        Invoke-Sql -File 'install\00-create-schema.sql' | Out-Null

        $c = Invoke-Sql -Db $Database -Query @"
SELECT CAST(COUNT(*) AS VARCHAR(10)) FROM [$Database].sys.computed_columns
WHERE object_id = OBJECT_ID('monitor.BackupHistory') AND name = 'HoursSinceLastBackup';
"@
        Assert-Equal -Expected '1' -Actual $c[0] -Message 'computed column restored'
    }

    Invoke-Scenario 'Re-running 08-extended-schema adds missing columns' {
        Invoke-Sql -Db $Database -File 'install\08-extended-schema.sql' | Out-Null
        Remove-Column -Table 'TempDbObjectUsage' -Column 'ObjectName'

        Invoke-Sql -Db $Database -File 'install\08-extended-schema.sql' | Out-Null

        $c = Invoke-Sql -Db $Database -Query "SELECT COL_LENGTH('monitor.TempDbObjectUsage','ObjectName');"
        Assert-True -Condition (-not [string]::IsNullOrEmpty($c[0])) -Message 'extended-schema column restored'
    }

    # Scenarios for migrations and job schedules are added by the tasks that
    # implement them. A scenario that cannot pass yet is worse than no
    # scenario: it trains you to ignore red.
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