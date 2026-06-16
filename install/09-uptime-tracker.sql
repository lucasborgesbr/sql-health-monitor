/*
    SQL Health Monitor - Uptime Tracker Installation
    Installs the complete uptime tracking system with SLA monitoring.
    
    Components:
    - Incident tracking tables (already in 00-create-schema.sql)
    - Uptime tracker collector procedure
    - Monthly uptime report generator
    - Uptime dashboard views
    
    Run after: 00-create-schema.sql, 05-configure.sql
    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

PRINT '================================================';
PRINT '  Uptime Tracker Installation';
PRINT '================================================';
GO

--------------------------------------------------------------
-- STEP 1: Deploy collector procedure
--------------------------------------------------------------
PRINT '';
PRINT '[1/4] Deploying uptime tracker collector...';
:r ..\collectors\collect_uptime_tracker.sql
GO

--------------------------------------------------------------
-- STEP 2: Deploy report procedures
--------------------------------------------------------------
PRINT '';
PRINT '[2/4] Deploying monthly uptime report generator...';
:r ..\reports\monthly_uptime_report.sql
GO

--------------------------------------------------------------
-- STEP 3: Deploy views
--------------------------------------------------------------
PRINT '';
PRINT '[3/4] Deploying uptime tracker views...';
:r ..\views\vw_UptimeTracker.sql
GO

--------------------------------------------------------------
-- STEP 4: Insert default SLA configuration
--------------------------------------------------------------
PRINT '';
PRINT '[4/4] Configuring SLA defaults...';

-- Add SLA settings if they don't exist
IF NOT EXISTS (SELECT 1 FROM [monitor].[Settings] WHERE Category = 'SLA' AND SettingName = 'TargetUptime')
    INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
    VALUES ('SLA', 'TargetUptime', '99.9', 'Target uptime percentage for SLA compliance', 'decimal');
GO

IF NOT EXISTS (SELECT 1 FROM [monitor].[Settings] WHERE Category = 'SLA' AND SettingName = 'CriticalUptimeThreshold')
    INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
    VALUES ('SLA', 'CriticalUptimeThreshold', '99.0', 'Uptime percentage below which is considered critical', 'decimal');
GO

IF NOT EXISTS (SELECT 1 FROM [monitor].[Settings] WHERE Category = 'SLA' AND SettingName = 'IncidentAutoResolveHours')
    INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
    VALUES ('SLA', 'IncidentAutoResolveHours', '24', 'Auto-resolve incidents after this many hours', 'int');
GO

IF NOT EXISTS (SELECT 1 FROM [monitor].[Settings] WHERE Category = 'SLA' AND SettingName = 'UptimeReportDay')
    INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
    VALUES ('SLA', 'UptimeReportDay', '1', 'Day of month to generate uptime report', 'int');
GO

IF NOT EXISTS (SELECT 1 FROM [monitor].[Settings] WHERE Category = 'SLA' AND SettingName = 'TrackPlannedMaintenance')
    INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
    VALUES ('SLA', 'TrackPlannedMaintenance', '1', 'Include planned maintenance in uptime calculations', 'bool');
GO

PRINT '';
PRINT '================================================';
PRINT '  Uptime Tracker Installation Complete!';
PRINT '================================================';
PRINT '';
PRINT 'Components installed:';
PRINT '  - monitor.Incidents table';
PRINT '  - monitor.UptimePeriods table';
PRINT '  - monitor.SLATracking table';
PRINT '  - monitor.IncidentSources table';
PRINT '  - monitor.usp_Collect_UptimeTracker procedure';
PRINT '  - monitor.usp_Generate_MonthlyUptimeReport procedure';
PRINT '  - 6 uptime tracking views';
PRINT '';
PRINT 'Usage:';
PRINT '  -- Run uptime tracker collection (hourly)';
PRINT '  EXEC monitor.usp_Collect_UptimeTracker;';
PRINT '';
PRINT '  -- Generate monthly report';
PRINT '  EXEC monitor.usp_Generate_MonthlyUptimeReport @ReportMonth = ''2026-06-01'';';
PRINT '';
PRINT '  -- View current uptime status';
PRINT '  SELECT * FROM monitor.vw_CurrentUptimeStatus;';
PRINT '';
PRINT '  -- View monthly summary';
PRINT '  SELECT * FROM monitor.vw_MonthlyUptimeSummary;';
PRINT '';
PRINT '  -- View active incidents';
PRINT '  SELECT * FROM monitor.vw_ActiveIncidents;';
PRINT '';
GO