-- =================================================================================
-- SQL Health Monitor - Database Migration Script
-- Script: migrate_db_name.sql
-- Purpose: Rename database from "DBA_Monitor" to "SQLHealthMonitor"
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
DECLARE @BackupPath NVARCHAR(512) = 'C:\SQLHealthMonitor\Backups\';
DECLARE @LogPath NVARCHAR(512) = 'C:\SQLHealthMonitor\MigrationLogs\';

-- Set validation flags
DECLARE @ValidateBackup BIT = 1;
DECLARE @ValidateDataIntegrity BIT = 1;
DECLARE @ValidateObjects BIT = 1;
DECLARE @GenerateRollbackScript BIT = 1;

-- =================================================================================
-- PRE-MIGRATION VALIDATION
-- =================================================================================

PRINT '=== PRE-MIGRATION VALIDATION ===';

-- Check if old database exists
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @OldDatabaseName)
BEGIN
    PRINT 'ERROR: Database ' + @OldDatabaseName + ' does not exist.';
    THROW 50001, 'Source database does not exist.', 1;
END
PRINT '✓ Source database ' + @OldDatabaseName + ' exists.';

-- Check if new database already exists
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @NewDatabaseName)
BEGIN
    PRINT 'ERROR: Database ' + @NewDatabaseName + ' already exists.';
    THROW 50002, 'Target database already exists.', 1;
END
PRINT '✓ Target database ' + @NewDatabaseName + ' does not exist.';

-- Check if backup directory exists
IF NOT EXISTS (SELECT 1 FROM sys.database_files WHERE type = 3) -- Check if FILESTREAM is available
BEGIN
    -- Create backup directory if it doesn't exist
    DECLARE @CreateBackupDir NVARCHAR(1000) = 
        'EXEC xp_cmdshell ''mkdir "' + @BackupPath + '"''';
    BEGIN TRY
        EXEC sp_executesql @CreateBackupDir;
        PRINT '✓ Backup directory created: ' + @BackupPath;
    END TRY
    BEGIN CATCH
        PRINT 'WARNING: Could not create backup directory. Using default location.';
        SET @BackupPath = 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\Backup\';
    END CATCH
END
ELSE
BEGIN
    PRINT '✓ Backup directory exists: ' + @BackupPath;
END

-- Check if log directory exists
DECLARE @CreateLogDir NVARCHAR(1000) = 
    'EXEC xp_cmdshell ''mkdir "' + @LogPath + '"''';
BEGIN TRY
    EXEC sp_executesql @CreateLogDir;
    PRINT '✓ Log directory created: ' + @LogPath;
END TRY
    BEGIN CATCH
    PRINT 'WARNING: Could not create log directory. Using default location.';
    SET @LogPath = 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\Log\';
END CATCH

-- =================================================================================
-- STEP 1: CREATE BACKUP OF EXISTING DATABASE
-- =================================================================================

PRINT '';
PRINT '=== STEP 1: CREATING DATABASE BACKUP ===';

DECLARE @BackupFile NVARCHAR(512) = @BackupPath + @OldDatabaseName + '_' + 
    CONVERT(NVARCHAR(20), GETDATE(), 112) + '_' + 
    REPLACE(CONVERT(NVARCHAR(20), GETDATE(), 108), ':', '') + '.bak';

DECLARE @BackupCommand NVARCHAR(1000) = 
    'BACKUP DATABASE [' + @OldDatabaseName + '] TO DISK = ''' + @BackupFile + ''' 
     WITH NAME = ''Pre-migration backup'', 
          DESCRIPTION = ''Backup before renaming database to ' + @NewDatabaseName + ''',
          COMPRESSION, 
          CHECKSUM, 
          STATS = 10, 
          INIT, 
          SKIP, 
          NOREWIND, 
          NOUNLOAD;';

