/*
    SQL Health Monitor - Index Health Collector
    Collects index fragmentation and usage statistics.
    
    Schedule: Every 15 minutes
    Compatibility: SQL Server 2016+
*/

IF OBJECT_ID('[monitor].[usp_Collect_IndexHealth]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_IndexHealth] AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_IndexHealth]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_Collect_IndexHealth] AS SET NOCOUNT ON; PRINT ''Placeholder'';');
GO
ALTER PROCEDURE [monitor].[usp_Collect_IndexHealth]
AS
BEGIN
    SET NOCOUNT ON;

    -- Schema columns: CollectedAt, DatabaseName, SchemaName, TableName, IndexName,
    --                 IndexType, FragmentationPct, PageCount,
    --                 UserSeeks, UserScans, UserLookups, UserUpdates
    INSERT INTO [monitor].[IndexHealthHistory]
        (DatabaseName, SchemaName, TableName, IndexName,
         IndexType, FragmentationPct, PageCount,
         UserSeeks, UserScans, UserLookups, UserUpdates)
    SELECT
        DB_NAME()       AS DatabaseName,
        s.name          AS SchemaName,
        t.name          AS TableName,
        i.name          AS IndexName,
        CASE i.type
            WHEN 0 THEN 'Heap'
            WHEN 1 THEN 'Clustered'
            WHEN 2 THEN 'NonClustered'
            WHEN 3 THEN 'XML'
            WHEN 4 THEN 'Spatial'
            WHEN 5 THEN 'Clustered Columnstore'
            WHEN 6 THEN 'NonClustered Columnstore'
            ELSE 'Unknown'
        END             AS IndexType,
        CAST(ips.avg_fragmentation_in_percent AS DECIMAL(5,2)) AS FragmentationPct,
        ips.page_count  AS PageCount,
        ius.user_seeks  AS UserSeeks,
        ius.user_scans  AS UserScans,
        ius.user_lookups AS UserLookups,
        ius.user_updates AS UserUpdates
    FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
    INNER JOIN sys.tables t  ON ips.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
    LEFT JOIN sys.dm_db_index_usage_stats ius
        ON ius.object_id = ips.object_id
       AND ius.index_id  = ips.index_id
       AND ius.database_id = DB_ID()
    WHERE ips.database_id = DB_ID()
      AND ips.avg_fragmentation_in_percent IS NOT NULL
      AND ips.page_count > 0
      AND t.is_ms_shipped = 0
      AND t.is_published = 0
      AND t.is_schema_published = 0;

    -- Note: IndexUsageHistory table does not exist in the schema; that insert has been removed.
END;
GO