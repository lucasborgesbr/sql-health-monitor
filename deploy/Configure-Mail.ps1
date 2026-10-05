#Requires -Version 5.1
<#
.SYNOPSIS
    Points SQL Health Monitor at an existing Database Mail profile, creating
    one only if the instance has none.

.DESCRIPTION
    Most instances already have a Database Mail profile -- a relay, an SMTP
    gateway, something the DBA set up. This script finds it and just writes
    the profile name and recipients into [monitor].[Settings].

    If no profile exists at all, it says so and tells you what to supply to
    have one created, instead of failing obscurely.

    Re-runnable: nothing is duplicated.

.PARAMETER ServerInstance
    SQL Server instance. Default: localhost,1433

.PARAMETER ProfileName
    Profile to use. Omit to auto-detect: the only profile if there is one,
    otherwise you are asked to choose.

.PARAMETER Recipients
    Comma-separated. Written to Email.Recipients. Omit to leave it alone.

.PARAMETER Username
    SMTP user, needed only when creating a profile.

.PARAMETER FromAddress
    Envelope sender. Must match -Username on Gmail or the mail is rejected.

.PARAMETER AppPassword
    The SMTP password. Omit to be prompted securely -- passing it as a
    parameter puts it in your shell history.

.PARAMETER SmtpServer
    Default: smtp.gmail.com

.PARAMETER Port
    Default: 587 (STARTTLS)

.PARAMETER CreateProfile
    Create a profile even though one already exists.

.PARAMETER ListProfiles
    Show the available profiles and exit.

.PARAMETER SkipTest
    Do not send a test message.

.EXAMPLE
    # Already have a relay -- point the monitor at it
    .\Configure-Mail.ps1 -Recipients "dba@corp.com"

    # See what is available
    .\Configure-Mail.ps1 -ListProfiles

    # Nothing configured yet -- create one
    .\Configure-Mail.ps1 -Recipients "you@gmail.com" -Username "you@gmail.com"
