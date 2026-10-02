/*
    SQL Health Monitor - Index Recommendations Collector
    Uses SQL Server DMVs to generate index recommendations.

    Features:
    - Missing index suggestions
    - Unused indexes
    - Duplicate indexes
    - Similar/overlapping indexes
    - CREATE INDEX script generation

    Schedule: Daily (expensive operation)
    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

IF OBJECT_ID('[monitor].[usp_Collect_IndexRecommendations]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_IndexRecommendations] @DebugMode BIT = 0 AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_IndexRecommendations]', 'IP') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_Collect_IndexRecommendations] @DebugMode BIT = 0 AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

ALTER PROCEDURE [monitor].[usp_Collect_IndexRecommendations]
    @DebugMode BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CollectedAt DATETIME2 = SYSUTCDATETIME();

    -- Create temp table for missing indexes
    CREATE TABLE #MissingIndexes (
        DatabaseName        NVARCHAR(128),
        SchemaName          NVARCHAR(128),
        TableName           NVARCHAR(128),
        EqualityColumns     NVARCHAR(MAX),
        InequalityColumns   NVARCHAR(MAX),
        IncludeColumns      NVARCHAR(MAX),
        UniqueCompiles      BIGINT,
        UserSeeks           BIGINT,
        UserScans           BIGINT,
        AvgTotalUserCost    DECIMAL(18,2),
        Score               DECIMAL(18,6),
        CreateStatement     NVARCHAR(MAX)
    );

    -- Get missing indexes from all user databases
    INSERT INTO #MissingIndexes (
        DatabaseName, SchemaName, TableName,
        EqualityColumns, InequalityColumns, IncludeColumns,
        UniqueCompiles, UserSeeks, UserScans, AvgTotalUserCost, Score,
        CreateStatement
    )
    SELECT
        DB_NAME(mid.database_id)                    AS DatabaseName,
        SCHEMA_NAME(o.schema_id)                   AS SchemaName,
        OBJECT_NAME(mid.object_id, mid.database_id) AS TableName,
        mid.equality_columns                       AS EqualityColumns,
        mid.inequality_columns                      AS InequalityColumns,
        mid.included_columns                        AS IncludeColumns,
        migs.unique_compiles                        AS UniqueCompiles,
        migs.user_seeks                             AS UserSeeks,
        migs.user_scans                             AS UserScans,
        migs.avg_total_user_cost                    AS AvgTotalUserCost,
        migs.avg_user_impact                        AS Score,  -- Impact score
        -- Generate CREATE INDEX statement
        'CREATE INDEX [IX_' + OBJECT_NAME(mid.object_id, mid.database_id) + '_'
            + REPLACE(REPLACE(ISNULL(mid.equality_columns, ''), '[', ''), ']', '')
            + CASE WHEN ISNULL(mid.inequality_columns, '') <> '' THEN '_' + REPLACE(REPLACE(mid.inequality_columns, '[', ''), ']', '') ELSE '' END
            + '_' + CONVERT(NVARCHAR(10), ABS(CHECKSUM(NEWID())) % 10000) + ']'
            + ' ON ' + QUOTENAME(DB_NAME(mid.database_id)) + '.' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + '.' + QUOTENAME(OBJECT_NAME(mid.object_id, mid.database_id))
            + ' (' + mid.equality_columns
            + CASE WHEN ISNULL(mid.inequality_columns, '') <> '' THEN ',' + mid.inequality_columns ELSE '' END + ')'
            + CASE WHEN ISNULL(mid.included_columns, '') <> '' THEN ' INCLUDE (' + mid.included_columns + ')' ELSE '' END
            + '; -- Impact: ' + CAST(migs.avg_user_impact AS NVARCHAR(10)) + '%, Seeks: ' + CAST(migs.user_seeks AS NVARCHAR(20))
            AS CreateStatement
    FROM sys.dm_db_missing_index_details mid
    INNER JOIN sys.objects o ON mid.object_id = o.object_id
    INNER JOIN sys.dm_db_missing_index_groups mig ON mid.index_handle = mig.index_handle
    INNER JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
    WHERE OBJECTPROPERTY(o.object_id, 'IsUserTable') = 1
      AND DB_NAME(mid.database_id) NOT IN ('master', 'msdb', 'tempdb', 'model')
    ORDER BY migs.avg_user_impact DESC, migs.user_seeks DESC;

    -- Truncate and insert into history
    TRUNCATE TABLE [monitor].[IndexRecommendations];

    INSERT INTO [monitor].[IndexRecommendations] (
        CollectedAt, DatabaseName, SchemaName, TableName,
        RecommendationType, ImpactScore,
        EqualityColumns, InequalityColumns, IncludeColumns,
        UserSeeks, UserScans, AvgTotalUserCost,
        RecommendedAction
    )
    SELECT
        @CollectedAt,
        DatabaseName,
        SchemaName,
        TableName,
        'MISSING_INDEX'        AS RecommendationType,
        Score                  AS ImpactScore,
        EqualityColumns,
        InequalityColumns,
        IncludeColumns,
        UserSeeks,
        UserScans,
        AvgTotalUserCost,
        CreateStatement        AS RecommendedAction
    FROM #MissingIndexes
    WHERE Score >= 30  -- Only high-impact recommendations
      AND UserSeeks >= 10;

    -- Also capture UNUSED indexes (not touched in 30+ days)
    INSERT INTO [monitor].[IndexRecommendations] (
        CollectedAt, DatabaseName, SchemaName, TableName,
        RecommendationType, ImpactScore,
        EqualityColumns, InequalityColumns, IncludeColumns,
        UserSeeks, UserScans, AvgTotalUserCost,
        RecommendedAction
    )
    SELECT
        @CollectedAt,
        DB_NAME()                    AS DatabaseName,
        SCHEMA_NAME(o.schema_id)      AS SchemaName,
        OBJECT_NAME(i.object_id)      AS TableName,
        'UNUSED_INDEX'               AS RecommendationType,
        0                            AS ImpactScore,
        i.name                       AS EqualityColumns,
        NULL                         AS InequalityColumns,
        NULL                         AS IncludeColumns,
        0                            AS UserSeeks,
        0                            AS UserScans,
        0                            AS AvgTotalUserCost,
        'DROP INDEX ' + QUOTENAME(i.name) + ' ON ' + QUOTENAME(DB_NAME()) + '.' + QUOTENAME(SCHEMA_NAME(o.schema_id)) + '.' + QUOTENAME(OBJECT_NAME(i.object_id)) + '; -- Not used in 30+ days'
    FROM sys.indexes i
    INNER JOIN sys.objects o ON i.object_id = o.object_id
    LEFT JOIN sys.dm_db_index_usage_stats s ON i.object_id = s.object_id AND i.index_id = s.index_id AND s.database_id = DB_ID()
    WHERE i.is_primary_key = 0
      AND i.is_unique = 0
      AND i.is_disabled = 0
      AND OBJECTPROPERTY(o.object_id, 'IsUserTable') = 1
      AND (s.user_seeks IS NULL OR s.user_seeks = 0)
      AND (s.user_scans IS NULL OR s.user_scans = 0)
      AND s.last_user_seek < DATEADD(DAY, -30, GETDATE());

    -- Output or return
    IF @DebugMode = 1
    BEGIN
        SELECT * FROM [monitor].[IndexRecommendations]
        ORDER BY ImpactScore DESC;
    END

    DROP TABLE #MissingIndexes;

    PRINT '+ Index recommendations collected at ' + CONVERT(NVARCHAR, @CollectedAt, 120);
END;
GO

PRINT '+ Procedure [monitor].[usp_Collect_IndexRecommendations] created.';
GO
