/*
    SQL Health Monitor - Backup Status Collector
    Collects last backup dates and sizes per database.
    
    Schedule: Every 30 minutes
    Compatibility: SQL Server 2016+
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_BackupStatus]
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [monitor].[BackupHistory]
        (DatabaseName, BackupType, LastBackupDate, BackupSizeMB, CompressedSizeMB, DurationSeconds)
    SELECT
        d.name AS DatabaseName,
        bt.BackupType,
        bt.LastBackupDate,
        bt.BackupSizeMB,
        bt.CompressedSizeMB,
        bt.DurationSeconds
    FROM sys.databases d
    CROSS APPLY (
        SELECT 'D' AS BackupType UNION ALL
        SELECT 'I' UNION ALL
        SELECT 'L'
    ) types
    OUTER APPLY (
        SELECT TOP 1
            types.BackupType,
            bs.backup_finish_date AS LastBackupDate,
            bs.backup_size / 1048576 AS BackupSizeMB,
            bs.compressed_backup_size / 1048576 AS CompressedSizeMB,
            DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date) AS DurationSeconds
        FROM msdb.dbo.backupset bs
        WHERE bs.database_name = d.name
            AND bs.type = types.BackupType
        ORDER BY bs.backup_finish_date DESC
    ) bt
    WHERE d.state = 0  -- ONLINE
        AND d.name NOT IN ('tempdb')
        AND d.source_database_id IS NULL;  -- Not a snapshot
END;
GO
