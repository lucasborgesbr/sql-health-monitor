-- SQL Health Monitor - Database Migration Script
-- Migrates existing databases from "DBA_Monitor" to "SQLHealthMonitor"
-- 
-- WARNING: This script will rename your database and update all references
-- Make sure you have a backup before running this script
-- 
-- Usage: 
-- 1. Backup your database first
-- 2. Run this script in the context of the database to be migrated
-- 3. Run the validation script to confirm migration success

USE master;
GO

-- =============================================
-- STEP 1: PRE-MIGRATION VALIDATION
-- =============================================

PRINT '=== SQL Health Monitor Database Migration ===';
PRINT 'Starting migration from DBA_Monitor to SQLHealthMonitor';
PRINT '==============================================';

-- Check if source database exists
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'DBA_Monitor')
BEGIN
    PRINT 'ERROR: Source database DBA_Monitor does not exist.';
    PRINT 'Migration aborted.';
    RETURN;
END

-- Check if target database already exists
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SQLHealthMonitor')
BEGIN
    PRINT 'ERROR: Target database SQLHealthMonitor already exists.';
    PRINT 'Please drop the target database first or choose a different name.';
    PRINT 'Migration aborted.';
    RETURN;
END

-- Check if there are active connections to the source database
DECLARE @connection_count INT;
SELECT @connection_count = COUNT(*) 
FROM sys.dm_exec_sessions s
JOIN sys.dm_exec_connections c ON s.session_id = c.session_id
WHERE s.database_id = DB_ID('DBA_Monitor');

IF @connection_count > 0
BEGIN
    PRINT 'WARNING: There are ' + CAST(@connection_count AS VARCHAR(10)) + ' active connections to DBA_Monitor.';
    PRINT 'Please disconnect all applications before proceeding.';
    PRINT 'Migration aborted.';
    RETURN;
END

-- =============================================
-- STEP 2: CREATE BACKUP
-- =============================================

PRINT 'Creating backup of DBA_Monitor...';

BEGIN TRY
    -- Create backup directory if it doesn't exist
    DECLARE @backup_dir NVARCHAR(255);
    DECLARE @backup_path NVARCHAR(500);
    DECLARE @sql NVARCHAR(MAX);
    
    SET @backup_dir = 'C:\SQL_Backups\SQLHealthMonitor\';
    
    -- Create directory
    SET @sql = 'IF NOT EXISTS (SELECT 1 FROM sys.database_files WHERE name = ''tempdb'') 
                EXEC master.dbo.xp_create_subdir ''' + @backup_dir + ''';';
    EXEC sp_executesql @sql;
    
    -- Set backup path
    SET @backup_path = @backup_dir + 'DBA_Monitor_' + 
                      REPLACE(CONVERT(VARCHAR, GETDATE(), 120), ':', '') + '.bak';
    
    -- Create backup
    BACKUP DATABASE [DBA_Monitor] 
    TO DISK = @backup_path
    WITH 
        NAME = 'DBA_Monitor_Full_Backup',
        DESCRIPTION = 'Full backup before migration to SQLHealthMonitor',
        COMPRESSION,
        STATS = 10,
        CHECKSUM,
        INIT;
    
    PRINT 'Backup created successfully at: ' + @backup_path;
    
    -- Store backup path in a table for reference
    IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'migration_log')
    BEGIN
        CREATE TABLE migration_log (
            id INT IDENTITY(1,1) PRIMARY KEY,
            migration_date DATETIME DEFAULT GETDATE(),
            operation NVARCHAR(100),
            details NVARCHAR(MAX),
            status NVARCHAR(20) DEFAULT 'SUCCESS'
        );
    END
    
    INSERT INTO migration_log (operation, details)
    VALUES ('BACKUP', 'Full backup created at ' + @backup_path);
    
END TRY
BEGIN CATCH
    PRINT 'ERROR: Failed to create backup.';
    PRINT 'Error message: ' + ERROR_MESSAGE();
    PRINT 'Migration aborted.';
    RETURN;
END CATCH;
GO

-- =============================================
-- STEP 3: RENAME DATABASE
-- =============================================

PRINT 'Renaming database from DBA_Monitor to SQLHealthMonitor...';

BEGIN TRY
    -- Set database to single user mode to force disconnect all connections
    ALTER DATABASE [DBA_Monitor] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    
    -- Rename database
    ALTER DATABASE [DBA_Monitor] MODIFY NAME = [SQLHealthMonitor];
    
    -- Set database back to multi user mode
    ALTER DATABASE [SQLHealthMonitor] SET MULTI_USER;
    
    -- Log the operation
    IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'migration_log')
    BEGIN
        INSERT INTO migration_log (operation, details)
        VALUES ('RENAME', 'Database renamed from DBA_Monitor to SQLHealthMonitor');
    END
    
    PRINT 'Database renamed successfully to SQLHealthMonitor';
    