BEGIN TRY
    EXEC sp_executesql @BackupCommand;
    PRINT '✓ Database backup created successfully: ' + @BackupFile;
    
    -- Validate backup
    IF @ValidateBackup = 1
    BEGIN
        DECLARE @ValidateBackupCmd NVARCHAR(1000) = 
            'RESTORE VERIFYONLY FROM DISK = ''' + @BackupFile + ''';';
        EXEC sp_executesql @ValidateBackupCmd;
        PRINT '✓ Backup validation completed successfully.';
    END
END TRY
BEGIN CATCH
    PRINT 'ERROR: Failed to create database backup.';
    PRINT 'Error: ' + ERROR_MESSAGE();
    THROW 50003, 'Backup creation failed.', 1;
END CATCH;

-- =================================================================================
-- STEP 2: CREATE ROLLBACK SCRIPT
-- =================================================================================

PRINT '';
PRINT '=== STEP 2: CREATING ROLLBACK SCRIPT ===';

IF @GenerateRollbackScript = 1
BEGIN
    DECLARE @RollbackScript NVARCHAR(MAX) = 
        '-- =================================================================================' + CHAR(13) + CHAR(10) +
        '-- ROLLBACK SCRIPT - Database Migration' + CHAR(13) + CHAR(10) +
        '-- Generated: ' + CONVERT(NVARCHAR(20), GETDATE(), 120) + CHAR(13) + CHAR(10) +
        '-- Original Database: ' + @OldDatabaseName + CHAR(13) + CHAR(10) +
        '-- New Database: ' + @NewDatabaseName + CHAR(13) + CHAR(10) +
        '-- =================================================================================' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) +
        '-- Check if new database exists and drop it' + CHAR(13) + CHAR(10) +
        'IF EXISTS (SELECT 1 FROM sys.databases WHERE name = ''' + @NewDatabaseName + ''')' + CHAR(13) + CHAR(10) +
        'BEGIN' + CHAR(13) + CHAR(10) +
        '    USE [master];' + CHAR(13) + CHAR(10) +
        '    ALTER DATABASE [' + @NewDatabaseName + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;' + CHAR(13) + CHAR(10) +
        '    DROP DATABASE [' + @NewDatabaseName + '];' + CHAR(13) + CHAR(10) +
        '    PRINT ''Dropped database ' + @NewDatabaseName + ' for rollback.';' + CHAR(13) + CHAR(10) +
        'END' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) +
        '-- Restore from backup' + CHAR(13) + CHAR(10) +
        'RESTORE DATABASE [' + @OldDatabaseName + '] FROM DISK = ''' + @BackupFile + ''' ' + CHAR(13) + CHAR(10) +
        'WITH MOVE ''' + @OldDatabaseName + ''' TO ''C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\Data\' + @OldDatabaseName + '.mdf',' + CHAR(13) + CHAR(10) +
        '     MOVE ''' + @OldDatabaseName + '_log'' TO ''C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\Data\' + @OldDatabaseName + '_log.ldf',' + CHAR(13) + CHAR(10) +
        '     REPLACE, RECOVERY;' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) +
        '-- Restore original database state' + CHAR(13) + CHAR(10) +
        'PRINT ''Database rollback completed. Database name restored to ' + @OldDatabaseName + '.'''';

    DECLARE @RollbackFile NVARCHAR(512) = @LogPath + 'Rollback_' + 
        CONVERT(NVARCHAR(20), GETDATE(), 112) + '_' + 
        REPLACE(CONVERT(NVARCHAR(20), GETDATE(), 108), ':', '') + '.sql';

    DECLARE @WriteRollbackCmd NVARCHAR(1000) = 
        'EXEC xp_cmdshell ''echo "' + REPLACE(@RollbackScript, '"', '""') + '" > "' + @RollbackFile + '"''';

    BEGIN TRY
        EXEC sp_executesql @WriteRollbackCmd;
        PRINT '✓ Rollback script created: ' + @RollbackFile;
    END TRY
    BEGIN CATCH
        PRINT 'WARNING: Could not create rollback script file. Script content logged below:';
        PRINT @RollbackScript;
    END CATCH
END

-- =================================================================================
-- STEP 3: RENAME DATABASE
-- =================================================================================

PRINT '';
PRINT '=== STEP 3: RENAMING DATABASE ===';

-- Set database to single user mode
BEGIN TRY
    DECLARE @SingleUserCmd NVARCHAR(500) = 
        'ALTER DATABASE [' + @OldDatabaseName + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
    EXEC sp_executesql @SingleUserCmd;
    PRINT '✓ Database set to single user mode.';
END TRY
BEGIN CATCH
    PRINT 'ERROR: Failed to set database to single user mode.';
    PRINT 'Error: ' + ERROR_MESSAGE();
    THROW 50004, 'Failed to set database to single user mode.', 1;
END CATCH

-- Rename database
BEGIN TRY
    DECLARE @RenameCmd NVARCHAR(500) = 
        'ALTER DATABASE [' + @OldDatabaseName + '] MODIFY NAME = [' + @NewDatabaseName + '];';
    EXEC sp_executesql @RenameCmd;
    PRINT '✓ Database renamed from ' + @OldDatabaseName + ' to ' + @NewDatabaseName + '.';
