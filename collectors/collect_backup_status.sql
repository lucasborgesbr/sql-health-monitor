/*
    SQL Health Monitor - Backup Status Collector
    Collects backup history, last backup dates, and backup types.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_BackupStatus]
AS
BEGIN
    SET NOCOUNT ON;

    -- Get last backup for each database
    INSERT INTO [monitor].[BackupStatus]
        (DatabaseName, BackupType, LastBackupDate, BackupSizeMB, BackupDurationMinutes)
    SELECT
        d.name AS DatabaseName,
        CASE b.type
            WHEN 'D' THEN 'Full'
            WHEN 'I' THEN 'Differential'
            WHEN 'L' THEN 'Log'
            WHEN 'F' THEN 'File'
            ELSE 'Unknown'
        END AS BackupType,
        CASE WHEN b.backup_finish_date > 0 THEN
            CONVERT(DATETIME2, b.backup_finish_date)
        END AS LastBackupDate,
        CASE WHEN b.backup_size > 0 THEN
            CAST(b.backup_size / 1024.0 / 1024.0 AS DECIMAL(10, 2))
        END AS BackupSizeMB,
        CASE WHEN b.backup_finish_date > b.backup_start_date AND b.backup_finish_date > 0 THEN
            DATEDIFF(MINUTE, b.backup_start_date, b.backup_finish_date)
        END AS BackupDurationMinutes
    FROM sys.databases d
    LEFT JOIN msdb.dbo.backupset b ON b.database_name = d.name
        AND b.type IN ('D', 'I', 'L', 'F')
        AND b.type <> 'D'  -- Exclude differential backups that don't have backupset row
        AND b.is_differential = 0
        AND b.is_copy_only = 0
        AND b.server_name = @@SERVERNAME
        AND b.backup_finish_date = (
            SELECT MAX(b2.backup_finish_date)
            FROM msdb.dbo.backupset b2
            WHERE b2.database_name = d.name
              AND b2.type IN ('D', 'I', 'L', 'F')
              AND b2.type <> 'D'
              AND b2.is_differential = 0
              AND b2.is_copy_only = 0
              AND b2.server_name = @@SERVERNAME
        )
    WHERE d.database_id > 4  -- Exclude system databases
      AND d.state_desc = 'ONLINE';
END;
GO
