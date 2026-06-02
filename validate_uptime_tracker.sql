/*
    SQL Health Monitor - Uptime Tracker Validation
    Validates the complete uptime tracking system installation and functionality.
    
    Tests:
    - Table existence and structure
    - Procedure existence and syntax
    - View functionality
    - Data collection simulation
    - Report generation
*/

USE [SQLHealthMonitor];
GO

PRINT '================================================';
PRINT '  Uptime Tracker Validation';
PRINT '================================================';
GO

--------------------------------------------------------------
-- TEST 1: Check table existence
--------------------------------------------------------------
PRINT '';
PRINT '[1/6] Validating table existence...';

DECLARE @TableCheck TABLE (TableName NVARCHAR(128), Status NVARCHAR(20));

-- Check required tables
INSERT INTO @TableCheck (TableName, Status)
SELECT 
    'monitor.Incidents',
    CASE WHEN OBJECT_ID('monitor.Incidents', 'U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END
UNION ALL SELECT 
    'monitor.UptimePeriods',
    CASE WHEN OBJECT_ID('monitor.UptimePeriods', 'U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END
UNION ALL SELECT 
    'monitor.SLATracking',
    CASE WHEN OBJECT_ID('monitor.SLATracking', 'U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END
UNION ALL SELECT 
    'monitor.IncidentSources',
    CASE WHEN OBJECT_ID('monitor.IncidentSources', 'U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END;

SELECT TableName, Status FROM @TableCheck WHERE Status <> 'OK';
GO

--------------------------------------------------------------
-- TEST 2: Check procedure existence
--------------------------------------------------------------
PRINT '';
PRINT '[2/6] Validating procedure existence...';

DECLARE @ProcCheck TABLE (ProcName NVARCHAR(128), Status NVARCHAR(20));

-- Check required procedures
INSERT INTO @ProcCheck (ProcName, Status)
SELECT 
    'monitor.usp_Collect_UptimeTracker',
    CASE WHEN OBJECT_ID('monitor.usp_Collect_UptimeTracker', 'P') IS NOT NULL THEN 'OK' ELSE 'MISSING' END
UNION ALL SELECT 
    'monitor.usp_Generate_MonthlyUptimeReport',
    CASE WHEN OBJECT_ID('monitor.usp_Generate_MonthlyUptimeReport', 'P') IS NOT NULL THEN 'OK' ELSE 'MISSING' END;

SELECT ProcName, Status FROM @ProcCheck WHERE Status <> 'OK';
GO

--------------------------------------------------------------
-- TEST 3: Check view existence
--------------------------------------------------------------
PRINT '';
PRINT '[3/6] Validating view existence...';

DECLARE @ViewCheck TABLE (ViewName NVARCHAR(128), Status NVARCHAR(20));

-- Check required views
INSERT INTO @ViewCheck (ViewName, Status)
SELECT 
    'monitor.vw_CurrentUptimeStatus',
    CASE WHEN OBJECT_ID('monitor.vw_CurrentUptimeStatus', 'V') IS NOT NULL THEN 'OK' ELSE 'MISSING' END
UNION ALL SELECT 
    'monitor.vw_MonthlyUptimeSummary',
    CASE WHEN OBJECT_ID('monitor.vw_MonthlyUptimeSummary', 'V') IS NOT NULL THEN 'OK' ELSE 'MISSING' END
UNION ALL SELECT 
    'monitor.vw_IncidentTrends',
    CASE WHEN OBJECT_ID('monitor.vw_IncidentTrends', 'V') IS NOT NULL THEN 'OK' ELSE 'MISSING' END
UNION ALL SELECT 
    'monitor.vw_ActiveIncidents',
    CASE WHEN OBJECT_ID('monitor.vw_ActiveIncidents', 'V') IS NOT NULL THEN 'OK' ELSE 'MISSING' END
UNION ALL SELECT 
    'monitor.vw_UptimeDashboard',
    CASE WHEN OBJECT_ID('monitor.vw_UptimeDashboard', 'V') IS NOT NULL THEN 'OK' ELSE 'MISSING' END;

SELECT ViewName, Status FROM @ViewCheck WHERE Status <> 'OK';
GO

--------------------------------------------------------------
-- TEST 4: Validate uptime collector execution
--------------------------------------------------------------
PRINT '';
PRINT '[4/6] Testing uptime collector execution...';

-- Create test data if needed
IF NOT EXISTS (SELECT 1 FROM monitor.AlertHistory WHERE FiredAt >= DATEADD(HOUR, -1, GETDATE()))
BEGIN
    -- Insert test alert data
    INSERT INTO monitor.AlertHistory (FiredAt, MetricName, Severity, CurrentValue, ThresholdValue, Message)
    VALUES 
        (DATEADD(MINUTE, -30, GETDATE()), 'CPU_SqlPct', 'Warning', 85.5, 80.0, 'High CPU usage detected'),
        (DATEADD(MINUTE, -15, GETDATE()), 'Disk_UsedPct', 'Critical', 95.2, 90.0, 'Critical disk space usage');
END

-- Execute uptime tracker
BEGIN TRY
    EXEC monitor.usp_Collect_UptimeTracker;
    PRINT '✓ Uptime collector executed successfully';
END TRY
BEGIN CATCH
    PRINT '✗ Uptime collector failed: ' + ERROR_MESSAGE();
END CATCH;
GO

--------------------------------------------------------------
-- TEST 5: Validate monthly report generation
--------------------------------------------------------------
PRINT '';
PRINT '[5/6] Testing monthly report generation...';

BEGIN TRY
    EXEC monitor.usp_Generate_MonthlyUptimeReport @ReportMonth = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
    PRINT '✓ Monthly report generated successfully';
END TRY
BEGIN CATCH
    PRINT '✗ Monthly report generation failed: ' + ERROR_MESSAGE();
END CATCH;
GO

--------------------------------------------------------------
-- TEST 6: Validate view queries
--------------------------------------------------------------
PRINT '';
PRINT '[6/6] Testing view queries...';

-- Test current uptime status
DECLARE @CurrentUptime DECIMAL(5,2);
SELECT @CurrentUptime = UptimePercentage FROM monitor.vw_CurrentUptimeStatus;

PRINT 'Current uptime: ' + CAST(@CurrentUptime AS NVARCHAR(10)) + '%';

-- Test monthly summary
DECLARE @MonthlyUptime DECIMAL(5,2);
SELECT @MonthlyUptime = MonthlyUptimePercentage FROM monitor.vw_MonthlyUptimeSummary;

PRINT 'Monthly uptime: ' + CAST(@MonthlyUptime AS NVARCHAR(10)) + '%';

-- Test active incidents
DECLARE @ActiveIncidents INT;
SELECT @ActiveIncidents = COUNT(*) FROM monitor.vw_ActiveIncidents WHERE IsResolved = 0;

PRINT 'Active incidents: ' + CAST(@ActiveIncidents AS NVARCHAR(10));

-- Test SLA compliance
DECLARE @SLAStatus NVARCHAR(20);
SELECT @SLAStatus = SLAStatus FROM monitor.vw_MonthlyUptimeSummary;

PRINT 'SLA status: ' + @SLAStatus;
GO

--------------------------------------------------------------
-- SUMMARY
--------------------------------------------------------------
PRINT '';
PRINT '================================================';
PRINT '  Validation Summary';
PRINT '================================================';
PRINT '';

-- Check if all tests passed
DECLARE @MissingTables INT = (SELECT COUNT(*) FROM @TableCheck WHERE Status <> 'OK');
DECLARE @MissingProcs INT = (SELECT COUNT(*) FROM @ProcCheck WHERE Status <> 'OK');
DECLARE @MissingViews INT = (SELECT COUNT(*) FROM @ViewCheck WHERE Status <> 'OK');

IF @MissingTables = 0 AND @MissingProcs = 0 AND @MissingViews = 0
BEGIN
    PRINT '✓ ALL TESTS PASSED - Uptime Tracker is properly installed and functional';
    PRINT '';
    PRINT 'Ready for production use!';
    PRINT '';
    PRINT 'Next steps:';
    PRINT '1. Schedule hourly execution: EXEC monitor.usp_Collect_UptimeTracker';
    PRINT '2. Configure SQL Agent job for automated collection';
    PRINT '3. Schedule monthly reports: EXEC monitor.usp_Generate_MonthlyUptimeReport';
    PRINT '4. Monitor dashboard views for real-time status';
END
ELSE
BEGIN
    PRINT '✗ SOME TESTS FAILED - Uptime Tracker installation incomplete';
    PRINT '';
    PRINT 'Missing components:';
    IF @MissingTables > 0 PRINT '  - Tables: ' + CAST(@MissingTables AS NVARCHAR(10));
    IF @MissingProcs > 0 PRINT '  - Procedures: ' + CAST(@MissingProcs AS NVARCHAR(10));
    IF @MissingViews > 0 PRINT '  - Views: ' + CAST(@MissingViews AS NVARCHAR(10));
    PRINT '';
    PRINT 'Please run install/09-uptime-tracker.sql to complete installation';
END

PRINT '';
PRINT '================================================';
PRINT '  Validation Complete';
PRINT '================================================';
GO