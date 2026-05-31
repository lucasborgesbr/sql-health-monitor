-- =================================================================================
-- SQL Health Monitor - Post-Migration Validation Script
-- Script: validate_migration.sql
-- Purpose: Validate the database migration from "DBA_Monitor" to "SQLHealthMonitor"
-- Author: Lucas Allan Borges
-- Version: 1.0.0
-- Date: 2026-05-31
-- =================================================================================

-- =================================================================================
-- CONFIGURATION SECTION
-- =================================================================================

-- Set database names
DECLARE @OldDatabaseName NVARCHAR(128) = 'DBA_Monitor';
DECLARE @NewDatabaseName NVARCHAR(128) = 'SQLHealthMonitor';
DECLARE @LogPath NVARCHAR(512) = 'C:\SQLHealthMonitor\MigrationLogs\';

-- =================================================================================
-- VALIDATION CHECKS
-- =================================================================================

PRINT '=== SQL HEALTH MONITOR - MIGRATION VALIDATION ===';
PRINT 'Date: ' + CONVERT(NVARCHAR(20), GETDATE(), 120);
PRINT '';

-- =================================================================================
-- SECTION 1: DATABASE EXISTENCE CHECKS
-- =================================================================================

PRINT '=== SECTION 1: DATABASE EXISTENCE CHECKS ===';

-- Check if new database exists
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @NewDatabaseName)
BEGIN
    PRINT '✓ SUCCESS: Database ' + @NewDatabaseName + ' exists.';
END
ELSE
BEGIN
    PRINT '✗ ERROR: Database ' + @NewDatabaseName + ' does not exist.';
    SET @ErrorMessage = 'Target database not found.';
END

-- Check if old database no longer exists
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @OldDatabaseName)
BEGIN
    PRINT '✓ SUCCESS: Old database ' + @OldDatabaseName + ' no longer exists.';
END
ELSE
BEGIN
    PRINT '✗ ERROR: Old database ' + @OldDatabaseName + ' still exists.';
    SET @ErrorMessage = 'Source database still exists.';
END

PRINT '';

-- =================================================================================
-- SECTION 2: DATABASE PROPERTIES CHECK
-- =================================================================================

PRINT '=== SECTION 2: DATABASE PROPERTIES CHECK ===';

-- Check database state
DECLARE @DatabaseState NVARCHAR(128);
SELECT @DatabaseState = state_desc FROM sys.databases WHERE name = @NewDatabaseName;

IF @DatabaseState = 'ONLINE'
BEGIN
    PRINT '✓ SUCCESS: Database ' + @NewDatabaseName + ' is ONLINE.';
END
ELSE
BEGIN
    PRINT '✗ WARNING: Database ' + @NewDatabaseName + ' state is ' + @DatabaseState + '.';
END

-- Check recovery model
DECLARE @RecoveryModel NVARCHAR(128);
SELECT @RecoveryModel = recovery_model_desc FROM sys.databases WHERE name = @NewDatabaseName;

IF @RecoveryModel = 'SIMPLE'
BEGIN
    PRINT '✓ SUCCESS: Database ' + @NewDatabaseName + ' has SIMPLE recovery model.';
END
ELSE
BEGIN
    PRINT '⚠ INFO: Database ' + @NewDatabaseName + ' has ' + @RecoveryModel + ' recovery model.';
END

-- Check compatibility level
DECLARE @CompatibilityLevel INT;
SELECT @CompatibilityLevel = compatibility_level FROM sys.databases WHERE name = @NewDatabaseName;

PRINT 'INFO: Database ' + @NewDatabaseName + ' compatibility level: ' + CAST(@CompatibilityLevel AS NVARCHAR(10));

PRINT '';

-- =================================================================================
-- SECTION 3: OBJECT VALIDATION
-- =================================================================================

PRINT '=== SECTION 3: OBJECT VALIDATION ===';

-- Check tables
DECLARE @TableCount INT;
SELECT @TableCount = COUNT(*) FROM sys.tables WHERE type = 'U';

