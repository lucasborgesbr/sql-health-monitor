/*
    SQL Health Monitor - TempDB Collector
    Collects TempDB space usage breakdown.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_TempDB]
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [monitor].[TempDbHistory]
        (TotalSizeMB, UsedSpaceMB, FreeSpaceMB, VersionStoreMB, UserObjectsMB, InternalObjectsMB)
    SELECT
        SUM(size) * 8 / 1024 AS TotalSizeMB,
        SUM(FILEPROPERTY(name, 'SpaceUsed')) * 8 / 1024 AS UsedSpaceMB,
        (SUM(size) - SUM(FILEPROPERTY(name, 'SpaceUsed'))) * 8 / 1024 AS FreeSpaceMB,
        (SELECT SUM(version_store_reserved_page_count) * 8 / 1024 
         FROM sys.dm_db_file_space_usage) AS VersionStoreMB,
        (SELECT SUM(user_object_reserved_page_count) * 8 / 1024 
         FROM sys.dm_db_file_space_usage) AS UserObjectsMB,
        (SELECT SUM(internal_object_reserved_page_count) * 8 / 1024 
         FROM sys.dm_db_file_space_usage) AS InternalObjectsMB
    FROM tempdb.sys.database_files
    WHERE type = 0;  -- Data files only
END;
GO
