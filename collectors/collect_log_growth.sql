/*
    SQL Health Monitor - Log Growth Collector
    Collects transaction log growth and space usage with detailed tracking.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+
    Features: Log space usage, growth tracking, backup status, VLF analysis
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_LogGrowth]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @CurrentTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @CriticalThreshold DECIMAL(5,2) = 90.0;  -- 90% usage
    DECLARE @WarningThreshold DECIMAL(5,2) = 80.0;   -- 80% usage
    
    -- Get current log space usage
    INSERT INTO [monitor].[LogGrowthHistory]
        (CollectedAt, DatabaseName, LogSizeMB, LogUsedPct, LogFreePct,
         LastBackupSizeMB, LastBackupDate, GrowthRateMBPerHour,
         AutoGrowthCount, LastAutoGrowthAt, LastAutoGrowthSizeMB,
         VLFCount, MinVLFSizeMB, MaxVLFSizeMB, AvgVLFSizeMB,
         LastTruncationDate, LogTruncationLagMinutes,
         IsLogShipping, IsInStandby, IsCritical, IsWarning)
    SELECT
        @CurrentTime,
        d.name AS DatabaseName,
        CAST(l.total_log_size_kb / 1024.0 AS BIGINT) AS LogSizeMB,
        l.log_space_used_percent AS LogUsedPct,
        (100.0 - l.log_space_used_percent) AS LogFreePct,
        
        -- Backup information
        b.backup_size_mb,
        b.backup_date,
        
        -- Calculate growth rate (MB per hour)
        CASE WHEN b.backup_date IS NOT NULL AND DATEDIFF(HOUR, b.backup_date, @CurrentTime) > 0
             THEN (CAST(l.total_log_size_kb / 1024.0 AS BIGINT) - b.backup_size_mb) / 
                  DATEDIFF(HOUR, b.backup_date, @CurrentTime)
             ELSE NULL END AS GrowthRateMBPerHour,
        
        -- Auto-growth tracking
        ag.auto_growth_count,
        ag.last_auto_growth_at,
        ag.last_auto_growth_size_mb,
        
        -- VLF analysis
        vlf.vlf_count,
        vlf.min_vlf_size_mb,
        vlf.max_vlf_size_mb,
        vlf.avg_vlf_size_mb,
        
        -- Truncation info
        t.last_truncation_date,
        CASE WHEN t.last_truncation_date IS NOT NULL AND l.log_space_used_percent < 95.0
             THEN DATEDIFF(MINUTE, t.last_truncation_date, @CurrentTime)
             ELSE NULL END AS LogTruncationLagMinutes,
        
        -- Database status
        CASE WHEN d.is_in_standby = 1 THEN 1 ELSE 0 END AS IsInStandby,
        CASE WHEN d.is_in_standby = 0 AND d.is_read_only = 0 AND d.state_desc = 'ONLINE' 
             THEN 1 ELSE 0 END AS IsLogShipping,
        
        -- Health indicators
        CASE WHEN l.log_space_used_percent >= @CriticalThreshold THEN 1 ELSE 0 END AS IsCritical,
        CASE WHEN l.log_space_used_percent >= @WarningThreshold AND l.log_space_used_percent < @CriticalThreshold THEN 1 ELSE 0 END AS IsWarning
    FROM sys.databases d
    LEFT JOIN sys.dm_db_log_space_usage l ON d.database_id = l.database_id
    LEFT JOIN (
        -- Get last backup info
        SELECT DISTINCT
            b.database_id,
            MAX(b.backup_size) / 1024.0 AS backup_size_mb,
            MAX(b.backup_finish_date) AS backup_date
        FROM msdb.dbo.backupset b
        WHERE b.type = 'L'  -- Log backups
        GROUP BY b.database_id
    ) b ON d.database_id = b.database_id
    LEFT JOIN (
        -- Auto-growth tracking
        SELECT
            mf.database_id,
            COUNT(*) AS auto_growth_count,
            MAX(mf.last_auto_growth_at) AS last_auto_growth_at,
            MAX(mf.last_auto_growth_size_mb) AS last_auto_growth_size_mb
        FROM sys.master_files mf
        WHERE mf.last_auto_growth_at IS NOT NULL
        GROUP BY mf.database_id
    ) ag ON d.database_id = ag.database_id
    LEFT JOIN (
        -- VLF analysis
        SELECT
            db.database_id,
            COUNT(*) AS vlf_count,
            MIN(size_mb) AS min_vlf_size_mb,
            MAX(size_mb) AS max_vlf_size_mb,
            AVG(size_mb) AS avg_vlf_size_mb
        FROM (
            -- Estimate VLF count and sizes (requires sys.database_files with log files)
            SELECT
                mf.database_id,
                mf.size / 128.0 AS size_mb
            FROM sys.master_files mf
            WHERE mf.type = 1  -- Log files
        ) db
        GROUP BY db.database_id
    ) vlf ON d.database_id = vlf.database_id
    LEFT JOIN (
        -- Last truncation date (approximate)
        SELECT
            b.database_id,
            MAX(b.backup_finish_date) AS last_truncation_date
        FROM msdb.dbo.backupset b
        WHERE b.type = 'L'  -- Log backups
        GROUP BY b.database_id
    ) t ON d.database_id = t.database_id
    WHERE d.database_id > 4  -- Exclude system databases
      AND d.state_desc = 'ONLINE';
    
    -- Log backup history
    INSERT INTO [monitor].[LogBackupHistory]
        (CollectedAt, DatabaseName, BackupStartDate, BackupEndDate, BackupDurationSec,
         BackupSizeMB, CompressedSizeMB, CompressionRatio, BackupDevice,
         BackupSetId, IsSuccessful, ErrorMessage)
    SELECT
        @CurrentTime,
        DB_NAME(b.database_id) AS DatabaseName,
        b.backup_start_date,
        b.backup_finish_date,
        DATEDIFF(SECOND, b.backup_start_date, b.backup_finish_date) AS BackupDurationSec,
        b.backup_size / 1024.0 AS BackupSizeMB,
        b.compressed_backup_size / 1024.0 AS CompressedSizeMB,
        CASE WHEN b.backup_size > 0 
             THEN (b.backup_size - b.compressed_backup_size) * 100.0 / b.backup_size
             ELSE 0 END AS CompressionRatio,
        mf.physical_name AS BackupDevice,
        b.backup_set_id,
        1 AS IsSuccessful,  -- Assuming successful unless error
        NULL AS ErrorMessage
    FROM msdb.dbo.backupset b
    JOIN sys.master_files mf ON b.media_set_id = mf.media_set_id
    WHERE b.type = 'L'  -- Log backups
      AND b.backup_finish_date >= DATEADD(MINUTE, -5, @CurrentTime)  -- Last 5 minutes
      AND b.database_id > 4  -- Exclude system databases;
    
    PRINT '✓ Log growth statistics collected successfully';
END;
GO
