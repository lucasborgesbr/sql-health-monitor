/*
    Enhanced Analytics Engine - Performance Pattern Detection
    Advanced pattern recognition for performance analysis.
    
    Features:
    - Query performance trends (7-day rolling average)
    - Resource correlation analysis (CPU vs I/O vs Memory)
    - Seasonal pattern detection (hourly, daily, weekly)
    - Performance degradation scoring
    - Bottleneck identification
    
    Schema: [monitor]
    Compatibility: SQL Server 2016+
    Author: Lucas Allan Borges
    
    Parameters:
        @AnalysisType       NVARCHAR(50)  - QueryTrends, ResourceCorrelation, SeasonalPatterns, DegradationScore, BottleneckAnalysis
        @DatabaseName      NVARCHAR(128) - Optional database filter
        @HoursBack         INT           - Default: 168 (7 days)
        @MinExecutionCount INT           - Minimum execution count for analysis
        @OutputFormat      NVARCHAR(10)  - Detailed, Summary, RawData
        @DebugMode         BIT           - 1 = Return additional debug information
    
    Example Usage:
        -- Query performance trends
        EXEC [monitor].[usp_EnhancedAnalytics] @AnalysisType = 'QueryTrends', @HoursBack = 168, @OutputFormat = 'Detailed';
        
        -- Resource correlation analysis
        EXEC [monitor].[usp_EnhancedAnalytics] @AnalysisType = 'ResourceCorrelation', @HoursBack = 72;
        
        -- Performance degradation scoring
        EXEC [monitor].[usp_EnhancedAnalytics] @AnalysisType = 'DegradationScore', @HoursBack = 168;
*/

USE [DBA_Monitor];
GO

