@{
    RootModule        = 'Invoke-SQLHealthMonitor.ps1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a3f7b2c1-4d5e-6f78-9a0b-1c2d3e4f5a6b'
    Author            = 'Lucas Allan Borges'
    CompanyName       = 'DataBank'
    Copyright         = '(c) 2026 Lucas Allan Borges. All rights reserved.'
    Description       = 'SQL Server Health Monitor - Proactive monitoring, alerting, and reporting for SQL Server environments.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    RequiredModules   = @('dbatools')
    FunctionsToExport = @(
        'Invoke-SQLHealthMonitor',
        'Send-HealthReport',
        'Install-SQLHealthMonitor'
    )
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
    PrivateData = @{
        PSData = @{
            Tags         = @('SQLServer', 'Monitoring', 'Health', 'DBA', 'Alerting', 'Reporting')
            LicenseUri   = 'https://github.com/lucasborgesbr/sql-health-monitor/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/lucasborgesbr/sql-health-monitor'
            ReleaseNotes = 'Initial release - Core monitoring, alerting, and reporting capabilities.'
        }
    }
}
