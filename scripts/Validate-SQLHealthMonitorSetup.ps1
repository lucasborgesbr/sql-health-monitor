<#
.SYNOPSIS
    SQL Health Monitor - Installation Validation Script
    Validates the complete installation setup and configuration.

.DESCRIPTION
    This script performs comprehensive validation of the SQL Health Monitor installation,
    including database objects, configuration, permissions, and job setup.

.PARAMETER ServerInstance
    Target SQL Server instance (e.g., 'localhost', 'SQL-PRD-01')

.PARAMETER Database
    Database name. Default: 'SQLHealthMonitor'

.PARAMETER AuthMethod
    Authentication method: 'Windows' (default) or 'Sql'

.PARAMETER SqlCredential
    SQL credential object for SQL authentication

.EXAMPLE
    # Basic validation
    .\Validate-SQLHealthMonitorSetup.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor'

.EXAMPLE
    # SQL authentication
    $cred = Get-Credential
    .\Validate-SQLHealthMonitorSetup.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -AuthMethod 'Sql' -SqlCredential $cred

.NOTES
    Author: Lucas Allan Borges
    Version: 1.0.0
    Generic version - no hardcoded environment dependencies
#>

[CmdletBinding()]
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
    [System.Management.Automation.PSCredential]$SqlCredential
)

begin {
    $scriptStart = Get-Date
    $validationResults = @{
        Passed = 0
        Failed = 0
        Warnings = 0
        Issues = @()
        Recommendations = @()
    }
    
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  SQL Health Monitor - Setup Validation" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Server:    $ServerInstance"
    Write-Host "  Database:  $Database"
    Write-Host ""
}