IF @TableCount > 0
BEGIN
    PRINT '✓ SUCCESS: Database contains ' + CAST(@TableCount AS NVARCHAR(10)) + ' tables.';
    
    -- List system tables
    DECLARE @SystemTableCount INT;
    SELECT @SystemTableCount = COUNT(*) FROM sys.tables WHERE type = 'U' AND is_ms_shipped = 1;
    
    -- List user tables
    DECLARE @UserTableCount INT;
    SELECT @UserTableCount = COUNT(*) FROM sys.tables WHERE type = 'U' AND is_ms_shipped = 0;
    
    PRINT '  - System tables: ' + CAST(@SystemTableCount AS NVARCHAR(10));
    PRINT '  - User tables: ' + CAST(@UserTableCount AS NVARCHAR(10));
END
ELSE
BEGIN
    PRINT '✗ ERROR: Database contains no tables.';
END

-- Check views
DECLARE @ViewCount INT;
SELECT @ViewCount = COUNT(*) FROM sys.views;

IF @ViewCount > 0
BEGIN
    PRINT '✓ SUCCESS: Database contains ' + CAST(@ViewCount AS NVARCHAR(10)) + ' views.';
END
ELSE
BEGIN
    PRINT '⚠ INFO: Database contains no views.';
END

-- Check stored procedures
DECLARE @ProcCount INT;
SELECT @ProcCount = COUNT(*) FROM sys.procedures;

IF @ProcCount > 0
BEGIN
    PRINT '✓ SUCCESS: Database contains ' + CAST(@ProcCount AS NVARCHAR(10)) + ' stored procedures.';
END
ELSE
BEGIN
    PRINT '⚠ INFO: Database contains no stored procedures.';
END

-- Check functions
DECLARE @FunctionCount INT;
SELECT @FunctionCount = COUNT(*) FROM sys.objects WHERE type IN ('FN', 'IF', 'TF', 'FS', 'FT');

IF @FunctionCount > 0
BEGIN
    PRINT '✓ SUCCESS: Database contains ' + CAST(@FunctionCount AS NVARCHAR(10)) + ' functions.';
END
ELSE
BEGIN
    PRINT '⚠ INFO: Database contains no functions.';
END

PRINT '';

-- =================================================================================
-- SECTION 4: DATA INTEGRITY CHECKS
-- =================================================================================

PRINT '=== SECTION 4: DATA INTEGRITY CHECKS ===';

-- Check database consistency
BEGIN TRY
    DECLARE @CheckDBCmd NVARCHAR(500) = 'DBCC CHECKDB ([' + @NewDatabaseName + ']) WITH NO_INFOMSGS, ALL_ERRORMSGS;';
    EXEC sp_executesql @CheckDBCmd;
    PRINT '✓ SUCCESS: Database consistency check passed.';
END TRY
BEGIN CATCH
    PRINT '✗ ERROR: Database consistency check failed.';
    PRINT 'Error: ' + ERROR_MESSAGE();
END CATCH

-- Check allocation units
BEGIN TRY
    DECLARE @CheckAllocCmd NVARCHAR(500) = 'DBCC CHECKALLOC ([' + @NewDatabaseName + ']) WITH NO_INFOMSGS;';
    EXEC sp_executesql @CheckAllocCmd;
    PRINT '✓ SUCCESS: Database allocation check passed.';
END TRY
BEGIN CATCH
    PRINT '⚠ WARNING: Database allocation check failed.';
    PRINT 'Error: ' + ERROR_MESSAGE();
END CATCH

PRINT '';

-- =================================================================================
-- SECTION 5: SCHEMA VALIDATION
-- =================================================================================

PRINT '=== SECTION 5: SCHEMA VALIDATION ===';

-- Check for expected schemas
DECLARE @SchemaCount INT;
SELECT @SchemaCount = COUNT(*) FROM sys.schemas WHERE name NOT IN ('dbo', 'sys', 'guest', 'INFORMATION_SCHEMA', 'db_owner');

IF @SchemaCount > 0
BEGIN
    PRINT '✓ SUCCESS: Database contains ' + CAST(@SchemaCount AS NVARCHAR(10)) + ' custom schemas.';
    
    -- List custom schemas
    DECLARE SchemaCursor CURSOR FOR
    SELECT name FROM sys.schemas WHERE name NOT IN ('dbo', 'sys', 'guest', 'INFORMATION_SCHEMA', 'db_owner');
    
    DECLARE @SchemaName NVARCHAR(128);
    OPEN SchemaCursor;
    FETCH NEXT FROM SchemaCursor INTO @SchemaName;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        PRINT '  - Schema: ' + @SchemaName;
        FETCH NEXT FROM SchemaCursor INTO @SchemaName;
    END
    
    CLOSE SchemaCursor;
    DEALLOCATE SchemaCursor;
