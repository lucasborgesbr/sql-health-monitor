/*
    SQL Health Monitor - Backup Status Collector
    Collects backup history, last backup dates, and backup types.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+
*/

IF OBJECT_ID('[monitor].[usp_Collect_BackupStatus]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_BackupStatus] AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_BackupStatus]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_Collect_BackupStatus] AS SET NOCOUNT ON; PRINT ''Placeholder'';');
GO
ALTER PROCEDURE [monitor].[usp_Collect_BackupStatus]
AS
BEGIN
    SET NOCOUNT ON;

    -- Schema columns: CollectedAt, DatabaseName, BackupType (CHAR(1): D/I/L),
    --                 LastBackupDate, BackupSizeMB, CompressedSizeMB, DurationSeconds
    -- One row per database per backup type (D, I, L)
    INSERT INTO [monitor].[BackupHistory]
        (DatabaseName, BackupType, LastBackupDate, BackupSizeMB, CompressedSizeMB, DurationSeconds)
    SELECT
        d.name                                                          AS DatabaseName,
        b.type                                                          AS BackupType,
        CONVERT(DATETIME2, b.backup_finish_date)                       AS LastBackupDate,
        CAST(b.backup_size / 1024.0 / 1024.0 AS BIGINT)               AS BackupSizeMB,
        CAST(b.compressed_backup_size / 1024.0 / 1024.0 AS BIGINT)    AS CompressedSizeMB,
        DATEDIFF(SECOND, b.backup_start_date, b.backup_finish_date)    AS DurationSeconds
    FROM sys.databases d
    CROSS APPLY (
        SELECT TOP 1 bs.type, bs.backup_finish_date, bs.backup_start_date,
                     bs.backup_size, bs.compressed_backup_size
        FROM msdb.dbo.backupset bs
        WHERE bs.database_name = d.name
          AND bs.type IN ('D', 'I', 'L')
          AND bs.is_copy_only = 0
          AND bs.server_name = @@SERVERNAME
        ORDER BY bs.backup_finish_date DESC
    ) b
    WHERE d.database_id > 4
      AND d.state_desc = 'ONLINE';
END;
GO