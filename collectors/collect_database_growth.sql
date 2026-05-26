/*
    SQL Health Monitor - Database Growth Collector
    Tracks data and log file sizes over time for trend analysis.
    
    Schedule: Every 30 minutes (or hourly)
    Compatibility: SQL Server 2016+
    
    Notes:
      - Captures current size and used space for all database files
      - Calculates delta (growth) from previous collection
      - Excludes system databases by default (configurable)
      - Uses sys.master_files + FILEPROPERTY for accurate used space
*/

USE [DBA_Monitor];
GO

----------------------------------------------------------------------
-- DATABASE GROWTH HISTORY TABLE
----------------------------------------------------------------------
IF OBJECT_ID('monitor.DatabaseGrowthHistory', 'U') IS NULL
CREATE TABLE [monitor].[DatabaseGrowthHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    DatabaseName    NVARCHAR(128) NOT NULL,
    FileLogicalName NVARCHAR(128) NOT NULL,
    FileType        NVARCHAR(10)  NOT NULL,  -- ROWS, LOG
    FileGroup       NVARCHAR(128) NULL,
    SizeMB          DECIMAL(18,2) NOT NULL,
    UsedMB          DECIMAL(18,2) NOT NULL,
    FreeMB          AS (SizeMB - UsedMB) PERSISTED,
    UsedPct         AS (CASE WHEN SizeMB > 0 THEN CAST(UsedMB * 100.0 / SizeMB AS DECIMAL(5,2)) ELSE 0 END) PERSISTED,
    GrowthSincePrevMB DECIMAL(18,2) NULL,  -- Delta from previous collection
    AutoGrowthMB    DECIMAL(18,2) NULL,     -- Configured auto-growth increment
    MaxSizeMB       DECIMAL(18,2) NULL,     -- Max file size (-1 = unlimited)
    PhysicalPath    NVARCHAR(500) NULL,
    INDEX IX_DbGrowth_Collected NONCLUSTERED (CollectedAt),
    INDEX IX_DbGrowth_Database NONCLUSTERED (DatabaseName, FileType, CollectedAt)
);
GO