END
ELSE
BEGIN
    PRINT '⚠ INFO: Database contains no custom schemas (only standard schemas).';
END

-- Check for expected table names
DECLARE @ExpectedTables TABLE (TableName NVARCHAR(128));
INSERT INTO @ExpectedTables VALUES ('Configurations'), ('Alerts'), ('Servers'), ('Jobs'), ('Errors');

DECLARE @FoundTableCount INT = 0;
DECLARE ExpectedTableCursor CURSOR FOR
SELECT TableName FROM @ExpectedTables;

DECLARE @ExpectedTableName NVARCHAR(128);
OPEN ExpectedTableCursor;
FETCH NEXT FROM ExpectedTableCursor INTO @ExpectedTableName;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT 1 FROM sys.tables WHERE name = @ExpectedTableName)
    BEGIN
        PRINT '✓ SUCCESS: Found expected table: ' + @ExpectedTableName;
        SET @FoundTableCount = @FoundTableCount + 1;
    END
    ELSE
    BEGIN
        PRINT '⚠ INFO: Table not found: ' + @ExpectedTableName;
    END
    
    FETCH NEXT FROM ExpectedTableCursor INTO @ExpectedTableName;
END

CLOSE ExpectedTableCursor;
DEALLOCATE ExpectedTableCursor;

PRINT 'Found ' + CAST(@FoundTableCount AS NVARCHAR(10)) + ' out of ' + 
      CAST((SELECT COUNT(*) FROM @ExpectedTables) AS NVARCHAR(10)) + ' expected tables.';

PRINT '';

-- =================================================================================
-- SECTION 6: USER PERMISSIONS CHECK
-- =================================================================================

PRINT '=== SECTION 6: USER PERMISSIONS CHECK ===';

-- Check database users
DECLARE @UserCount INT;
SELECT @UserCount = COUNT(*) FROM sys.database_principals WHERE type IN ('S', 'U') AND name NOT IN ('dbo', 'guest', 'sys', 'INFORMATION_SCHEMA');

IF @UserCount > 0
BEGIN
    PRINT '✓ SUCCESS: Database contains ' + CAST(@UserCount AS NVARCHAR(10)) + ' users.';
    
    -- List users
    DECLARE UserCursor CURSOR FOR
    SELECT name, type_desc FROM sys.database_principals 
    WHERE type IN ('S', 'U') AND name NOT IN ('dbo', 'guest', 'sys', 'INFORMATION_SCHEMA');
    
    DECLARE @UserName NVARCHAR(128), @UserType NVARCHAR(128);
    OPEN UserCursor;
    FETCH NEXT FROM UserCursor INTO @UserName, @UserType;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        PRINT '  - User: ' + @UserName + ' (' + @UserType + ')';
        FETCH NEXT FROM UserCursor INTO @UserName, @UserType;
    END
    
    CLOSE UserCursor;
    DEALLOCATE UserCursor;
END
ELSE
BEGIN
    PRINT '⚠ INFO: Database contains no custom users.';
END

-- Check role membership
DECLARE @RoleCount INT;
SELECT @RoleCount = COUNT(*) FROM sys.database_principals WHERE type = 'R';

IF @RoleCount > 0
BEGIN
    PRINT '✓ SUCCESS: Database contains ' + CAST(@RoleCount AS NVARCHAR(10)) + ' roles.';
END
ELSE
BEGIN
    PRINT '⚠ INFO: Database contains no custom roles.';
END

PRINT '';

-- =================================================================================
-- SECTION 7: PERFORMANCE METRICS
-- =================================================================================

PRINT '=== SECTION 7: PERFORMANCE METRICS ===';

-- Check database size
DECLARE @DatabaseSizeMB DECIMAL(10,2);
SELECT @DatabaseSizeMB = SUM(size * 8.0 / 1024) 
FROM sys.master_files 
WHERE database_id = DB_ID(@NewDatabaseName);

PRINT 'INFO: Database size: ' + CAST(@DatabaseSizeMB AS NVARCHAR(10)) + ' MB';

-- Check file count
DECLARE @FileCount INT;
SELECT @FileCount = COUNT(*) FROM sys.master_files WHERE database_id = DB_ID(@NewDatabaseName);

PRINT 'INFO: Database file count: ' + CAST(@FileCount AS NVARCHAR(10));

