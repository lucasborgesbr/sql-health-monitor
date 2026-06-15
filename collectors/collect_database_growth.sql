/*
    SQL Health Monitor - Database Growth Collector
    Collects database size and growth trends.
    
    Schedule: Every 15 minutes
    Compatibility: SQL Server 2016+
*/

IF OBJECT_ID('[monitor].[usp_Collect_DatabaseGrowth]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_DatabaseGrowth]  AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_DatabaseGrowth]', 'P') IS NULL
    
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
        D
        a
        t
        a
        b
        a
        s
        e
        G
        r
        o
        w
        t
        h
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

ALTER PROCEDURE [monitor].[usp_Collect_DatabaseGrowth]
    
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [monitor].[DatabaseGrowthHistory]
        (DatabaseName, DataSizeMB, LogSizeMB, TotalSizeMB, 
         DataGrowthMB, LogGrowthMB, GrowthRatePercent, DaysSinceLastGrowth)
    SELECT
        d.name AS DatabaseName,
        CAST(FILEGROUPPROPERTY(d.data_space_id, 'FILEGROUP_SIZE') / 1024.0 / 1024.0 AS DECIMAL(10, 2)) AS DataSizeMB,
        CAST((SELECT SUM(size) FROM sys.master_files mf 
              WHERE mf.database_id = d.database_id 
                AND mf.type = 1) / 1024.0 / 1024.0 AS DECIMAL(10, 2)) AS LogSizeMB,
        CAST((SELECT SUM(size) FROM sys.master_files mf 
              WHERE mf.database_id = d.database_id) / 1024.0 / 1024.0 AS DECIMAL(10, 2)) AS TotalSizeMB,
        -- Calculate growth since last measurement (if history exists)
        CASE WHEN EXISTS (
            SELECT 1 FROM [monitor].[DatabaseGrowthHistory] h 
            WHERE h.DatabaseName = d.name 
              AND h.CollectTime > DATEADD(HOUR, -24, SYSDATETIME())
        ) THEN (
            SELECT CAST((SUM(size) / 1024.0 / 1024.0) - 
                       (SELECT ISNULL(DataSizeMB + LogSizeMB, 0) 
                        FROM [monitor].[DatabaseGrowthHistory] h2 
                        WHERE h2.DatabaseName = d.name 
                          AND h2.CollectTime = (
                            SELECT MAX(CollectTime) 
                            FROM [monitor].[DatabaseGrowthHistory] 
                            WHERE DatabaseName = d.name
                          )
                       ) AS DECIMAL(10, 2))
            FROM sys.master_files mf
            WHERE mf.database_id = d.database_id
        ) ELSE 0 END AS DataGrowthMB,
        -- Log growth calculation
        CASE WHEN EXISTS (
            SELECT 1 FROM [monitor].[DatabaseGrowthHistory] h 
            WHERE h.DatabaseName = d.name 
              AND h.CollectTime > DATEADD(HOUR, -24, SYSDATETIME())
        ) THEN (
            SELECT CAST((SELECT SUM(size) FROM sys.master_files mf 
                         WHERE mf.database_id = d.database_id AND mf.type = 1) / 1024.0 / 1024.0 - 
                       (SELECT ISNULL(LogSizeMB, 0) 
                        FROM [monitor].[DatabaseGrowthHistory] h2 
                        WHERE h2.DatabaseName = d.name 
                          AND h2.CollectTime = (
                            SELECT MAX(CollectTime) 
                            FROM [monitor].[DatabaseGrowthHistory] 
                            WHERE DatabaseName = d.name
                          )
                       ) AS DECIMAL(10, 2))
        ) ELSE 0 END AS LogGrowthMB,
        -- Growth rate percentage
        CASE WHEN EXISTS (
            SELECT 1 FROM [monitor].[DatabaseGrowthHistory] h 
            WHERE h.DatabaseName = d.name 
              AND h.CollectTime > DATEADD(HOUR, -24, SYSDATETIME())
        ) THEN (
            SELECT CAST(((SUM(size) / 1024.0 / 1024.0) / 
                        (SELECT ISNULL(DataSizeMB + LogSizeMB, 0) 
                         FROM [monitor].[DatabaseGrowthHistory] h2 
                         WHERE h2.DatabaseName = d.name 
                           AND h2.CollectTime = (
                             SELECT MAX(CollectTime) 
                             FROM [monitor].[DatabaseGrowthHistory] 
                             WHERE DatabaseName = d.name
                           )
                        ) - 1) * 100 AS DECIMAL(10, 2))
            FROM sys.master_files mf
            WHERE mf.database_id = d.database_id
        ) ELSE 0 END AS GrowthRatePercent,
        -- Days since last growth
        CASE WHEN EXISTS (
            SELECT 1 FROM [monitor].[DatabaseGrowthHistory] h 
            WHERE h.DatabaseName = d.name 
        ) THEN DATEDIFF(DAY, 
            (SELECT MAX(CollectTime) 
             FROM [monitor].[DatabaseGrowthHistory] 
             WHERE DatabaseName = d.name),
            SYSDATETIME()
        ) ELSE NULL END AS DaysSinceLastGrowth
    FROM sys.databases d
    WHERE d.database_id > 4  -- Exclude system databases
      AND d.state_desc = 'ONLINE';
END;
GO