#>
[CmdletBinding()]
param(
    [string]$ServerInstance = "",
    [string]$Database       = "SQLHealthMonitor",

    [switch]$SqlAuth,
    [string]$Login,
    [string]$Password,

    [string]$ProfileName,
    [string]$Recipients,

    [string]$Username,
    [string]$FromAddress,
    [string]$SmtpServer = "smtp.gmail.com",
    [int]$Port          = 587,
    [string]$AppPassword,
    [string]$AccountName = "SQLHealthMonitor_SMTP",

    [switch]$CreateProfile,
    [switch]$ListProfiles,
    [switch]$SkipTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
if (-not $sqlcmd) {
    Write-Error "sqlcmd not found. Install SQL Server Command Line Utilities: https://aka.ms/sqlcmdinstall"
    exit 1
}

$authArgs = if ($SqlAuth) {
    @("-U", $Login, "-P", $Password)
} elseif ($env:SQLCMDUSER) {
    # No explicit auth asked for, but SQLCMDUSER is set -- let sqlcmd read the
    # SQLCMDSERVER / SQLCMDUSER / SQLCMDPASSWORD environment variables itself.
    # Passing -E here would force Windows auth and silently override them.
    @()
} else {
    @("-E")
}

$serverArg = if ($ServerInstance) { @("-S", $ServerInstance) } else { @() }
if (-not $serverArg -and $env:SQLCMDSERVER) { $serverArg = @() }
elseif (-not $serverArg) { $serverArg = @("-S", "localhost,1433") }

$baseArgs = $serverArg + $authArgs + @("-b", "-V", "1", "-C")

function Invoke-Sql {
    param([string]$Query, [string]$Db = 'msdb')
    # SET NOCOUNT ON, otherwise "(N rows affected)" pollutes the returned lines.
    $out = & $sqlcmd @baseArgs -d $Db -h -1 -W -Q "SET NOCOUNT ON; $Query" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd failed on '$Db':`n$($out | Out-String)" }
    return @($out | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -ne '' -and $_ -notmatch '^\(\d+ rows? affected\)$' })
}

function Quote-Sql { param([string]$V) return "'" + $V.Replace("'", "''") + "'" }

function Get-ExistingProfiles {
    $rows = Invoke-Sql -Query "SELECT name FROM msdb.dbo.sysmail_profile ORDER BY name;"
    return @($rows | Where-Object { $_ -and $_ -ne 'NULL' })
}

Write-Host ""
Write-Host "SQL Health Monitor - Configure Mail" -ForegroundColor Cyan
Write-Host "  Server    : $(if ($ServerInstance) { $ServerInstance } elseif ($env:SQLCMDSERVER) { "$env:SQLCMDSERVER (from SQLCMDSERVER)" } else { 'localhost,1433' })"
Write-Host "  Database  : $Database"
Write-Host ""

# ---- what does this instance already have? ------------------------------------

$profiles = Get-ExistingProfiles

Write-Host "  Database Mail profiles on this instance:" -ForegroundColor Cyan
if ($profiles.Count -eq 0) {
    Write-Host "    (none)" -ForegroundColor Yellow
} else {
    $profiles | ForEach-Object { Write-Host "    - $_" }
}

if ($ListProfiles) { Write-Host ""; exit 0 }

# ---- decide which profile to use ----------------------------------------------

$create = $false
$chosen = $null

if ($CreateProfile) {
    $create = $true
} elseif ($ProfileName) {
    if ($profiles -notcontains $ProfileName) {
        Write-Host ""
        Write-Warning "Profile '$ProfileName' does not exist on this instance."
        Write-Host "  Available: $(if ($profiles.Count) { $profiles -join ', ' } else { '(none)' })"
        Write-Host "  Re-run with -ListProfiles to see them, or -CreateProfile to make one." -ForegroundColor Yellow
        exit 1
    }
    $chosen = $ProfileName
} elseif ($profiles.Count -eq 1) {
    $chosen = $profiles[0]
    Write-Host "  Using the only profile: $chosen" -ForegroundColor Green
} elseif ($profiles.Count -eq 0) {
    $create = $true
} else {
    Write-Host ""
    Write-Host "  More than one profile exists -- which one?" -ForegroundColor Yellow
    for ($i = 0; $i -lt $profiles.Count; $i++) { Write-Host "    [$($i+1)] $($profiles[$i])" }
    $choice = Read-Host "  Number (blank to cancel)"
    if ($choice -notmatch '^\d+$' -or [int]$choice -lt 1 -or [int]$choice -gt $profiles.Count) {
        Write-Host "Cancelled."; exit 0
    }
    $chosen = $profiles[[int]$choice - 1]
}

# ---- create only when there is nothing to point at ---------------------------

if ($create) {
    Write-Host ""
    Write-Host "  No Database Mail profile found on this instance." -ForegroundColor Yellow
    Write-Host "  A profile is a named set of SMTP credentials that sp_send_dbmail can use." -ForegroundColor DarkGray
    Write-Host ""

    if (-not $Username) {
        Write-Host "  To create one, re-run with -Username (and -AppPassword, or be prompted):" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "    # Gmail -- needs 2FA and an App Password from your Google account" -ForegroundColor DarkGray
        Write-Host "    .\Configure-Mail.ps1 -Recipients `"you@gmail.com`" -Username `"you@gmail.com`"" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "    # Company relay" -ForegroundColor DarkGray
        Write-Host "    .\Configure-Mail.ps1 -Recipients `"dba@corp.com`" -Username `"apikey`" ``" -ForegroundColor DarkGray
        Write-Host "        -FromAddress `"ops@corp.com`" -SmtpServer `"smtp.corp.com`" -Port 587" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Or configure Database Mail yourself and re-run this script." -ForegroundColor DarkGray
        exit 1
    }

    if (-not $FromAddress) { $FromAddress = $Username }
    if (-not $chosen) {
        $chosen = $ProfileName
        if (-not $chosen) { $chosen = 'DBA_Mail' }
    }

    # Read the password without echoing it or writing it to shell history.
    if (-not $AppPassword) {
        $secure = Read-Host "SMTP password / App Password (input hidden)" -AsSecureString
        $AppPassword = [System.Net.NetworkCredential]::new('', $secure).Password
    }
    if (-not $AppPassword) { Write-Error "SMTP password is required."; exit 1 }

    Write-Host "  Creating profile '$chosen' with account '$AccountName' -> ${SmtpServer}:${Port}" -ForegroundColor Cyan

    Invoke-Sql -Query "EXEC msdb.dbo.sp_configure 'Database Mail XPs', 1; RECONFIGURE;" | Out-Null
    Write-Host "    Database Mail XPs enabled" -ForegroundColor Green

    # sysmail_update_account_sp cannot rotate the credential on every build, so
    # an existing account is removed and recreated. The account holds no state.
    if ((Invoke-Sql -Query "SELECT COUNT(*) FROM msdb.dbo.sysmail_account WHERE name = $(Quote-Sql $AccountName);")[0] -ne '0') {
        Invoke-Sql -Query @"
DECLARE @aid INT = (SELECT account_id FROM msdb.dbo.sysmail_account WHERE name = $(Quote-Sql $AccountName));
DELETE FROM msdb.dbo.sysmail_profileaccount WHERE account_id = @aid;
DELETE FROM msdb.dbo.sysmail_credential WHERE credential_id IN
    (SELECT credential_id FROM msdb.dbo.sysmail_account WHERE account_id = @aid);
DELETE FROM msdb.dbo.sysmail_account WHERE account_id = @aid;
"@ | Out-Null
        Write-Host "    Existing account removed" -ForegroundColor DarkGray
    }

    Invoke-Sql -Query @"
EXEC msdb.dbo.sysmail_add_account_sp
    @account_name     = $(Quote-Sql $AccountName),
    @description      = 'SQL Health Monitor - report delivery',
    @display_name     = 'SQL Health Monitor',
    @email_address    = $(Quote-Sql $FromAddress),
    @replyto_email    = $(Quote-Sql $FromAddress),
    @mailserver       = $(Quote-Sql $SmtpServer),
    @port             = $Port,
    @username         = $(Quote-Sql $Username),
    @password         = $(Quote-Sql $AppPassword),
    @authentication   = 'Basic',
    @enable_ssl_async = 1;
"@ | Out-Null
    Write-Host "    Account created" -ForegroundColor Green

    Invoke-Sql -Query "EXEC msdb.dbo.sysmail_add_profile_sp @profile_name = $(Quote-Sql $chosen), @description = 'SQL Health Monitor';" | Out-Null
    Write-Host "    Profile created" -ForegroundColor Green

    $profileId = (Invoke-Sql -Query "SELECT profile_id FROM msdb.dbo.sysmail_profile WHERE name = $(Quote-Sql $chosen);")[0]
    Invoke-Sql -Query @"
DECLARE @pid INT = $profileId;
IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysmail_profileaccount WHERE profile_id = @pid)
    EXEC msdb.dbo.sysmail_add_profileaccount_sp
        @profile_id   = @pid,
        @account_name = $(Quote-Sql $AccountName),
        @principal_id = 0;