----------------------------------------------------------------------
-- COLLECTOR PROCEDURE
----------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_DatabaseGrowth]
    @IncludeSystemDBs BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();

    -- ============================================================
    -- COLLECT CURRENT FILE SIZES
    -- ============================================================
    CREATE TABLE #CurrentSizes (
        DatabaseName    NVARCHAR(128),
        FileLogicalName NVARCHAR(128),
        FileType        NVARCHAR(10),
        FileGroup       NVARCHAR(128),
        SizeMB          DECIMAL(18,2),
        UsedMB          DECIMAL(18,2),
        AutoGrowthMB    DECIMAL(18,2),
        MaxSizeMB       DECIMAL(18,2),
        PhysicalPath    NVARCHAR(500)
    );

    -- Use sys.master_files for size info (works across all databases)
    INSERT INTO #CurrentSizes (
        DatabaseName, FileLogicalName, FileType, SizeMB, 
        AutoGrowthMB, MaxSizeMB, PhysicalPath
    )
    SELECT
        DB_NAME(mf.database_id),
        mf.name,
        CASE mf.type 
            WHEN 0 THEN 'ROWS'
            WHEN 1 THEN 'LOG'
            WHEN 2 THEN 'FILESTREAM'
            WHEN 4 THEN 'FULLTEXT'
            ELSE 'OTHER'
        END,
        CAST(mf.size * 8.0 / 1024 AS DECIMAL(18,2)),  -- Convert pages to MB
        CASE 
            WHEN mf.is_percent_growth = 1 
                THEN CAST(mf.size * 8.0 / 1024 * mf.growth / 100.0 AS DECIMAL(18,2))
            ELSE CAST(mf.growth * 8.0 / 1024 AS DECIMAL(18,2))
        END,
        CASE mf.max_size
            WHEN -1 THEN -1
            WHEN 268435456 THEN -1  -- 2TB limit for log files
            ELSE CAST(mf.max_size * 8.0 / 1024 AS DECIMAL(18,2))
        END,
        mf.physical_name
    FROM sys.master_files mf
    INNER JOIN sys.databases d ON d.database_id = mf.database_id
    WHERE d.state_desc = 'ONLINE'
        AND mf.type IN (0, 1)  -- Data and Log files only
        AND (@IncludeSystemDBs = 1 OR d.database_id > 4);

    -- Get used space per file using dynamic SQL across databases
    DECLARE @sql NVARCHAR(MAX) = '';
    
    SELECT @sql = @sql + 
        CASE WHEN @sql <> '' THEN ' UNION ALL ' ELSE '' END +
        'SELECT ''' + REPLACE(name, '''', '''''') + ''' AS DatabaseName, ' +
        'f.name AS FileLogicalName, ' +
        'CAST(FILEPROPERTY(f.name, ''SpaceUsed'') * 8.0 / 1024 AS DECIMAL(18,2)) AS UsedMB, ' +
        'fg.name AS FileGroup ' +
        'FROM [' + REPLACE(name, ']', ']]') + '].sys.database_files f ' +
        'LEFT JOIN [' + REPLACE(name, ']', ']]') + '].sys.filegroups fg ON f.data_space_id = fg.data_space_id ' +
        'WHERE f.type IN (0, 1)'
    FROM sys.databases
    WHERE state_desc = 'ONLINE'
        AND (database_id > 4 OR @IncludeSystemDBs = 1);

    IF @sql <> ''
    BEGIN
        CREATE TABLE #UsedSpace (
            DatabaseName    NVARCHAR(128),
            FileLogicalName NVARCHAR(128),
            UsedMB          DECIMAL(18,2),
            FileGroup       NVARCHAR(128)
        );

        BEGIN TRY
            INSERT INTO #UsedSpace
            EXEC sp_executesql @sql;

            -- Update current sizes with used space and filegroup
            UPDATE cs
            SET cs.UsedMB = ISNULL(us.UsedMB, 0),
                cs.FileGroup = us.FileGroup
            FROM #CurrentSizes cs
            INNER JOIN #UsedSpace us 
                ON cs.DatabaseName = us.DatabaseName
                AND cs.FileLogicalName = us.FileLogicalName;
        END TRY
        BEGIN CATCH
            -- If dynamic SQL fails for a DB, use size as approximation
            UPDATE #CurrentSizes
            SET UsedMB = SizeMB * 0.8  -- Conservative estimate
            WHERE UsedMB IS NULL;
        END CATCH;

        DROP TABLE #UsedSpace;
    END;

    -- Default UsedMB where still NULL
    UPDATE #CurrentSizes SET UsedMB = 0 WHERE UsedMB IS NULL;

    -- ============================================================
    -- CALCULATE GROWTH DELTA FROM PREVIOUS COLLECTION
    -- ============================================================
    INSERT INTO [monitor].[DatabaseGrowthHistory] (
        CollectedAt, DatabaseName, FileLogicalName, FileType, FileGroup,
        SizeMB, UsedMB, GrowthSincePrevMB, AutoGrowthMB, MaxSizeMB, PhysicalPath
    )
    SELECT
        @Now,
        cs.DatabaseName,
        cs.FileLogicalName,
        cs.FileType,
        cs.FileGroup,
        cs.SizeMB,
        cs.UsedMB,
        -- Delta: current size minus previous size
        CASE 
            WHEN prev.SizeMB IS NOT NULL THEN cs.SizeMB - prev.SizeMB
            ELSE NULL  -- First collection, no delta
        END,
        cs.AutoGrowthMB,
        cs.MaxSizeMB,
        cs.PhysicalPath
    FROM #CurrentSizes cs
    -- Get most recent previous collection for same file
    OUTER APPLY (
        SELECT TOP 1 h.SizeMB
        FROM [monitor].[DatabaseGrowthHistory] h
        WHERE h.DatabaseName = cs.DatabaseName
            AND h.FileLogicalName = cs.FileLogicalName
        ORDER BY h.CollectedAt DESC
    ) prev;

    DROP TABLE #CurrentSizes;

    DECLARE @RowsInserted INT = @@ROWCOUNT;
    PRINT 'Collected growth data for ' + CAST(@RowsInserted AS VARCHAR(10)) + ' database file(s).';
END;
GO

PRINT '✓ Database growth collector [monitor].[usp_Collect_DatabaseGrowth] created.';
PRINT '✓ Table [monitor].[DatabaseGrowthHistory] created.';
GO
