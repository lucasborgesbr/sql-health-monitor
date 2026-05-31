-- SQL Health Monitor - Post-Migration Validation Script
-- Validates the successful migration from DBA_Monitor to SQLHealthMonitor
--
-- Usage: Run in the context of the SQLHealthMonitor database
-- 

USE [SQLHealthMonitor];
GO

PRINT '=== SQL Health Monitor - Post-Migration Validation ===';
PRINT 'Starting validation of SQLHealthMonitor database...';
PRINT '======================================================';

-- =============================================
-- VALIDATION 1: DATABASE EXISTENCE
-- =============================================

PRINT '';
PRINT '[1/10] Validating database existence...';

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SQLHealthMonitor')
BEGIN
    PRINT 'ERROR: SQLHealthMonitor database does not exist.';
    PRINT 'Migration may have failed.';
    RETURN;
END

PRINT '✓ Database SQLHealthMonitor exists';

-- =============================================
-- VALIDATION 2: CRITICAL TABLES
-- =============================================

PRINT '';
PRINT '[2/10] Validating critical tables...';

DECLARE @missing_tables INT = 0;

-- Check monitor schema tables
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Metrics' AND schema_id = SCHEMA_ID('monitor'))
BEGIN
    PRINT '✗ Table monitor.Metrics is missing';
    SET @missing_tables = @missing_tables + 1;
END
ELSE
BEGIN
    PRINT '✓ Table monitor.Metrics exists';
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Thresholds' AND schema_id = SCHEMA_ID('monitor'))
BEGIN
    PRINT '✗ Table monitor.Thresholds is missing';
    SET @missing_tables = @missing_tables + 1;
END
ELSE
BEGIN
    PRINT '✓ Table monitor.Thresholds exists';
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'AlertHistory' AND schema_id = SCHEMA_ID('monitor'))
BEGIN
    PRINT '✗ Table monitor.AlertHistory is missing';
    SET @missing_tables = @missing_tables + 1;
END
ELSE
BEGIN
    PRINT '✓ Table monitor.AlertHistory exists';
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Collectors' AND schema_id = SCHEMA_ID('monitor'))
BEGIN
    PRINT '✗ Table monitor.Collectors is missing';
    SET @missing_tables = @missing_tables + 1;
END
ELSE
BEGIN
    PRINT '✓ Table monitor.Collectors exists';
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Alerts' AND schema_id = SCHEMA_ID('monitor'))
BEGIN
    PRINT '✗ Table monitor.Alerts is missing';
    SET @missing_tables = @missing_tables + 1;
END
ELSE
BEGIN
    PRINT '✓ Table monitor.Alerts exists';
END

IF @missing_tables > 0
BEGIN
    PRINT '✗ Validation failed: ' + CAST(@missing_tables AS VARCHAR(10)) + ' tables are missing';
    RETURN;
END

-- =============================================
-- VALIDATION 3: CRITICAL STORED PROCEDURES
-- =============================================

PRINT '';
PRINT '[3/10] Validating critical stored procedures...';

DECLARE @missing_procs INT = 0;

-- Check main collector procedure
IF NOT EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_Collect_All' AND schema_id = SCHEMA_ID('monitor'))
BEGIN
    PRINT '✗ Procedure monitor.usp_Collect_All is missing';
    SET @missing_procs = @missing_procs + 1;
END
ELSE
BEGIN
    PRINT '✓ Procedure monitor.usp_Collect_All exists';
END

-- Check individual collectors (sample)
DECLARE @required_collectors TABLE (proc_name NVARCHAR(128));
INSERT INTO @required_collectors VALUES 
    ('usp_Collect_CPU'),
    ('usp_Collect_Memory'),
    ('usp_Collect_Disk'),
    ('usp_Collect_Waits'),
    ('usp_Collect_Blocking'),
    ('usp_Collect_Ag_Health'),
    ('usp_Collect_CDC_Health');

DECLARE @collector_count INT = 0;
DECLARE @missing_collectors INT = 0;

SELECT @collector_count = COUNT(*) 
FROM @required_collectors
WHERE EXISTS (SELECT 1 FROM sys.procedures WHERE name = proc_name AND schema_id = SCHEMA_ID('monitor'));

SELECT @missing_collectors = COUNT(*) 
FROM @required_collectors
WHERE NOT EXISTS (SELECT 1 FROM sys.procedures WHERE name = proc_name AND schema_id = SCHEMA_ID('monitor'));

IF @missing_collectors > 0
BEGIN
    PRINT '✗ ' + CAST(@missing_collectors AS VARCHAR(10)) + ' collector procedures are missing';
    SET @missing_procs = @missing_procs + @missing_collectors;
END
ELSE
BEGIN
    PRINT '✓ All required collector procedures exist';
END