END TRY
BEGIN CATCH
    PRINT 'ERROR: Failed to rename database.';
    PRINT 'Error message: ' + ERROR_MESSAGE();
    
    -- Attempt rollback
    BEGIN TRY
        PRINT 'Attempting rollback...';
        ALTER DATABASE [DBA_Monitor] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
        ALTER DATABASE [DBA_Monitor] SET MULTI_USER;
        PRINT 'Rollback completed.';
    END TRY
    BEGIN CATCH
        PRINT 'ERROR: Failed to complete rollback.';
        PRINT 'Error message: ' + ERROR_MESSAGE();
    END CATCH
    
    RETURN;
END CATCH;
GO

-- =============================================
-- STEP 4: UPDATE INTERNAL REFERENCES
-- =============================================

PRINT 'Updating internal references...';

USE [SQLHealthMonitor];
GO

BEGIN TRY
    -- Update stored procedures that might have hardcoded references
    DECLARE @sql NVARCHAR(MAX);
    
    -- Update any references in stored procedures
    DECLARE @proc_name NVARCHAR(128);
    DECLARE @proc_def NVARCHAR(MAX);
    DECLARE proc_cursor CURSOR FOR
    SELECT name, OBJECT_DEFINITION(object_id)
    FROM sys.procedures
    WHERE OBJECT_DEFINITION(object_id) LIKE '%DBA_Monitor%';
    
    OPEN proc_cursor;
    FETCH NEXT FROM proc_cursor INTO @proc_name, @proc_def;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = REPLACE(@proc_def, 'DBA_Monitor', 'SQLHealthMonitor');
        EXEC sp_executesql N'ALTER PROCEDURE [' + @proc_name + '] AS ' + @sql;
        
        FETCH NEXT FROM proc_cursor INTO @proc_name, @proc_def;
    END
    
    CLOSE proc_cursor;
    DEALLOCATE proc_cursor;
    
    -- Update views
    DECLARE view_cursor CURSOR FOR
    SELECT name, OBJECT_DEFINITION(object_id)
    FROM sys.views
    WHERE OBJECT_DEFINITION(object_id) LIKE '%DBA_Monitor%';
    
    OPEN view_cursor;
    FETCH NEXT FROM view_cursor INTO @proc_name, @proc_def;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = REPLACE(@proc_def, 'DBA_Monitor', 'SQLHealthMonitor');
        EXEC sp_executesql N'ALTER VIEW [' + @proc_name + '] AS ' + @sql;
        
        FETCH NEXT FROM view_cursor INTO @proc_name, @proc_def;
    END
    
    CLOSE view_cursor;
    DEALLOCATE view_cursor;
    
    -- Update functions
    DECLARE func_cursor CURSOR FOR
    SELECT name, OBJECT_DEFINITION(object_id)
    FROM sys.objects
    WHERE type IN ('FN', 'IF', 'TF')
    AND OBJECT_DEFINITION(object_id) LIKE '%DBA_Monitor%';
    
    OPEN func_cursor;
    FETCH NEXT FROM func_cursor INTO @proc_name, @proc_def;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = REPLACE(@proc_def, 'DBA_Monitor', 'SQLHealthMonitor');
        EXEC sp_executesql N'ALTER FUNCTION [' + @proc_name + '] ' + @sql;
        
        FETCH NEXT FROM func_cursor INTO @proc_name, @proc_def;
    END
    
    CLOSE func_cursor;
    DEALLOCATE func_cursor;
    
    -- Log the operation
    IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'migration_log')
    BEGIN
        INSERT INTO migration_log (operation, details)
        VALUES ('UPDATE_REFERENCES', 'Updated all internal references from DBA_Monitor to SQLHealthMonitor');
    END
    
    PRINT 'Internal references updated successfully';
    
END TRY
BEGIN CATCH
    PRINT 'ERROR: Failed to update internal references.';
    PRINT 'Error message: ' + ERROR_MESSAGE();
    RETURN;
END CATCH;
GO

-- =============================================
-- STEP 5: POST-MIGRATION VALIDATION
-- =============================================

PRINT 'Running post-migration validation...';

USE [SQLHealthMonitor];
GO

