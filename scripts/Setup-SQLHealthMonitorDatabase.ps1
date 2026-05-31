<#
.SYNOPSIS
    SQL Health Monitor - Generic Installation Setup Script
    Creates database, schemas, tables, and stored procedures for any environment.

.DESCRIPTION
    This is a generic installation script that creates the SQL Health Monitor
    database structure without hardcoding any specific environment names.
    It works with any SQL Server instance and database name.

.PARAMETER ServerInstance
    Target SQL Server instance (e.g., 'localhost', 'SQL-PRD-01')

.PARAMETER Database
    Database name to create/use. Default: 'SQLHealthMonitor'

.PARAMETER AuthMethod
    Authentication method: 'Windows' (default) or 'Sql'

.PARAMETER SqlCredential
    SQL credential object for SQL authentication

.PARAMETER Force
    Overwrite existing database without prompting

.EXAMPLE
    # Windows authentication
    .\Setup-SQLHealthMonitorDatabase.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor'

.EXAMPLE
    # SQL authentication
    $cred = Get-Credential
    .\Setup-SQLHealthMonitorDatabase.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -AuthMethod 'Sql' -SqlCredential $cred

.EXAMPLE
    # Force overwrite existing database
    .\Setup-SQLHealthMonitorDatabase.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -Force

.NOTES
    Author: Lucas Allan Borges
    Version: 1.0.0
    Generic version - no hardcoded environment dependencies
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
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
    [switch]$Force
)

begin {
    $scriptStart = Get-Date
    $modulePath = $PSScriptRoot
    $installPath = Join-Path $modulePath 'install'
    
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  SQL Health Monitor - Database Setup" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Server:    $ServerInstance"
    Write-Host "  Database:  $Database"
    Write-Host "  Auth:      $AuthMethod"
    Write-Host ""
}

process {
    try {
        # --- Step 1: Connect to SQL Server ---
        Write-Host "[1/5] Connecting to SQL Server..." -ForegroundColor Yellow
        
        $sqlParams = @{
            SqlInstance = $ServerInstance
            ErrorAction = 'Stop'
        }
        
        if ($AuthMethod -eq 'Sql' -and $SqlCredential) {
            $sqlParams.SqlCredential = $SqlCredential
        }
        
        $sqlInstance = Connect-DbaInstance @sqlParams
        Write-Host "      Connected successfully to $ServerInstance" -ForegroundColor Green

        # --- Step 2: Create database if not exists ---
        Write-Host "[2/5] Creating database..." -ForegroundColor Yellow
        if ($PSCmdlet.ShouldProcess($Database, "Create database")) {
            $dbExists = Get-DbaDatabase -SqlInstance $sqlInstance -Database $Database -ErrorAction SilentlyContinue
            
            if ($dbExists) {
                if ($Force) {
                    Write-Host "      Database exists, dropping due to -Force..." -ForegroundColor Yellow
                    Remove-DbaDatabase -SqlInstance $sqlInstance -Database $Database -Confirm:$false
                    $dbExists = $null
                }
                else {
                    Write-Host "      Database '$Database' already exists." -ForegroundColor Green
                    Write-Host "      Use -Force to overwrite existing database." -ForegroundColor Yellow
                }
            }
            
            if (-not $dbExists) {
                $createDbSql = @"
CREATE DATABASE [$Database]
ALTER DATABASE [$Database] SET RECOVERY SIMPLE
ALTER DATABASE [$Database] SET AUTO_CLOSE OFF
ALTER DATABASE [$Database] SET AUTO_SHRINK OFF
ALTER DATABASE [$Database] SET ALLOW_SNAPSHOT_ISOLATION ON
ALTER DATABASE [$Database] SET READ_COMMITTED_SNAPSHOT ON
"@
                Invoke-DbaQuery -SqlInstance $sqlInstance -Query $createDbSql
                Write-Host "      Database '$Database' created successfully." -ForegroundColor Green
            }
        }

        # --- Step 3: Create schema and tables ---
        Write-Host "[3/5] Creating schema and tables..." -ForegroundColor Yellow
        if ($PSCmdlet.ShouldProcess($Database, "Create schema and tables")) {
            $schemaScript = Get-Content -Path "$installPath\00-create-schema.sql" -Raw
            $schemaScript = $schemaScript -replace '\[SQLHealthMonitor\]', "[$Database]"
            
            Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query $schemaScript -QueryTimeout 300
            Write-Host "      Schema and tables created successfully." -ForegroundColor Green
        }

        # --- Step 4: Create stored procedures and functions ---
        Write-Host "[4/5] Creating stored procedures and functions..." -ForegroundColor Yellow
        if ($PSCmdlet.ShouldProcess($Database, "Create stored procedures")) {
            $procsPath = Join-Path $modulePath 'collectors'
            $procs = Get-ChildItem -Path $procsPath -Filter '*.sql' -Recurse -ErrorAction SilentlyContinue
            
            foreach ($proc in $procs) {
                Write-Host "      $($proc.Name)..." -NoNewline
                try {
                    $procSql = Get-Content -Path $proc.FullName -Raw
                    Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query $procSql -QueryTimeout 300
                    Write-Host " OK" -ForegroundColor Green
                }
                catch {
                    Write-Host " FAILED" -ForegroundColor Red
                    Write-Warning "Failed to create $($proc.Name): $($_.Exception.Message)"
                }
            }
        }

        # --- Step 5: Create views and reports ---
        Write-Host "[5/5] Creating views and reports..." -ForegroundColor Yellow
        if ($PSCmdlet.ShouldProcess($Database, "Create views and reports")) {
            $viewsPath = Join-Path $modulePath 'views'
            $reportsPath = Join-Path $modulePath 'reports'
            
            $viewDirs = @($viewsPath, $reportsPath)
            
            foreach ($dir in $viewDirs) {
                if (Test-Path $dir) {
                    $sqlFiles = Get-ChildItem -Path $dir -Filter '*.sql' -Recurse -ErrorAction SilentlyContinue
                    
                    foreach ($file in $sqlFiles) {
                        Write-Host "      $($file.Name)..." -NoNewline
                        try {
                            $viewSql = Get-Content -Path $file.FullName -Raw
                            Invoke-DbaQuery -SqlInstance $sqlInstance -Database $Database -Query $viewSql -QueryTimeout 300
                            Write-Host " OK" -ForegroundColor Green
                        }
                        catch {
                            Write-Host " FAILED" -ForegroundColor Red
                            Write-Warning "Failed to create $($file.Name): $($_.Exception.Message)"
                        }
                    }
                }
            }
        }

        # --- Done ---
        $duration = (Get-Date) - $scriptStart
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Green
        Write-Host "  Database setup completed in $($duration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
        Write-Host "============================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "  1. Configure: .\Configure-SQLHealthMonitor.ps1 -ServerInstance '$ServerInstance' -Database '$Database'"
        Write-Host "  2. Test:      .\Test-SQLHealthMonitorInstallation.ps1 -ServerInstance '$ServerInstance' -Database '$Database'"
        Write-Host "  3. Deploy:   .\Deploy-SQLHealthMonitorJobs.ps1 -ServerInstance '$ServerInstance' -Database '$Database'"
        Write-Host ""
        
        # Return database info for pipeline
        [PSCustomObject]@{
            ServerInstance = $ServerInstance
            Database = $Database
            Status = 'Completed'
            Duration = $duration
        }
    }
    catch {
        Write-Host ""
        Write-Host "DATABASE SETUP FAILED" -ForegroundColor Red
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