IF @missing_procs > 0
BEGIN
    PRINT '✗ Validation failed: ' + CAST(@missing_procs AS VARCHAR(10)) + ' procedures are missing';
    RETURN;
END

-- =============================================
-- VALIDATION 4: REPORT PROCEDURES
-- =============================================

PRINT '';
PRINT '[4/10] Validating report procedures...';

IF NOT EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_Generate_Daily_Report' AND schema_id = SCHEMA_ID('monitor'))
BEGIN
    PRINT '✗ Procedure monitor.usp_Generate_Daily_Report is missing';
    RETURN;
END
ELSE
BEGIN
    PRINT '✓ Procedure monitor.usp_Generate_Daily_Report exists';
END

IF NOT EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_Generate_Weekly_Report' AND schema_id = SCHEMA_ID('monitor'))
BEGIN
    PRINT '✗ Procedure monitor.usp_Generate_Weekly_Report is missing';
    RETURN;
END
ELSE
BEGIN
    PRINT '✓ Procedure monitor.usp_Generate_Weekly_Report exists';
END

-- =============================================
-- VALIDATION 5: ALERT ENGINE PROCEDURES
-- =============================================

PRINT '';
PRINT '[5/10] Validating alert engine procedures...';

IF NOT EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_Check_Alerts' AND schema_id = SCHEMA_ID('monitor'))
BEGIN
    PRINT '✗ Procedure monitor.usp_Check_Alerts is missing';
    RETURN;
END
ELSE
BEGIN
    PRINT '✓ Procedure monitor.usp_Check_Alerts exists';
END

IF NOT EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_Check_Baselines' AND schema_id = SCHEMA_ID('monitor'))
BEGIN
    PRINT '✗ Procedure monitor.usp_Check_Baselines is missing';
    RETURN;
END
ELSE
BEGIN
    PRINT '✓ Procedure monitor.usp_Check_Baselines exists';
END

-- =============================================
-- VALIDATION 6: DATABASE METRICS
-- =============================================

PRINT '';
PRINT '[6/10] Validating database metrics...';

-- Check if there's any data in the metrics table
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Metrics' AND schema_id = SCHEMA_ID('monitor'))
BEGIN
    DECLARE @metrics_count INT;
    SELECT @metrics_count = COUNT(*) FROM monitor.Metrics;
    
    IF @metrics_count > 0
    BEGIN
        PRINT '✓ Database contains ' + CAST(@metrics_count AS VARCHAR(10)) + ' metric records';
    END
    ELSE
    BEGIN
        PRINT '⚠ Database metrics table is empty (expected if first run)';
    END
END

-- Check if there are thresholds configured
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Thresholds' AND schema_id = SCHEMA_ID('monitor'))
BEGIN
    DECLARE @thresholds_count INT;
    SELECT @thresholds_count = COUNT(*) FROM monitor.Thresholds;
    
    IF @thresholds_count > 0
    BEGIN
        PRINT '✓ Database contains ' + CAST(@thresholds_count AS VARCHAR(10)) + ' threshold configurations';
    END
    ELSE
    BEGIN
        PRINT '⚠ Thresholds table is empty (expected if first run)';
    END
END

-- =============================================
-- VALIDATION 7: ALERT HISTORY
-- =============================================

PRINT '';
PRINT '[7/10] Validating alert history...';

IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'AlertHistory' AND schema_id = SCHEMA_ID('monitor'))
BEGIN
    DECLARE @alert_history_count INT;
    SELECT @alert_history_count = COUNT(*) FROM monitor.AlertHistory;
    
    IF @alert_history_count > 0
    BEGIN
        PRINT '✓ Database contains ' + CAST(@alert_history_count AS VARCHAR(10)) + ' alert history records';
    END
    ELSE
    BEGIN
        PRINT '⚠ Alert history table is empty (expected if first run)';
    END
END

-- =============================================
-- VALIDATION 8: BASELINES
-- =============================================

PRINT '';
PRINT '[8/10] Validating baselines...';

IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Baselines' AND schema_id = SCHEMA_ID('monitor'))
BEGIN
    DECLARE @baselines_count INT;
    SELECT @baselines_count = COUNT(*) FROM monitor.Baselines;
    
    IF @baselines_count > 0
    BEGIN
        PRINT '✓ Database contains ' + CAST(@baselines_count AS VARCHAR(10)) + ' baseline records';
    END
    ELSE
    BEGIN
        PRINT '⚠ Baselines table is empty (expected if first run)';
    END
END

-- =============================================
-- VALIDATION 9: JOB DEFINITIONS
-- =============================================

PRINT '';
PRINT '[9/10] Validating SQL Agent jobs...';

IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_Get_Job_Status' AND schema_id = SCHEMA_ID('monitor'))
BEGIN
    PRINT '✓ Job status procedure exists';
    
    -- Try to execute the procedure to check for errors
    BEGIN TRY
        EXEC monitor.usp_Get_Job_Status;
        PRINT '✓ Job status procedure executed successfully';
    END TRY
    BEGIN CATCH
        PRINT '✗ Error executing job status procedure:';
        PRINT '   ' + ERROR_MESSAGE();
    END CATCH
END
ELSE
BEGIN
    PRINT '⚠ Job status procedure not found (may not be installed)';
END

-- =============================================
-- VALIDATION 10: VIEW DEFINITIONS
-- =============================================

PRINT '';
PRINT '[10/10] Validating views...';

IF EXISTS (SELECT 1 FROM sys.views WHERE name = 'vw_CurrentHealth' AND schema_id = SCHEMA_ID('monitor'))
BEGIN
    PRINT '✓ View monitor.vw_CurrentHealth exists';
END
ELSE
BEGIN
    PRINT '⚠ View monitor.vw_CurrentHealth not found (may not be installed)';
END

-- =============================================
-- FINAL SUMMARY
-- =============================================

PRINT '';
PRINT '======================================================';
PRINT 'VALIDATION SUMMARY';
PRINT '======================================================';

-- Calculate overall status
DECLARE @overall_status VARCHAR(10) = 'SUCCESS';
DECLARE @total_checks INT = 10;
DECLARE @passed_checks INT = 10;
DECLARE @failed_checks INT = 0;

SELECT @failed_checks = COUNT(*) 
FROM (
    SELECT 1 WHERE EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Metrics' AND schema_id = SCHEMA_ID('monitor')) 
    UNION ALL
    SELECT 1 WHERE EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Thresholds' AND schema_id = SCHEMA_ID('monitor')) 
    UNION ALL
    SELECT 1 WHERE EXISTS (SELECT 1 FROM sys.tables WHERE name = 'AlertHistory' AND schema_id = SCHEMA_ID('monitor')) 
    UNION ALL
    SELECT 1 WHERE EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_Collect_All' AND schema_id = SCHEMA_ID('monitor')) 
    UNION ALL
    SELECT 1 WHERE EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_Generate_Daily_Report' AND schema_id = SCHEMA_ID('monitor')) 
    UNION ALL
    SELECT 1 WHERE EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_Check_Alerts' AND schema_id = SCHEMA_ID('monitor')) 
    UNION ALL
    SELECT 1 WHERE EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_Get_Job_Status' AND schema_id = SCHEMA_ID('monitor')) 
    UNION ALL
    SELECT 1 WHERE EXISTS (SELECT 1 FROM sys.views WHERE name = 'vw_CurrentHealth' AND schema_id = SCHEMA_ID('monitor')) 
) AS checks;

SET @passed_checks = 8 - @failed_checks;

IF @failed_checks > 0
BEGIN
    SET @overall_status = 'FAILED';
END

PRINT 'Total checks: ' + CAST(@total_checks AS VARCHAR(10));
PRINT 'Passed: ' + CAST(@passed_checks AS VARCHAR(10));
PRINT 'Failed: ' + CAST(@failed_checks AS VARCHAR(10));
PRINT 'Status: ' + @overall_status;

IF @overall_status = 'SUCCESS'
BEGIN
    PRINT '';
    PRINT '✓✓✓ VALIDATION PASSED - Migration was successful! ✓✓✓';
    PRINT '';
    PRINT 'Next steps:';
    PRINT '1. Run the collection procedure to populate metrics:';
    PRINT '   EXEC monitor.usp_Collect_All;';
    PRINT '';
    PRINT '2. Check alert thresholds:';
    PRINT '   SELECT * FROM monitor.Thresholds;';
    PRINT '';
    PRINT '3. Generate initial reports:';
    PRINT '   EXEC monitor.usp_Generate_Daily_Report;';
    PRINT '';
    PRINT '4. Schedule SQL Agent jobs for automated monitoring:';
    PRINT '   EXEC monitor.usp_Create_Jobs;';
    PRINT '';
    PRINT 'For more information:';
    PRINT '   EXEC monitor.usp_Get_Migration_Status;';
ELSE
BEGIN
    PRINT '';
    PRINT '✗✗✗ VALIDATION FAILED - Migration may have issues! ✗✗✗';
    PRINT '';
    PRINT 'Please review the failed checks above.';
    PRINT 'If needed, restore from backup and try migration again.';
    PRINT '';
    PRINT 'Rollback instructions:';
    PRINT '1. Restore database: RESTORE DATABASE DBA_Monitor FROM DISK = ''C:\\SQL_Backups\\SQLHealthMonitor\\DBA_Monitor_*.bak''';
    PRINT '2. Drop SQLHealthMonitor: DROP DATABASE SQLHealthMonitor;';
END

PRINT '=======================================================';