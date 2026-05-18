/*
    SQL Health Monitor - Index Health Collector
    Collects index fragmentation and usage stats.
    
    Schedule: Daily (low activity window)
    Compatibility: SQL Server 2016+
    Note: Can be resource-intensive on large databases. Runs LIMITED mode.
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_IndexHealth]
    @MinPageCount BIGINT = 1000,  -- Skip small indexes
    @MinFragPct DECIMAL(5,2) = 10.0  -- Only record fragmented indexes
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [monitor].[IndexHealthHistory]
        (DatabaseName, SchemaName, TableName, IndexName, IndexType,
         FragmentationPct, PageCount, UserSeeks, UserScans, UserLookups, UserUpdates)
    SELECT
        DB_NAME() AS DatabaseName,
        s.name AS SchemaName,
        t.name AS TableName,
        i.name AS IndexName,
        i.type_desc AS IndexType,
        ips.avg_fragmentation_in_percent AS FragmentationPct,
        ips.page_count AS PageCount,
        ius.user_seeks AS UserSeeks,
        ius.user_scans AS UserScans,
        ius.user_lookups AS UserLookups,
        ius.user_updates AS UserUpdates
    FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
    INNER JOIN sys.indexes i ON i.object_id = ips.object_id AND i.index_id = ips.index_id
    INNER JOIN sys.tables t ON t.object_id = i.object_id
    INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
    LEFT JOIN sys.dm_db_index_usage_stats ius 
        ON ius.object_id = i.object_id AND ius.index_id = i.index_id AND ius.database_id = DB_ID()
    WHERE ips.page_count >= @MinPageCount
        AND ips.avg_fragmentation_in_percent >= @MinFragPct
        AND i.type > 0  -- Skip heaps
        AND t.is_ms_shipped = 0;
END;
GO