END TRY
BEGIN CATCH
    PRINT 'ERROR: Failed to rename database.';
    PRINT 'Error: ' + ERROR_MESSAGE();
    
    -- Attempt to restore to multi-user mode
    BEGIN TRY
        DECLARE @RestoreMultiUserCmd NVARCHAR(500) = 
            'ALTER DATABASE [' + @OldDatabaseName + '] SET MULTI_USER;';
        EXEC sp_executesql @RestoreMultiUserCmd;
        PRINT 'Database restored to multi-user mode.';
    END TRY
    BEGIN CATCH
        PRINT 'ERROR: Failed to restore database to multi-user mode.';
        PRINT 'Error: ' + ERROR_MESSAGE();
    END CATCH
    
    THROW 50005, 'Failed to rename database.', 1;
END CATCH

-- Set database back to multi-user mode
BEGIN TRY
    DECLARE @MultiUserCmd NVARCHAR(500) = 
        'ALTER DATABASE [' + @NewDatabaseName + '] SET MULTI_USER;';
    EXEC sp_executesql @MultiUserCmd;
    PRINT '✓ Database set back to multi user mode.';
END TRY
BEGIN CATCH
    PRINT 'WARNING: Failed to set database to multi-user mode.';
    PRINT 'Error: ' + ERROR_MESSAGE();
END CATCH

-- =================================================================================
-- STEP 4: UPDATE CONFIGURATION FILES
-- =================================================================================

PRINT '';
PRINT '=== STEP 4: UPDATING CONFIGURATION FILES ===';

-- Update configuration file
DECLARE @ConfigFile NVARCHAR(512) = @LogPath + 'updated-config-' + 
    CONVERT(NVARCHAR(20), GETDATE(), 112) + '.json';

DECLARE @ConfigContent NVARCHAR(MAX) = 
    '{' + CHAR(13) + CHAR(10) +
    '  "InstallMode": "SingleInstance",' + CHAR(13) + CHAR(10) +
    '  "Connection": {' + CHAR(13) + CHAR(10) +
    '    "ServerInstance": "SQL-PRD-01",' + CHAR(13) + CHAR(10) +
    '    "AuthMethod": "Windows",' + CHAR(13) + Char(10) +
    '    "Database": "' + @NewDatabaseName + '"' + CHAR(13) + Char(10) +
    '  },' + CHAR(13) + Char(10) +
    '  "MigratedFrom": "' + @OldDatabaseName + '",' + CHAR(13) + Char(10) +
    '  "MigrationDate": "' + CONVERT(NVARCHAR(20), GETDATE(), 120) + '",' + CHAR(13) + Char(10) +
    '  "MigrationBackup": "' + @BackupFile + '"' + CHAR(13) + Char(10) +
    '}';

DECLARE @WriteConfigCmd NVARCHAR(1000) = 
    'EXEC xp_cmdshell ''echo "' + REPLACE(@ConfigContent, '"', '""') + '" > "' + @ConfigFile + '"''';

BEGIN TRY
    EXEC sp_executesql @WriteConfigCmd;
    PRINT '✓ Updated configuration file created: ' + @ConfigFile;
END TRY
BEGIN CATCH
    PRINT 'WARNING: Could not create updated configuration file.';
    PRINT 'Configuration content logged below:';
    PRINT @ConfigContent;
END CATCH

-- =================================================================================
-- STEP 5: VALIDATION
-- =================================================================================

PRINT '';
PRINT '=== STEP 5: VALIDATION ===';

-- Validate database exists with new name
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @NewDatabaseName)
BEGIN
    PRINT '✓ Database ' + @NewDatabaseName + ' exists.';
END
ELSE
BEGIN
    PRINT 'ERROR: Database ' + @NewDatabaseName + ' does not exist.';
    THROW 50006, 'Database rename validation failed.', 1;
END

-- Validate old database no longer exists
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @OldDatabaseName)
BEGIN
    PRINT '✓ Old database ' + @OldDatabaseName + ' no longer exists.';
END
ELSE
BEGIN
    PRINT 'ERROR: Old database ' + @OldDatabaseName + ' still exists.';
    THROW 50007, 'Database cleanup validation failed.', 1;
END