CREATE OR ALTER PROCEDURE [monitor].[usp_EnhancedAnalytics]
    @AnalysisType NVARCHAR(50) = 'QueryTrends',
    @DatabaseName NVARCHAR(128) = NULL,
    @HoursBack INT = 168,
    @MinExecutionCount INT = 10,
    @OutputFormat NVARCHAR(10) = 'Detailed',
    @DebugMode BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @AnalysisStartTime DATETIME2 = DATEADD(HOUR, -@HoursBack, SYSUTCDATETIME());
    DECLARE @ServerName NVARCHAR(128) = @@SERVERNAME;

    -- ============================================================
    -- RESULT SET 1: ANALYSIS METADATA
    -- ============================================================
    SELECT 
        @ServerName AS ServerName,
        @AnalysisType AS AnalysisType,
        @HoursBack AS HoursAnalyzed,
        @AnalysisStartTime AS AnalysisStartTime,
        SYSUTCDATETIME() AS AnalysisEndTime,
        @DatabaseName AS DatabaseFilter,
        @MinExecutionCount AS MinExecutionCount;

    -- ============================================================
    -- MAIN ANALYSIS SWITCH
    -- ============================================================
    IF @AnalysisType = 'QueryTrends'
    BEGIN
        -- Query performance trends analysis
        SELECT 
            q.DatabaseName,
            q.QueryHash,
            q.QueryText,
            COUNT(DISTINCT q.ExecutionDate) AS ExecutionDays,
            SUM(q.ExecutionCount) AS TotalExecutions,
            SUM(q.TotalCpuMs) / NULLIF(SUM(q.TotalReads + q.TotalWrites), 0) AS CpuPerIO,
            AVG(q.AvgDurationMs) AS AvgDurationMs,
            MAX(q.MaxDurationMs) AS MaxDurationMs,
            MIN(q.MinDurationMs) AS MinDurationMs,
            STDEV(q.AvgDurationMs) AS DurationStdDev,
            CASE 
                WHEN STDEV(q.AvgDurationMs) / NULLIF(AVG(q.AvgDurationMs), 0) > 0.5 THEN 'HIGH'
                WHEN STDEV(q.AvgDurationMs) / NULLIF(AVG(q.AvgDurationMs), 0) > 0.2 THEN 'MEDIUM'
                ELSE 'LOW'
            END AS Variability,
            -- Trend calculation (last 24h vs previous 24h)
            CASE 
                WHEN EXISTS (
                    SELECT 1 FROM [monitor].[TopQueriesHistory] recent
                    WHERE recent.DatabaseName = q.DatabaseName 
                        AND recent.QueryHash = q.QueryHash
                        AND recent.CollectedAt >= DATEADD(HOUR, -24, SYSUTCDATETIME())
                ) THEN 'ACTIVE'
                ELSE 'INACTIVE'
            END AS RecentActivity,
            -- Performance degradation indicator
            CASE 
                WHEN AVG(q.AvgDurationMs) > 1000 THEN 'SLOW'
                WHEN AVG(q.AvgDurationMs) > 500 THEN 'MODERATE'
                ELSE 'FAST'
            END AS PerformanceTier
        FROM [monitor].[TopQueriesHistory] q
        WHERE q.CollectedAt >= @AnalysisStartTime
            AND (@DatabaseName IS NULL OR q.DatabaseName = @DatabaseName)
            AND q.ExecutionCount >= @MinExecutionCount
        GROUP BY q.DatabaseName, q.QueryHash, q.QueryText
        HAVING SUM(q.TotalCpuMs) > 0  -- Only queries that consumed CPU
        ORDER BY SUM(q.TotalCpuMs) DESC;

        -- Top 10 degraded queries (performance regression)
        SELECT TOP 10
            DatabaseName,
            QueryHash,
            QueryText,
            CurrentWeekAvgDuration,
            PreviousWeekAvgDuration,
            DurationChangePct,
            CurrentWeekExecutions,
            PreviousWeekExecutions,
            ExecutionChangePct,
            CpuImpactMs
        FROM (
            SELECT 
                tw.DatabaseName,
                tw.QueryHash,
                tw.QueryText,
                tw.AvgDurationMs AS CurrentWeekAvgDuration,
                ISNULL(lw.AvgDurationMs, 0) AS PreviousWeekAvgDuration,
                CASE 
                    WHEN ISNULL(lw.AvgDurationMs, 0) = 0 THEN NULL
                    ELSE CAST(ROUND((CAST(tw.AvgDurationMs - ISNULL(lw.AvgDurationMs, 0) AS DECIMAL(18,2)) / NULLIF(lw.AvgDurationMs, 0)) * 100, 1) AS DECIMAL(10,1))
                END AS DurationChangePct,
                tw.ExecutionCount AS CurrentWeekExecutions,
                ISNULL(lw.ExecutionCount, 0) AS PreviousWeekExecutions,
                CASE 
                    WHEN ISNULL(lw.ExecutionCount, 0) = 0 THEN NULL
                    ELSE CAST(ROUND((CAST(tw.ExecutionCount - ISNULL(lw.ExecutionCount, 0) AS DECIMAL(18,2)) / NULLIF(lw.ExecutionCount, 0)) * 100, 1) AS DECIMAL(10,1))
                END AS ExecutionChangePct,
                (tw.AvgDurationMs - ISNULL(lw.AvgDurationMs, 0)) * tw.ExecutionCount AS CpuImpactMs
            FROM (
                SELECT DatabaseName, QueryHash, QueryText, 
                    AVG(AvgDurationMs) AS AvgDurationMs, SUM(ExecutionCount) AS ExecutionCount
                FROM [monitor].[TopQueriesHistory]
                WHERE CollectedAt >= DATEADD(HOUR, -168, SYSUTCDATETIME())
                GROUP BY DatabaseName, QueryHash, QueryText
            ) tw
            LEFT JOIN (
                SELECT DatabaseName, QueryHash, QueryText,
                    AVG(AvgDurationMs) AS AvgDurationMs, SUM(ExecutionCount) AS ExecutionCount
                FROM [monitor].[TopQueriesHistory]
                WHERE CollectedAt >= DATEADD(HOUR, -336, SYSUTCDATETIME()) 
                    AND CollectedAt < DATEADD(HOUR, -168, SYSUTCDATETIME())
                GROUP BY DatabaseName, QueryHash, QueryText
            ) lw ON tw.DatabaseName = lw.DatabaseName AND tw.QueryHash = lw.QueryHash
            WHERE tw.AvgDurationMs > ISNULL(lw.AvgDurationMs, 0) * 1.2  -- 20% degradation
                AND tw.ExecutionCount >= @MinExecutionCount
        ) degraded
        ORDER BY CpuImpactMs DESC;
    END
    ELSE IF @AnalysisType = 'ResourceCorrelation'
    BEGIN
        -- Resource correlation analysis
        SELECT 
            time_slot.TimeSlot,
            time_slot.CpuAvg,
            time_slot.CpuMax,
            time_slot.PleAvg,
            time_slot.PleMin,
            time_slot.DiskReadMB,
            time_slot.DiskWriteMB,
            time_slot.ReadRequests,
            time_slot.WriteRequests,
            time_slot.QueryCount,
            -- Correlation calculations
            CASE 
                WHEN time_slot.PleAvg < 300 AND time_slot.CpuAvg > 70 THEN 'CPU-Bound'
                WHEN time_slot.PleAvg < 100 AND time_slot.CpuAvg > 50 THEN 'Memory-Bound'
                WHEN time_slot.DiskReadMB > 1024 AND time_slot.ReadRequests > 10000 THEN 'IO-Bound'
                ELSE 'Balanced'
            END AS BottleneckType,
            -- Resource pressure score (0-100)
            ( 
                (time_slot.CpuAvg / 100.0) * 30 +
                (CASE WHEN time_slot.PleAvg < 300 THEN 100 ELSE 0 END / 100.0) * 30 +
                (MIN(time_slot.DiskReadMB / 1024.0, 1)) * 40
            ) AS ResourcePressureScore
        FROM (
            -- 1-hour time slots
            SELECT 
                DATEADD(HOUR, DATEDIFF(HOUR, 0, CollectedAt), 0) AS TimeSlot,
                AVG(SqlCpuPct) AS CpuAvg,
                MAX(SqlCpuPct) AS CpuMax,
                AVG(PageLifeExpectancy) AS PleAvg,
                MIN(PageLifeExpectancy) AS PleMin,
                SUM(PhysicalReadsMB) AS DiskReadMB,
                SUM(PhysicalWritesMB) AS DiskWriteMB,
                SUM(ReadRequests) AS ReadRequests,
                SUM(WriteRequests) AS WriteRequests,
                COUNT(DISTINCT QueryHash) AS QueryCount
            FROM [monitor].[TopQueriesHistory] q
            JOIN [monitor].[CpuHistory] c ON q.CollectedAt = c.CollectedAt
            WHERE q.CollectedAt >= @AnalysisStartTime
                AND (@DatabaseName IS NULL OR q.DatabaseName = @DatabaseName)
            GROUP BY DATEADD(HOUR, DATEDIFF(HOUR, 0, CollectedAt), 0)
        ) time_slot
        ORDER BY time_slot.TimeSlot DESC;

        -- Resource correlation matrix
        SELECT 
            'CPU vs Memory' AS CorrelationType,
            CAST(AVG(CpuAvg) AS DECIMAL(10,2)) AS Resource1_Avg,
            CAST(AVG(PleAvg) AS DECIMAL(10,2)) AS Resource2_Avg,
            CAST(CORR(CpuAvg, PleAvg) AS DECIMAL(10,4)) AS CorrelationCoefficient,
            CASE 
                WHEN CORR(CpuAvg, PleAvg) < -0.5 THEN 'Strong Negative'
                WHEN CORR(CpuAvg, PleAvg) < -0.2 THEN 'Moderate Negative'
                WHEN CORR(CpuAvg, PleAvg) > 0.5 THEN 'Strong Positive'
                WHEN CORR(CpuAvg, PleAvg) > 0.2 THEN 'Moderate Positive'
                ELSE 'Weak'
            END AS CorrelationStrength
        FROM [monitor].[CpuHistory] c
        JOIN [monitor].[MemoryHistory] m ON c.CollectedAt = m.CollectedAt
        WHERE c.CollectedAt >= @AnalysisStartTime
            AND (@DatabaseName IS NULL OR EXISTS (
                SELECT 1 FROM [monitor].[TopQueriesHistory] q 
                WHERE q.CollectedAt = c.CollectedAt AND q.DatabaseName = @DatabaseName
            ));

        SELECT 
            'CPU vs IO' AS CorrelationType,
            CAST(AVG(SqlCpuPct) AS DECIMAL(10,2)) AS Resource1_Avg,
            CAST(AVG(PhysicalReadsMB + PhysicalWritesMB) AS DECIMAL(10,2)) AS Resource2_Avg,
            CAST(CORR(SqlCpuPct, PhysicalReadsMB + PhysicalWritesMB) AS DECIMAL(10,4)) AS CorrelationCoefficient
        FROM [monitor].[CpuHistory] c
        JOIN [monitor].[TopQueriesHistory] q ON c.CollectedAt = q.CollectedAt
        WHERE q.CollectedAt >= @AnalysisStartTime
            AND (@DatabaseName IS NULL OR q.DatabaseName = @DatabaseName);
    END
    ELSE IF @AnalysisType = 'SeasonalPatterns'
    BEGIN
        -- Seasonal pattern detection
        SELECT 
            DATEPART(HOUR, CollectedAt) AS HourOfDay,
            DATEPART(WEEKDAY, CollectedAt) AS DayOfWeek,
            COUNT(*) AS CollectionCount,
            AVG(SqlCpuPct) AS AvgCpu,
            AVG(PageLifeExpectancy) AS AvgPle,
            AVG(PhysicalReadsMB) AS AvgReadsMB,
            AVG(PhysicalWritesMB) AS AvgWritesMB,
            -- Peak detection
            CASE 
                WHEN AVG(SqlCpuPct) > 80 THEN 'Peak'
                WHEN AVG(SqlCpuPct) > 60 THEN 'High'
                WHEN AVG(SqlCpuPct) > 40 THEN 'Medium'
                ELSE 'Low'
            END AS LoadLevel,
            -- Pattern classification
            CASE 
                WHEN DATEPART(WEEKDAY, CollectedAt) IN (1, 7) THEN 'Weekend'
                ELSE 'Weekday'
            END AS PeriodType
        FROM [monitor].[CpuHistory] c
        WHERE c.CollectedAt >= @AnalysisStartTime
            AND (@DatabaseName IS NULL OR EXISTS (
                SELECT 1 FROM [monitor].[TopQueriesHistory] q 
                WHERE q.CollectedAt = c.CollectedAt AND q.DatabaseName = @DatabaseName
            ))
        GROUP BY DATEPART(HOUR, CollectedAt), DATEPART(WEEKDAY, CollectedAt)
        ORDER BY DayOfWeek, HourOfDay;

        -- Hourly trend analysis
        SELECT 
            HourOfDay,
            Weekday,
            CpuAvg,
            CpuTrend,
            PLEAvg,
            PLETrend,
            IOAvg,
            IOTrend,
            PeakHours
        FROM (
            SELECT 
                DATEPART(HOUR, CollectedAt) AS HourOfDay,
                CASE 
                    WHEN DATEPART(WEEKDAY, CollectedAt) IN (1, 7) THEN 'Weekend'
                    ELSE 'Weekday'
                END AS Weekday,
                AVG(SqlCpuPct) AS CpuAvg,
                -- Trend calculation (last 3 collections)
                CASE 
                    WHEN COUNT(*) >= 3 THEN
                        AVG(SqlCpuPct) - 
                        AVG(SqlCpuPct) OVER (
                            ORDER BY CollectedAt 
                            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
                        )
                    ELSE 0
                END AS CpuTrend,
                AVG(PageLifeExpectancy) AS PLEAvg,
                CASE 
                    WHEN COUNT(*) >= 3 THEN
                        AVG(PageLifeExpectancy) - 
                        AVG(PageLifeExpectancy) OVER (
                            ORDER BY CollectedAt 
                            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
                        )
                    ELSE 0
                END AS PLETrend,
                AVG(PhysicalReadsMB + PhysicalWritesMB) AS IOAvg,
                CASE 
                    WHEN COUNT(*) >= 3 THEN
                        AVG(PhysicalReadsMB + PhysicalWritesMB) - 
                        AVG(PhysicalReadsMB + PhysicalWritesMB) OVER (
                            ORDER BY CollectedAt 
                            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
                        )
                    ELSE 0
                END AS IOTrend,
                CASE 
                    WHEN AVG(SqlCpuPct) > 80 THEN 1
                    WHEN AVG(SqlCpuPct) > 60 THEN 1
                    ELSE 0
                END AS PeakHours
            FROM [monitor].[CpuHistory]
            WHERE CollectedAt >= @AnalysisStartTime
                AND (@DatabaseName IS NULL OR EXISTS (
                    SELECT 1 FROM [monitor].[TopQueriesHistory] q 
                    WHERE q.CollectedAt = CollectedAt AND q.DatabaseName = @DatabaseName
                ))
            GROUP BY DATEPART(HOUR, CollectedAt), 
                     CASE 
                         WHEN DATEPART(WEEKDAY, CollectedAt) IN (1, 7) THEN 'Weekend'
                         ELSE 'Weekday'
                     END,
                     DATEPART(HOUR, CollectedAt), DATEPART(WEEKDAY, CollectedAt)
        ) hourly
        ORDER BY Weekday, HourOfDay;
    END
    ELSE IF @AnalysisType = 'DegradationScore'
    BEGIN
        -- Performance degradation scoring
        DECLARE @DegradationScore TABLE (
            DatabaseName NVARCHAR(128),
            DegradationScore INT,
            PerformanceGrade NVARCHAR(10),
            Issues NVARCHAR(MAX),
            Recommendations NVARCHAR(MAX)
        );

        -- Calculate degradation score for each database
        INSERT INTO @DegradationScore
        SELECT 
            d.DatabaseName,
            -- Score calculation (0-100, higher is worse)
            (
                -- CPU degradation (0-30 points)
                CASE 
                    WHEN MAX(c.SqlCpuPct) > 95 THEN 30
                    WHEN MAX(c.SqlCpuPct) > 80 THEN 20
                    WHEN MAX(c.SqlCpuPct) > 60 THEN 10
                    ELSE 0
                END +
                -- Memory degradation (0-30 points)
                CASE 
                    WHEN MIN(m.PageLifeExpectancy) < 100 THEN 30
                    WHEN MIN(m.PageLifeExpectancy) < 300 THEN 15
                    WHEN MIN(m.PageLifeExpectancy) < 1000 THEN 5
                    ELSE 0
                END +
                -- Query performance degradation (0-20 points)
                CASE 
                    WHEN AVG(q.AvgDurationMs) > 5000 THEN 20
                    WHEN AVG(q.AvgDurationMs) > 2000 THEN 10
                    WHEN AVG(q.AvgDurationMs) > 1000 THEN 5
                    ELSE 0
                END +
                -- Blocking issues (0-10 points)
                CASE 
                    WHEN COUNT(bh.BlockingSpid) > 100 THEN 10
                    WHEN COUNT(bh.BlockingSpid) > 50 THEN 5
                    WHEN COUNT(bh.BlockingSpid) > 10 THEN 2
                    ELSE 0
                END +
                -- Error rate (0-10 points)
                CASE 
                    WHEN COUNT(elh.Severity) > 50 THEN 10
                    WHEN COUNT(elh.Severity) > 20 THEN 5
                    WHEN COUNT(elh.Severity) > 5 THEN 2
                    ELSE 0
                END +
                -- Disk pressure (0-10 points)
                CASE 
                    WHEN MAX(dh.UsedPct) > 95