"@ | Out-Null
    Write-Host "    Account attached to profile" -ForegroundColor Green
}

# ---- write the settings -------------------------------------------------------

Write-Host ""
$settings = @()
if ($chosen)     { $settings += @{ Name = 'ProfileName'; Value = $chosen } }
if ($Recipients) { $settings += @{ Name = 'Recipients';  Value = $Recipients } }

if ($settings.Count -eq 0) {
    Write-Host "  Nothing to change. Pass -Recipients, -ProfileName, or -CreateProfile." -ForegroundColor Yellow
    exit 0
}

foreach ($s in $settings) {
    $affected = Invoke-Sql -Db $Database -Query @"
UPDATE [monitor].[Settings]
SET SettingValue = $(Quote-Sql $s.Value), ModifiedBy = SUSER_SNAME(), ModifiedDate = SYSUTCDATETIME()
WHERE Category = 'Email' AND SettingName = $(Quote-Sql $s.Name);
SELECT CAST(@@ROWCOUNT AS VARCHAR(10));
"@
    if ($affected[-1] -eq '0') {
        Write-Warning "  No setting named '$($s.Name)' -- it may not be seeded. Check 05-configure.sql ran."
    } else {
        Write-Host "  $($s.Name) = $($s.Value)" -ForegroundColor Green
    }
}

# ---- test ---------------------------------------------------------------------

if ($SkipTest -or -not $chosen -or -not $Recipients) {
    Write-Host ""
    Write-Host "  Skipping the test message. Send a report with:" -ForegroundColor Yellow
    Write-Host "    EXEC [monitor].[usp_RunReport] @ReportType = 'Daily', @DebugMode = 1;"
    Write-Host ""
    exit 0
}

Write-Host ""
Write-Host "  Sending a test message..." -ForegroundColor Cyan
try {
    Invoke-Sql -Query @"
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = $(Quote-Sql $chosen),
    @recipients   = $(Quote-Sql $Recipients),
    @subject      = 'SQL Health Monitor - test message',
    @body         = '<p>Database Mail is configured for SQL Health Monitor.</p>',
    @body_format  = 'HTML';
"@ | Out-Null
    Write-Host "  Accepted by Database Mail." -ForegroundColor Green
} catch {
    Write-Host "  sp_send_dbmail failed:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "  Delivery is asynchronous. To see the outcome:" -ForegroundColor Yellow
Write-Host "    SELECT TOP 3 * FROM msdb.dbo.sysmail_allitems ORDER BY mailitem_id DESC;"
Write-Host ""
Write-Host "  Then send the real report:" -ForegroundColor Yellow
Write-Host "    EXEC [monitor].[usp_RunReport] @ReportType = 'Daily', @DebugMode = 1;"
Write-Host ""