process {
    try {
        # --- Step 1: Connect to SQL Server ---
        Write-Host "[1/5] Connecting to SQL Server..." -ForegroundColor Yellow
        
        $sqlParams = @{
            SqlInstance = $ServerInstance
            Database = $Database
            ErrorAction = 'Stop'
        }
        
        if ($AuthMethod -eq 'Sql' -and $SqlCredential) {
            $sqlParams.SqlCredential = $SqlCredential
        }
        
        $sqlInstance = Connect-DbaInstance @sqlParams
        Write-Host "      Connected successfully to $ServerInstance" -ForegroundColor Green

        # --- Step 2: Validate database structure ---
        Write-Host "[2/5] Validating database structure..." -ForegroundColor Yellow
        
        # Validate database
        $dbValidation = Validate-Database -SqlInstance $sqlInstance -Database $Database
        Add-ValidationResult -Result $dbValidation -Type 'Database'
        
        # Validate schema
        $schemaValidation = Validate-Schema -SqlInstance $sqlInstance -Database $Database
        Add-ValidationResult -Result $schemaValidation -Type 'Schema'
        
        # Validate tables
        $tablesValidation = Validate-Tables -SqlInstance $sqlInstance -Database $Database
        Add-ValidationResult -Result $tablesValidation -Type 'Tables'
        
        # Validate procedures
        $procsValidation = Validate-Procedures -SqlInstance $sqlInstance -Database $Database
        Add-ValidationResult -Result $procsValidation -Type 'Procedures'

        # --- Step 3: Validate configuration ---
        Write-Host "[3/5] Validating configuration..." -ForegroundColor Yellow
        
        # Validate settings
        $settingsValidation = Validate-Settings -SqlInstance $sqlInstance -Database $Database
        Add-ValidationResult -Result $settingsValidation -Type 'Settings'
        
        # Validate thresholds
        $thresholdsValidation = Validate-Thresholds -SqlInstance $sqlInstance -Database $Database
        Add-ValidationResult -Result $thresholdsValidation -Type 'Thresholds'

        # --- Step 4: Validate permissions ---
        Write-Host "[4/5] Validating permissions..." -ForegroundColor Yellow
        
        # Validate database permissions
        $permsValidation = Validate-Permissions -SqlInstance $sqlInstance -Database $Database
        Add-ValidationResult -Result $permsValidation -Type 'Permissions'

        # --- Step 5: Validate SQL Agent jobs ---
        Write-Host "[5/5] Validating SQL Agent jobs..." -ForegroundColor Yellow
        
        $jobsValidation = Validate-AgentJobs -SqlInstance $sqlInstance -Database $Database
        Add-ValidationResult -Result $jobsValidation -Type 'Jobs'

        # --- Generate validation report ---
        $duration = (Get-Date) - $scriptStart
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Green
        Write-Host "  Validation Results Summary" -ForegroundColor Green
        Write-Host "============================================" -ForegroundColor Green
        Write-Host "  Passed:      $($validationResults.Passed)"
        Write-Host "  Failed:      $($validationResults.Failed)"
        Write-Host "  Warnings:    $($validationResults.Warnings)"
        Write-Host "  Duration:    $($duration.TotalSeconds.ToString('F1'))s"
        Write-Host ""
        
        # Show issues
        if ($validationResults.Issues.Count -gt 0) {
            Write-Host "Issues Found:" -ForegroundColor Red
            foreach ($issue in $validationResults.Issues) {
                Write-Host "  ❌ $($issue.Type): $($issue.Message)" -ForegroundColor Red
            }
            Write-Host ""
        }
        
        # Show recommendations
        if ($validationResults.Recommendations.Count -gt 0) {
            Write-Host "Recommendations:" -ForegroundColor Yellow
            foreach ($rec in $validationResults.Recommendations) {
                Write-Host "  ⚠️  $($rec.Type): $($rec.Message)" -ForegroundColor Yellow
            }
            Write-Host ""
        }
        
        # Overall status
        if ($validationResults.Failed -eq 0) {
            Write-Host "✅ VALIDATION PASSED" -ForegroundColor Green
            Write-Host ""
            Write-Host "The SQL Health Monitor installation is properly configured and ready for use." -ForegroundColor Green
        }
        else {
            Write-Host "❌ VALIDATION FAILED" -ForegroundColor Red
            Write-Host "Please address the failed validations before proceeding." -ForegroundColor Red
        }
        
        # Return validation results
        [PSCustomObject]@{
            ServerInstance = $ServerInstance
            Database = $Database
            Results = $validationResults
            Status = if ($validationResults.Failed -eq 0) { 'Passed' } else { 'Failed' }
            Duration = $duration
        }
    }
    catch {
        Write-Host ""
        Write-Host "VALIDATION FAILED" -ForegroundColor Red
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

function Add-ValidationResult {
    param(
        [object]$Result,
        [string]$Type
    )
    
    if ($Result.Passed) {
        Write-Host "      ✅ $Type - PASSED" -ForegroundColor Green
        $validationResults.Passed++
    }
    elseif ($Result.Warning) {
        Write-Host "      ⚠️  $Type - WARNING: $($Result.Message)" -ForegroundColor Yellow
        $validationResults.Warnings++
        $validationResults.Recommendations += @{
            Type = $Type
            Message = $Result.Message
        }
    }
    else {
        Write-Host "      ❌ $Type - FAILED: $($Result.Message)" -ForegroundColor Red
        $validationResults.Failed++
        $validationResults.Issues += @{
            Type = $Type
            Message = $Result.Message
        }
    }
}

function Validate-Database {
    param(
        $SqlInstance,
        [string]$Database
    )
    
    try {
        $db = Get-DbaDatabase -SqlInstance $sqlInstance -Database $Database -ErrorAction SilentlyContinue
        if ($db) {
            if ($db.Status -ne 'ONLINE') {
                return @{ 
                    Passed = $false 
                    Message = "Database status is $($db.Status), expected ONLINE"
                }
            }
            return @{ Passed = $true }
        }
        else {
            return @{ 
                Passed = $false 
                Message = "Database '$Database' does not exist"
            }
        }
    }
    catch {
        return @{ 
            Passed = $false 
            Message = "Failed to validate database: $($_.Exception.Message)"
        }
    }
}

function Validate-Schema {
    param(
        $SqlInstance,
        [string]$Database
    )
    
    try {
        $schema = Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query "
            IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'monitor')
                SELECT 1 AS exists
            ELSE
                SELECT 0 AS exists
        " -ErrorAction SilentlyContinue
        
        if ($schema.exists -eq 1) {
            return @{ Passed = $true }
        }
        else {
            return @{ 
                Passed = $false 
                Message = 'monitor schema does not exist'
            }
        }
    }
    catch {
        return @{ 
            Passed = $false 
            Message = "Failed to validate schema: $($_.Exception.Message)"
        }
    }
}

function Validate-Tables {
    param(
        $SqlInstance,
        [string]$Database
    )
    
    try {
        $requiredTables = @('Settings', 'Thresholds', 'Languages', 'AlertHistory')
        $missingTables = @()
        
        foreach ($table in $requiredTables) {
            $exists = Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query "
                IF EXISTS (SELECT 1 FROM sys.tables t 
                          INNER JOIN sys.schemas s ON t.schema_id = s.schema_id 
                          WHERE s.name = 'monitor' AND t.name = '$table')
                    SELECT 1 AS exists
                ELSE
                    SELECT 0 AS exists
            " -ErrorAction SilentlyContinue
            
            if ($exists.exists -ne 1) {
                $missingTables += $table
            }
        }
        
        if ($missingTables.Count -eq 0) {
            return @{ Passed = $true }
        }
        else {
            return @{ 
                Passed = $false 
                Message = "Missing tables: $($missingTables -join ', ')"
            }
        }
    }
    catch {
        return @{ 
            Passed = $false 
            Message = "Failed to validate tables: $($_.Exception.Message)"
        }
    }
}

function Validate-Procedures {
    param(
        $SqlInstance,
        [string]$Database
    )
    
    try {
        $requiredProcs = @('usp_CollectSystemInfo', 'usp_GenerateDailyReport')
        $missingProcs = @()
        
        foreach ($proc in $requiredProcs) {
            $exists = Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query "
                IF EXISTS (SELECT 1 FROM sys.procedures p 
                          INNER JOIN sys.schemas s ON p.schema_id = s.schema_id 
                          WHERE s.name = 'monitor' AND p.name = '$proc')
                    SELECT 1 AS exists
                ELSE
                    SELECT 0 AS exists
            " -ErrorAction SilentlyContinue
            
            if ($exists.exists -ne 1) {
                $missingProcs += $proc
            }
        }
        
        if ($missingProcs.Count -eq 0) {
            return @{ Passed = $true }
        }
        else {
            return @{ 
                Passed = $false 
                Message = "Missing procedures: $($missingProcs -join ', ')"
            }
        }
    }
    catch {
        return @{ 
            Passed = $false 
            Message = "Failed to validate procedures: $($_.Exception.Message)"
        }
    }
}

function Validate-Settings {
    param(
        $SqlInstance,
        [string]$Database
    )
    
    try {
        $settings = Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query "
            SELECT COUNT(*) AS settingCount 
            FROM monitor.Settings 
            WHERE Category = 'General'
        " -ErrorAction SilentlyContinue
        
        if ($settings.settingCount -gt 0) {
            return @{ Passed = $true }
        }
        else {
            return @{ 
                Warning = $true
                Message = 'No general settings configured (run configuration script)'
            }
        }
    }
    catch {
        return @{ 
            Passed = $false 
            Message = "Failed to validate settings: $($_.Exception.Message)"
        }
    }
}

function Validate-Thresholds {
    param(
        $SqlInstance,
        [string]$Database
    )
    
    try {
        $thresholds = Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query "
            SELECT COUNT(*) AS thresholdCount 
            FROM monitor.Thresholds
        " -ErrorAction SilentlyContinue
        
        if ($thresholds.thresholdCount -gt 0) {
            return @{ Passed = $true }
        }
        else {
            return @{ 
                Warning = $true
                Message = 'No thresholds configured (using defaults)'
            }
        }
    }
    catch {
        return @{ 
            Passed = $false 
            Message = "Failed to validate thresholds: $($_.Exception.Message)"
        }
    }
}

function Validate-Permissions {
    param(
        $SqlInstance,
        [string]$Database
    )
    
    try {
        $currentUser = Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query "SUSER_SNAME()" -ErrorAction SilentlyContinue
        $perms = Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query "
            SELECT COUNT(*) AS hasPermissions
            FROM sys.database_principals p
            INNER JOIN sys.database_permissions dp ON p.principal_id = dp.grantee_principal_id
            WHERE p.name = '$currentUser'
            AND dp.permission_name IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'EXECUTE')
        " -ErrorAction SilentlyContinue
        
        if ($perms.hasPermissions -ge 4) {
            return @{ Passed = $true }
        }
        else {
            return @{ 
                Passed = $false 
                Message = 'Insufficient database permissions'
            }
        }
    }
    catch {
        return @{ 
            Passed = $false 
            Message = "Failed to validate permissions: $($_.Exception.Message)"
        }
    }
}

function Validate-AgentJobs {
    param(
        $SqlInstance,
        [string]$Database
    )
    
    try {
        $requiredJobs = @('SQLHealthMonitor - Collection', 'SQLHealthMonitor - Daily Report')
        $missingJobs = @()
        
        foreach ($job in $requiredJobs) {
            $exists = Invoke-DbaQuery -SqlInstance $sqlInstance -Database 'msdb' -Query "
                IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = '$job')
                    SELECT 1 AS exists
                ELSE
                    SELECT 0 AS exists
            " -ErrorAction SilentlyContinue
            
            if ($exists.exists -ne 1) {
                $missingJobs += $job
            }
        }
        
        if ($missingJobs.Count -eq 0) {
            return @{ Passed = $true }
        }
        else {
            return @{ 
                Warning = $true
                Message = "Jobs not created: $($missingJobs -join ', ') (manual deployment may be needed)"
            }
        }
    }
    catch {
        return @{ 
            Warning = $true
            Message = "Could not validate SQL Agent jobs: $($_.Exception.Message)"
        }
    }
}