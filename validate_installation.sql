-- =================================================================================
-- SQL Health Monitor - Installation Validation Script
-- Script: validate_installation.sql
-- Purpose: Validate complete installation after fixes
-- Author: Lucas Allan Borges
-- Date: 2026-06-02
-- =================================================================================

USE [SQLHealthMonitor];
GO

PRINT 'SQL Health Monitor - Installation Validation';
PRINT '==========================================';
PRINT '';

-- Test 1: Check if all required tables exist
DECLARE @TableCount INT;
SELECT @TableCount = COUNT(*) 
FROM sys.tables 
WHERE schema_id = SCHEMA_ID('monitor');

PRINT 'Tables in [monitor] schema: ' + CAST(@TableCount AS VARCHAR(10));
IF @TableCount >= 15
BEGIN
    PRINT '✓ Schema tables created successfully';
END
ELSE
BEGIN
    PRINT '✗ Missing schema tables';
END
PRINT '';

-- Test 2: Check if all required procedures exist
DECLARE @ProcCount INT;
SELECT @ProcCount = COUNT(*) 
FROM sys.procedures 
WHERE schema_id = SCHEMA_ID('monitor');

PRINT 'Procedures in [monitor] schema: ' + CAST(@ProcCount AS VARCHAR(10));
IF @ProcCount >= 16
BEGIN
    PRINT '✓ Core procedures created successfully';
END
ELSE
BEGIN
    PRINT '✗ Missing core procedures';
END
PRINT '';

-- Test 3: Check if stub files have been implemented
DECLARE @StubFilesFixed BIT = 1;

-- Check vw_CurrentHealth
IF EXISTS (SELECT 1 FROM sys.views WHERE name = 'vw_CurrentHealth' AND schema_id = SCHEMA_ID('monitor'))
BEGIN
    PRINT '✓ vw_CurrentHealth view implemented';
END
ELSE
BEGIN
    PRINT '✗ vw_CurrentHealth view missing';
    SET @StubFilesFixed = 0;
END

-- Check languages table data
DECLARE @LangCount INT;
SELECT @LangCount = COUNT(*) FROM [monitor].[Languages];
IF @LangCount > 0
BEGIN
    PRINT '✓ Language data loaded (' + CAST(@LangCount AS VARCHAR(10)) + ' strings)';
END
ELSE
BEGIN
    PRINT '✗ Language data missing';
    SET @StubFilesFixed = 0;
END

-- Check settings data
DECLARE @SettingsCount INT;
SELECT @SettingsCount = COUNT(*) FROM [monitor].[Settings];
IF @SettingsCount > 0
BEGIN
    PRINT '✓ Default settings loaded (' + CAST(@SettingsCount AS VARCHAR(10)) + ' settings)';
END
ELSE
BEGIN
    PRINT '✗ Default settings missing';
    SET @StubFilesFixed = 0;
END

-- Test 4: Check thresholds
DECLARE @ThresholdsCount INT;
SELECT @ThresholdsCount = COUNT(*) FROM [monitor].[Thresholds];
IF @ThresholdsCount > 0
BEGIN
    PRINT '✓ Default thresholds loaded (' + CAST(@ThresholdsCount AS VARCHAR(10)) + ' thresholds)';
END
ELSE
BEGIN
    PRINT '✗ Default thresholds missing';
    SET @StubFilesFixed = 0;
END

PRINT '';
PRINT 'Installation Summary:';
PRINT '==================';
IF @TableCount >= 15 AND @ProcCount >= 16 AND @StubFilesFixed = 1
BEGIN
    PRINT '✓ INSTALLATION SUCCESSFUL - All components validated';
    PRINT '✓ Ready for production deployment';
END
ELSE
BEGIN
    PRINT '✗ INSTALLATION INCOMPLETE - Check missing components';
    IF @TableCount < 15 PRINT '  - Missing tables';
    IF @ProcCount < 16 PRINT '  - Missing procedures';
    IF @StubFilesFixed = 0 PRINT '  - Stub files not implemented';
END
PRINT '';

-- Test 5: Check data collection procedures
DECLARE @CollectorProcs TABLE (ProcName NVARCHAR(128));
INSERT INTO @CollectorProcs VALUES
('usp_Collect_CPU'), ('usp_Collect_Memory'), ('usp_Collect_Disk'),
('usp_Collect_Waits'), ('usp_Collect_Blocking'), ('usp_Collect_AG_Health'),
('usp_Collect_CDC_Health'), ('usp_Collect_TopQueries'), ('usp_Collect_IndexHealth'),
('usp_Collect_BackupStatus'), ('usp_Collect_JobHistory'), ('usp_Collect_TempDB'),
('usp_Collect_DatabaseGrowth'), ('usp_Collect_ErrorLog'), ('usp_Collect_LogGrowth'),
('usp_Collect_Deadlocks');

-- COUNT(*) over a LEFT JOIN counts every row whether it matched or not, so it
-- reports every expected procedure as missing. Count the unmatched ones.
DECLARE @MissingProcs INT;
SELECT @MissingProcs = COUNT(*)
FROM @CollectorProcs cp
LEFT JOIN sys.procedures p ON cp.ProcName = p.name AND SCHEMA_NAME(p.schema_id) = 'monitor'
WHERE p.object_id IS NULL;

IF @MissingProcs = 0
BEGIN
    -- A subquery is not allowed inside the PRINT concatenation.
    DECLARE @ExpectedProcs INT = (SELECT COUNT(*) FROM @CollectorProcs);
    PRINT '✓ All ' + CAST(@ExpectedProcs AS VARCHAR(10)) + ' collector procedures implemented';
END
ELSE
BEGIN
    PRINT '✗ Missing ' + CAST(@MissingProcs AS VARCHAR(10)) + ' collector procedures:';
    SELECT cp.ProcName AS MissingProcedure
    FROM @CollectorProcs cp
    LEFT JOIN sys.procedures p ON cp.ProcName = p.name AND SCHEMA_NAME(p.schema_id) = 'monitor'
    WHERE p.object_id IS NULL;
END
PRINT '';

----------------------------------------------------------------------
-- VERSION TRACKING
----------------------------------------------------------------------

IF OBJECT_ID('monitor.SchemaVersion', 'U') IS NULL
BEGIN
    PRINT '! [monitor].[SchemaVersion] not found -- this install predates version tracking.';
    PRINT '  Run deploy\Install.ps1 -Mode Upgrade to stamp it.';
END
ELSE
BEGIN
    DECLARE @Installed VARCHAR(20) = [monitor].[fn_GetInstalledVersion]();
    IF @Installed IS NULL
        PRINT '! No version recorded. Run deploy\Install.ps1 -Mode Upgrade to stamp it.';
    ELSE
        PRINT 'OK  Installed version ' + @Installed;
END;

IF OBJECT_ID('monitor.AppliedMigrations', 'U') IS NULL
    PRINT '! [monitor].[AppliedMigrations] not found -- migrations cannot be tracked.';
ELSE
BEGIN
    -- A subquery is not allowed inside the PRINT concatenation, so take the
    -- count first.
    DECLARE @Migrations INT = (SELECT COUNT(*) FROM [monitor].[AppliedMigrations]);
    PRINT 'OK  Migrations applied: ' + CAST(@Migrations AS VARCHAR(10));
END;
PRINT '';

PRINT 'Validation completed at ' + CONVERT(VARCHAR, GETDATE(), 120);
GO