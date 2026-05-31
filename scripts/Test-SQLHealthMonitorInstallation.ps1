<#
.SYNOPSIS
    SQL Health Monitor - Installation Validation and Testing Script
    Validates the installation and performs comprehensive testing of the SQL Health Monitor.

.DESCRIPTION
    This script performs comprehensive validation and testing of the SQL Health Monitor installation.
    It checks database objects, configuration, permissions, and performs functional tests.

.PARAMETER ServerInstance
    Target SQL Server instance (e.g., 'localhost', 'SQL-PRD-01')

.PARAMETER Database
    Database name. Default: 'SQLHealthMonitor'

.PARAMETER AuthMethod
    Authentication method: 'Windows' (default) or 'Sql'

.PARAMETER SqlCredential
    SQL credential object for SQL authentication

.PARAMETER TestMode
    Test mode: 'Basic' (default) or 'Comprehensive'

.EXAMPLE
    # Basic validation
    .\Test-SQLHealthMonitorInstallation.ps1 -ServerInstance 'SQL-PRD-01' -Database 'DBA_Monitor'

.EXAMPLE
    # Comprehensive testing
    .\Test-SQLHealthMonitorInstallation.ps1 -ServerInstance 'SQL-PRD-01' -Database 'DBA_Monitor' -TestMode 'Comprehensive'

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
    [System.Management.Automation.PSCredential]$SqlCredential,

    [Parameter()]
    [ValidateSet('Basic', 'Comprehensive')]
    [string]$TestMode = 'Basic'
)

begin {
    $scriptStart = Get-Date
    $testResults = @{
        Passed = 0
        Failed = 0
        Warnings = 0
        Details = @()
    }
    
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  SQL Health Monitor - Installation Testing" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Server:    $ServerInstance"
    Write-Host "  Database:  $Database"
    Write-Host "  Test Mode: $TestMode"
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

        # --- Step 2: Test database structure ---
        Write-Host "[2/5] Testing database structure..." -ForegroundColor Yellow
        
        # Test database existence
        $dbCheck = Test-Database -SqlInstance $sqlInstance -Database $Database
        Add-TestResult -Result $dbCheck -TestName "Database existence"
        
        if ($dbCheck.Passed) {
            # Test schema existence
            $schemaCheck = Test-Schema -SqlInstance $sqlInstance -Database $Database
            Add-TestResult -Result $schemaCheck -TestName "Schema existence"
            
            # Test tables existence
            $tablesCheck = Test-Tables -SqlInstance $sqlInstance -Database $Database
            Add-TestResult -Result $tablesCheck -TestName "Tables existence"
            
            # Test stored procedures existence
            $procsCheck = Test-Procedures -SqlInstance $sqlInstance -Database $Database
            Add-TestResult -Result $procsCheck -TestName "Stored procedures existence"
            
            # Test views existence
            $viewsCheck = Test-Views -SqlInstance $sqlInstance -Database $Database
            Add-TestResult -Result $viewsCheck -TestName "Views existence"
        }

        # --- Step 3: Test configuration ---
        Write-Host "[3/5] Testing configuration..." -ForegroundColor Yellow
        
        # Test settings table
        $settingsCheck = Test-Settings -SqlInstance $sqlInstance -Database $Database
        Add-TestResult -Result $settingsCheck -TestName "Settings configuration"
        
        # Test thresholds configuration
        $thresholdsCheck = Test-Thresholds -SqlInstance $sqlInstance -Database $Database
        Add-TestResult -Result $thresholdsCheck -TestName "Thresholds configuration"

        # --- Step 4: Test permissions ---
        Write-Host "[4/5] Testing permissions..." -ForegroundColor Yellow
        
        # Test database permissions
        $dbPermsCheck = Test-DatabasePermissions -SqlInstance $sqlInstance -Database $Database
        Add-TestResult -Result $dbPermsCheck -TestName "Database permissions"

        # --- Step 5: Functional testing (if comprehensive mode) ---
        if ($TestMode -eq 'Comprehensive') {
            Write-Host "[5/5] Performing functional tests..." -ForegroundColor Yellow
            
            # Test basic collection
            $collectionCheck = Test-Collection -SqlInstance $sqlInstance -Database $Database
            Add-TestResult -Result $collectionCheck -TestName "Data collection"
            
            # Test report generation
            $reportCheck = Test-ReportGeneration -SqlInstance $sqlInstance -Database $Database
            Add-TestResult -Result $reportCheck -TestName "Report generation"
        }

        # --- Generate test report ---
        $duration = (Get-Date) - $scriptStart
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Green
        Write-Host "  Test Results Summary" -ForegroundColor Green
        Write-Host "============================================" -ForegroundColor Green
        Write-Host "  Passed:      $($testResults.Passed)"
        Write-Host "  Failed:      $($testResults.Failed)"
        Write-Host "  Warnings:    $($testResults.Warnings)"
        Write-Host "  Duration:    $($duration.TotalSeconds.ToString('F1'))s"
        Write-Host ""
        
        if ($testResults.Failed -eq 0) {
            Write-Host "✅ ALL TESTS PASSED" -ForegroundColor Green
            Write-Host ""
            Write-Host "The SQL Health Monitor installation is ready for use." -ForegroundColor Green
        }
        else {
            Write-Host "❌ SOME TESTS FAILED" -ForegroundColor Red
            Write-Host "Please review the failed tests above and fix the issues." -ForegroundColor Red
        }
        
        if ($testResults.Warnings -gt 0) {
            Write-Host "⚠️  $($testResults.Warnings) warnings detected" -ForegroundColor Yellow
        }
        
        Write-Host ""
        
        # Return test results for pipeline
        [PSCustomObject]@{
            ServerInstance = $ServerInstance
            Database = $Database
            TestMode = $TestMode
            Results = $testResults
            Status = if ($testResults.Failed -eq 0) { 'Passed' } else { 'Failed' }
            Duration = $duration
        }
    }
    catch {
        Write-Host ""
        Write-Host "TESTING FAILED" -ForegroundColor Red
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

function Add-TestResult {
    param(
        [object]$Result,
        [string]$TestName
    )
    
    if ($Result.Passed) {
        Write-Host "      ✅ $TestName - PASSED" -ForegroundColor Green
        $testResults.Passed++
    }
    elseif ($Result.Warning) {
        Write-Host "      ⚠️  $TestName - WARNING: $($Result.Message)" -ForegroundColor Yellow
        $testResults.Warnings++
        $testResults.Details += @{
            Test = $TestName
            Status = 'Warning'
            Message = $Result.Message
        }
    }
    else {
        Write-Host "      ❌ $TestName - FAILED: $($Result.Message)" -ForegroundColor Red
        $testResults.Failed++
        $testResults.Details += @{
            Test = $TestName
            Status = 'Failed'
            Message = $Result.Message
        }
    }
}

function Test-Database {
    param(
        $SqlInstance,
        [string]$Database
    )
    
    try {
        $db = Get-DbaDatabase -SqlInstance $sqlInstance -Database $Database -ErrorAction SilentlyContinue
        if ($db) {
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
            Message = "Failed to check database: $($_.Exception.Message)"
        }
    }
}

function Test-Schema {
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
            Message = "Failed to check schema: $($_.Exception.Message)"
        }
    }
}

