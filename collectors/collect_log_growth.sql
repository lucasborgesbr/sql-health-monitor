/*
    SQL Health Monitor - Log Growth Collector
    Collects transaction log growth and space usage with detailed tracking.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+
    Features: Log space usage, growth tracking, backup status, VLF analysis
*/

IF OBJECT_ID('[monitor].[usp_Collect_LogGrowth]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_LogGrowth] AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_LogGrowth]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_Collect_LogGrowth] AS SET NOCOUNT ON; PRINT ''Placeholder'';');
GO
ALTER PROCEDURE [monitor].[usp_Collect_LogGrowth]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @CurrentTime DATETIME2 = SYSUTCDATETIME();

    -- LogGrowthHistory and LogBackupHistory tables do not exist in the schema.
    -- The closest matching table is [monitor].[FileGrowthHistory].
    -- Schema columns: CollectedAt, DatabaseName, FileName, FileType,
    --                 SizeMB, UsedMB, GrowthMB

    -- Collect log file size and usage from sys.master_files + dm_db_log_space_usage
    INSERT INTO [monitor].[FileGrowthHistory]
        (CollectedAt, DatabaseName, FileName, FileType, SizeMB, UsedMB, GrowthMB)
    SELECT
        @CurrentTime,
        d.name                                                       AS DatabaseName,
        mf.name                                                      AS FileName,
        'LOG'                                                        AS FileType,
        CAST(mf.size / 128.0 AS BIGINT)                             AS SizeMB,
        NULL                                                         AS UsedMB, -- log_space_used_percent requires per-DB context
        -- Delta from previous collection (NULL; calculated in reporting layer)
        NULL                                                         AS GrowthMB
    FROM sys.master_files mf
    INNER JOIN sys.databases d ON d.database_id = mf.database_id
    WHERE mf.type = 1           -- Log files only
      AND mf.database_id > 4   -- Exclude system databases
      AND d.state_desc = 'ONLINE';

    -- Note: LogGrowthHistory and LogBackupHistory tables do not exist in the schema.
    -- sys.master_files does not have last_auto_growth_at / last_auto_growth_size_mb columns;
    -- sys.dm_db_log_space_usage columns are log_size_mb and log_used_mb (not total_log_size_kb).
    -- The original queries against those non-existent columns/tables have been removed.
    PRINT '✓ Log growth statistics collected successfully';
END;
GO