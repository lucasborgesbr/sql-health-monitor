-- recommendations_engine.sql - Generates actionable recommendations based on collected data
-- Updated: 2026-06-02 for release-ready version

USE [SQLHealthMonitor];
GO

IF OBJECT_ID('[monitor].[usp_GenerateRecommendations]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_GenerateRecommendations]  AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_GenerateRecommendations]', 'P') IS NULL
    
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
        G
        e
        n
        e
        r
        a
        t
        e
        R
        e
        c
        o
        m
        m
        e
        n
        d
        a
        t
        i
        o
        n
        s
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

ALTER PROCEDURE [monitor].[usp_GenerateRecommendations]
    
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @RecommendationDate DATETIME2 = SYSDATETIME();
    DECLARE @DatabaseName NVARCHAR(128) = DB_NAME();
    
    -- Clear previous recommendations
    TRUNCATE TABLE [monitor].[Recommendations];
    
    -- CPU Recommendations
    INSERT INTO [monitor].[Recommendations] 
        (MetricName, CurrentValue, Recommendation, Priority, CreatedAt)
    SELECT 
        'CPU Usage', 
        ch.SqlCpuPct,
        CASE WHEN ch.SqlCpuPct > 95 THEN 'CRITICAL: High CPU usage detected. Consider adding more CPU resources or optimizing heavy queries.'
             WHEN ch.SqlCpuPct > 80 THEN 'WARNING: High CPU usage detected. Monitor for performance degradation.'
             ELSE 'INFO: CPU usage is within normal parameters.'
        END,
        CASE WHEN ch.SqlCpuPct > 95 THEN 'HIGH'
             WHEN ch.SqlCpuPct > 80 THEN 'MEDIUM'
             ELSE 'LOW'
        END,
        @RecommendationDate
    FROM (SELECT TOP 1 SqlCpuPct FROM [monitor].[CPUHistory] ORDER BY CollectedAt DESC) ch;
    
    -- Memory Recommendations
    INSERT INTO [monitor].[Recommendations] 
        (MetricName, CurrentValue, Recommendation, Priority, CreatedAt)
    SELECT 
        'Memory Usage', 
        mh.AvailableMemoryMB,
        CASE WHEN mh.AvailableMemoryMB < 1024 THEN 'CRITICAL: Low available memory. Consider increasing server memory or optimizing memory usage.'
             WHEN mh.AvailableMemoryMB < 2048 THEN 'WARNING: Low available memory. Monitor memory pressure.'
             ELSE 'INFO: Memory usage is within normal parameters.'
        END,
        CASE WHEN mh.AvailableMemoryMB < 1024 THEN 'HIGH'
             WHEN mh.AvailableMemoryMB < 2048 THEN 'MEDIUM'
             ELSE 'LOW'
        END,
        @RecommendationDate
    FROM (SELECT TOP 1 AvailableMemoryMB FROM [monitor].[MemoryHistory] ORDER BY CollectedAt DESC) mh;
    
    -- Disk Space Recommendations
    INSERT INTO [monitor].[Recommendations] 
        (MetricName, CurrentValue, Recommendation, Priority, CreatedAt)
    SELECT 
        'Disk Space', 
        dh.UsedPct,
        CASE WHEN dh.UsedPct > 95 THEN 'CRITICAL: Critical disk space usage. Immediate action required to prevent database failure.'
             WHEN dh.UsedPct > 85 THEN 'WARNING: High disk space usage. Consider cleanup or expansion.'
             ELSE 'INFO: Disk space usage is within normal parameters.'
        END,
        CASE WHEN dh.UsedPct > 95 THEN 'HIGH'
             WHEN dh.UsedPct > 85 THEN 'MEDIUM'
             ELSE 'LOW'
        END,
        @RecommendationDate
    FROM (SELECT TOP 1 UsedPct FROM [monitor].[DiskHistory] ORDER BY CollectedAt DESC) dh;
    
    -- Backup Recommendations
    INSERT INTO [monitor].[Recommendations] 
        (MetricName, CurrentValue, Recommendation, Priority, CreatedAt)
    SELECT 
        'Backup Status', 
        bh.HoursSinceLastBackup,
        CASE WHEN bh.HoursSinceLastBackup > 48 THEN 'CRITICAL: No recent backup available. Database at risk of data loss.'
             WHEN bh.HoursSinceLastBackup > 24 THEN 'WARNING: Backup older than 24 hours. Review backup schedule.'
             WHEN bh.HoursSinceLastBackup > 12 THEN 'INFO: Backup is within acceptable timeframe.'
             ELSE 'INFO: Backup schedule is current.'
        END,
        CASE WHEN bh.HoursSinceLastBackup > 48 THEN 'HIGH'
             WHEN bh.HoursSinceLastBackup > 24 THEN 'MEDIUM'
             ELSE 'LOW'
        END,
        @RecommendationDate
    FROM (SELECT TOP 1 HoursSinceLastBackup FROM [monitor].[BackupHistory] ORDER BY CollectedAt DESC) bh;
    
    -- Index Fragmentation Recommendations
    INSERT INTO [monitor].[Recommendations] 
        (MetricName, CurrentValue, Recommendation, Priority, CreatedAt)
    SELECT 
        'Index Fragmentation', 
        ih.FragmentationPct,
        CASE WHEN ih.FragmentationPct > 60 THEN 'CRITICAL: High index fragmentation. Rebuild indexes to improve performance.'
             WHEN ih.FragmentationPct > 30 THEN 'WARNING: Moderate index fragmentation. Consider rebuilding or reorganizing indexes.'
             WHEN ih.FragmentationPct > 10 THEN 'INFO: Index fragmentation is within acceptable limits.'
             ELSE 'INFO: Index health is good.'
        END,
        CASE WHEN ih.FragmentationPct > 60 THEN 'HIGH'
             WHEN ih.FragmentationPct > 30 THEN 'MEDIUM'
             ELSE 'LOW'
        END,
        @RecommendationDate
    FROM (SELECT TOP 1 FragmentationPct FROM [monitor].[IndexHealthHistory] ORDER BY CollectedAt DESC) ih;
    
    -- Job Status Recommendations
    INSERT INTO [monitor].[Recommendations] 
        (MetricName, CurrentValue, Recommendation, Priority, CreatedAt)
    SELECT 
        'SQL Agent Jobs', 
        jh.FailedJobsCount,
        CASE WHEN jh.FailedJobsCount > 3 THEN 'CRITICAL: Multiple job failures detected. Review job schedules and error logs.'
             WHEN jh.FailedJobsCount > 1 THEN 'WARNING: Some jobs have failed. Investigate root cause.'
             ELSE 'INFO: All jobs are running successfully.'
        END,
        CASE WHEN jh.FailedJobsCount > 3 THEN 'HIGH'
             WHEN jh.FailedJobsCount > 1 THEN 'MEDIUM'
             ELSE 'LOW'
        END,
        @RecommendationDate
    FROM (
        SELECT 
            SUM(CASE WHEN LastRunStatus = 'Failed' THEN 1 ELSE 0 END) as FailedJobsCount
        FROM (SELECT TOP 1 LastRunStatus FROM [monitor].[JobHistory] ORDER BY CollectedAt DESC) jh
    ) jh;
    
    -- TempDB Recommendations
    INSERT INTO [monitor].[Recommendations] 
        (MetricName, CurrentValue, Recommendation, Priority, CreatedAt)
    SELECT 
        'TempDB Usage', 
        th.UsedSpaceMB,
        CASE WHEN th.UsedSpaceMB > 8192 THEN 'CRITICAL: High TempDB usage. Consider increasing TempDB files or optimizing queries.'
             WHEN th.UsedSpaceMB > 4096 THEN 'WARNING: Elevated TempDB usage. Monitor for growth patterns.'
             ELSE 'INFO: TempDB usage is within normal parameters.'
        END,
        CASE WHEN th.UsedSpaceMB > 8192 THEN 'HIGH'
             WHEN th.UsedSpaceMB > 4096 THEN 'MEDIUM'
             ELSE 'LOW'
        END,
        @RecommendationDate
    FROM (SELECT TOP 1 UsedSpaceMB FROM [monitor].[TempDbHistory] ORDER BY CollectedAt DESC) th;
    
    PRINT '✓ Recommendations generated successfully.';
END;
GO

-- Execute recommendations generation
EXEC [monitor].[usp_GenerateRecommendations];
GO

PRINT '✓ Recommendations engine executed successfully.';
GO
