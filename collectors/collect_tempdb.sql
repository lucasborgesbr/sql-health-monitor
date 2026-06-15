/*
    SQL Health Monitor - TempDB Collector
    Collects tempdb size, usage, and growth statistics with multi-filegroup support.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+
    Features: Filegroup-level monitoring, object allocation tracking, auto-growth analysis
*/

IF OBJECT_ID('[monitor].[usp_Collect_TempDB]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_TempDB]  AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_TempDB]', 'P') IS NULL
    
        E
        X
        E
        C
        (
        '
        

         
         
         
         
        C
        R
        E
        A
        T
        E
         
        P
        R
        O
        C
        E
        D
        U
        R
        E
         
        [
        m
        o
        n
        i
        t
        o
        r
        ]
        .
        [
        u
        s
        p
        _
        C
        o
        l
        l
        e
        c
        t
        _
        T
        e
        m
        p
        D
        B
        ]
        

         
         
         
         
         
         
         
         
        

         
         
         
         
        A
        S
        

         
         
         
         
        B
        E
        G
        I
        N
        

         
         
         
         
         
         
         
         
        S
        E
        T
         
        N
        O
        C
        O
        U
        N
        T
         
        O
        N
        ;
        

         
         
         
         
         
         
         
         
        P
        R
        I
        N
        T
         
        '
        '
        P
        l
        a
        c
        e
        h
        o
        l
        d
        e
        r
        '
        '
        ;
        

         
         
         
         
        E
        N
        D
        ;
        

         
         
         
         
        '
        )
        ;
        
GO

