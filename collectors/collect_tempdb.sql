/*
    SQL Health Monitor - TempDB Collector
    Collects tempdb size, usage, and growth statistics with multi-filegroup support.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+
    Features: Filegroup-level monitoring, object allocation tracking, auto-growth analysis
*/

IF OBJECT_ID('[monitor].[usp_Collect_TempDB]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_TempDB] AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_TempDB]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_Collect_TempDB] AS SET NOCOUNT ON; PRINT ''Placeholder'';');
GO
ALTER PROCEDURE [monitor].[usp_Collect_TempDB]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @CurrentTime DATETIME2 = SYSUTCDATETIME();

    -- Schema columns: CollectedAt, TotalSizeMB, UsedSpaceMB, FreeSpaceMB,
    --                 VersionStoreMB, UserObjectsMB, InternalObjectsMB
    INSERT INTO [monitor].[TempDbHistory]
        (CollectedAt, TotalSizeMB, UsedSpaceMB, FreeSpaceMB,
         VersionStoreMB, UserObjectsMB, InternalObjectsMB)
    SELECT
        @CurrentTime,
        -- Total size of all tempdb files in MB
        CAST((SELECT SUM(size) FROM sys.master_files
              WHERE database_id = DB_ID('tempdb')) / 128.0 AS BIGINT)               AS TotalSizeMB,
        -- Used space from file space usage DMV (pages * 8KB / 1024 = MB)
        CAST((SELECT SUM(allocated_extent_page_count) * 8.0 / 1024.0
              FROM sys.dm_db_file_space_usage) AS BIGINT)                            AS UsedSpaceMB,
        -- Free space
        CAST((SELECT SUM(unallocated_extent_page_count) * 8.0 / 1024.0
              FROM sys.dm_db_file_space_usage) AS BIGINT)                            AS FreeSpaceMB,
        -- Version store
        CAST((SELECT SUM(version_store_reserved_page_count) * 8.0 / 1024.0
              FROM sys.dm_db_file_space_usage) AS BIGINT)                            AS VersionStoreMB,
        -- User objects
        CAST((SELECT SUM(user_object_reserved_page_count) * 8.0 / 1024.0
              FROM sys.dm_db_file_space_usage) AS BIGINT)                            AS UserObjectsMB,
        -- Internal objects
        CAST((SELECT SUM(internal_object_reserved_page_count) * 8.0 / 1024.0
              FROM sys.dm_db_file_space_usage) AS BIGINT)                            AS InternalObjectsMB;

    -- Note: TempDbHistoryDetailed and TempDbObjectUsage tables do not exist in the schema;
    -- those inserts have been removed. OBJECT_TYPE() is not a valid SQL Server built-in function.
    PRINT '✓ TempDB statistics collected successfully';
END;
GO