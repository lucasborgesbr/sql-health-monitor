# Install Version Tracking & Idempotent Upgrade — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `deploy/Install.ps1` able to upgrade an existing install in place — preserving data, operator configuration and SQL Agent schedules — while recording which version is installed on each server.

**Architecture:** Two tracking tables (`SchemaVersion`, `AppliedMigrations`) plus a `VERSION` file at repo root form the source of truth. Every script in the chain becomes preservation-safe rather than create-only: columns reconcile via `COL_LENGTH`, config inserts via `MERGE` that never overwrites, Agent jobs update steps but never schedules. `Install.ps1` gains `-Mode Status|Upgrade|Fresh`; genuinely non-idempotent changes go in a new `install/migrations/` folder.

**Tech Stack:** T-SQL (SQL Server 2016+), PowerShell 5.1, `sqlcmd`, LocalDB for tests.

**Spec:** `docs/superpowers/specs/2026-10-05-install-versioning-design.md`

## Global Constraints

- **Version is `1.1.0`.** Not `1.0.1` — the bootstrap test depends on installed `1.0.0` ≠ repo `1.1.0` being distinguishable.
- **Compatibility floor: SQL Server 2016.** No `DROP IF EXISTS`, no `CREATE OR ALTER` in plain batches (use the repo's existing placeholder+`ALTER` pattern instead), no `MERGE` features beyond SQL 2008.
- **Repository convention for procedures and views:** guard with `IF OBJECT_ID(...) IS NOT NULL EXEC('ALTER ... AS <placeholder>')`, then `IF OBJECT_ID(...) IS NULL EXEC('CREATE ... AS <placeholder>')`, then the real `ALTER`. Follow it verbatim for new functions.
- **`sqlcmd` resolves `:r` paths relative to CWD.** Every invocation must `Push-Location` to the repo root. This is already documented in commit `a6d39a2`.
- **Database name is hardcoded `SQLHealthMonitor` in 33 of 35 files.** Only `install/00-create-schema.sql`, `install/04-create-jobs.sql` and `install/10-record-version.sql` receive `:setvar DatabaseName`. Do not widen this in this plan.
- **`-SkipJobs` is required** (not optional scope creep): LocalDB has no SQL Agent so the tests cannot run `04-create-jobs.sql`, and Azure SQL Managed Instance has none either.
- **Every PowerShell script starts with `Set-StrictMode -Version Latest` and `$ErrorActionPreference = "Stop"`.**
- **Every PowerShell script that calls `sqlcmd` passes `-b`** so a script failure produces a non-zero exit code.

## Review Focus

Five input/failure classes the spec implies but no stated test covers. Each is pinned to a task below.

1. **Pre-release version string (`VERSION` = `1.2.0-rc1`).** `[version]::Parse("1.2.0-rc1")` throws in PowerShell. A naive semver comparison in `Install.ps1` crashes on pre-releases. → Task 8.
2. **No `.git` directory** (user downloaded a GitHub ZIP). `git rev-parse --short HEAD` fails. `CommitHash` must be `NULL`, install must succeed. → Task 8.
3. **Chain fails halfway** (e.g. `07-baselines.sql` errors). `LastVerifiedAt` must not advance and no new `SchemaVersion` row may appear, so `Status` still reports the previous version. → Task 3.
4. **`BACKUP DATABASE` fails** (database busy, or path unwritable). Upgrade must abort *before* touching any object, not continue with the chain. → Task 8.
5. **Table exists but was created by an older release missing a column** — the exact situation `IF OBJECT_ID IS NULL` silently drops. → Task 5.

---

## File Structure

| File | Responsibility |
|---|---|
| `VERSION` | Single semver string. Read by `Install.ps1` and by tests. |
| `install/00-create-schema.sql` | Creates `SchemaVersion`, `AppliedMigrations`, `fn_GetInstalledVersion`; reconciles columns on its 20 tables. |
| `install/10-record-version.sql` | Idempotently records the version just deployed. Runs last. |
| `install/migrations/V<major>_<minor>_<patch>__<desc>.sql` | Non-idempotent changes only. Applied in ascending version order. |
| `install/migrations/README.md` | The rule for when a change belongs here vs. in the idempotent chain. |
| `install/04-create-jobs.sql` | Creates jobs if absent; updates steps if present; never touches schedules unless reset. |
| `install/05-configure.sql` | `MERGE` × 3. Insert-only for `Settings`/`Thresholds`; upsert for `Languages`. |
| `install/08-extended-schema.sql` | Column reconciliation for its 11 tables. |
| `deploy/Install.ps1` | `-Mode Status\|Upgrade\|Fresh`, bootstrap, downgrade guard, backup, row counts. |
| `deploy/Uninstall.ps1` | Drops jobs + database; consistent with the modes above. |
| `validate_installation.sql` | Extended with version and expected-object checks. |
| `tests/Test-Install.ps1` | LocalDB-backed scenario runner. Tasks 1 and 10 own it. |

---

## Task 1: Test harness and VERSION file

**Files:**
- Create: `VERSION`
- Create: `tests/Test-Install.ps1`

**Interfaces:**
- Consumes: nothing.
- Produces: `tests/Test-Install.ps1` exporting `Invoke-Sql`, `Assert-Equal`, `Assert-True`, `Reset-TestDatabase`, `Get-RepoRoot`. Tasks 2–10 call these.

- [ ] **Step 1: Create `VERSION`**

Single line, no trailing spaces:

```
1.1.0
```

- [ ] **Step 2: Write the harness**

`tests/Test-Install.ps1`:

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Scenario tests for SQL Health Monitor installation and upgrade.
.DESCRIPTION
    Uses a dedicated LocalDB instance for isolation. The database inside it is
    named SQLHealthMonitor because 33 of 35 SQL files hardcode that name
    (see spec section 9) -- isolation comes from the instance name, not the
    database name.

    Scenarios requiring SQL Agent (job schedules) are SKIPPED unless
    -ServerInstance is supplied, because LocalDB has no SQL Agent.
#>
[CmdletBinding()]
param(
    # Real instance for job scenarios. Omit to skip them.
    [string]$ServerInstance,

    [switch]$SqlAuth,
    [string]$Login,
    [string]$Password
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot       = Split-Path $PSScriptRoot -Parent
$LocalDbName    = 'SQLHealthMonitorTest'
$DatabaseName   = 'SQLHealthMonitor'
$Sqlcmd         = (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source

if (-not $Sqlcmd) { throw "sqlcmd not found." }

# ---- assertions -------------------------------------------------------------

$script:PassCount = 0
$script:FailCount = 0
$script:SkipCount = 0
$script:Failures  = @()

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -eq $Actual) {
        Write-Host "      PASS: $Message" -ForegroundColor DarkGreen
        $script:PassCount++
    } else {
        Write-Host "      FAIL: $Message" -ForegroundColor Red
        Write-Host "        expected: [$Expected]" -ForegroundColor Red
        Write-Host "        actual  : [$Actual]" -ForegroundColor Red
        $script:FailCount++
        $script:Failures += $Message
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    Assert-Equal -Expected $true -Actual $Condition -Message $Message
}

function Skip-Scenario {
    param([string]$Reason)
    Write-Host "      SKIP: $Reason" -ForegroundColor Yellow
    $script:SkipCount++
}

# ---- SQL execution ----------------------------------------------------------

$script:Target = if ($ServerInstance) { $ServerInstance } else { "(localdb)\$LocalDbName" }
$script:Auth   = if ($SqlAuth) { @('-U', $Login, '-P', $Password) } else { @('-E') }

function Invoke-Sql {
    <#
    .SYNOPSIS
        Runs a query or script file and returns trimmed output lines.
    .PARAMETER File
        Path to a .sql file, relative to repo root. Mutually exclusive with Query.
    #>
    param(
        [string]$Query,
        [string]$File,
        [string]$Database = 'master',
        [string[]]$Vars  = @()
    )

    $args = @('-S', $script:Target) + $script:Auth + @('-b', '-V', '1', '-h', '-1', '-W')

    foreach ($v in $Vars) { $args += @('-v', $v) }

    $args += @('-d', $Database)

    Push-Location $RepoRoot
    try {
        if ($File) {
            $args += @('-i', $File)
            $out = & $Sqlcmd @args 2>&1
        } else {
            $args += @('-Q', $Query)
            $out = & $Sqlcmd @args 2>&1
        }
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    if ($code -ne 0) {
        throw "sqlcmd failed (exit $code) on Database='$Database'. Output:`n$($out | Out-String)"
    }

    return @($out | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -ne '' })
}

function Get-RepoRoot { return $RepoRoot }

function Reset-TestDatabase {
    <#
    Drops the database so each scenario starts from nothing. Jobs are dropped too
    when running against a real instance.
    #>
    param()
    Invoke-Sql -Query @"
IF DB_ID('$DatabaseName') IS NOT NULL
BEGIN
    ALTER DATABASE [$DatabaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$DatabaseName];
END
"@
}

# ---- LocalDB lifecycle ------------------------------------------------------

function Initialize-LocalDb {
    if ($ServerInstance) { return }

    $sqllocaldb = Get-Command sqllocaldb -ErrorAction SilentlyContinue
    if (-not $sqllocaldb) {
        throw "sqllocaldb not found. Install SQL Server LocalDB, or pass -ServerInstance to test against a real instance."
    }

    $existing = & $sqllocaldb.Sources 'info' | Out-String
    if ($existing -notmatch [regex]::Escape($LocalDbName)) {
        & $sqllocaldb.Sources 'create' $LocalDbName | Out-Null
    }
    & $sqllocaldb.Sources 'start' $LocalDbName | Out-Null
}

function Invoke-SqlScriptChain {
    <#
    Runs an install/*.sql file with the :setvar every installer-owned file expects.
    #>
    param([string]$File, [switch]$SkipJobs)

    $scripts = if ($SkipJobs) {
        @($File)
    } else {
        @($File)
    }
    foreach ($s in $scripts) {
        Invoke-Sql -File $s -Database 'master' -Vars @("DatabaseName=$DatabaseName") | Out-Null
    }
}

# ---- runner -----------------------------------------------------------------

function Invoke-Scenario {
    param([string]$Name, [scriptblock]$Body)

    Write-Host ""
    Write-Host "  [$Name]" -ForegroundColor Cyan
    try {
        & $Body
    } catch {
        Write-Host "      ERROR: $_" -ForegroundColor Red
        $script:FailCount++
        $script:Failures += "$Name threw: $_"
    }
}

try {
    Write-Host ""
    Write-Host "SQL Health Monitor - Install Tests" -ForegroundColor Cyan
    Write-Host "  Target : $script:Target" -ForegroundColor Cyan

    Initialize-LocalDb

    $repoVersion = (Get-Content (Join-Path $RepoRoot 'VERSION') -Raw).Trim()
    Write-Host "  VERSION: $repoVersion" -ForegroundColor Cyan

    Invoke-Scenario 'Harness self-check' {
        Reset-TestDatabase
        $r = Invoke-Sql -Query "SELECT 42"
        Assert-Equal -Expected '42' -Actual $r[0] -Message 'Invoke-Sql returns query output'
    }
}
finally {
    Write-Host ""
    Write-Host "Results: $($script:PassCount) passed, $($script:FailCount) failed, $($script:SkipCount) skipped" -ForegroundColor $(if ($script:FailCount -eq 0) { 'Green' } else { 'Red' })
    if ($script:FailCount -gt 0) {
        Write-Host ""
        foreach ($f in $script:Failures) { Write-Host "  - $f" -ForegroundColor Red }
        exit 1
    }
}
```

- [ ] **Step 3: Run the harness to verify it works**

Run:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-Install.ps1
```
Expected: `Harness self-check` prints `PASS: Invoke-Sql returns query output`, and the summary line reads `1 passed, 0 failed, 0 skipped`.

If it reports `sqllocaldb not found`, stop and tell the user — the remaining tasks depend on this harness working. They can install LocalDB or supply `-ServerInstance`.

- [ ] **Step 4: Commit**

```bash
git add VERSION tests/Test-Install.ps1
git commit -m "test: add VERSION file and LocalDB-backed install test harness

VERSION is the single semver source for the installer. The harness gives
each scenario isolation via a dedicated LocalDB instance rather than a
custom database name, because 33 of 35 SQL files hardcode SQLHealthMonitor.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 2: Tracking tables and version function

**Files:**
- Modify: `install/00-create-schema.sql` (top — database creation and schema; and the end, before the final `PRINT`)

**Interfaces:**
- Consumes: `tests/Test-Install.ps1` `Invoke-Sql`, `Reset-TestDatabase` (Task 1).
- Produces: `[monitor].[SchemaVersion]`, `[monitor].[AppliedMigrations]`, `[monitor].[fn_GetInstalledVersion]()` returning `VARCHAR(20)` or `NULL`. Task 3 and Task 8 depend on the exact column names.

- [ ] **Step 1: Write the failing test**

Append to the `Harness self-check` scenario in `tests/Test-Install.ps1`, or add a new scenario:

```powershell
    Invoke-Scenario 'Tracking objects exist after 00-create-schema' {
        Reset-TestDatabase
        Invoke-Sql -File 'install\00-create-schema.sql' -Database 'master' `
                   -Vars @("DatabaseName=$DatabaseName") | Out-Null

        $t = Invoke-Sql -Query @"
SELECT COUNT(*) FROM [SQLHealthMonitor].[sys].[objects]
WHERE name IN ('SchemaVersion','AppliedMigrations','fn_GetInstalledVersion');
"@
        Assert-Equal -Expected '3' -Actual $t[0] -Message 'SchemaVersion, AppliedMigrations and fn_GetInstalledVersion all created'

        $empty = Invoke-Sql -Query "SELECT [SQLHealthMonitor].[monitor].[fn_GetInstalledVersion]();"
        Assert-True -Condition ([string]::IsNullOrEmpty($empty[0])) `
                    -Message 'fn_GetInstalledVersion returns NULL before any install'
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-Install.ps1
```
Expected: FAIL — count is `0`, not `3`.

- [ ] **Step 3: Add `:setvar` and the tracking objects**

In `install/00-create-schema.sql`, replace the header block (lines 10–20) with:

```sql
:setvar DatabaseName "SQLHealthMonitor"

USE [master];
GO

IF DB_ID('$(DatabaseName)') IS NULL
BEGIN
    EXEC('CREATE DATABASE [$(DatabaseName)]');
    PRINT 'Created database $(DatabaseName).';
END
GO

USE [$(DatabaseName)];
GO
```

Then, immediately after the `EXEC('CREATE SCHEMA [monitor]')` block, insert:

```sql
----------------------------------------------------------------------
-- VERSION TRACKING
----------------------------------------------------------------------

IF OBJECT_ID('monitor.SchemaVersion', 'U') IS NULL
CREATE TABLE [monitor].[SchemaVersion] (
    Id               INT IDENTITY(1,1) PRIMARY KEY,
    Version          VARCHAR(20)   NOT NULL,
    PreviousVersion  VARCHAR(20)   NULL,
    InstallMode      VARCHAR(10)   NOT NULL,
    InstalledAt      DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    InstalledBy      NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
    CommitHash       VARCHAR(40)   NULL,
    LastVerifiedAt   DATETIME2     NULL
);
GO

IF OBJECT_ID('monitor.AppliedMigrations', 'U') IS NULL
CREATE TABLE [monitor].[AppliedMigrations] (
    FileName     NVARCHAR(255) NOT NULL PRIMARY KEY,
    Version      VARCHAR(20)   NOT NULL,
    AppliedAt    DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    AppliedBy    NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME()
);
GO

-- Returns the most recently applied version, or NULL if never installed.
IF OBJECT_ID('[monitor].[fn_GetInstalledVersion]', 'FN') IS NOT NULL
    EXEC('ALTER FUNCTION [monitor].[fn_GetInstalledVersion]() RETURNS VARCHAR(20) AS BEGIN RETURN NULL; END;');
GO

IF OBJECT_ID('[monitor].[fn_GetInstalledVersion]', 'FN') IS NULL
    EXEC('CREATE FUNCTION [monitor].[fn_GetInstalledVersion]() RETURNS VARCHAR(20) AS BEGIN RETURN NULL; END;');
GO

ALTER FUNCTION [monitor].[fn_GetInstalledVersion]()
RETURNS VARCHAR(20)
AS
BEGIN
    IF OBJECT_ID('[monitor].[SchemaVersion]', 'U') IS NULL
        RETURN NULL;

    RETURN (SELECT TOP 1 [Version] FROM [monitor].[SchemaVersion] ORDER BY [Id] DESC);
END;
GO
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-Install.ps1
```
Expected: PASS on both assertions; summary shows `3 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add install/00-create-schema.sql tests/Test-Install.ps1
git commit -m "feat: add SchemaVersion, AppliedMigrations and fn_GetInstalledVersion

Existing installs have no way to report what they are running. These
give the installer something to read before deciding what to do, and
fn_GetInstalledVersion follows the repo's placeholder+ALTER pattern.

00-create-schema.sql also takes the database name from a :setvar so
Install.ps1 can stop silently ignoring its -Database parameter.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 3: Version recording script

**Files:**
- Create: `install/10-record-version.sql`
- Modify: `tests/Test-Install.ps1`

**Interfaces:**
- Consumes: `fn_GetInstalledVersion()` (Task 2).
- Produces: sqlcmd variables `$(Version)`, `$(Mode)`, `$(Commit)` — the contract `Install.ps1` must pass. Also pins Review Focus #3: a failed chain leaves `LastVerifiedAt` unchanged.

- [ ] **Step 1: Write the failing test**

Add to `tests/Test-Install.ps1`:

```powershell
    Invoke-Scenario '10-record-version is idempotent and refreshes LastVerifiedAt' {
        Reset-TestDatabase
        Invoke-Sql -File 'install\00-create-schema.sql' -Database 'master' `
                   -Vars @("DatabaseName=$DatabaseName") | Out-Null

        Invoke-Sql -File 'install\10-record-version.sql' -Database $DatabaseName `
                   -Vars @("Version=1.1.0", "Mode=Fresh", "Commit=abc1234") | Out-Null

        $v = Invoke-Sql -Query "SELECT [SQLHealthMonitor].[monitor].[fn_GetInstalledVersion]();"
        Assert-Equal -Expected '1.1.0' -Actual $v[0] -Message 'version recorded'

        $rows = Invoke-Sql -Query "SELECT COUNT(*) FROM [SQLHealthMonitor].[monitor].[SchemaVersion];"
        Assert-Equal -Expected '1' -Actual $rows[0] -Message 'exactly one row after first record'

        # Second run at the same version must not add a row, but must refresh LastVerifiedAt.
        Invoke-Sql -Query "UPDATE [SQLHealthMonitor].[monitor].[SchemaVersion] SET LastVerifiedAt = NULL;" -Database $DatabaseName | Out-Null
        Invoke-Sql -File 'install\10-record-version.sql' -Database $DatabaseName `
                   -Vars @("Version=1.1.0", "Mode=Upgrade", "Commit=abc1234") | Out-Null

        $rows = Invoke-Sql -Query "SELECT COUNT(*) FROM [SQLHealthMonitor].[monitor].[SchemaVersion];"
        Assert-Equal -Expected '1' -Actual $rows[0] -Message 're-running same version adds no row'

        $verified = Invoke-Sql -Query "SELECT CASE WHEN LastVerifiedAt IS NULL THEN 'NULL' ELSE 'SET' END FROM [SQLHealthMonitor].[monitor].[SchemaVersion];"
        Assert-Equal -Expected 'SET' -Actual $verified[0] -Message 'LastVerifiedAt refreshed on re-run'
    }

    Invoke-Scenario 'Recording a new version carries PreviousVersion' {
        Invoke-Sql -File 'install\10-record-version.sql' -Database $DatabaseName `
                   -Vars @("Version=1.2.0", "Mode=Upgrade", "Commit=deadbee") | Out-Null

        $prev = Invoke-Sql -Query "SELECT PreviousVersion FROM [SQLHealthMonitor].[monitor].[SchemaVersion] WHERE Version = '1.2.0';"
        Assert-Equal -Expected '1.1.0' -Actual $prev[0] -Message 'PreviousVersion records where the upgrade came from'

        $hash = Invoke-Sql -Query "SELECT CommitHash FROM [SQLHealthMonitor].[monitor].[SchemaVersion] WHERE Version = '1.2.0';"
        Assert-Equal -Expected 'deadbee' -Actual $hash[0] -Message 'CommitHash stored'
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-Install.ps1
```
Expected: ERROR — `install\10-record-version.sql` not found.

- [ ] **Step 3: Create the script**

`install/10-record-version.sql`:

```sql
/*
    SQL Health Monitor - Version Recording
    Records the version just deployed. Idempotent: re-running at the same
    version refreshes LastVerifiedAt rather than adding a row.

    sqlcmd variables:
      $(Version)  - semver being installed, e.g. 1.1.0
      $(Mode)     - 'Fresh' or 'Upgrade'
      $(Commit)   - git short hash, or empty

    Run last in the install chain. If an earlier script failed, this is
    never reached and LastVerifiedAt keeps its previous value -- which is
    how `Install.ps1 -Mode Status` reports a half-finished upgrade.
*/

:setvar DatabaseName "SQLHealthMonitor"

USE [$(DatabaseName)];
GO

DECLARE @Version     VARCHAR(20)   = '$(Version)';
DECLARE @Mode        VARCHAR(10)   = '$(Mode)';
DECLARE @Commit      VARCHAR(40)   = NULLIF(LTRIM(RTRIM('$(Commit)')), '');
DECLARE @Previous    VARCHAR(20)   = [monitor].[fn_GetInstalledVersion]();
GO

IF NOT EXISTS (SELECT 1 FROM [monitor].[SchemaVersion] WHERE [Version] = @Version)
BEGIN
    INSERT INTO [monitor].[SchemaVersion]
        ([Version], [PreviousVersion], [InstallMode], [InstalledBy], [CommitHash], [LastVerifiedAt])
    VALUES
        (@Version, @Previous, @Mode, SUSER_SNAME(), @Commit, SYSUTCDATETIME());

    PRINT '✓ Recorded version ' + @Version + ' (' + @Mode + ')';
END
ELSE
BEGIN
    UPDATE [monitor].[SchemaVersion]
    SET [LastVerifiedAt] = SYSUTCDATETIME(),
        [CommitHash]     = COALESCE(@Commit, [CommitHash])
    WHERE [Version] = @Version;

    PRINT '✓ Version ' + @Version + ' already recorded; LastVerifiedAt refreshed.';
END
GO
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-Install.ps1
```
Expected: both scenarios PASS; summary `5 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add install/10-record-version.sql tests/Test-Install.ps1
git commit -m "feat: add 10-record-version.sql to record deployed version

Idempotent by version: a repeat run at the same version refreshes
LastVerifiedAt instead of adding a row, so Status can answer 'did my
upgrade actually apply?' Running last in the chain means a mid-chain
failure leaves the previous version visible.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 4: Migrations folder

**Files:**
- Create: `install/migrations/README.md`

**Interfaces:**
- Consumes: `AppliedMigrations` (Task 2).
- Produces: the naming contract `Install.ps1` parses — `V<major>_<minor>_<patch>__<description>.sql`. Task 8 implements the parser; the regex below is the contract between them.

- [ ] **Step 1: Create the folder and README**

`install/migrations/README.md`:

```markdown
# Migrations

This folder holds the changes that **cannot be written idempotently**.

The install chain (`install/00` through `install/09`) already reconciles
itself: new columns arrive via `IF COL_LENGTH(...) IS NULL ALTER TABLE`,
procedures and views are updated in place, and configuration is inserted
without overwriting what you changed. You do not need a migration for
those.

You **do** need one for anything with a one-time effect:

- Renaming a column, table or procedure
- Changing a column's type or nullability
- Backfilling existing rows
- Splitting or merging a table
- Changing a default in `Settings` or `Thresholds` (see the note below)

## Naming

    V<major>_<minor>_<patch>__<short_description>.sql

Example: `V1_2_0__backfill-buffer-cache-hit-ratio.sql`

`Install.ps1 -Mode Upgrade` applies every migration whose version is
greater than `fn_GetInstalledVersion()`, in ascending order, and records
each file in `[monitor].[AppliedMigrations]` so it never runs twice.

## Writing one

Start with a guard so the migration is safe to re-run by hand:

```sql
:setvar DatabaseName "SQLHealthMonitor"
USE [$(DatabaseName)];
GO

IF NOT EXISTS (SELECT 1 FROM [monitor].[SchemaVersion] WHERE [Version] = '1.2.0')
BEGIN
    -- the actual change
END
```

## A note on default values

`Settings` and `Thresholds` are merged insert-only, so changing a default
in `05-configure.sql` will **not** update an existing installation. That
is deliberate -- those values belong to the operator. If you change a
default and existing installations should pick it up, write a migration
that updates the rows explicitly, and say so in the CHANGELOG.
```

- [ ] **Step 2: Verify the naming contract is unambiguous**

```bash
ls install/migrations/
```
Expected: only `README.md`. The folder stays empty on purpose — the first real migration comes with a future change.

- [ ] **Step 3: Commit**

```bash
git add install/migrations/README.md
git commit -m "docs: add migrations folder for non-idempotent changes

Most schema changes reconcile themselves through the install chain. This
folder is the escape hatch for renames, backfills and type changes, and
the README states the naming contract Install.ps1 parses.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 5: Column reconciliation

**Files:**
- Modify: `install/00-create-schema.sql` (after each `CREATE TABLE`, for all 20 tables)
- Modify: `install/08-extended-schema.sql` (same, for its 11 tables)
- Modify: `tests/Test-Install.ps1`

**Interfaces:**
- Consumes: `fn_GetInstalledVersion()` (Task 2).
- Produces: no new symbols. Pins Review Focus #5 — a table created by an older release gains its missing columns on upgrade.

- [ ] **Step 1: Write the failing test**

Add to `tests/Test-Install.ps1`:

```powershell
    Invoke-Scenario 'Upgrade adds columns missing from an older table definition' {
        Reset-TestDatabase
        Invoke-Sql -File 'install\00-create-schema.sql' -Database 'master' `
                   -Vars @("DatabaseName=$DatabaseName") | Out-Null

        # Simulate drift: drop a column the current schema defines.
        Invoke-Sql -Query "ALTER TABLE [SQLHealthMonitor].[monitor].[MemoryHistory] DROP COLUMN [MemoryGrantsPending];" `
                   -Database $DatabaseName | Out-Null
        $before = Invoke-Sql -Query "SELECT COL_LENGTH('monitor.MemoryHistory','MemoryGrantsPending');"
        Assert-True -Condition ([string]::IsNullOrEmpty($before[0])) -Message 'column absent before re-run'

        # Re-run the schema script exactly as Install.ps1 -Mode Upgrade does.
        Invoke-Sql -File 'install\00-create-schema.sql' -Database 'master' `
                   -Vars @("DatabaseName=$DatabaseName") | Out-Null

        $after = Invoke-Sql -Query "SELECT COL_LENGTH('monitor.MemoryHistory','MemoryGrantsPending');"
        Assert-True -Condition (-not [string]::IsNullOrEmpty($after[0])) -Message 'column restored on re-run'
    }

    Invoke-Scenario 'Re-running 00 restores computed columns' {
        # HoursSinceLastBackup is AS DATEDIFF(...) and must probe sys.computed_columns.
        Invoke-Sql -Query "ALTER TABLE [SQLHealthMonitor].[monitor].[BackupHistory] DROP COLUMN [HoursSinceLastBackup];" `
                   -Database $DatabaseName | Out-Null

        Invoke-Sql -File 'install\00-create-schema.sql' -Database 'master' `
                   -Vars @("DatabaseName=$DatabaseName") | Out-Null

        $c = Invoke-Sql -Query "SELECT COUNT(*) FROM [SQLHealthMonitor].[sys].[computed_columns] WHERE object_id = OBJECT_ID('monitor.BackupHistory') AND name = 'HoursSinceLastBackup';"
        Assert-Equal -Expected '1' -Actual $c[0] -Message 'computed column restored'
    }

    Invoke-Scenario 'Re-running 08-extended-schema adds missing columns' {
        Invoke-Sql -File 'install\08-extended-schema.sql' -Database $DatabaseName | Out-Null
        Invoke-Sql -Query "ALTER TABLE [SQLHealthMonitor].[monitor].[TempDbObjectUsage] DROP COLUMN [UserObjectsMB];" `
                   -Database $DatabaseName | Out-Null

        Invoke-Sql -File 'install\08-extended-schema.sql' -Database $DatabaseName | Out-Null

        $c = Invoke-Sql -Query "SELECT COL_LENGTH('monitor.TempDbObjectUsage','UserObjectsMB');"
        Assert-True -Condition (-not [string]::IsNullOrEmpty($c[0])) -Message 'extended-schema column restored'
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-Install.ps1
```
Expected: the first and third scenarios FAIL on the restoration assertion. The computed-column scenario FAILS too.

- [ ] **Step 3: Add reconciliation to `install/00-create-schema.sql`**

The rule, applied to every table: read each column out of that file's existing `CREATE TABLE` and emit a matching guard. For `Settings`:

```sql
-- Column reconciliation: reaches installations that predate this column.
IF COL_LENGTH('monitor.Settings', 'SettingName') IS NULL
    ALTER TABLE [monitor].[Settings] ADD SettingName NVARCHAR(100) NOT NULL;
GO
```

Two exceptions:

**Nullable back-fill.** A `NOT NULL` column with no `DEFAULT` cannot be added to a populated table in one step. For those, use three steps:

```sql
IF COL_LENGTH('monitor.SomeTable', 'SomeNotNullCol') IS NULL
BEGIN
    ALTER TABLE [monitor].[SomeTable] ADD SomeNotNullCol INT NULL;
    UPDATE [monitor].[SomeTable] SET SomeNotNullCol = 0 WHERE SomeNotNullCol IS NULL;
    ALTER TABLE [monitor].[SomeTable] ALTER COLUMN SomeNotNullCol INT NOT NULL;
END
GO
```

**Computed columns.** `HoursSinceLastBackup` in `BackupHistory` is `AS DATEDIFF(HOUR, LastBackupDate, SYSUTCDATETIME())`. `COL_LENGTH` is not the probe for those; use `sys.computed_columns`:

```sql
IF NOT EXISTS (SELECT 1 FROM sys.computed_columns
               WHERE object_id = OBJECT_ID('monitor.BackupHistory')
                 AND name = 'HoursSinceLastBackup')
    ALTER TABLE [monitor].[BackupHistory]
        ADD HoursSinceLastBackup AS DATEDIFF(HOUR, LastBackupDate, SYSUTCDATETIME());
GO
```

Enumerate the columns before writing this step:

```bash
grep -nE "^\s{4}[A-Za-z]+\s+(INT|BIGINT|NVARCHAR|VARCHAR|CHAR|TINYINT|DECIMAL|DATETIME2|UNIQUEIDENTIFIER|BINARY|VARBINARY|BIT)" install/00-create-schema.sql
```
Expected: the full column list for all 20 tables. The `Id ... IDENTITY(1,1) PRIMARY KEY` columns must **not** get a reconciliation guard.

- [ ] **Step 4: Apply the same treatment to `install/08-extended-schema.sql`**

Its 11 tables (`DiskHistoryDetailed`, `DiskIoWaits`, `LogGrowthHistory`, `LogBackupHistory`, `TempDbHistoryDetailed`, `TempDbObjectUsage`, `DeadlockHistory`, `DeadlockWaitStats`, `DeadlockPatterns`, `XESessionStatus`, `XEEventConfig`) get the same `COL_LENGTH` guards, immediately after each `CREATE TABLE ... GO`.

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-Install.ps1
```
Expected: all three scenarios PASS; summary `8 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add install/00-create-schema.sql install/08-extended-schema.sql tests/Test-Install.ps1
git commit -m "feat: reconcile columns on existing tables during upgrade

The IF OBJECT_ID IS NULL guard meant a table created by an older release
kept its old shape forever, so new columns never reached existing
installations. Each column now gets a COL_LENGTH guard, NOT NULL columns
get add-backfill-alter, and the one computed column probes
sys.computed_columns instead.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 6: Configuration MERGE

**Files:**
- Modify: `install/05-configure.sql` (three `DELETE` + `INSERT` pairs → three `MERGE` statements)
- Modify: `tests/Test-Install.ps1`

**Interfaces:**
- Consumes: nothing new.
- Produces: no new symbols. Establishes the rule that `Settings` and `Thresholds` are operator-owned and `Languages` is repo-owned.

- [ ] **Step 1: Write the failing test**

Add to `tests/Test-Install.ps1`:

```powershell
    Invoke-Scenario 'Upgrade preserves operator configuration' {
        Invoke-Sql -Query @"
UPDATE [SQLHealthMonitor].[monitor].[Settings] SET SettingValue = 'sentinel@corp.example'
WHERE Category = 'Email' AND SettingName = 'Recipients';
UPDATE [SQLHealthMonitor].[monitor].[Settings] SET SettingValue = 'ptbr'
WHERE Category = 'General' AND SettingName = 'Language';
UPDATE [SQLHealthMonitor].[monitor].[Thresholds] SET WarningValue = 42
WHERE MetricName = 'CPU_SqlPct';
"@ -Database $DatabaseName | Out-Null

        Invoke-Sql -File 'install\05-configure.sql' -Database $DatabaseName | Out-Null

        $r = Invoke-Sql -Query "SELECT SettingValue FROM [SQLHealthMonitor].[monitor].[Settings] WHERE Category='Email' AND SettingName='Recipients';"
        Assert-Equal -Expected 'sentinel@corp.example' -Actual $r[0] -Message 'Email.Recipients survived the re-run'

        $l = Invoke-Sql -Query "SELECT SettingValue FROM [SQLHealthMonitor].[monitor].[Settings] WHERE Category='General' AND SettingName='Language';"
        Assert-Equal -Expected 'ptbr' -Actual $l[0] -Message 'General.Language survived the re-run'

        $t = Invoke-Sql -Query "SELECT WarningValue FROM [SQLHealthMonitor].[monitor].[Thresholds] WHERE MetricName='CPU_SqlPct';"
        Assert-Equal -Expected '42' -Actual $t[0] -Message 'tuned threshold survived the re-run'
    }

    Invoke-Scenario 'Upgrade adds new defaults and refreshes language strings' {
        # A setting the script knows about but the database does not.
        Invoke-Sql -Query "DELETE FROM [SQLHealthMonitor].[monitor].[Settings] WHERE Category='General' AND SettingName='ServerName';" `
                   -Database $DatabaseName | Out-Null
        Invoke-Sql -File 'install\05-configure.sql' -Database $DatabaseName | Out-Null
        $s = Invoke-Sql -Query "SELECT COUNT(*) FROM [SQLHealthMonitor].[monitor].[Settings] WHERE Category='General' AND SettingName='ServerName';"
        Assert-Equal -Expected '1' -Actual $s[0] -Message 'missing default is re-inserted'

        # Languages ARE repo-owned: a stale translation must be corrected.
        Invoke-Sql -Query "UPDATE [SQLHealthMonitor].[monitor].[Languages] SET StringValue = 'stale text' WHERE LanguageCode='en' AND StringKey='report.daily.title';" `
                   -Database $DatabaseName | Out-Null
        Invoke-Sql -File 'install\05-configure.sql' -Database $DatabaseName | Out-Null
        $g = Invoke-Sql -Query "SELECT StringValue FROM [SQLHealthMonitor].[monitor].[Languages] WHERE LanguageCode='en' AND StringKey='report.daily.title';"
        Assert-Equal -Expected 'Daily SQL Health Report' -Actual $g[0] -Message 'stale translation corrected'
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-Install.ps1
```
Expected: the first scenario FAILS — `DELETE FROM [monitor].[Settings]` wipes the sentinels, so `Recipients` reads `dba@company.com` instead of `sentinel@corp.example`.

- [ ] **Step 3: Replace the Settings `DELETE` + `INSERT` with a `MERGE`**

In `install/05-configure.sql`, delete the `DELETE FROM [monitor].[Settings];` line and its `GO`, and change the following `INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType) VALUES` to:

```sql
-- Operator-owned: insert what is missing, never overwrite what exists.
MERGE [monitor].[Settings] WITH (HOLDLOCK) AS T
USING (VALUES
('General', 'Language', 'en', 'Report language: en or ptbr', 'string'),
('General', 'ServerName', @@SERVERNAME, 'Server identifier for reports', 'string'),
('General', 'MonitoringEnabled', '1', 'Master switch for all monitoring', 'bool'),
-- ... every remaining row, copied unchanged from the existing INSERT ...
('Features', 'CollectUptimeTracker', '1', 'Enable uptime SLA tracking', 'bool')
) AS S (Category, SettingName, SettingValue, Description, DataType)
    ON T.[Category] = S.Category AND T.[SettingName] = S.SettingName
WHEN NOT MATCHED BY TARGET THEN
    INSERT ([Category], [SettingName], [SettingValue], [Description], [DataType])
    VALUES (S.Category, S.SettingName, S.SettingValue, S.Description, S.DataType);
GO
```

There is **no** `WHEN MATCHED` clause. That absence is the whole point.

- [ ] **Step 4: Same for `Thresholds`**

Replace `DELETE FROM [monitor].[Thresholds];` and its `INSERT`:

```sql
-- Operator-owned: a tuned threshold is not reset by an upgrade.
MERGE [monitor].[Thresholds] WITH (HOLDLOCK) AS T
USING (VALUES
('CPU_SqlPct', 80, 95, '>=', 'SQL Server CPU utilization percentage'),
('CPU_SystemPct', 90, 98, '>=', 'Total system CPU utilization'),
-- ... every remaining row, copied unchanged from the existing INSERT ...
('SLA_IncidentResponseTime', 60, 240, '<=', 'Incident response time threshold (minutes)')
) AS S (MetricName, WarningValue, CriticalValue, Operator, Description)
    ON T.[MetricName] = S.MetricName
WHEN NOT MATCHED BY TARGET THEN
    INSERT ([MetricName], [WarningValue], [CriticalValue], [Operator], [Description])
    VALUES (S.MetricName, S.WarningValue, S.CriticalValue, S.Operator, S.Description);
GO
```

- [ ] **Step 5: `Languages` keeps the refresh, as a `MERGE` with `WHEN MATCHED`**

Replace `DELETE FROM [monitor].[Languages];` and its `INSERT`:

```sql
-- Repo-owned: translations must track the release, so matched rows are updated.
MERGE [monitor].[Languages] WITH (HOLDLOCK) AS T
USING (VALUES
('en', 'report.daily.title', 'Daily SQL Health Report'),
('en', 'report.daily.subtitle', 'Server: {server} | Date: {date}'),
-- ... every remaining row, copied unchanged from the existing INSERT ...
('ptbr', 'section.summary', 'Resumo Executivo')
) AS S (LanguageCode, StringKey, StringValue)
    ON T.[LanguageCode] = S.LanguageCode AND T.[StringKey] = S.StringKey
WHEN MATCHED AND T.[StringValue] <> S.StringValue THEN
    UPDATE SET T.[StringValue] = S.StringValue
WHEN NOT MATCHED BY TARGET THEN
    INSERT ([LanguageCode], [StringKey], [StringValue])
    VALUES (S.LanguageCode, S.StringKey, S.StringValue);
GO
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-Install.ps1
```
Expected: both scenarios PASS; summary `10 passed, 0 failed`.

- [ ] **Step 7: Commit**

```bash
git add install/05-configure.sql tests/Test-Install.ps1
git commit -m "fix: stop wiping operator configuration on re-run

DELETE + INSERT meant any re-run reset Email.Recipients, General.Language,
MonitoringEnabled and every tuned threshold. Settings and Thresholds are
now insert-only MERGEs; Languages keeps refreshing translations because
those belong to the release, not the operator.

Consequence, documented in install/migrations/README.md: changing a default
in the repo no longer reaches existing installations and needs a migration.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 7: Agent jobs — steps follow the repo, schedules follow the operator

**Files:**
- Modify: `install/04-create-jobs.sql`

**Interfaces:**
- Consumes: `:setvar DatabaseName`, and `$(ResetSchedules)` (`0` or `1`) passed by `Install.ps1` (Task 8).
- Produces: jobs named exactly as today — `SQL Health Monitor - {Collectors, Alert Engine, Daily Report, Weekly Report, Purge Old Data, Update Baselines}` — with steps named as today, so `Status` (Task 8) can find them.

**Note:** this task has no automated test — LocalDB has no SQL Agent. Its verification is Task 10's scenario 4, which requires a real `-ServerInstance`.

- [ ] **Step 1: Add the `:setvar` and gate the deletion block**

At the top of `install/04-create-jobs.sql`, after the header comment, add:

```sql
:setvar DatabaseName "SQLHealthMonitor"
:setvar ResetSchedules 0
```

Then change the comment above the deletion cursor (line 18) and guard the cursor so it only runs when schedules are explicitly being reset:

```sql
----------------------------------------------------------------------
-- HELPER: Delete job if exists
-- Only when the operator asked for default schedules back (-ResetSchedules).
-- An ordinary upgrade must never touch a schedule someone adjusted by hand.
----------------------------------------------------------------------
IF CONVERT(INT, '$(ResetSchedules)') = 1
BEGIN
DECLARE @JobName NVARCHAR(128);

DECLARE @JobsToCreate TABLE (JobName NVARCHAR(128));
INSERT INTO @JobsToCreate VALUES
    (N'SQL Health Monitor - Collectors'),
    (N'SQL Health Monitor - Alert Engine'),
    (N'SQL Health Monitor - Daily Report'),
    (N'SQL Health Monitor - Weekly Report'),
    (N'SQL Health Monitor - Purge Old Data'),
    (N'SQL Health Monitor - Update Baselines');

DECLARE job_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT JobName FROM @JobsToCreate;

OPEN job_cursor;
FETCH NEXT FROM job_cursor INTO @JobName;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
        EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;
    FETCH NEXT FROM job_cursor INTO @JobName;
END;
CLOSE job_cursor;
DEALLOCATE job_cursor;
END
GO
```

Deleting the whole job (which removes its schedules with it) is what makes `-ResetSchedules` correct — partial schedule surgery leaves orphans behind.

- [ ] **Step 2: Wrap each of the six job blocks in a conditional, with a step-update branch**

For job 1, the existing block from `DECLARE @JobId UNIQUEIDENTIFIER;` through `EXEC msdb.dbo.sp_add_jobserver ...` becomes:

```sql
DECLARE @JobId UNIQUEIDENTIFIER;
DECLARE @Owner NVARCHAR(128) = SUSER_SNAME();

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'SQL Health Monitor - Collectors')
BEGIN
    EXEC msdb.dbo.sp_add_job
        @job_name = N'SQL Health Monitor - Collectors',
        @enabled = 1,
        @description = N'Runs all SQL Health Monitor collectors every 5 minutes.',
        @category_name = N'Database Maintenance',
        @owner_login_name = @Owner,
        @job_id = @JobId OUTPUT;

    EXEC msdb.dbo.sp_add_jobstep
        @job_id = @JobId,
        @step_name = N'Run All Collectors',
        @step_id = 1,
        @subsystem = N'TSQL',
        @command = N'EXEC [monitor].[usp_RunAllCollectors];',
        @database_name = N'$(DatabaseName)',
        @on_success_action = 1,
        @on_fail_action = 2;

    EXEC msdb.dbo.sp_add_jobschedule
        @job_id = @JobId,
        @name = N'Every 5 Minutes',
        @freq_type = 4,           -- Daily
        @freq_interval = 1,
        @freq_subday_type = 4,    -- Minutes
        @freq_subday_interval = 5,
        @active_start_time = 0;

    EXEC msdb.dbo.sp_add_jobserver @job_id = @JobId, @server_name = N'(local)';
    PRINT '✓ Created job: SQL Health Monitor - Collectors';
END
ELSE
BEGIN
    SELECT @JobId = job_id FROM msdb.dbo.sysjobs WHERE name = N'SQL Health Monitor - Collectors';

    -- Job steps belong to the repo: keep them in sync with the scripts.
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobsteps WHERE job_id = @JobId AND step_id = 1)
        EXEC msdb.dbo.sp_update_jobstep
            @job_id = @JobId,
            @step_name = N'Run All Collectors',
            @step_id = 1,
            @subsystem = N'TSQL',
            @command = N'EXEC [monitor].[usp_RunAllCollectors];',
            @database_name = N'$(DatabaseName)',
            @on_success_action = 1,
            @on_fail_action = 2;
    ELSE
        EXEC msdb.dbo.sp_add_jobstep
            @job_id = @JobId,
            @step_name = N'Run All Collectors',
            @step_id = 1,
            @subsystem = N'TSQL',
            @command = N'EXEC [monitor].[usp_RunAllCollectors];',
            @database_name = N'$(DatabaseName)',
            @on_success_action = 1,
            @on_fail_action = 2;

    PRINT '• Updated step on existing job: SQL Health Monitor - Collectors (schedule untouched)';
END
```

The `IF EXISTS` probe before `sp_update_jobstep` matters: `sp_update_jobstep` errors when no step matches, so a job created by an older release with a different step name would break the whole chain.

- [ ] **Step 3: Repeat Step 2 for the remaining five jobs**

| Job name | Step name | Command |
|---|---|---|
| `SQL Health Monitor - Alert Engine` | `Run Alert Engine` | `EXEC [monitor].[usp_RunAlertEngine];` |
| `SQL Health Monitor - Daily Report` | `Generate Daily Report` | `EXEC [monitor].[usp_RunReport] @ReportType = 'Daily';` |
| `SQL Health Monitor - Weekly Report` | `Generate Weekly Report` | `EXEC [monitor].[usp_RunReport] @ReportType = 'Weekly';` |
| `SQL Health Monitor - Purge Old Data` | (read from the file) | (read from the file) |
| `SQL Health Monitor - Update Baselines` | (read from the file) | (read from the file) |

Read the current values before editing:

```bash
grep -nE "job_name|step_name|@command" install/04-create-jobs.sql
```

Keep each job's existing schedule definition verbatim inside the `IF NOT EXISTS` branch — those are the defaults, and they only ever apply to a job that does not exist yet.

- [ ] **Step 4: Replace every hardcoded job database name**

```bash
grep -n "SQLHealthMonitor" install/04-create-jobs.sql
```
Expected: one hit per `sp_add_jobstep` / `sp_update_jobstep` `@database_name`. Replace each with `N'$(DatabaseName)'`.

- [ ] **Step 5: Verify the script parses**

There is no LocalDB test for this. At minimum, confirm the guards are balanced and no stray `CREATE` was left:

```bash
grep -c "END$" install/04-create-jobs.sql
grep -n "IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysjobs" install/04-create-jobs.sql
```
Expected: six `IF NOT EXISTS` blocks, one per job, and the `END` count matching the `BEGIN` count plus the pre-existing ones.

- [ ] **Step 6: Commit**

```bash
git add install/04-create-jobs.sql
git commit -m "feat: update Agent job steps on upgrade, preserve schedules

The script deleted and recreated all six jobs on every run, discarding
any schedule the operator had adjusted. Jobs are now created only when
absent; existing jobs get their steps refreshed so command fixes ship
(exactly the class of fix in 28bd0ae and 4451c93) while the schedule
is left alone. -ResetSchedules restores the repo defaults.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 8: Install.ps1 modes

**Files:**
- Modify: `deploy/Install.ps1` (full rewrite)

**Interfaces:**
- Consumes: `VERSION` (Task 1), `fn_GetInstalledVersion()` (Task 2), `AppliedMigrations` (Task 2), the `$(DatabaseName)`/`$(ResetSchedules)`/`$(Version)`/`$(Mode)`/`$(Commit)` sqlcmd variables (Tasks 2, 3, 7), the migration filename regex (Task 4).
- Produces: the CLI contract the README documents.

**Pins Review Focus #1 (pre-release versions), #2 (no `.git`), #4 (backup failure aborts before any change).**

- [ ] **Step 1: Write the failing tests**

Add to `tests/Test-Install.ps1`. These drive `Install.ps1` end to end, so they need the harness's chain runner to invoke it with `-SkipJobs`:

```powershell
function Invoke-Install {
    param([string[]]$ExtraArgs)
    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                (Join-Path $RepoRoot 'deploy\Install.ps1'),
                '-ServerInstance', $script:Target)
    if ($SqlAuth) { $psArgs += @('-SqlAuth', '-Login', $Login, '-Password', $Password) }
    $psArgs += $ExtraArgs
    $out = & powershell @psArgs 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($out | Out-String) }
}

    Invoke-Scenario 'Fresh install then immediate upgrade' {
        Reset-TestDatabase
        $f = Invoke-Install @('-Mode', 'Fresh', '-Force', '-SkipJobs')
        Assert-Equal -Expected 0 -Actual $f.ExitCode -Message 'Fresh install succeeds'

        $u = Invoke-Install @('-Mode', 'Upgrade', '-SkipJobs')
        Assert-Equal -Expected 0 -Actual $u.ExitCode -Message "Upgrade on a clean install succeeds. Output:`n$($u.Output)"
    }

    Invoke-Scenario 'Upgrade records the repo version' {
        $repoVersion = (Get-Content (Join-Path $RepoRoot 'VERSION') -Raw).Trim()
        $v = Invoke-Sql -Query "SELECT [SQLHealthMonitor].[monitor].[fn_GetInstalledVersion]();"
        Assert-Equal -Expected $repoVersion -Actual $v[0] -Message 'installed version matches VERSION file'
    }

    Invoke-Scenario 'Upgrade refuses a downgrade without -Force' {
        # Pretend the server is ahead of this checkout.
        Invoke-Sql -Query "INSERT INTO [SQLHealthMonitor].[monitor].[SchemaVersion] (Version, InstallMode) VALUES ('9.9.9', 'Upgrade');" `
                   -Database $DatabaseName | Out-Null

        $d = Invoke-Install @('-Mode', 'Upgrade', '-SkipJobs')
        Assert-Equal -Expected 1 -Actual $d.ExitCode -Message 'downgrade refused with exit 1'
        Assert-True -Condition ($d.Output -match 'newer') -Message 'refusal message explains the repo is older'

        $v = Invoke-Sql -Query "SELECT [SQLHealthMonitor].[monitor].[fn_GetInstalledVersion]();"
        Assert-Equal -Expected '9.9.9' -Actual $v[0] -Message 'installed version untouched by the refusal'
    }

    Invoke-Scenario 'Upgrade bootstraps an install with no version recorded' {
        Reset-TestDatabase
        Invoke-Sql -File 'install\00-create-schema.sql' -Database 'master' `
                   -Vars @("DatabaseName=$DatabaseName") | Out-Null
        Invoke-Sql -File 'install\01-create-collectors.sql' -Database $DatabaseName | Out-Null

        $u = Invoke-Install @('-Mode', 'Upgrade', '-SkipJobs')
        Assert-Equal -Expected 0 -Actual $u.ExitCode -Message 'bootstrap upgrade succeeds'
        Assert-True -Condition ($u.Output -match '1\.0\.0') -Message 'output names the assumed version'

        $prev = Invoke-Sql -Query "SELECT TOP 1 PreviousVersion FROM [SQLHealthMonitor].[monitor].[SchemaVersion] ORDER BY Id;"
        Assert-Equal -Expected '1.0.0' -Actual $prev[0] -Message '1.0.0 recorded as the starting point'
    }

    Invoke-Scenario 'Upgrade refuses when the database does not exist' {
        Reset-TestDatabase
        $u = Invoke-Install @('-Mode', 'Upgrade', '-SkipJobs')
        Assert-Equal -Expected 1 -Actual $u.ExitCode -Message 'no silent fallback to Fresh'
        Assert-True -Condition ($u.Output -match 'Fresh') -Message 'points the user at -Mode Fresh'
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-Install.ps1
```
Expected: FAIL — `Install.ps1` has no `-Mode` parameter, so it errors with a binding error.

- [ ] **Step 3: Rewrite `deploy/Install.ps1`**

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Installs or upgrades SQL Health Monitor on a SQL Server instance.

.DESCRIPTION
    All monitoring logic, scheduling and email delivery run inside SQL Server.

    -Mode Status   read-only: compares installed version to the repo VERSION,
                   lists Agent jobs and their schedules, reports pending migrations.
    -Mode Upgrade  runs the idempotent install chain plus any pending migrations.
                   Preserves collected data, operator configuration and job schedules.
    -Mode Fresh    drops the six Agent jobs and the database, then installs from
                   scratch. Requires -Force.

.PARAMETER ServerInstance
    SQL Server instance (e.g. "localhost", "SERVER\INSTANCE", "SERVER,1433").

.PARAMETER Database
    Target database name. Default: SQLHealthMonitor. Note that 33 of the SQL
    files hardcode this name (see spec section 9); a different value is only
    honoured by -Mode Fresh.

.PARAMETER Mode
    Status, Upgrade (default) or Fresh.

.PARAMETER Force
    Required by -Mode Fresh. Also permits a downgrade.

.PARAMETER ResetSchedules
    Let the repository own the SQL Agent job schedules again, discarding any
    schedule you adjusted. Default: off.

.PARAMETER SkipJobs
    Do not run install\04-create-jobs.sql. For instances without SQL Agent
    (Azure SQL Managed Instance) and for the LocalDB test harness.

.PARAMETER AssumeVersion
    Version to record for an installation that predates version tracking.
    Default: 1.0.0.

.PARAMETER BackupPath
    Directory for a BACKUP DATABASE taken before anything is changed. If not
    supplied, row counts are still reported so you can verify nothing was lost.

.EXAMPLE
    .\Install.ps1 -ServerInstance "SQLSERVER01" -Mode Status
    .\Install.ps1 -ServerInstance "SQLSERVER01"
    .\Install.ps1 -ServerInstance "SQLSERVER01" -Mode Fresh -Force
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ServerInstance,

    [string]$Database = "SQLHealthMonitor",

    [ValidateSet('Status', 'Upgrade', 'Fresh')]
    [string]$Mode = 'Upgrade',

    [switch]$Force,
    [switch]$ResetSchedules,
    [switch]$SkipJobs,

    [string]$AssumeVersion = '1.0.0',
    [string]$BackupPath,

    [switch]$SqlAuth,
    [string]$Login,
    [string]$Password
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent

# ---- sqlcmd -----------------------------------------------------------------

$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
if (-not $sqlcmd) {
    Write-Error "sqlcmd not found. Install SQL Server Command Line Utilities: https://aka.ms/sqlcmdinstall"
    exit 1
}

$authArgs = if ($SqlAuth) { @("-U", $Login, "-P", $Password) } else { @("-E") }
$baseArgs = @("-S", $ServerInstance) + $authArgs + @("-b", "-V", "1")

# ---- version helpers --------------------------------------------------------

$versionFile = Join-Path $repoRoot 'VERSION'
if (-not (Test-Path $versionFile)) {
    Write-Error "VERSION file not found at $versionFile."
    exit 1
}
$repoVersion = (Get-Content $versionFile -Raw).Trim()

function Get-GitCommit {
    # Returns $null when there is no .git directory -- someone who downloaded a
    # ZIP should still be able to install.
    try {
        if (-not (Test-Path (Join-Path $repoRoot '.git'))) { return $null }
        $hash = & git -C $repoRoot rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $hash) { return $null }
        return $hash.Trim()
    } catch {
        return $null
    }
}
$gitCommit = Get-GitCommit

function Compare-SemVer {
    # -1 / 0 / 1, and never throws -- "1.2.0-rc1" and anything unparseable fall
    # back to string comparison rather than crashing the install.
    param([string]$Left, [string]$Right)

    $rx = '^(\d+)\.(\d+)\.(\d+)(?:-(.+))?$'
    $l = [regex]::Match($Left, $rx)
    $r = [regex]::Match($Right, $rx)

    if (-not $l.Success -or -not $r.Success) {
        return [Math]::Sign([string]::Compare($Left, $Right, [System.StringComparison]::OrdinalIgnoreCase))
    }

    foreach ($i in 1, 2, 3) {
        $delta = [int]$l.Groups[$i].Value - [int]$r.Groups[$i].Value
        if ($delta -ne 0) { return [Math]::Sign($delta) }
    }

    $lp = $l.Groups[4].Success
    $rp = $r.Groups[4].Success
    if ($lp -and -not $rp) { return -1 }   # 1.2.0-rc1 sorts below 1.2.0
    if ($rp -and -not $lp) { return 1 }
    if ($lp -and $rp) {
        return [Math]::Sign([string]::Compare($l.Groups[4].Value, $r.Groups[4].Value,
                                             [System.StringComparison]::OrdinalIgnoreCase))
    }
    return 0
}

# ---- sql execution ----------------------------------------------------------

function Invoke-SqlQuery {
    param([string]$Query, [string]$Db = 'master')
    $out = & $sqlcmd @baseArgs -d $Db -h -1 -W -Q $Query 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd query failed: $($out | Out-String)" }
    $lines = @($out | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -ne '' })
    if ($lines.Count -eq 0) { return $null }
    return $lines[0]
}

function Invoke-SqlFile {
    param([string]$RelativePath, [string]$Db)

    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path $path)) {
        Write-Warning "  SKIP (not found): $RelativePath"
        return 0
    }

    Write-Host "  $RelativePath" -NoNewline
    $vars = @(
        "DatabaseName=$Database",
        "ResetSchedules=$(if ($ResetSchedules) { 1 } else { 0 })",
        "Version=$repoVersion",
        "Mode=$Mode",
        "Commit=$gitCommit"
    )
    $args = @($baseArgs) -d $Db
    foreach ($v in $vars) { $args += @('-v', $v) }
    $args += @('-i', $path)

    $out = & $sqlcmd @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host ($out | Out-String) -ForegroundColor Red
        return 1
    }
    Write-Host " OK" -ForegroundColor Green
    return 0
}

# ---- database state ---------------------------------------------------------

function Get-DatabaseExists {
    $r = Invoke-SqlQuery "SELECT CAST(CASE WHEN DB_ID(N'$Database') IS NULL THEN 0 ELSE 1 END AS VARCHAR(1));"
    return ($r -eq '1')
}

function Get-InstalledVersion {
    # $null means "no version recorded" -- either a pre-tracking install or none at all.
    $q = @"
IF OBJECT_ID('[monitor].[SchemaVersion]','U') IS NULL
    SELECT CAST(NULL AS VARCHAR(20));
ELSE
    SELECT [monitor].[fn_GetInstalledVersion]();
"@
    return (Invoke-SqlQuery $q $Database)
}

function Get-RowCounts {
    $tables = 'CpuHistory', 'MemoryHistory', 'DiskHistory', 'AlertHistory', 'Incidents', 'BaselineCapture'
    $result = @{}
    foreach ($t in $tables) {
        $q = "SELECT CAST(CASE WHEN OBJECT_ID('[monitor].[$t]','U') IS NULL THEN -1 ELSE 1 END AS VARCHAR(1));"
        if ((Invoke-SqlQuery $q $Database) -eq '1') {
            $result[$t] = Invoke-SqlQuery "SELECT CAST(COUNT_BIG(*) AS VARCHAR(20)) FROM [monitor].[$t];" $Database
        }
    }
    return $result
}

function Write-Report {
    param($Before, $After)
    if (-not $Before) { return }
    Write-Host ""
    Write-Host "  Data check:" -ForegroundColor Cyan
    foreach ($k in $Before.Keys) {
        $b = $Before[$k]
        $a = if ($After -and $After.ContainsKey($k)) { $After[$k] } else { '?' }
        $marker = if ($a -eq '?') { '?' } elseif ([long]$a -ge [long]$b) { '+' } else { '!' }
        Write-Host ("    {0,-16} {1,10} -> {2,10} {3}" -f $k, $b, $a, $marker)
    }
    Write-Host "    (a '!' means rows disappeared -- investigate before deploying further)"
}

# ---- install chain ----------------------------------------------------------

$jobScript = 'install\04-create-jobs.sql'
$scripts = @(
    "install\00-create-schema.sql",
    $jobScript,
    "install\01-create-collectors.sql",
    "install\02-create-reports.sql",
    "install\03-create-alerts.sql",
    "install\05-configure.sql",
    "install\06-alert-history.sql",
    "install\07-baselines.sql",
    "install\08-extended-schema.sql",
    "install\09-uptime-tracker.sql",
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
    "install\10-record-version.sql"
)
if ($SkipJobs) { $scripts = $scripts | Where-Object { $_ -ne $jobScript } }

$migrationRx = '^V(\d+)_(\d+)_(\d+)__(.+)\.sql$'

function Get-PendingMigrations {
    param([string]$InstalledVersion)
    $dir = Join-Path $repoRoot 'install\migrations'
    if (-not (Test-Path $dir)) { return @() }
    $pending = @()
    foreach ($f in Get-ChildItem $dir -Filter '*.sql') {
        $m = [regex]::Match($f.Name, $migrationRx)
        if (-not $m.Success) {
            Write-Warning "  Ignoring migration with unrecognised name: $($f.Name)"
            continue
        }
        $v = "$($m.Groups[1].Value).$($m.Groups[2].Value).$($m.Groups[3].Value)"
        $applied = Invoke-SqlQuery "SELECT COUNT(*) FROM [monitor].[AppliedMigrations] WHERE FileName = N'$($f.Name)';" $Database
        $isNew = $InstalledVersion -and ((Compare-SemVer $v $InstalledVersion) -gt 0)
        if (-not $installedHasRow -and $isNew) { $pending += [pscustomobject]@{ File = $f.Name; Version = $v } }
        elseif ($applied -eq '0' -and $isNew) { $pending += [pscustomobject]@{ File = $f.Name; Version = $v } }
    }
    return $pending
}

# ---- modes ------------------------------------------------------------------

Write-Host ""
Write-Host "SQL Health Monitor - $($Mode)" -ForegroundColor Cyan
Write-Host "  Server  : $ServerInstance"
Write-Host "  Database: $Database"
Write-Host "  Repo    : $repoVersion $(if ($gitCommit) { "($gitCommit)" } else { '(no git)' })"
Write-Host "  Auth    : $(if ($SqlAuth) { 'SQL (' + $Login + ')' } else { 'Windows' })"
Write-Host ""

$dbExists = Get-DatabaseExists
$installedVersion = if ($dbExists) { Get-InstalledVersion } else { $null }

if ($Mode -eq 'Status') {
    Write-Host "  Installed: $(if ($installedVersion) { $installedVersion } elseif ($dbExists) { 'unknown (pre-dates version tracking)' } else { 'not installed' })"
    Write-Host ""
    if (-not $dbExists) {
        Write-Host "  Database '$Database' does not exist." -ForegroundColor Yellow
        Write-Host "  To install it:  .\Install.ps1 -ServerInstance `"$ServerInstance`" -Mode Fresh -Force"
        exit 0
    }
    $rows = Get-RowCounts
    Write-Host "  Collected rows:" -ForegroundColor Cyan
    foreach ($k in $rows.Keys) { Write-Host ("    {0,-16} {1}" -f $k, $rows[$k]) }
    Write-Host ""
    $pend = Get-PendingMigrations -InstalledVersion $installedVersion
    if ($pend) {
        Write-Host "  Pending migrations:" -ForegroundColor Yellow
        foreach ($p in $pend) { Write-Host "    $($p.Version)  $($p.File)" }
    } else {
        Write-Host "  Pending migrations: none"
    }
    Write-Host ""
    if ($Database -ne 'SQLHealthMonitor') {
        Write-Warning "Database name is '$Database' but most SQL files hardcode 'SQLHealthMonitor' (spec section 9). Upgrade is not supported for custom names."
    }
    exit 0
}

if ($Mode -eq 'Fresh') {
    if (-not $Force) {
        Write-Error "-Mode Fresh deletes all collected data and requires -Force. Nothing was changed."
        exit 1
    }
    if ($dbExists) {
        Write-Host "  Dropping database $Database..." -ForegroundColor Yellow
        & $sqlcmd @baseArgs -d master -b -Q "IF DB_ID(N'$Database') IS NOT NULL BEGIN ALTER DATABASE [$Database] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$Database]; END;" | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Error "Could not drop the database."; exit 1 }
    }
    $installedVersion = $null
}