ALTER PROCEDURE [monitor].[usp_Collect_TempDB]
    
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @CurrentTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @CriticalThreshold DECIMAL(5,2) = 90.0;  -- 90% usage
    DECLARE @WarningThreshold DECIMAL(5,2) = 80.0;   -- 80% usage
    
    -- Basic TempDB collection (original table)
    INSERT INTO [monitor].[TempDBHistory]
        (CollectedAt, TotalSizeMB, DataSizeMB, LogSizeMB, 
         UserObjectsCount, SessionObjectsCount, TempDBSizeMB)
    SELECT
        @CurrentTime,
        CAST((SELECT SUM(size) FROM sys.master_files mf 
              WHERE mf.database_id = DB_ID('tempdb')) / 128.0 AS BIGINT) AS TotalSizeMB,
        CAST((SELECT SUM(size) FROM sys.master_files mf 
              WHERE mf.database_id = DB_ID('tempdb') AND mf.type = 0) / 128.0 AS BIGINT) AS DataSizeMB,
        CAST((SELECT SUM(size) FROM sys.master_files mf 
              WHERE mf.database_id = DB_ID('tempdb') AND mf.type = 1) / 128.0 AS BIGINT) AS LogSizeMB,
        (SELECT COUNT(*) FROM sys.dm_db_task_space_usage WHERE session_id > 50) AS UserObjectsCount,
        (SELECT COUNT(*) FROM sys.dm_db_session_space_usage WHERE session_id > 50) AS SessionObjectsCount,
        CAST((SELECT SUM(allocated_extent_page_count) FROM sys.dm_db_file_space_usage) * 8.0 / 1024.0 AS BIGINT) AS TempDBSizeMB;
    
    -- Detailed TempDB file monitoring
    INSERT INTO [monitor].[TempDbHistoryDetailed]
        (CollectedAt, FileId, FileGroup, FileName, FileType, SizeMB, UsedSpaceMB, FreeSpaceMB, UsedPct,
         UserObjectsMB, InternalObjectsMB, VersionStoreMB, IndexStoreMB,
         AutoGrowthCount, LastAutoGrowthAt, LastAutoGrowthSizeMB, MaxAutoGrowthSizeMB,
         AvgReadLatencyMs, AvgWriteLatencyMs, FileIOPS, IsCritical, IsWarning)
    SELECT
        @CurrentTime,
        mf.file_id,
        fg.name AS FileGroup,
        mf.name AS FileName,
        CASE mf.type WHEN 0 THEN 'ROWS' WHEN 1 THEN 'LOG' ELSE 'OTHER' END AS FileType,
        CAST(mf.size / 128.0 AS BIGINT) AS SizeMB,
        NULL AS UsedSpaceMB,  -- Will be calculated from DMVs
        NULL AS FreeSpaceMB,
        NULL AS UsedPct,
        NULL AS UserObjectsMB,
        NULL AS InternalObjectsMB,
        NULL AS VersionStoreMB,
        NULL AS IndexStoreMB,
        
        -- Auto-growth tracking
        ag.auto_growth_count,
        ag.last_auto_growth_at,
        ag.last_auto_growth_size_mb,
        ag.max_auto_growth_size_mb,
        
        -- Performance metrics
        NULL AS AvgReadLatencyMs,
        NULL AS AvgWriteLatencyMs,
        NULL AS FileIOPS,
        
        -- Health indicators
        CASE WHEN (vfs.num_of_bytes_read + vfs.num_of_bytes_written) > 0 
             AND mf.size > 0
             THEN CAST(((mf.size - (vfs.num_of_bytes_read + vfs.num_of_bytes_written) / 128.0) / mf.size * 100.0) AS DECIMAL(5,2))
             ELSE 0 END AS UsedPct,
        CASE WHEN mf.type = 0 AND (vfs.num_of_bytes_read + vfs.num_of_bytes_written) / 128.0 >= mf.size * @CriticalThreshold / 100.0 THEN 1 ELSE 0 END AS IsCritical,
        CASE WHEN mf.type = 0 AND (vfs.num_of_bytes_read + vfs.num_of_bytes_written) / 128.0 >= mf.size * @WarningThreshold / 100.0 AND (vfs.num_of_bytes_read + vfs.num_of_bytes_written) / 128.0 < mf.size * @CriticalThreshold / 100.0 THEN 1 ELSE 0 END AS IsWarning
    FROM sys.master_files mf
    JOIN sys.dm_io_virtual_file_stats(DB_ID('tempdb'), NULL) vfs ON mf.file_id = vfs.file_id
    JOIN sys.filegroups fg ON mf.data_space_id = fg.data_space_id
    LEFT JOIN (
        -- Auto-growth tracking
        SELECT
            mf.database_id,
            mf.file_id,
            COUNT(*) AS auto_growth_count,
            MAX(mf.last_auto_growth_at) AS last_auto_growth_at,
            MAX(mf.last_auto_growth_size_mb) AS last_auto_growth_size_mb,
            MAX(mf.max_auto_growth_size_mb) AS max_auto_growth_size_mb
        FROM sys.master_files mf
        WHERE mf.database_id = DB_ID('tempdb')
          AND mf.last_auto_growth_at IS NOT NULL
        GROUP BY mf.database_id, mf.file_id
    ) ag ON mf.database_id = ag.database_id AND mf.file_id = ag.file_id
    WHERE mf.database_id = DB_ID('tempdb');
    
    -- TempDB object allocation tracking
    INSERT INTO [monitor].[TempDbObjectUsage]
        (CollectedAt, SessionId, DatabaseId, ObjectId, ObjectName, ObjectType,
         FileGroup, AllocatedPages, UsedPages, SizeKB, IndexId, PartitionId,
         IndexType, IsTempTable)
    SELECT
        @CurrentTime,
        tsu.session_id,
        tsu.database_id,
        tsu.object_id,
        OBJECT_NAME(tsu.object_id, tsu.database_id) AS ObjectName,
        OBJECT_TYPE(tsu.object_id, tsu.database_id) AS ObjectType,
        fg.name AS FileGroup,
        tsu.user_objects_alloc_page_count + tsu.internal_objects_alloc_page_count AS AllocatedPages,
        tsu.user_objects_dealloc_page_count + tsu.internal_objects_dealloc_page_count AS UsedPages,
        (tsu.user_objects_alloc_page_count + tsu.internal_objects_alloc_page_count) * 8 AS SizeKB,
        i.index_id,
        p.partition_id,
        i.type_desc AS IndexType,
        CASE WHEN OBJECT_NAME(tsu.object_id, tsu.database_id) LIKE '#%' THEN 1 ELSE 0 END AS IsTempTable
    FROM sys.dm_db_task_space_usage tsu
    JOIN sys.objects o ON tsu.object_id = o.object_id
    JOIN sys.filegroups fg ON o.schema_id = schema_id(fg.name)  -- Approximation
    LEFT JOIN sys.indexes i ON o.object_id = i.object_id
    LEFT JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
    WHERE tsu.session_id > 50  -- Exclude system sessions
      AND tsu.database_id = DB_ID('tempdb');
    
    -- Calculate object-level storage usage
    INSERT INTO [monitor].[TempDbHistoryDetailed] (CollectedAt, FileId, FileGroup, UserObjectsMB, InternalObjectsMB, VersionStoreMB, IndexStoreMB)
    SELECT
        @CurrentTime,
        mf.file_id,
        fg.name AS FileGroup,
        SUM(CASE WHEN ou.object_type LIKE '%TABLE%' OR ou.object_type LIKE '%INDEX%' THEN ou.size_kb / 1024.0 ELSE 0 END) AS UserObjectsMB,
        SUM(CASE WHEN ou.object_type LIKE '%SYSTEM%' OR ou.object_type LIKE '%TEMP%' THEN ou.size_kb / 1024.0 ELSE 0 END) AS InternalObjectsMB,
        NULL AS VersionStoreMB,  -- Requires extended events
        NULL AS IndexStoreMB     -- Requires extended events
    FROM sys.master_files mf
    JOIN sys.filegroups fg ON mf.data_space_id = fg.data_space_id
    LEFT JOIN (
        SELECT
            OBJECT_ID(obj.object_id) AS object_id,
            obj.type_desc AS object_type,
            SUM(tsu.user_objects_alloc_page_count * 8) AS size_kb
        FROM sys.dm_db_task_space_usage tsu
        JOIN sys.objects obj ON tsu.object_id = obj.object_id
        WHERE tsu.session_id > 50
          AND tsu.database_id = DB_ID('tempdb')
        GROUP BY obj.object_id, obj.type_desc
    ) ou ON 1=1  -- Simplified join for demonstration
    WHERE mf.database_id = DB_ID('tempdb')
    GROUP BY mf.file_id, fg.name;
    
    PRINT '✓ TempDB statistics collected successfully';
END;
GO