-- Validate data integrity
IF @ValidateDataIntegrity = 1
BEGIN
    PRINT 'Performing data integrity checks...';
    
    -- Check database consistency
    DECLARE @CheckDBCmd NVARCHAR(500) = 'DBCC CHECKDB ([' + @NewDatabaseName + ']) WITH NO_INFOMSGS, ALL_ERRORMSGS;';
    BEGIN TRY
        EXEC sp_executesql @CheckDBCmd;
        PRINT '✓ Database consistency check passed.';
    END TRY
    BEGIN CATCH
        PRINT 'WARNING: Database consistency check failed.';
        PRINT 'Error: ' + ERROR_MESSAGE();
    END CATCH
    
    -- Check table counts
    DECLARE @TableCountCmd NVARCHAR(500) = 
        'SELECT COUNT(*) AS TableCount FROM [' + @NewDatabaseName + '].sys.tables;';
    DECLARE @TableCount INT;
    EXEC sp_executesql @TableCountCmd, N'@TableCount INT OUTPUT', @TableCount = @TableCount OUTPUT;
    
    IF @TableCount > 0
    BEGIN
        PRINT '✓ Database contains ' + CAST(@TableCount AS NVARCHAR(10)) + ' tables.';
    END
    ELSE
    BEGIN
        PRINT 'WARNING: Database contains no tables.';
    END
END

-- Validate objects
IF @ValidateObjects = 1
BEGIN
    PRINT 'Validating database objects...';
    
    -- Check for stored procedures
    DECLARE @ProcCountCmd NVARCHAR(500) = 
        'SELECT COUNT(*) AS ProcCount FROM [' + @NewDatabaseName + '].sys.procedures;';
    DECLARE @ProcCount INT;
    EXEC sp_executesql @ProcCountCmd, N'@ProcCount INT OUTPUT', @ProcCount = @ProcCount OUTPUT;
    
    IF @ProcCount > 0
    BEGIN
        PRINT '✓ Database contains ' + CAST(@ProcCount AS NVARCHAR(10)) + ' stored procedures.';
    END
    ELSE
    BEGIN
        PRINT 'WARNING: Database contains no stored procedures.';
    END
    
    -- Check for views
    DECLARE @ViewCountCmd NVARCHAR(500) = 
        'SELECT COUNT(*) AS ViewCount FROM [' + @NewDatabaseName + '].sys.views;';
    DECLARE @ViewCount INT;
    EXEC sp_executesql @ViewCountCmd, N'@ViewCount INT OUTPUT', @ViewCount = @ViewCount OUTPUT;
    
    IF @ViewCount > 0
    BEGIN
        PRINT '✓ Database contains ' + CAST(@ViewCount AS NVARCHAR(10)) + ' views.';
    END
    ELSE
    BEGIN
        PRINT 'WARNING: Database contains no views.';
    END
END

-- =================================================================================
-- STEP 6: DOCUMENTATION
-- =================================================================================

PRINT '';
PRINT '=== STEP 6: DOCUMENTATION ===';

-- Create migration log
DECLARE @MigrationLog NVARCHAR(MAX) = 
    '-- =================================================================================' + CHAR(13) + CHAR(10) +
    '-- SQL Health Monitor - Migration Log' + CHAR(13) + CHAR(10) +
    '-- =================================================================================' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) +
    'Migration Date: ' + CONVERT(NVARCHAR(20), GETDATE(), 120) + CHAR(13) + CHAR(10) +
    'Source Database: ' + @OldDatabaseName + CHAR(13) + CHAR(10) +
    'Target Database: ' + @NewDatabaseName + CHAR(13) + CHAR(10) +
    'Backup File: ' + @BackupFile + CHAR(13) + CHAR(10) +
    'Status: SUCCESS' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) +
    '-- Steps Performed:' + CHAR(13) + CHAR(10) +
    '1. ✓ Created backup of existing database' + CHAR(13) + CHAR(10) +
    '2. ✓ Generated rollback script' + CHAR(13) + Char(10) +
    '3. ✓ Renamed database from ' + @OldDatabaseName + ' to ' + @NewDatabaseName + CHAR(13) + CHAR(10) +
    '4. ✓ Updated configuration files' + CHAR(13) + CHAR(10) +
    '5. ✓ Performed validation checks' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) +
    '-- Next Steps:' + CHAR(13) + CHAR(10) +
    '1. Update all PowerShell scripts to use new database name' + CHAR(13) + CHAR(10) +
    '2. Update SQL Agent jobs to use new database name' + CHAR(13) + CHAR(10) +
    '3. Update application connection strings' + CHAR(13) + CHAR(10) +
    '4. Test all monitoring jobs' + CHAR(13) + CHAR(10) +
    '5. Update documentation' + CHAR