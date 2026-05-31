<#
.SYNOPSIS
    Interactive onboarding wizard for SQL Health Monitor.

.DESCRIPTION
    Walks the DBA through a guided, step-by-step installation of SQL Health Monitor.
    Supports single-instance, multi-instance (CMS), reconfiguration, and uninstall modes.

.PARAMETER NonInteractive
    Run in non-interactive mode using an answer file.

.PARAMETER AnswerFile
    Path to a JSON answer file for non-interactive mode.

.PARAMETER ExportAnswers
    Path to export the collected answers as JSON (for replication).

.EXAMPLE
    .\Start-SQLHealthMonitorSetup.ps1

.EXAMPLE
    .\Start-SQLHealthMonitorSetup.ps1 -NonInteractive -AnswerFile .\answers.json

.EXAMPLE
    .\Start-SQLHealthMonitorSetup.ps1 -ExportAnswers .\my-answers.json

.NOTES
    Author: Lucas Allan Borges
    Version: 1.0.0
    Requires: dbatools module, PowerShell 5.1+ or PowerShell 7+
#>

[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [string]$AnswerFile,
    [string]$ExportAnswers
)

#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region ===== GLOBALS =====

$script:Answers = @{}
$script:CurrentStep = 0
$script:TotalSteps = 13
$script:InstallStartTime = $null
$script:ScriptRoot = $PSScriptRoot
$script:ProjectRoot = Split-Path $PSScriptRoot -Parent
$script:Interrupted = $false

#endregion

#region ===== HELPER FUNCTIONS =====