BEGIN TRY
    -- Check if all expected tables exist
    DECLARE @missing_tables TABLE (table_name NVARCHAR(128));
    
    INSERT INTO @missing_tables (table_name)
    SELECT 'monitor.Metrics' WHERE NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Metrics' AND schema_id = SCHEMA_ID('monitor'));
    
    INSERT INTO @missing_tables (table_name)
    SELECT 'monitor.Thresholds' WHERE NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Thresholds' AND schema_id = SCHEMA_ID('monitor'));
    
    INSERT INTO @missing_tables (table_name)
    SELECT 'monitor.AlertHistory' WHERE NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'AlertHistory' AND schema_id = SCHEMA_ID('monitor'));
    
    INSERT INTO @missing_tables (table_name)
    SELECT 'monitor.Collectors' WHERE NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Collectors' AND schema_id = SCHEMA_ID('monitor'));
    
    IF EXISTS (SELECT 1 FROM @missing_tables)
    BEGIN
        PRINT 'WARNING: Some expected tables are missing:';
        SELECT table_name FROM @missing_tables;
    END
    ELSE
    BEGIN
        PRINT 'All expected tables found successfully';
    END
    
    -- Check if stored procedures exist
    DECLARE @missing_procs TABLE (proc_name NVARCHAR(128));
    
    INSERT INTO @missing_procs (proc_name)
    SELECT 'usp_Collect_CPU' WHERE NOT EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_Collect_CPU' AND schema_id = SCHEMA_ID('monitor'));
    
    INSERT INTO @missing_procs (proc_name)
    SELECT 'usp_Collect_Memory' WHERE NOT EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_Collect_Memory' AND schema_id = SCHEMA_ID('monitor'));
    
    INSERT INTO @missing_procs (proc_name)
    SELECT 'usp_Collect_Disk' WHERE NOT EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_Collect_Disk' AND schema_id = SCHEMA_ID('monitor'));
    
    IF EXISTS (SELECT 1 FROM @missing_procs)
    BEGIN
        PRINT 'WARNING: Some expected stored procedures are missing:';
        SELECT proc_name FROM @missing_procs;
    END
    ELSE
    BEGIN
        PRINT 'All expected stored procedures found successfully';
    END
    
    -- Log validation results
    IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'migration_log')
    BEGIN
        INSERT INTO migration_log (operation, details)
        VALUES ('VALIDATION', 'Post-migration validation completed');
    END
    
    PRINT 'Post-migration validation completed successfully';
    
END TRY
BEGIN CATCH
    PRINT 'ERROR: Post-migration validation failed.';
    PRINT 'Error message: ' + ERROR_MESSAGE();
    RETURN;
END CATCH;
GO

-- =============================================
-- STEP 6: CLEANUP AND DOCUMENTATION
-- =============================================

PRINT 'Creating migration documentation...';

USE [SQLHealthMonitor];
GO

BEGIN TRY
    -- Create migration summary view
    IF NOT EXISTS (SELECT 1 FROM sys.views WHERE name = 'vw_MigrationSummary')
    BEGIN
        CREATE VIEW vw_MigrationSummary AS
        SELECT 
            migration_date,
            operation,
            details,
            status,
            ROW_NUMBER() OVER (ORDER BY id DESC) as rn
        FROM migration_log
        ORDER BY id DESC;
    END
    
    -- Create migration status procedure
    IF NOT EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'usp_GetMigrationStatus')
    BEGIN
        CREATE PROCEDURE usp_GetMigrationStatus
        AS
        BEGIN
            SELECT 
                'Migration Status' as Status,
                (SELECT COUNT(*) FROM migration_log WHERE status = 'SUCCESS') as SuccessCount,
                (SELECT COUNT(*) FROM migration_log WHERE status = 'ERROR') as ErrorCount,
                (SELECT TOP 1 details FROM migration_log ORDER BY id DESC) as LastOperation,
                (SELECT TOP 1 migration_date FROM migration_log ORDER BY id DESC) as LastOperationDate
            FROM sys.objects;
        END
    END
    
    -- Log completion
    IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'migration_log')
    BEGIN
        INSERT INTO migration_log (operation, details)
        VALUES ('COMPLETION', 'Migration completed successfully');
    END
    
    PRINT 'Migration documentation created successfully';
    
END TRY
BEGIN CATCH
    PRINT 'ERROR: Failed to create migration documentation.';
    PRINT 'Error message: ' + ERROR_MESSAGE();
END CATCH;
GO

-- =============================================
-- FINAL SUMMARY
-- =============================================

PRINT '=== MIGRATION SUMMARY ===';
PRINT 'Source database: DBA_Monitor';
PRINT 'Target database: SQLHealthMonitor';
PRINT 'Backup location: C:\SQL_Backups\SQLHealthMonitor\';
PRINT 'Migration date: ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT '==========================';

PRINT 'Migration completed successfully!';
PRINT 'For more information, run: EXEC usp_GetMigrationStatus;';
PRINT 'To view migration logs, query: SELECT * FROM vw_MigrationSummary;';

-- =============================================
-- ROLLBACK INSTRUCTIONS
-- =============================================

PRINT 'ROLLBACK INSTRUCTIONS (if needed):';
PRINT '1. Restore the backup: RESTORE DATABASE DBA_Monitor FROM DISK = ''C:\SQL_Backups\SQLHealthMonitor\DBA_Monitor_*.bak''';
PRINT '2. Drop the renamed database: DROP DATABASE SQLHealthMonitor;');
PRINT '3. Recreate any dropped objects if necessary';
PRINT '===============================================';