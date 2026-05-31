/*
    SQL Health Monitor - Index Health Collector
    Collects index fragmentation and usage statistics.
    
    Schedule: Every 15 minutes
    Compatibility: SQL Server 2016+
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_IndexHealth]
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [monitor].[IndexHealthHistory]
        (DatabaseName, SchemaName, TableName, IndexName, 
         IndexType, FragmentationPercent, PageCount, FillFactor, 
         LastUsedDate, LastUpdateDate)
    SELECT
        DB_NAME() AS DatabaseName,
        s.name AS SchemaName,
        t.name AS TableName,
        i.name AS IndexName,
        CASE i.type
            WHEN 0 THEN 'Heap'
            WHEN 1 THEN 'Clustered'
            WHEN 2 THEN 'NonClustered'
            WHEN 3 THEN 'XML'
            WHEN 4 THEN 'Spatial'
            WHEN 5 THEN 'Clustered Columnstore'
            WHEN 6 THEN 'NonClustered Columnstore'
            ELSE 'Unknown'
        END AS IndexType,
        ips.avg_fragmentation_in_percent AS FragmentationPercent,
        ips.page_count AS PageCount,
        i.fill_factor AS FillFactor,
        i.last_user_seek AS LastUsedDate,
        i.modify_date AS LastUpdateDate
    FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
    INNER JOIN sys.tables t ON ips.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
    WHERE ips.database_id = DB_ID()
      AND ips.avg_fragmentation_in_percent IS NOT NULL
      AND ips.page_count > 0
      AND t.is_ms_shipped = 0  -- Exclude system tables
      AND t.is_published = 0  -- Exclude replication tables
      AND t.is_schema_published = 0;
      
    -- Also collect index usage statistics
    INSERT INTO [monitor].[IndexUsageHistory]
        (DatabaseName, SchemaName, TableName, IndexName, 
         UserSeeks, UserScans, UserLookups, UserUpdates, 
         LastUserSeek, LastUserScan, LastUserLookup)
    SELECT
        DB_NAME() AS DatabaseName,
        s.name AS SchemaName,
        t.name AS TableName,
        i.name AS IndexName,
        ius.user_seeks AS UserSeeks,
        ius.user_scans AS UserScans,
        ius.user_lookups AS UserLookups,
        ius.user_updates AS UserUpdates,
        ius.last_user_seek AS LastUserSeek,
        ius.last_user_scan AS LastUserScan,
        ius.last_user_lookup AS LastUserLookup
    FROM sys.dm_db_index_usage_stats ius
    INNER JOIN sys.tables t ON ius.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.indexes i ON ius.object_id = i.object_id AND ius.index_id = i.index_id
    WHERE ius.database_id = DB_ID()
      AND t.is_ms_shipped = 0
      AND t.is_published = 0
      AND t.is_schema_published = 0;
END;
GO