-- Check last backup (if any)
DECLARE @LastBackup DATETIME;
SELECT @LastBackup = MAX(backup_finish_date) 
FROM msdb.dbo.backupset 
WHERE database_name = @NewDatabaseName;

IF @LastBackup IS NOT NULL
BEGIN
    PRINT 'INFO: Last backup: ' + CONVERT(NVARCHAR(20), @LastBackup, 120);
END
ELSE
BEGIN
    PRINT '⚠ WARNING: No backup found in msdb.';
END

PRINT '';

-- =================================================================================
-- SECTION 8: MIGRATION SPECIFIC CHECKS
-- =================================================================================

PRINT '=== SECTION 8: MIGRATION SPECIFIC CHECKS ===';

-- Check for migration-related objects
DECLARE @MigrationObjects INT;
SELECT @MigrationObjects = COUNT(*) 
FROM sys.objects 
WHERE name LIKE '%Migration%' OR name LIKE '%migrate%' OR name LIKE '%backup%';

IF @MigrationObjects > 0
BEGIN
    PRINT '✓ INFO: Found ' + CAST(@MigrationObjects AS NVARCHAR(10)) + ' migration-related objects.';
END
ELSE
BEGIN
    PRINT '⚠ INFO: No migration-specific objects found.';
END

-- Check for configuration updates
DECLARE @ConfigCheckCmd NVARCHAR(500) = 
    'IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(''dbo.Configurations'') AND name = ''MigratedFrom'')
     BEGIN PRINT ''✓ SUCCESS: Migration tracking column found.'' END
     ELSE
     BEGIN PRINT ''⚠ INFO: Migration tracking column not found.'' END';

BEGIN TRY
    EXEC sp_executesql @ConfigCheckCmd;
END TRY
BEGIN CATCH
    PRINT '⚠ INFO: Could not check migration tracking (Configurations table may not exist).';
END CATCH

PRINT '';

-- =================================================================================
-- SUMMARY
-- =================================================================================

PRINT '=== MIGRATION VALIDATION SUMMARY ===';
PRINT 'Date: ' + CONVERT(NVARCHAR(20), GETDATE(), 120);
PRINT '';

-- Calculate overall status
DECLARE @ErrorCount INT = 0;
DECLARE @WarningCount INT = 0;
DECLARE @SuccessCount INT = 0;

-- Count errors (simplified logic)
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @NewDatabaseName) SET @ErrorCount = @ErrorCount + 1;
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @OldDatabaseName) SET @ErrorCount = @ErrorCount + 1;

-- Count warnings
IF @TableCount = 0 SET @WarningCount = @WarningCount + 1;
IF @ProcCount = 0 SET @WarningCount = @WarningCount + 1;
IF @ViewCount = 0 SET @WarningCount = @WarningCount + 1;

-- Count successes
IF @DatabaseState = 'ONLINE' SET @SuccessCount = @SuccessCount + 1;
IF @RecoveryModel = 'SIMPLE' SET @SuccessCount = @SuccessCount + 1;
IF @TableCount > 0 SET @SuccessCount = @SuccessCount + 1;

PRINT 'Results:';
PRINT '  - Errors: ' + CAST(@ErrorCount AS NVARCHAR(10));
PRINT '  - Warnings: ' + CAST(@WarningCount AS NVARCHAR(10));
PRINT '  - Successes: ' + CAST(@SuccessCount AS NVARCHAR(10));

-- Determine overall status
IF @ErrorCount = 0
BEGIN
    IF @WarningCount = 0
    BEGIN
        PRINT '';
        PRINT '🎉 MIGRATION STATUS: SUCCESS - All checks passed!';
    END
    ELSE
    BEGIN
        PRINT '';
        PRINT '⚠️ MIGRATION STATUS: WARNING - Migration completed with some non-critical issues.';
        PRINT 'Review the warnings above and take appropriate action if needed.';
    END
END
ELSE
BEGIN
    PRINT '';
    PRINT '❌ MIGRATION STATUS: FAILED - Critical errors detected.';
    PRINT 'Do not proceed with deployment until all errors are resolved.';
END

PRINT '';
PRINT '=== VALIDATION COMPLETE ===';

-- Return exit code for automation
IF @ErrorCount > 0
BEGIN
    RETURN 1; -- Failure
END
ELSE IF @WarningCount > 0
BEGIN
    RETURN 2; -- Warning
END
ELSE
BEGIN
    RETURN 0; -- Success
END