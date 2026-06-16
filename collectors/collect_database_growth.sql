/*
    SQL Health Monitor - Database Growth Collector
    Collects database size and growth trends.
    
    Schedule: Every 15 minutes
    Compatibility: SQL Server 2016+
*/

IF OBJECT_ID('[monitor].[usp_Collect_DatabaseGrowth]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_DatabaseGrowth] AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_DatabaseGrowth]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_Collect_DatabaseGrowth] AS SET NOCOUNT ON; PRINT ''Placeholder'';');
GO
ALTER PROCEDURE [monitor].[usp_Collect_DatabaseGrowth]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @CurrentTime DATETIME2 = SYSUTCDATETIME();

    -- DatabaseGrowthHistory does not exist in the schema.
    -- The closest matching table is [monitor].[FileGrowthHistory].
    -- Schema columns: CollectedAt, DatabaseName, FileName, FileType,
    --                 SizeMB, UsedMB, GrowthMB

    -- Collect data file sizes per database file; GrowthMB is a delta computed in reporting.
    INSERT INTO [monitor].[FileGrowthHistory]
        (CollectedAt, DatabaseName, FileName, FileType, SizeMB, UsedMB, GrowthMB)
    SELECT
        @CurrentTime,
        d.name                                                         AS DatabaseName,
        mf.name                                                        AS FileName,
        CASE mf.type WHEN 0 THEN 'ROWS' WHEN 1 THEN 'LOG' ELSE 'OTHER' END AS FileType,
        CAST(mf.size / 128.0 AS BIGINT)                               AS SizeMB,
        -- Used space: pages used from virtual file stats (bytes -> MB)
        CAST(ISNULL(vfs.size_on_disk_bytes, 0) / 1024.0 / 1024.0 AS BIGINT) AS UsedMB,
        -- Delta from previous collection is calculated in the reporting layer
        NULL                                                           AS GrowthMB
    FROM sys.master_files mf
    INNER JOIN sys.databases d ON d.database_id = mf.database_id
    LEFT JOIN sys.dm_io_virtual_file_stats(NULL, NULL) vfs
        ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
    WHERE mf.database_id > 4   -- Exclude system databases
      AND d.state_desc = 'ONLINE';

    -- Note: DatabaseGrowthHistory table does not exist in the schema.
    -- sys.databases does not have data_space_id; FILEGROUPPROPERTY() takes a name, not an int.
    -- The original queries against those have been replaced with FileGrowthHistory inserts.
END;
GO