function Write-Banner {
    $banner = @"

    ╔══════════════════════════════════════════════════════════════╗
    ║                                                              ║
    ║        SQL Health Monitor - Interactive Setup Wizard          ║
    ║                                                              ║
    ║        Proactive monitoring, alerting & reporting             ║
    ║        for SQL Server 2016+                                  ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝

"@
    Write-Host $banner -ForegroundColor Cyan
    Write-Host "    Version 1.0.0 | dbatools-powered | MIT License" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-StepHeader {
    param([string]$Title)
    $script:CurrentStep++
    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  Step $($script:CurrentStep) of $($script:TotalSteps): $Title" -ForegroundColor Cyan
    Write-Host "  ─────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Success {
    param([string]$Message)
    Write-Host "  ✓ $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "  ℹ $Message" -ForegroundColor Gray
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  ⚠ $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "  ✗ $Message" -ForegroundColor Red
}

function Read-ValidatedInput {
    param(
        [string]$Prompt,
        [string]$Default = '',
        [string[]]$ValidOptions = @(),
        [scriptblock]$Validator = $null,
        [string]$ErrorMessage = 'Invalid input. Please try again.',
        [switch]$Required,
        [switch]$Secret
    )

    $displayDefault = if ($Default) { " [$Default]" } else { '' }

    while ($true) {
        if ($Secret) {
            Write-Host "  $Prompt$displayDefault`: " -ForegroundColor Cyan -NoNewline
            $input = Read-Host -AsSecureString
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($input)
            $value = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
        else {
            Write-Host "  $Prompt$displayDefault`: " -ForegroundColor Cyan -NoNewline
            $value = Read-Host
        }

        # Apply default
        if ([string]::IsNullOrWhiteSpace($value) -and $Default) {
            $value = $Default
        }

        # Required check
        if ($Required -and [string]::IsNullOrWhiteSpace($value)) {
            Write-Err "This field is required."
            continue
        }

        # Empty non-required is OK
        if ([string]::IsNullOrWhiteSpace($value) -and -not $Required) {
            return $value
        }

        # Valid options check
        if ($ValidOptions.Count -gt 0) {
            if ($value -notin $ValidOptions) {
                Write-Err "Valid options: $($ValidOptions -join ', ')"
                continue
            }
        }

        # Custom validator
        if ($Validator) {
            $result = & $Validator $value
            if ($result -ne $true) {
                $msg = if ($result -is [string]) { $result } else { $ErrorMessage }
                Write-Err $msg
                continue
            }
        }

        return $value
    }
}

function Read-YesNo {
    param(
        [string]$Prompt,
        [string]$Default = 'Y'
    )

    $displayDefault = if ($Default -eq 'Y') { '[Y/n]' } else { '[y/N]' }

    while ($true) {
        Write-Host "  $Prompt $displayDefault`: " -ForegroundColor Cyan -NoNewline
        $value = Read-Host

        if ([string]::IsNullOrWhiteSpace($value)) {
            return ($Default -eq 'Y')
        }

        switch ($value.ToUpper()) {
            'Y' { return $true }
            'YES' { return $true }
            'N' { return $false }
            'NO' { return $false }
            default {
                Write-Err "Please enter Y or N."
            }
        }
    }
}

function Read-MenuChoice {
    param(
        [string]$Prompt,
        [hashtable[]]$Options,
        [string]$Default = ''
    )

    Write-Host ""
    foreach ($opt in $Options) {
        $marker = if ($opt.Key -eq $Default) { '*' } else { ' ' }
        Write-Host "    $marker[$($opt.Key)] $($opt.Label)" -ForegroundColor White
    }
    Write-Host ""

    $validKeys = $Options | ForEach-Object { $_.Key }
    $choice = Read-ValidatedInput -Prompt $Prompt -Default $Default -ValidOptions $validKeys -Required
    return $choice
}

function Test-SqlConnection {
    param(
        [string]$Instance,
        [string]$AuthMode = 'Windows',
        [pscredential]$Credential = $null
    )

    try {
        $params = @{ SqlInstance = $Instance; EnableException = $true }
        if ($AuthMode -eq 'SQL' -and $Credential) {
            $params['SqlCredential'] = $Credential
        }

        $server = Connect-DbaInstance @params
        $info = @{
            ServerName = $server.Name
            Version    = $server.VersionString
            Edition    = $server.Edition
            ProductLevel = $server.ProductLevel
            Collation  = $server.Collation
            HasAG      = ($server.AvailabilityGroups.Count -gt 0)
            HasCDC     = $false
        }

        # Check for CDC
        try {
            $cdcCheck = Invoke-DbaQuery -SqlInstance $server -Query "SELECT COUNT(*) AS cnt FROM sys.databases WHERE is_cdc_enabled = 1" -EnableException
            $info.HasCDC = ($cdcCheck.cnt -gt 0)
        }
        catch { }

        return @{ Success = $true; Info = $info; Connection = $server }
    }
    catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Show-ServerInfo {
    param([hashtable]$Info)
    Write-Host ""
    Write-Host "    ┌─────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "    │ Server:    $($Info.ServerName)" -ForegroundColor White
    Write-Host "    │ Version:   $($Info.Version) ($($Info.ProductLevel))" -ForegroundColor White
    Write-Host "    │ Edition:   $($Info.Edition)" -ForegroundColor White
    Write-Host "    │ Collation: $($Info.Collation)" -ForegroundColor White
    Write-Host "    │ AG:        $(if ($Info.HasAG) { 'Detected' } else { 'Not detected' })" -ForegroundColor White
    Write-Host "    │ CDC:       $(if ($Info.HasCDC) { 'Detected' } else { 'Not detected' })" -ForegroundColor White
    Write-Host "    └─────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-ProgressStep {
    param(
        [string]$StepName,
        [string]$Status = 'Running'
    )

    switch ($Status) {
        'Running' { Write-Host "    ◌ $StepName..." -ForegroundColor Yellow -NoNewline }
        'Done'    { Write-Host "`r    ✓ $StepName   " -ForegroundColor Green }
        'Failed'  { Write-Host "`r    ✗ $StepName   " -ForegroundColor Red }
        'Skipped' { Write-Host "`r    ○ $StepName (skipped)" -ForegroundColor DarkGray }
    }
}

function Get-AnswerFromFile {
    param([string]$Key, $Default = $null)

    if ($script:NonInteractiveAnswers -and $script:NonInteractiveAnswers.PSObject.Properties[$Key]) {
        return $script:NonInteractiveAnswers.$Key
    }
    return $Default
}

#endregion

#region ===== STEP FUNCTIONS =====

function Invoke-Step1-Welcome {
    Write-StepHeader "Welcome & Mode Selection"

    Write-Host "  Welcome to the SQL Health Monitor setup wizard." -ForegroundColor White
    Write-Host "  This will guide you through the complete installation process." -ForegroundColor White
    Write-Host ""

    if ($NonInteractive) {
        $mode = Get-AnswerFromFile -Key 'InstallMode' -Default '1'
    }
    else {
        $options = @(
            @{ Key = '1'; Label = 'Single Instance — monitor one SQL Server' }
            @{ Key = '2'; Label = 'Multi-Instance / CMS — central server monitors multiple instances' }
            @{ Key = '3'; Label = 'Reconfigure existing installation' }
            @{ Key = '4'; Label = 'Uninstall' }
        )
        $mode = Read-MenuChoice -Prompt "Select installation mode" -Options $options -Default '1'
    }

    $script:Answers.InstallMode = $mode

    switch ($mode) {
        '1' { Write-Success "Mode: Single Instance" }
        '2' { Write-Success "Mode: Multi-Instance (CMS)" }
        '3' { Write-Success "Mode: Reconfigure" }
        '4' { Write-Success "Mode: Uninstall" }
    }

    if ($mode -eq '4') {
        $script:TotalSteps = 3
    }
}

function Invoke-Step2-Connection {
    Write-StepHeader "SQL Server Connection"

    if ($NonInteractive) {
        $instance = Get-AnswerFromFile -Key 'ServerInstance' -Default 'localhost'
        $authMode = Get-AnswerFromFile -Key 'AuthMode' -Default 'Windows'
        $database = Get-AnswerFromFile -Key 'Database' -Default 'SQLHealthMonitor'
    }
    else {
        $instance = Read-ValidatedInput -Prompt "SQL Server instance name" -Default "localhost" -Required
        
        $authOptions = @(
            @{ Key = '1'; Label = 'Windows Authentication (Trusted)' }
            @{ Key = '2'; Label = 'SQL Server Authentication' }
        )
        $authChoice = Read-MenuChoice -Prompt "Authentication method" -Options $authOptions -Default '1'
        $authMode = if ($authChoice -eq '1') { 'Windows' } else { 'SQL' }

        $database = Read-ValidatedInput -Prompt "Monitor database name" -Default "SQLHealthMonitor"
    }

    $script:Answers.ServerInstance = $instance
    $script:Answers.AuthMode = $authMode
    $script:Answers.Database = $database

    # Get SQL credentials if needed
    $credential = $null
    if ($authMode -eq 'SQL') {
        if ($NonInteractive) {
            $sqlUser = Get-AnswerFromFile -Key 'SqlUser'
            $sqlPass = Get-AnswerFromFile -Key 'SqlPassword'
            $secPass = ConvertTo-SecureString $sqlPass -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential($sqlUser, $secPass)
        }
        else {
            $sqlUser = Read-ValidatedInput -Prompt "SQL Login username" -Required
            Write-Host "  SQL Login password: " -ForegroundColor Cyan -NoNewline
            $secPass = Read-Host -AsSecureString
            $credential = New-Object System.Management.Automation.PSCredential($sqlUser, $secPass)
            $script:Answers.SqlUser = $sqlUser
        }
    }

    $script:Answers.SqlCredential = $credential

    # Test connection
    Write-Host ""
    Write-Host "  Testing connection..." -ForegroundColor Yellow
    $result = Test-SqlConnection -Instance $instance -AuthMode $authMode -Credential $credential

    if ($result.Success) {
        Write-Success "Connected successfully!"
        Show-ServerInfo -Info $result.Info
        $script:Answers.ServerInfo = $result.Info
        $script:Answers.SqlConnection = $result.Connection
    }
    else {
        Write-Err "Connection failed: $($result.Error)"
        if (-not $NonInteractive) {
            $retry = Read-YesNo -Prompt "Would you like to try again?"
            if ($retry) {
                $script:CurrentStep--
                Invoke-Step2-Connection
                return
            }
            else {
                throw "Cannot proceed without a valid SQL Server connection."
            }
        }
        else {
            throw "Connection failed in non-interactive mode: $($result.Error)"
        }
    }
}

function Invoke-Step3-MultiInstance {
    Write-StepHeader "Multi-Instance Registration"

    if ($script:Answers.InstallMode -ne '2') {
        Write-Info "Skipped (single-instance mode)."
        return
    }

    if ($NonInteractive) {
        $instances = Get-AnswerFromFile -Key 'RemoteInstances' -Default @()
    }
    else {
        Write-Host "  Register the remote instances this CMS server will monitor." -ForegroundColor White
        Write-Host "  (The current server is automatically included.)" -ForegroundColor DarkGray
        Write-Host ""

        $instanceCount = Read-ValidatedInput -Prompt "How many additional instances to register" -Default "1" `
            -Validator { param($v) if ($v -match '^\d+$' -and [int]$v -ge 1 -and [int]$v -le 50) { $true } else { "Enter a number between 1 and 50." } }

        $instances = @()
        for ($i = 1; $i -le [int]$instanceCount; $i++) {
            Write-Host ""
            Write-Host "  --- Instance $i of $instanceCount ---" -ForegroundColor DarkGray

            $instName = Read-ValidatedInput -Prompt "  Instance name (e.g., SQL-PRD-02)" -Required
            $displayName = Read-ValidatedInput -Prompt "  Display name" -Default $instName

            $envOptions = @(
                @{ Key = 'DEV'; Label = 'Development' }
                @{ Key = 'STG'; Label = 'Staging' }
                @{ Key = 'PRD'; Label = 'Production' }
                @{ Key = 'DR';  Label = 'Disaster Recovery' }
            )
            $env = Read-MenuChoice -Prompt "  Environment" -Options $envOptions -Default 'PRD'

            $roleOptions = @(
                @{ Key = 'OLTP';      Label = 'OLTP (Transactional)' }
                @{ Key = 'REPORTING'; Label = 'Reporting / Read-Only' }
                @{ Key = 'ETL';       Label = 'ETL / Data Processing' }
                @{ Key = 'MIXED';     Label = 'Mixed Workload' }
            )
            $role = Read-MenuChoice -Prompt "  Server role" -Options $roleOptions -Default 'MIXED'

            # Test connectivity
            Write-Host "    Testing connection to $instName..." -ForegroundColor Yellow -NoNewline
            $testResult = Test-SqlConnection -Instance $instName -AuthMode $script:Answers.AuthMode -Credential $script:Answers.SqlCredential
            if ($testResult.Success) {
                Write-Host " OK" -ForegroundColor Green
            }
            else {
                Write-Host " FAILED" -ForegroundColor Red
                Write-Warn "    $($testResult.Error)"
                $addAnyway = Read-YesNo -Prompt "  Add anyway (can fix connectivity later)?" -Default 'Y'
                if (-not $addAnyway) { continue }
            }

            $instances += @{
                InstanceName = $instName
                DisplayName  = $displayName
                Environment  = $env
                ServerRole   = $role
                Reachable    = $testResult.Success
            }
        }

        # Show summary table
        if ($instances.Count -gt 0) {
            Write-Host ""
            Write-Host "  Registered Instances:" -ForegroundColor White
            Write-Host "  ┌──────────────────────┬──────────────────────┬─────┬───────────┬────────┐" -ForegroundColor DarkGray
            Write-Host "  │ Instance             │ Display Name         │ Env │ Role      │ Status │" -ForegroundColor DarkGray
            Write-Host "  ├──────────────────────┼──────────────────────┼─────┼───────────┼────────┤" -ForegroundColor DarkGray
            foreach ($inst in $instances) {
                $status = if ($inst.Reachable) { '  ✓   ' } else { '  ✗   ' }
                $statusColor = if ($inst.Reachable) { 'Green' } else { 'Red' }
                $line = "  │ {0,-20} │ {1,-20} │ {2,-3} │ {3,-9} │" -f $inst.InstanceName, $inst.DisplayName, $inst.Environment, $inst.ServerRole
                Write-Host $line -ForegroundColor White -NoNewline
                Write-Host $status -ForegroundColor $statusColor -NoNewline
                Write-Host "│" -ForegroundColor DarkGray
            }
            Write-Host "  └──────────────────────┴──────────────────────┴─────┴───────────┴────────┘" -ForegroundColor DarkGray
        }
    }

    $script:Answers.RemoteInstances = $instances
}

function Invoke-Step4-Collectors {
    Write-StepHeader "Collectors Configuration"

    $allCollectors = @(
        @{ Name = 'CPU';               Description = 'CPU utilization and processor queue' }
        @{ Name = 'Memory';            Description = 'Memory usage, PLE, buffer cache' }
        @{ Name = 'Disk';              Description = 'Disk space, I/O latency' }
        @{ Name = 'WaitStats';         Description = 'Wait statistics analysis' }
        @{ Name = 'Blocking';          Description = 'Active blocking chains' }
        @{ Name = 'Deadlocks';         Description = 'Deadlock detection via XEvents' }
        @{ Name = 'AvailabilityGroups'; Description = 'AG health, sync lag, replica status' }
        @{ Name = 'CDC';               Description = 'Change Data Capture latency and health' }
        @{ Name = 'TopQueries';        Description = 'Top resource-consuming queries' }
        @{ Name = 'IndexHealth';       Description = 'Index fragmentation and missing indexes' }
        @{ Name = 'BackupStatus';      Description = 'Backup recency and chain validation' }
        @{ Name = 'Jobs';              Description = 'SQL Agent job failures and duration' }
        @{ Name = 'ErrorLog';          Description = 'Error log severity analysis' }
        @{ Name = 'TempDB';            Description = 'TempDB contention and space' }
        @{ Name = 'LogGrowth';         Description = 'Transaction log growth events' }
        @{ Name = 'DatabaseGrowth';    Description = 'Database file growth tracking' }
    )

    if ($NonInteractive) {
        $enabledCollectors = Get-AnswerFromFile -Key 'Collectors' -Default ($allCollectors | ForEach-Object { $_.Name })
    }
    else {
        Write-Host "  Available collectors:" -ForegroundColor White
        Write-Host ""
        $i = 1
        foreach ($col in $allCollectors) {
            $agCdc = ''
            if ($col.Name -eq 'AvailabilityGroups' -and -not $script:Answers.ServerInfo.HasAG) {
                $agCdc = ' (AG not detected)'
            }
            if ($col.Name -eq 'CDC' -and -not $script:Answers.ServerInfo.HasCDC) {
                $agCdc = ' (CDC not detected)'
            }
            Write-Host "    [$("{0:D2}" -f $i)] $($col.Name.PadRight(20)) $($col.Description)$agCdc" -ForegroundColor White
            $i++
        }
        Write-Host ""

        $enableAll = Read-YesNo -Prompt "Enable all collectors?" -Default 'Y'

        if ($enableAll) {
            $enabledCollectors = $allCollectors | ForEach-Object { $_.Name }
            # Auto-disable AG/CDC if not detected
            if (-not $script:Answers.ServerInfo.HasAG) {
                $enabledCollectors = $enabledCollectors | Where-Object { $_ -ne 'AvailabilityGroups' }
                Write-Info "AvailabilityGroups collector disabled (AG not detected)."
            }
            if (-not $script:Answers.ServerInfo.HasCDC) {
                $enabledCollectors = $enabledCollectors | Where-Object { $_ -ne 'CDC' }
                Write-Info "CDC collector disabled (CDC not detected)."
            }
        }
        else {
            Write-Host "  Enter collector numbers to enable (comma-separated, e.g., 1,2,3,5,9):" -ForegroundColor White
            $selection = Read-ValidatedInput -Prompt "Collectors" -Required `
                -Validator {
                    param($v)
                    $nums = $v -split ',' | ForEach-Object { $_.Trim() }
                    foreach ($n in $nums) {
                        if ($n -notmatch '^\d+$' -or [int]$n -lt 1 -or [int]$n -gt 16) {
                            return "Invalid number: $n. Use 1-16."
                        }
                    }
                    $true
                }

            $selectedNums = $selection -split ',' | ForEach-Object { [int]$_.Trim() }
            $enabledCollectors = $selectedNums | ForEach-Object { $allCollectors[$_ - 1].Name }
        }

        Write-Host ""
        Write-Success "$($enabledCollectors.Count) collectors enabled."
    }

    $script:Answers.Collectors = @($enabledCollectors)
}

function Invoke-Step5-Alerts {
    Write-StepHeader "Alert Configuration"

    if ($NonInteractive) {
        $enableAlerts = Get-AnswerFromFile -Key 'EnableAlerts' -Default $true
        $alertRecipients = Get-AnswerFromFile -Key 'AlertRecipients' -Default @('dba@company.com')
        $thresholds = Get-AnswerFromFile -Key 'AlertThresholds' -Default @{}
    }
    else {
        $enableAlerts = Read-YesNo -Prompt "Enable alerting?" -Default 'Y'

        $alertRecipients = @()
        $thresholds = @{}

        if ($enableAlerts) {
            $recipientInput = Read-ValidatedInput -Prompt "Alert recipients (comma-separated emails)" -Required `
                -Validator {
                    param($v)
                    $emails = $v -split ',' | ForEach-Object { $_.Trim() }
                    foreach ($e in $emails) {
                        if ($e -notmatch '^[^@]+@[^@]+\.[^@]+$') {
                            return "Invalid email: $e"
                        }
                    }
                    $true
                }
            $alertRecipients = $recipientInput -split ',' | ForEach-Object { $_.Trim() }

            Write-Host ""
            $customThresholds = Read-YesNo -Prompt "Customize alert thresholds? (No = use defaults)" -Default 'N'

            if ($customThresholds) {
                Write-Host ""
                Write-Host "  Set thresholds (press Enter to keep default):" -ForegroundColor White
                Write-Host ""

                $thresholds.CpuWarning = Read-ValidatedInput -Prompt "CPU Warning %" -Default "80" `
                    -Validator { param($v) if ($v -match '^\d+$' -and [int]$v -ge 1 -and [int]$v -le 100) { $true } else { "Enter 1-100" } }
                $thresholds.CpuCritical = Read-ValidatedInput -Prompt "CPU Critical %" -Default "95" `
                    -Validator { param($v) if ($v -match '^\d+$' -and [int]$v -ge 1 -and [int]$v -le 100) { $true } else { "Enter 1-100" } }
                $thresholds.DiskWarning = Read-ValidatedInput -Prompt "Disk Used Warning %" -Default "85" `
                    -Validator { param($v) if ($v -match '^\d+$' -and [int]$v -ge 1 -and [int]$v -le 100) { $true } else { "Enter 1-100" } }
                $thresholds.DiskCritical = Read-ValidatedInput -Prompt "Disk Used Critical %" -Default "95" `
                    -Validator { param($v) if ($v -match '^\d+$' -and [int]$v -ge 1 -and [int]$v -le 100) { $true } else { "Enter 1-100" } }
                $thresholds.PleWarning = Read-ValidatedInput -Prompt "PLE Warning (seconds, below)" -Default "300" `
                    -Validator { param($v) if ($v -match '^\d+$' -and [int]$v -ge 1) { $true } else { "Enter a positive number" } }
                $thresholds.BlockingDuration = Read-ValidatedInput -Prompt "Blocking alert duration (seconds)" -Default "30" `
                    -Validator { param($v) if ($v -match '^\d+$' -and [int]$v -ge 1) { $true } else { "Enter a positive number" } }
            }
        }
    }

    $script:Answers.EnableAlerts = $enableAlerts
    $script:Answers.AlertRecipients = $alertRecipients
    $script:Answers.AlertThresholds = $thresholds

    if ($enableAlerts) {
        Write-Success "Alerting enabled for $($alertRecipients.Count) recipient(s)."
    }
    else {
        Write-Info "Alerting disabled. You can enable it later."
    }
}

#endregion

function Invoke-Step6-Reports {
    Write-StepHeader "Report Configuration"

    if ($NonInteractive) {
        $enableDaily = Get-AnswerFromFile -Key 'EnableDailyReport' -Default $true
        $enableWeekly = Get-AnswerFromFile -Key 'EnableWeeklyReport' -Default $true
        $reportRecipients = Get-AnswerFromFile -Key 'ReportRecipients' -Default @('dba@company.com')
        $language = Get-AnswerFromFile -Key 'Language' -Default 'EN'
        $dailyTime = Get-AnswerFromFile -Key 'DailyReportTime' -Default '07:00'
        $weeklyDay = Get-AnswerFromFile -Key 'WeeklyReportDay' -Default 'Monday'
        $weeklyTime = Get-AnswerFromFile -Key 'WeeklyReportTime' -Default '08:00'
    }
    else {
        $enableDaily = Read-YesNo -Prompt "Enable daily health report?" -Default 'Y'
        $enableWeekly = Read-YesNo -Prompt "Enable weekly deep-dive report?" -Default 'Y'

        $reportRecipients = @()
        $language = 'EN'
        $dailyTime = '07:00'
        $weeklyDay = 'Monday'
        $weeklyTime = '08:00'

        if ($enableDaily -or $enableWeekly) {
            # Recipients
            if ($script:Answers.AlertRecipients.Count -gt 0) {
                $sameAsAlerts = Read-YesNo -Prompt "Use same recipients as alerts ($($script:Answers.AlertRecipients -join ', '))?" -Default 'Y'
                if ($sameAsAlerts) {
                    $reportRecipients = $script:Answers.AlertRecipients
                }
            }

            if ($reportRecipients.Count -eq 0) {
                $recipientInput = Read-ValidatedInput -Prompt "Report recipients (comma-separated emails)" -Required `
                    -Validator {
                        param($v)
                        $emails = $v -split ',' | ForEach-Object { $_.Trim() }
                        foreach ($e in $emails) {
                            if ($e -notmatch '^[^@]+@[^@]+\.[^@]+$') {
                                return "Invalid email: $e"
                            }
                        }
                        $true
                    }
                $reportRecipients = $recipientInput -split ',' | ForEach-Object { $_.Trim() }
            }

            # Language
            $langOptions = @(
                @{ Key = '1'; Label = 'English (EN)' }
                @{ Key = '2'; Label = 'Português Brasil (PT-BR)' }
            )
            $langChoice = Read-MenuChoice -Prompt "Report language" -Options $langOptions -Default '1'
            $language = if ($langChoice -eq '1') { 'EN' } else { 'PTBR' }

            # Schedule
            if ($enableDaily) {
                $dailyTime = Read-ValidatedInput -Prompt "Daily report time (HH:MM, 24h)" -Default '07:00' `
                    -Validator {
                        param($v)
                        if ($v -match '^([01]\d|2[0-3]):[0-5]\d$') { $true } else { "Use HH:MM format (e.g., 07:00, 18:30)" }
                    }
            }

            if ($enableWeekly) {
                $dayOptions = @(
                    @{ Key = '1'; Label = 'Monday' }
                    @{ Key = '2'; Label = 'Tuesday' }
                    @{ Key = '3'; Label = 'Wednesday' }
                    @{ Key = '4'; Label = 'Thursday' }
                    @{ Key = '5'; Label = 'Friday' }
                    @{ Key = '6'; Label = 'Saturday' }
                    @{ Key = '7'; Label = 'Sunday' }
                )
                $dayChoice = Read-MenuChoice -Prompt "Weekly report day" -Options $dayOptions -Default '1'
                $dayMap = @{ '1' = 'Monday'; '2' = 'Tuesday'; '3' = 'Wednesday'; '4' = 'Thursday'; '5' = 'Friday'; '6' = 'Saturday'; '7' = 'Sunday' }
                $weeklyDay = $dayMap[$dayChoice]

                $weeklyTime = Read-ValidatedInput -Prompt "Weekly report time (HH:MM, 24h)" -Default '08:00' `
                    -Validator {
                        param($v)
                        if ($v -match '^([01]\d|2[0-3]):[0-5]\d$') { $true } else { "Use HH:MM format (e.g., 08:00)" }
                    }
            }
        }
    }

    $script:Answers.EnableDailyReport = $enableDaily
    $script:Answers.EnableWeeklyReport = $enableWeekly
    $script:Answers.ReportRecipients = $reportRecipients
    $script:Answers.Language = $language
    $script:Answers.DailyReportTime = $dailyTime
    $script:Answers.WeeklyReportDay = $weeklyDay
    $script:Answers.WeeklyReportTime = $weeklyTime

    $reports = @()
    if ($enableDaily) { $reports += "Daily ($dailyTime)" }
    if ($enableWeekly) { $reports += "Weekly ($weeklyDay $weeklyTime)" }
    if ($reports.Count -gt 0) {
        Write-Success "Reports: $($reports -join ', ') | Language: $language"
    }
    else {
        Write-Info "No reports enabled."
    }
}

function Invoke-Step7-Email {
    Write-StepHeader "Email Configuration"

    $needsEmail = $script:Answers.EnableAlerts -or $script:Answers.EnableDailyReport -or $script:Answers.EnableWeeklyReport

    if (-not $needsEmail) {
        Write-Info "No email configuration needed (alerts and reports are disabled)."
        $script:Answers.EmailMethod = 'None'
        return
    }

    if ($NonInteractive) {
        $emailMethod = Get-AnswerFromFile -Key 'EmailMethod' -Default 'DatabaseMail'
        $mailProfile = Get-AnswerFromFile -Key 'DatabaseMailProfile' -Default ''
        $smtpServer = Get-AnswerFromFile -Key 'SmtpServer' -Default ''
        $smtpPort = Get-AnswerFromFile -Key 'SmtpPort' -Default 587
        $smtpSsl = Get-AnswerFromFile -Key 'SmtpUseSsl' -Default $true
        $smtpFrom = Get-AnswerFromFile -Key 'SmtpFrom' -Default ''
    }
    else {
        $methodOptions = @(
            @{ Key = '1'; Label = 'Database Mail (existing profile on SQL Server)' }
            @{ Key = '2'; Label = 'SMTP (direct connection)' }
        )
        $methodChoice = Read-MenuChoice -Prompt "Email delivery method" -Options $methodOptions -Default '1'
        $emailMethod = if ($methodChoice -eq '1') { 'DatabaseMail' } else { 'SMTP' }

        $mailProfile = ''
        $smtpServer = ''
        $smtpPort = 587
        $smtpSsl = $true
        $smtpFrom = ''

        if ($emailMethod -eq 'DatabaseMail') {
            # Try to list existing profiles
            Write-Host "  Checking for existing Database Mail profiles..." -ForegroundColor Yellow
            try {
                $profiles = Invoke-DbaQuery -SqlInstance $script:Answers.SqlConnection -Query @"
SELECT p.name, p.description
FROM msdb.dbo.sysmail_profile p
ORDER BY p.name
"@ -EnableException

                if ($profiles -and $profiles.Count -gt 0) {
                    Write-Host ""
                    Write-Host "  Available profiles:" -ForegroundColor White
                    $i = 1
                    foreach ($p in $profiles) {
                        Write-Host "    [$i] $($p.name)$(if ($p.description) { " - $($p.description)" })" -ForegroundColor White
                        $i++
                    }
                    Write-Host ""
                    $profileChoice = Read-ValidatedInput -Prompt "Select profile number (or type a name)" -Required
                    if ($profileChoice -match '^\d+$' -and [int]$profileChoice -le $profiles.Count) {
                        $mailProfile = $profiles[[int]$profileChoice - 1].name
                    }
                    else {
                        $mailProfile = $profileChoice
                    }
                }
                else {
                    Write-Warn "No Database Mail profiles found."
                    $mailProfile = Read-ValidatedInput -Prompt "Enter profile name to create/use" -Required
                }
            }
            catch {
                Write-Warn "Could not query Database Mail profiles: $($_.Exception.Message)"
                $mailProfile = Read-ValidatedInput -Prompt "Enter Database Mail profile name" -Required
            }
        }
        else {
            # SMTP configuration
            $smtpServer = Read-ValidatedInput -Prompt "SMTP server (e.g., smtp.company.com)" -Required
            $smtpPort = Read-ValidatedInput -Prompt "SMTP port" -Default '587' `
                -Validator { param($v) if ($v -match '^\d+$' -and [int]$v -ge 1 -and [int]$v -le 65535) { $true } else { "Enter a valid port (1-65535)" } }
            $smtpSsl = Read-YesNo -Prompt "Use SSL/TLS?" -Default 'Y'
            $smtpFrom = Read-ValidatedInput -Prompt "From address (e.g., sqlmonitor@company.com)" -Required `
                -Validator { param($v) if ($v -match '^[^@]+@[^@]+\.[^@]+$') { $true } else { "Enter a valid email" } }

            $smtpAuth = Read-YesNo -Prompt "SMTP requires authentication?" -Default 'Y'
            if ($smtpAuth) {
                $smtpUser = Read-ValidatedInput -Prompt "SMTP username" -Required
                Write-Host "  SMTP password: " -ForegroundColor Cyan -NoNewline
                $smtpPass = Read-Host -AsSecureString
                $script:Answers.SmtpCredential = New-Object System.Management.Automation.PSCredential($smtpUser, $smtpPass)
            }
        }

        # Test email
        $testEmail = Read-YesNo -Prompt "Send a test email now?" -Default 'Y'
        if ($testEmail) {
            $testRecipient = $script:Answers.AlertRecipients[0]
            if (-not $testRecipient) { $testRecipient = $script:Answers.ReportRecipients[0] }
            Write-Host "  Sending test email to $testRecipient..." -ForegroundColor Yellow

            try {
                if ($emailMethod -eq 'DatabaseMail') {
                    $testSql = @"
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = '$mailProfile',
    @recipients = '$testRecipient',
    @subject = 'SQL Health Monitor - Test Email',
    @body = 'This is a test email from SQL Health Monitor setup wizard. If you received this, email is configured correctly.',
    @body_format = 'TEXT'
"@
                    Invoke-DbaQuery -SqlInstance $script:Answers.SqlConnection -Query $testSql -EnableException
                    Write-Success "Test email sent via Database Mail. Check inbox."
                }
                else {
                    $mailParams = @{
                        From       = $smtpFrom
                        To         = $testRecipient
                        Subject    = 'SQL Health Monitor - Test Email'
                        Body       = 'This is a test email from SQL Health Monitor setup wizard. If you received this, email is configured correctly.'
                        SmtpServer = $smtpServer
                        Port       = [int]$smtpPort
                        UseSsl     = $smtpSsl
                    }
                    if ($script:Answers.SmtpCredential) {
                        $mailParams['Credential'] = $script:Answers.SmtpCredential
                    }
                    Send-MailMessage @mailParams
                    Write-Success "Test email sent via SMTP. Check inbox."
                }
            }
            catch {
                Write-Err "Test email failed: $($_.Exception.Message)"
                Write-Warn "You can fix email configuration later. Continuing..."
            }
        }
    }

    $script:Answers.EmailMethod = $emailMethod
    $script:Answers.DatabaseMailProfile = $mailProfile
    $script:Answers.SmtpServer = $smtpServer
    $script:Answers.SmtpPort = [int]$smtpPort
    $script:Answers.SmtpUseSsl = $smtpSsl
    $script:Answers.SmtpFrom = $smtpFrom

    Write-Success "Email: $emailMethod$(if ($emailMethod -eq 'DatabaseMail') { " (profile: $mailProfile)" } else { " ($smtpServer`:$smtpPort)" })"
}

function Invoke-Step8-Scheduling {
    Write-StepHeader "SQL Agent Job Scheduling"

    if ($NonInteractive) {
        $createJobs = Get-AnswerFromFile -Key 'CreateAgentJobs' -Default $true
        $collectionInterval = Get-AnswerFromFile -Key 'CollectionIntervalMinutes' -Default 15
        $alertInterval = Get-AnswerFromFile -Key 'AlertCheckIntervalMinutes' -Default 5
    }
    else {
        $createJobs = Read-YesNo -Prompt "Create SQL Agent jobs for automated scheduling?" -Default 'Y'

        $collectionInterval = 15
        $alertInterval = 5

        if ($createJobs) {
            Write-Host ""
            Write-Host "  Proposed schedule:" -ForegroundColor White
            Write-Host "    • Collection:    Every 15 minutes" -ForegroundColor Gray
            Write-Host "    • Alert checks:  Every 5 minutes" -ForegroundColor Gray
            if ($script:Answers.EnableDailyReport) {
                Write-Host "    • Daily report:  $($script:Answers.DailyReportTime)" -ForegroundColor Gray
            }
            if ($script:Answers.EnableWeeklyReport) {
                Write-Host "    • Weekly report: $($script:Answers.WeeklyReportDay) $($script:Answers.WeeklyReportTime)" -ForegroundColor Gray
            }
            Write-Host "    • Baseline:      Sunday 02:00" -ForegroundColor Gray
            Write-Host "    • Housekeeping:  Daily 03:00" -ForegroundColor Gray
            Write-Host ""

            $customSchedule = Read-YesNo -Prompt "Customize intervals?" -Default 'N'

            if ($customSchedule) {
                $collectionInterval = Read-ValidatedInput -Prompt "Collection interval (minutes)" -Default '15' `
                    -Validator { param($v) if ($v -match '^\d+$' -and [int]$v -ge 1 -and [int]$v -le 1440) { $true } else { "Enter 1-1440" } }
                $alertInterval = Read-ValidatedInput -Prompt "Alert check interval (minutes)" -Default '5' `
                    -Validator { param($v) if ($v -match '^\d+$' -and [int]$v -ge 1 -and [int]$v -le 60) { $true } else { "Enter 1-60" } }
            }
        }
        else {
            Write-Host ""
            Write-Host "  Manual execution examples:" -ForegroundColor White
            Write-Host "    Invoke-SQLHealthMonitor -ServerInstance '$($script:Answers.ServerInstance)' -RunType Collection" -ForegroundColor Gray
            Write-Host "    Invoke-SQLHealthMonitor -ServerInstance '$($script:Answers.ServerInstance)' -RunType Alert" -ForegroundColor Gray
            Write-Host "    Invoke-SQLHealthMonitor -ServerInstance '$($script:Answers.ServerInstance)' -RunType DailyReport" -ForegroundColor Gray
            Write-Host ""
        }
    }

    $script:Answers.CreateAgentJobs = $createJobs
    $script:Answers.CollectionIntervalMinutes = [int]$collectionInterval
    $script:Answers.AlertCheckIntervalMinutes = [int]$alertInterval

    if ($createJobs) {
        Write-Success "SQL Agent jobs will be created (collection: ${collectionInterval}min, alerts: ${alertInterval}min)."
    }
    else {
        Write-Info "No Agent jobs. Use manual execution or external scheduler."
    }
}

function Invoke-Step9-Baseline {
    Write-StepHeader "Baseline Configuration"

    if ($NonInteractive) {
        $enableBaseline = Get-AnswerFromFile -Key 'EnableBaseline' -Default $true
        $captureNow = Get-AnswerFromFile -Key 'CaptureBaselineNow' -Default $false
    }
    else {
        Write-Host "  The baseline engine captures statistical profiles of your server's" -ForegroundColor White
        Write-Host "  normal behavior, then alerts when metrics deviate significantly." -ForegroundColor White
        Write-Host ""
        Write-Host "  How it works:" -ForegroundColor DarkGray
        Write-Host "    1. Weekly capture: calculates avg + stddev for each metric" -ForegroundColor DarkGray
        Write-Host "    2. Real-time detection: compares current values vs baseline" -ForegroundColor DarkGray
        Write-Host "    3. Alerts when current > baseline + (N x stddev)" -ForegroundColor DarkGray
        Write-Host ""

        $enableBaseline = Read-YesNo -Prompt "Enable baseline engine?" -Default 'Y'

        $captureNow = $false
        if ($enableBaseline) {
            $captureOptions = @(
                @{ Key = '1'; Label = 'Capture initial baseline now (needs ~7 days of data for accuracy)' }
                @{ Key = '2'; Label = 'Schedule first capture for next Sunday 02:00 (recommended)' }
            )
            $captureChoice = Read-MenuChoice -Prompt "Initial baseline" -Options $captureOptions -Default '2'
            $captureNow = ($captureChoice -eq '1')
        }
    }

    $script:Answers.EnableBaseline = $enableBaseline
    $script:Answers.CaptureBaselineNow = $captureNow

    if ($enableBaseline) {
        $msg = if ($captureNow) { "Baseline enabled (will capture after install)." } else { "Baseline enabled (first capture: next Sunday 02:00)." }
        Write-Success $msg
    }
    else {
        Write-Info "Baseline engine disabled. Anomaly detection will not be available."
    }
}

function Invoke-Step10-Retention {
    Write-StepHeader "Retention / Housekeeping"

    $defaults = @{
        RawDataDays      = 30
        DailySummaryDays = 90
        WeeklySummaryDays = 365
        AlertHistoryDays = 365
        ReportHistoryDays = 90
        AnomalyDays      = 90
    }

    if ($NonInteractive) {
        $retention = Get-AnswerFromFile -Key 'Retention' -Default $defaults
    }
    else {
        Write-Host "  Default retention periods:" -ForegroundColor White
        Write-Host "    • Raw collector data:   $($defaults.RawDataDays) days" -ForegroundColor Gray
        Write-Host "    • Daily summaries:      $($defaults.DailySummaryDays) days" -ForegroundColor Gray
        Write-Host "    • Weekly summaries:     $($defaults.WeeklySummaryDays) days" -ForegroundColor Gray
        Write-Host "    • Alert history:        $($defaults.AlertHistoryDays) days" -ForegroundColor Gray
        Write-Host "    • Report history:       $($defaults.ReportHistoryDays) days" -ForegroundColor Gray
        Write-Host "    • Baseline anomalies:   $($defaults.AnomalyDays) days" -ForegroundColor Gray
        Write-Host "    • Baselines:            Forever (never purged)" -ForegroundColor Gray
        Write-Host ""

        $useDefaults = Read-YesNo -Prompt "Use default retention periods?" -Default 'Y'

        if ($useDefaults) {
            $retention = $defaults
        }
        else {
            $retention = @{}
            $retention.RawDataDays = [int](Read-ValidatedInput -Prompt "Raw data retention (days)" -Default "$($defaults.RawDataDays)" `
                -Validator { param($v) if ($v -match '^\d+$' -and [int]$v -ge 7) { $true } else { "Minimum 7 days" } })
            $retention.DailySummaryDays = [int](Read-ValidatedInput -Prompt "Daily summary retention (days)" -Default "$($defaults.DailySummaryDays)" `
                -Validator { param($v) if ($v -match '^\d+$' -and [int]$v -ge 30) { $true } else { "Minimum 30 days" } })
            $retention.WeeklySummaryDays = [int](Read-ValidatedInput -Prompt "Weekly summary retention (days)" -Default "$($defaults.WeeklySummaryDays)" `
                -Validator { param($v) if ($v -match '^\d+$' -and [int]$v -ge 90) { $true } else { "Minimum 90 days" } })
            $retention.AlertHistoryDays = [int](Read-ValidatedInput -Prompt "Alert history retention (days)" -Default "$($defaults.AlertHistoryDays)" `
                -Validator { param($v) if ($v -match '^\d+$' -and [int]$v -ge 30) { $true } else { "Minimum 30 days" } })
            $retention.ReportHistoryDays = [int](Read-ValidatedInput -Prompt "Report history retention (days)" -Default "$($defaults.ReportHistoryDays)" `
                -Validator { param($v) if ($v -match '^\d+$' -and [int]$v -ge 30) { $true } else { "Minimum 30 days" } })
            $retention.AnomalyDays = [int](Read-ValidatedInput -Prompt "Anomaly history retention (days)" -Default "$($defaults.AnomalyDays)" `
                -Validator { param($v) if ($v -match '^\d+$' -and [int]$v -ge 30) { $true } else { "Minimum 30 days" } })
        }
    }

    $script:Answers.Retention = $retention
    Write-Success "Retention configured (raw: $($retention.RawDataDays)d, summaries: $($retention.DailySummaryDays)d/$($retention.WeeklySummaryDays)d)."
}

#region ===== STEPS 11-13 AND MAIN LOGIC =====
# Continued below
#endregion