function Test-Tables {
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
            Message = "Failed to check tables: $($_.Exception.Message)"
        }
    }
}

function Test-Procedures {
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
            Message = "Failed to check procedures: $($_.Exception.Message)"
        }
    }
}

function Test-Views {
    param(
        $SqlInstance,
        [string]$Database
    )
    
    try {
        $requiredViews = @('vw_CurrentHealth', 'vw_AlertSummary')
        $missingViews = @()
        
        foreach ($view in $requiredViews) {
            $exists = Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query "
                IF EXISTS (SELECT 1 FROM sys.views v 
                          INNER JOIN sys.schemas s ON v.schema_id = s.schema_id 
                          WHERE s.name = 'monitor' AND v.name = '$view')
                    SELECT 1 AS exists
                ELSE
                    SELECT 0 AS exists
            " -ErrorAction SilentlyContinue
            
            if ($exists.exists -ne 1) {
                $missingViews += $view
            }
        }
        
        if ($missingViews.Count -eq 0) {
            return @{ Passed = $true }
        }
        else {
            return @{ 
                Passed = $false 
                Message = "Missing views: $($missingViews -join ', ')"
            }
        }
    }
    catch {
        return @{ 
            Passed = $false 
            Message = "Failed to check views: $($_.Exception.Message)"
        }
    }
}

function Test-Settings {
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
                Passed = $false 
                Message = 'No general settings found'
            }
        }
    }
    catch {
        return @{ 
            Passed = $false 
            Message = "Failed to check settings: $($_.Exception.Message)"
        }
    }
}

function Test-Thresholds {
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
            Message = "Failed to check thresholds: $($_.Exception.Message)"
        }
    }
}

function Test-DatabasePermissions {
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
        
        if ($perms.hasPermissions -ge 4) { # At least SELECT, INSERT, UPDATE, DELETE
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
            Message = "Failed to check permissions: $($_.Exception.Message)"
        }
    }
}

function Test-Collection {
    param(
        $SqlInstance,
        [string]$Database
    )
    
    try {
        $test = Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query "
            DECLARE @result INT
            EXEC @result = [monitor].[usp_CollectSystemInfo]
            SELECT @result AS success
        " -ErrorAction SilentlyContinue
        
        if ($test.success -eq 0) {
            return @{ Passed = $true }
        }
        else {
            return @{ 
                Passed = $false 
                Message = 'Data collection failed'
            }
        }
    }
    catch {
        return @{ 
            Passed = $false 
            Message = "Failed to test collection: $($_.Exception.Message)"
        }
    }
}

function Test-ReportGeneration {
    param(
        $SqlInstance,
        [string]$Database
    )
    
    try {
        $test = Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query "
            DECLARE @result INT
            EXEC @result = [monitor].[usp_GenerateDailyReport]
            SELECT @result AS success
        " -ErrorAction SilentlyContinue
        
        if ($test.success -eq 0) {
            return @{ Passed = $true }
        }
        else {
            return @{ 
                Passed = $false 
                Message = 'Report generation failed'
            }
        }
    }
    catch {
        return @{ 
            Passed = $false 
            Message = "Failed to test report generation: $($_.Exception.Message)"
        }
    }
}