if ($Mode -eq 'Upgrade') {
    if (-not $dbExists) {
        Write-Error "Database '$Database' does not exist. Run: .\Install.ps1 -ServerInstance `"$ServerInstance`" -Mode Fresh -Force"
        exit 1
    }

    if (-not $installedVersion) {
        Write-Warning "No version recorded. This installation predates version tracking; recording it as $AssumeVersion."
        Write-Warning "Override with -AssumeVersion if that is not what is installed."
        $installedVersion = $AssumeVersion
    }

    $cmp = Compare-SemVer $repoVersion $installedVersion
    if ($cmp -lt 0) {
        if (-not $Force) {
            Write-Error "This checkout is version $repoVersion but the database has $installedVersion."
            Write-Error "Downgrading would revert procedure fixes. Switch to the matching tag (git checkout v$installedVersion), or pass -Force to proceed anyway."
            exit 1
        }
        Write-Warning "Downgrading from $installedVersion to $repoVersion because -Force was supplied."
    } elseif ($cmp -eq 0) {
        Write-Host "  Already at $repoVersion; re-running for idempotency." -ForegroundColor DarkGray
    } else {
        Write-Host "  Upgrading $installedVersion -> $repoVersion" -ForegroundColor Green
    }

    if ($Database -ne 'SQLHealthMonitor') {
        Write-Warning "Database name is '$Database' but most SQL files hardcode 'SQLHealthMonitor' (spec section 9). Custom names are not supported in Upgrade mode."
    }
}

# ---- optional backup --------------------------------------------------------

if ($Mode -ne 'Fresh' -and $BackupPath) {
    if (-not (Test-Path $BackupPath)) {
        Write-Error "BackupPath '$BackupPath' does not exist. Nothing was changed."
        exit 1
    }
    $bak = Join-Path $BackupPath "$Database`_pre$repoVersion`_$(Get-Date -Format yyyyMMddHHmmss).bak"
    Write-Host "  Backing up $Database to $bak ..." -ForegroundColor Yellow
    & $sqlcmd @baseArgs -d master -b -Q "BACKUP DATABASE [$Database] TO DISK = N'$bak' WITH INIT, COMPRESSION;" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Backup failed. Nothing was changed -- fix the backup and retry."
        exit 1
    }
}

$before = Get-RowCounts

# ---- run the chain ----------------------------------------------------------

$errors = 0
Push-Location $repoRoot
try {
    $total = $scripts.Count
    $i = 0
    foreach ($rel in $scripts) {
        $i++
        $dbArg = if ($rel -eq 'install\00-create-schema.sql') { 'master' } else { $Database }
        $errors += Invoke-SqlFile -RelativePath $rel -Db $dbArg
    }
}
finally {
    Pop-Location
}

if ($errors -gt 0) {
    Write-Host ""
    Write-Host "Deployment stopped: $errors script(s) failed. The recorded version was NOT advanced," -ForegroundColor Red
    Write-Host "so -Mode Status will still report the previous one. Re-run -Mode Upgrade after fixing the cause."
    exit 1
}

# ---- migrations -------------------------------------------------------------

$pend = Get-PendingMigrations -InstalledVersion $installedVersion
if ($pend) {
    Write-Host ""
    Write-Host "  Applying $($pend.Count) migration(s):" -ForegroundColor Cyan
    foreach ($p in $pend) {
        Write-Host "  $($p.File)" -NoNewline
        $rel = "install\migrations\$($p.File)"
        $dbArg = 'master'
        $out = & $sqlcmd @baseArgs -d $dbArg -b `
                  -v "DatabaseName=$Database" -v "Version=$($p.Version)" `
                  -i (Join-Path $repoRoot $rel) 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host " FAILED" -ForegroundColor Red
            Write-Host ($out | Out-String) -ForegroundColor Red
            exit 1
        }
        Write-Host " OK" -ForegroundColor Green
        Invoke-SqlQuery "INSERT INTO [monitor].[AppliedMigrations] (FileName, Version) VALUES (N'$($p.File)', N'$($p.Version)');" $Database | Out-Null
    }
}

# ---- report -----------------------------------------------------------------

$after = Get-RowCounts
Write-Report -Before $before -After $after

Write-Host ""
if ($Mode -eq 'Fresh') {
    Write-Host "Installation complete at $repoVersion." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Configure Database Mail in SQL Server (if not already done)"
    Write-Host "  2. Update Email.ProfileName and Email.Recipients in [monitor].[Settings]"
    Write-Host "  3. Verify jobs: .\Install.ps1 -ServerInstance `"$ServerInstance`" -Mode Status"
} else {
    Write-Host "Upgrade complete: $repoVersion." -ForegroundColor Green
    Write-Host "  Verify any time with: .\Install.ps1 -ServerInstance `"$ServerInstance`" -Mode Status"
}
```

- [ ] **Step 4: Fix the `$installedHasRow` reference**

The `Get-PendingMigrations` function as written references an undefined `$installedHasRow` under `Set-StrictMode`, which will throw. Replace the body of the selection logic with:

```powershell
        $applied = Invoke-SqlQuery "SELECT COUNT(*) FROM [monitor].[AppliedMigrations] WHERE FileName = N'$($f.Name)';" $Database
        $isNew  = $InstalledVersion -and ((Compare-SemVer $v $InstalledVersion) -gt 0)
        if ($isNew -and $applied -eq '0') {
            $pending += [pscustomobject]@{ File = $f.Name; Version = $v }
        }
```

Run the test suite again and confirm no `Set-StrictMode` error appears.

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-Install.ps1
```
Expected: all `Install.ps1` scenarios PASS; summary `16 passed, 0 failed`.

- [ ] **Step 6: Manually verify `Status` against your real server**

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File deploy/Install.ps1 -ServerInstance "<your-instance>" -Mode Status
```
Expected: it names the assumed `1.0.0`, lists your row counts and the six jobs' schedules, and **writes nothing**.

- [ ] **Step 7: Commit**

```bash
git add deploy/Install.ps1 tests/Test-Install.ps1
git commit -m "feat: add Status/Upgrade/Fresh modes to Install.ps1

Upgrade reads the installed version, refuses a downgrade unless -Force,
runs the idempotent chain plus pending migrations, and reports row counts
so a lost row is visible. Fresh requires -Force and never runs implicitly.
Status is read-only and writes nothing.

Version comparison handles pre-release suffixes and unparseable strings
without throwing, and CommitHash is simply null outside a git checkout so
ZIP downloads still install.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 9: Uninstall and validation

**Files:**
- Modify: `deploy/Uninstall.ps1`
- Modify: `validate_installation.sql`

**Interfaces:**
- Consumes: `fn_GetInstalledVersion()` (Task 2) — `Uninstall.ps1` reports it before dropping.
- Produces: nothing new.

- [ ] **Step 1: Make `Uninstall.ps1` report the version and honour `-Database`**

`deploy/Uninstall.ps1` currently hardcodes `SQLHealthMonitor` in its prompt and never accepts `-Database`, so it can drop a different database than the one installed. Add the parameter and report the version being destroyed:

```powershell
    [string]$Database = "SQLHealthMonitor",
```

and replace the confirmation block:

```powershell
$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
if (-not $sqlcmd) {
    Write-Error "sqlcmd not found. Install SQL Server Command Line Utilities."
    exit 1
}

$authArgs = if ($SqlAuth) { @("-U", $Login, "-P", $Password) } else { @("-E") }
$script   = Join-Path $PSScriptRoot "..\install\Uninstall.sql"

# Best effort: report what is about to be destroyed.
try {
    $q = @"
IF DB_ID(N'$Database') IS NOT NULL
   AND OBJECT_ID('[monitor].[SchemaVersion]','U') IS NOT NULL
    SELECT [monitor].[fn_GetInstalledVersion]();
"@
    $v = & $sqlcmd -S $ServerInstance @authArgs -d $Database -h -1 -W -b -V 1 -Q $q 2>&1
    $installed = if ($LASTEXITCODE -eq 0) { ($v | Out-String).Trim() } else { '' }
} catch {
    $installed = ''
}

Write-Host ""
Write-Host "SQL Health Monitor - Uninstall" -ForegroundColor Yellow
Write-Host "  Server  : $ServerInstance"
Write-Host "  Database: $Database"
if ($installed) { Write-Host "  Version : $installed" }
Write-Host ""
Write-Warning "This will permanently delete all SQL Agent Jobs and the '$Database' database."
$confirm = Read-Host "Type YES to continue"
if ($confirm -ne 'YES') { Write-Host "Cancelled."; exit 0 }

$output = & $sqlcmd -S $ServerInstance @authArgs -d master -b -V 1 -v "DatabaseName=$Database" -i $script 2>&1
$rc     = $LASTEXITCODE
```

- [ ] **Step 2: Make `install/Uninstall.sql` take the database name**

Read the file first, then replace every literal `SQLHealthMonitor` with `$(DatabaseName)` and add at the top:

```sql
:setvar DatabaseName "SQLHealthMonitor"
```

```bash
grep -n "SQLHealthMonitor" install/Uninstall.sql
```
Expected: the database name in the `USE` statement and the `DB_ID`/`DROP DATABASE` logic. Job names inside are the `SQL Health Monitor - ...` strings — leave those alone, they use spaces and are not the database name.

- [ ] **Step 3: Extend `validate_installation.sql` with version checks**

Append before the final output block:

```sql
----------------------------------------------------------------------
-- VERSION TRACKING
----------------------------------------------------------------------

IF OBJECT_ID('monitor.SchemaVersion', 'U') IS NULL
    PRINT 'WARN: [monitor].[SchemaVersion] not found - this install predates version tracking.'
ELSE
BEGIN
    DECLARE @Installed VARCHAR(20) = [monitor].[fn_GetInstalledVersion]();
    IF @Installed IS NULL
        PRINT 'WARN: No version recorded. Run Install.ps1 -Mode Upgrade to stamp it.'
    ELSE
        PRINT 'OK: Installed version ' + @Installed;
END;

IF OBJECT_ID('monitor.AppliedMigrations', 'U') IS NULL
    PRINT 'WARN: [monitor].[AppliedMigrations] not found.'
GO
```

- [ ] **Step 4: Verify the validation script still runs**

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-Install.ps1
```
Expected: still `16 passed, 0 failed` — these changes touch no code the harness runs.

Then, against your real server:
```bash
sqlcmd -S "<your-instance>" -E -d SQLHealthMonitor -i validate_installation.sql
```
Expected: `OK: Installed version 1.0.0` (or your current version), and no new warnings.

- [ ] **Step 5: Commit**

```bash
git add deploy/Uninstall.ps1 install/Uninstall.sql validate_installation.sql
git commit -m "fix: Uninstall honours -Database and reports the version being dropped

Uninstall.ps1 had no -Database parameter, so it could destroy a different
database than the one installed. It now names the database and its version
in the confirmation prompt. validate_installation.sql checks the version
tables and says something useful when they are missing.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 10: End-to-end scenarios

**Files:**
- Modify: `tests/Test-Install.ps1`

**Interfaces:**
- Consumes: `Invoke-Install` (Task 8), `Reset-TestDatabase`, `Invoke-Sql` (Task 1).
- Produces: the seven scenarios the spec promises.

- [ ] **Step 1: Add the migration scenario**

```powershell
    Invoke-Scenario 'A migration runs once and is not repeated' {
        Reset-TestDatabase
        $null = Invoke-Install @('-Mode', 'Fresh', '-Force', '-SkipJobs')

        $migDir = Join-Path $RepoRoot 'install\migrations'
        $migName = 'V1_2_0__test-sentinel.sql'
        $migPath = Join-Path $migDir $migName
        $migBody = @"
:setvar DatabaseName "SQLHealthMonitor"
USE [SQLHealthMonitor];
GO
IF OBJECT_ID('monitor.SchemaVersion','U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM [monitor].[AppliedMigrations] WHERE FileName = N'$migName')
BEGIN
    EXEC('CREATE TABLE [monitor].[__MigrationSentinel] (Id INT)');
END
GO
"@
        Set-Content -Path $migPath -Value $migBody -Encoding UTF8

        try {
            $u1 = Invoke-Install @('-Mode', 'Upgrade', '-SkipJobs')
            Assert-Equal -Expected 0 -Actual $u1.ExitCode -Message "first migration run succeeds. Output:`n$($u1.Output)"

            $c = Invoke-Sql -Query "SELECT COUNT(*) FROM [SQLHealthMonitor].[sys].[objects] WHERE name = '__MigrationSentinel';"
            Assert-Equal -Expected '1' -Actual $c[0] -Message 'migration created its object'

            $a = Invoke-Sql -Query "SELECT COUNT(*) FROM [SQLHealthMonitor].[monitor].[AppliedMigrations] WHERE FileName = N'$migName';"
            Assert-Equal -Expected '1' -Actual $a[0] -Message 'migration recorded in AppliedMigrations'

            $u2 = Invoke-Install @('-Mode', 'Upgrade', '-SkipJobs')
            Assert-Equal -Expected 0 -Actual $u2.ExitCode -Message 'second upgrade succeeds'
            $c2 = Invoke-Sql -Query "SELECT COUNT(*) FROM [SQLHealthMonitor].[sys].[objects] WHERE name = '__MigrationSentinel';"
            Assert-Equal -Expected '1' -Actual $c2[0] -Message 'migration did not re-run'
        } finally {
            Remove-Item $migPath -ErrorAction SilentlyContinue
        }
    }
```

- [ ] **Step 2: Add the chain-failure scenario**

This pins Review Focus #3 — a mid-chain failure must not advance the version.

```powershell
    Invoke-Scenario 'A failing script does not advance the recorded version' {
        Reset-TestDatabase
        $null = Invoke-Install @('-Mode', 'Fresh', '-Force', '-SkipJobs')
        $repoVersion = (Get-Content (Join-Path $RepoRoot 'VERSION') -Raw).Trim()

        Invoke-Sql -Query "DELETE FROM [SQLHealthMonitor].[monitor].[SchemaVersion];" `
                   -Database $DatabaseName | Out-Null
        Invoke-Sql -File 'install\10-record-version.sql' -Database $DatabaseName `
                   -Vars @("Version=1.0.0", "Mode=Fresh", "Commit=x") | Out-Null

        $breaker = Join-Path $RepoRoot 'install\99-test-failure.sql'
        Set-Content -Path $breaker -Value "SELECT 1/0 AS Boom;" -Encoding UTF8
        $patched = Join-Path $RepoRoot 'deploy\Install.ps1'
        $original = Get-Content $patched -Raw

        try {
            $withBreaker = $original -replace '("install\\10-record-version\.sql")', @("`"install\\07-broken-test.sql`"", $1)
            Set-Content -Path $patched -Value $withBreaker -Encoding UTF8
            Copy-Item $breaker (Join-Path $RepoRoot 'install\07-broken-test.sql')

            $u = Invoke-Install @('-Mode', 'Upgrade', '-SkipJobs')
            Assert-Equal -Expected 1 -Actual $u.ExitCode -Message 'upgrade reports failure'

            $v = Invoke-Sql -Query "SELECT [SQLHealthMonitor].[monitor].[fn_GetInstalledVersion]();"
            Assert-Equal -Expected '1.0.0' -Actual $v[0] -Message 'version not advanced past a failed run'
        } finally {
            Copy-Item $patched "$patched.bak" -ErrorAction SilentlyContinue
            Set-Content -Path $patched -Value $original -Encoding UTF8
            Remove-Item "$patched.bak", $breaker, (Join-Path $RepoRoot 'install\07-broken-test.sql') -ErrorAction SilentlyContinue
        }
    }
```

If the regex-based patching of `Install.ps1` proves brittle on your PowerShell version, replace it with a direct edit: insert `"install\07-broken-test.sql",` into the `$scripts` array, run, then revert. The assertion is what matters, not the patching mechanism.

- [ ] **Step 3: Add the job-schedule scenario, skipped without a real instance**

```powershell
    Invoke-Scenario 'Upgrade preserves a hand-adjusted job schedule' {
        if (-not $ServerInstance) {
            Skip-Scenario 'needs a real instance (LocalDB has no SQL Agent) - run with -ServerInstance to enable'
            return
        }
        Reset-TestDatabase
        $null = Invoke-Install @('-Mode', 'Fresh', '-Force')

        # Move the daily report from 07:00 to 06:30, as an operator would.
        Invoke-Sql -Query @"
DECLARE @JobId UNIQUEIDENTIFIER = (SELECT job_id FROM msdb.dbo.sysjobs WHERE name = N'SQL Health Monitor - Daily Report');
DECLARE @SchedId INT = (SELECT schedule_id FROM msdb.dbo.sysjobschedules WHERE job_id = @JobId);
UPDATE msdb.dbo.sysschedules SET active_start_time = 63000 WHERE schedule_id = @SchedId;
"@ | Out-Null

        $null = Invoke-Install @('-Mode', 'Upgrade')

        $t = Invoke-Sql -Query @"
DECLARE @JobId UNIQUEIDENTIFIER = (SELECT job_id FROM msdb.dbo.sysjobs WHERE name = N'SQL Health Monitor - Daily Report');
DECLARE @SchedId INT = (SELECT schedule_id FROM msdb.dbo.sysjobschedules WHERE job_id = @JobId);
SELECT CAST(active_start_time AS VARCHAR(10)) FROM msdb.dbo.sysschedules WHERE schedule_id = @SchedId;
"@
        Assert-Equal -Expected '63000' -Actual $t[0] -Message '06:30 schedule survived the upgrade'

        # -ResetSchedules gives the repo defaults back.
        $null = Invoke-Install @('-Mode', 'Upgrade', '-ResetSchedules')
        $t2 = Invoke-Sql -Query @"
DECLARE @JobId UNIQUEIDENTIFIER = (SELECT job_id FROM msdb.dbo.sysjobs WHERE name = N'SQL Health Monitor - Daily Report');
DECLARE @SchedId INT = (SELECT schedule_id FROM msdb.dbo.sysjobschedules WHERE job_id = @JobId);
SELECT CAST(active_start_time AS VARCHAR(10)) FROM msdb.dbo.sysschedules WHERE schedule_id = @SchedId;
"@
        Assert-Equal -Expected '70000' -Actual $t2[0] -Message '-ResetSchedules restored 07:00'
    }
```

- [ ] **Step 4: Run the LocalDB suite**

Run:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-Install.ps1
```
Expected: `18 passed, 0 failed, 1 skipped`, and the summary names the job scenario as skipped.

- [ ] **Step 5: Run the full suite against a real instance**

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Test-Install.ps1 -ServerInstance "<your-instance>" -SqlAuth -Login "<user>" -Password "<password>"
```
Expected: `19 passed, 0 failed, 0 skipped`.

**Do this on a throwaway instance.** The scenarios call `-Mode Fresh`, which drops the database.

- [ ] **Step 6: Commit**

```bash
git add tests/Test-Install.ps1
git commit -m "test: cover migrations, mid-chain failure and job schedules

Adds the three end-to-end scenarios the install path had no coverage for:
a migration applies exactly once, a failing script leaves the recorded
version alone, and a hand-adjusted job schedule survives an upgrade
unless -ResetSchedules is passed.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 11: Documentation and changelog

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `README.md`, `README-PTBR.md`
- Modify: `docs/INSTALL.md`

**Interfaces:** none — documentation only.

- [ ] **Step 1: Add the `1.1.0` changelog entry**

At the top of `CHANGELOG.md`, below the header block and above `## [1.0.0]`:

```markdown
## [1.1.0] - 2026-10-05

### Added
- `VERSION` file and git tags as the single source of the deployed version
- `[monitor].[SchemaVersion]` and `[monitor].[AppliedMigrations]` tracking tables
- `[monitor].[fn_GetInstalledVersion]()` helper
- `install/10-record-version.sql`, run last in the chain
- `install/migrations/` for changes that cannot be written idempotently
- `Install.ps1 -Mode Status | Upgrade | Fresh`, plus `-Force`, `-ResetSchedules`,
  `-SkipJobs`, `-AssumeVersion` and `-BackupPath`
- `tests/Test-Install.ps1`, a LocalDB-backed scenario suite

### Changed
- Install scripts reconcile table columns on existing installations
- `05-configure.sql` inserts defaults without overwriting existing values
- `04-create-jobs.sql` updates job steps on upgrade and leaves schedules alone
- `00-create-schema.sql` and `04-create-jobs.sql` take the database name from
  `:setvar` instead of hardcoding it

### Fixed
- Re-running the installer no longer wipes `Settings`, `Thresholds` or job schedules
- New columns now reach existing installations instead of silently being skipped
```

- [ ] **Step 2: Document the modes in `docs/INSTALL.md`**

Add a section, in both `README.md` and `README-PTBR.md`, replacing any text that implies re-running the installer is the way to update:

```markdown
### Installing, upgrading, checking

```powershell
# What is installed, and what is this checkout?
.\deploy\Install.ps1 -ServerInstance "SQLSERVER01" -Mode Status

# Apply the current version over an existing install (the usual case)
.\deploy\Install.ps1 -ServerInstance "SQLSERVER01"

# Start over -- deletes all collected data, configuration and jobs
.\deploy\Install.ps1 -ServerInstance "SQLSERVER01" -Mode Fresh -Force
```

`-Mode Upgrade` preserves collected metrics, your `Settings` and `Thresholds`,
and any SQL Agent schedule you have adjusted. It refuses to run if this
checkout is older than what the database has, unless you pass `-Force`.

**Install from a tag, not from `main`.** `git clone --branch v1.1.0` gives you
exactly that release. `-Mode Status` prints the version and commit it will deploy.
```

Write the Portuguese section in the same place in `README-PTBR.md` — the two
READMEs are kept in parallel throughout, so do not add it to one only.

- [ ] **Step 3: Document the release process**

In `docs/INSTALL.md`, add:

```markdown
## Publishing a release

1. Update `CHANGELOG.md` with the new version.
2. Update the `VERSION` file to match.
3. Commit both.
4. `git tag -a v1.1.0 -m "v1.1.0"` and `git push --tags`.
5. Create the GitHub Release from the tag.

`VERSION` and `CHANGELOG.md` must always agree -- `Install.ps1` reads `VERSION`
and nothing checks that the changelog was updated.
```

- [ ] **Step 4: Note the default-value caveat in the README**

Add to the upgrade section:

```markdown
> **Note:** configuration values in `[monitor].[Settings]` and
> `[monitor].[Thresholds]` belong to you -- an upgrade inserts new defaults but
> never overwrites what you have set. If a release changes a default value,
> existing installations keep their current one on purpose. See
> `install/migrations/README.md`.
```

- [ ] **Step 5: Tag the release**

```bash
git add -A
git commit -m "docs: document install modes and release process for 1.1.0

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git tag -a v1.1.0 -m "v1.1.0"
```

Do not push unless the user asks. Verify the tag landed:

```bash
git tag -l
```
Expected: `v1.1.0`.

---

## Self-Review

**Spec coverage**

| Spec section | Task |
|---|---|
| 4.1 idempotency + migrations escape hatch | 4, 5, 6, 7, 10 |
| 4.2 `VERSION` file | 1 |
| 4.2.1 tags | 11 (Step 5), README |
| 4.3 conservative bootstrap | 8 (Step 1, Step 3), 10 |
| 4.4 downgrade refused | 8, 10 |
| 5.2 tracking tables + function | 2 |
| 5.3 `10-record-version.sql` | 3 |
| 5.4 `Install.ps1` modes | 8 |
| 5.5 jobs | 7, 10 |
| 5.6 `MERGE` ×3 | 6 |
| 5.7 column reconciliation | 5 |
| 6 execution order | 8 |
| 7 seven scenarios | 10 (+ 2, 3, 5, 6, 8 for the units) |
| 8 files touched | all |
| 9 out of scope | respected — no task widens beyond `00`/`04`/`10` |

**Review Focus coverage**

1. Pre-release version — `Compare-SemVer` in Task 8, never throws.
2. No `.git` — `Get-GitCommit` in Task 8 returns `$null`.
3. Mid-chain failure — Task 3's design plus Task 10 Step 2.
4. Backup failure — Task 8, exits before `$before = Get-RowCounts`.
5. Older table missing a column — Task 5.

**Type consistency:** `fn_GetInstalledVersion()` returns `VARCHAR(20)` (Task 2), consumed as a string everywhere. `Invoke-Sql` returns `string[]`; every caller indexes `$r[0]`. `Invoke-Install` returns an object with `ExitCode` and `Output`. sqlcmd variable names `DatabaseName`, `ResetSchedules`, `Version`, `Mode`, `Commit` are set in Task 8 and read in Tasks 2, 3, 7.

**Known rough edge, deliberate:** Task 8 Step 4 patches a `$installedHasRow` typo after the fact rather than writing it correctly the first time. It is called out explicitly so the implementer does not miss it.