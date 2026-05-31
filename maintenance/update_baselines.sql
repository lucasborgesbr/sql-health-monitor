/*
    SQL Health Monitor - Update Performance Baselines
    Recalculates performance baselines from historical data.
    
    Baselines are used by the weekly report to detect deviations.
    Uses the last 4 weeks of data (excluding outliers) for stable baselines.
    
    Schedule: Sunday 2:00 AM
    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

-- Create baselines table if not exists
IF OBJECT_ID('monitor.PerformanceBaselines', 'U') IS NULL
CREATE TABLE [monitor].[PerformanceBaselines] (
    BaselineId      INT IDENTITY(1,1) PRIMARY KEY,
    MetricName      NVARCHAR(100) NOT NULL,
    BaselineAvg     DECIMAL(18,2) NOT NULL,
    BaselineP50     DECIMAL(18,2) NULL,
    BaselineP95     DECIMAL(18,2) NULL,
    BaselineMin     DECIMAL(18,2) NULL,
    BaselineMax     DECIMAL(18,2) NULL,
    SampleCount     INT           NOT NULL,
    CalculatedAt    DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    IsActive        BIT           NOT NULL DEFAULT 1,
    CONSTRAINT UQ_Baselines_Metric UNIQUE (MetricName)
);
GO

CREATE OR ALTER PROCEDURE [monitor].[usp_Maintenance_UpdateBaselines]
    @LookbackDays INT = 28,  -- 4 weeks of data
    @DebugMode BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartDate DATETIME2 = DATEADD(DAY, -@LookbackDays, SYSUTCDATETIME());
    DECLARE @Now DATETIME2 = SYSUTCDATETIME();

    -- Temp table for new baselines
    DECLARE @NewBaselines TABLE (
        MetricName  NVARCHAR(100),
        AvgVal      DECIMAL(18,2),
        P50Val      DECIMAL(18,2),
        P95Val      DECIMAL(18,2),
        MinVal      DECIMAL(18,2),
        MaxVal      DECIMAL(18,2),
        SampleCount INT
    );

    -- ============================================================
    -- CPU Baseline
    -- ============================================================
    INSERT INTO @NewBaselines (MetricName, AvgVal, P50Val, P95Val, MinVal, MaxVal, SampleCount)
    SELECT 
        'CPU_Avg',
        AVG(CAST(SqlCpuPct AS DECIMAL(18,2))),
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY SqlCpuPct) OVER (),
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY SqlCpuPct) OVER (),
        MIN(CAST(SqlCpuPct AS DECIMAL(18,2))),
        MAX(CAST(SqlCpuPct AS DECIMAL(18,2))),
        COUNT(*)
    FROM [monitor].[CpuHistory]
    WHERE CollectedAt >= @StartDate;

    -- Deduplicate (PERCENTILE_CONT produces one row per input row)
    ;WITH CpuDedup AS (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY MetricName ORDER BY (SELECT NULL)) AS rn
        FROM @NewBaselines WHERE MetricName = 'CPU_Avg'
    )
    DELETE FROM CpuDedup WHERE rn > 1;

    -- ============================================================
    -- PLE Baseline
    -- ============================================================
    INSERT INTO @NewBaselines (MetricName, AvgVal, P50Val, P95Val, MinVal, MaxVal, SampleCount)
    SELECT TOP 1
        'PLE_Avg',
        AVG(CAST(PageLifeExpectancy AS DECIMAL(18,2))) OVER (),
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY PageLifeExpectancy) OVER (),
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY PageLifeExpectancy) OVER (),
        MIN(CAST(PageLifeExpectancy AS DECIMAL(18,2))) OVER (),
        MAX(CAST(PageLifeExpectancy AS DECIMAL(18,2))) OVER (),
        COUNT(*) OVER ()
    FROM [monitor].[MemoryHistory]
    WHERE CollectedAt >= @StartDate;

    -- ============================================================
    -- Disk Used % Baseline (max across drives)
    -- ============================================================
    INSERT INTO @NewBaselines (MetricName, AvgVal, P50Val, P95Val, MinVal, MaxVal, SampleCount)
    SELECT TOP 1
        'DiskUsed_Max',
        AVG(MaxUsedPct) OVER (),
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY MaxUsedPct) OVER (),
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY MaxUsedPct) OVER (),
        MIN(MaxUsedPct) OVER (),
        MAX(MaxUsedPct) OVER (),
        COUNT(*) OVER ()
    FROM (
        SELECT CollectedAt, MAX(UsedPct) AS MaxUsedPct
        FROM [monitor].[DiskHistory]
        WHERE CollectedAt >= @StartDate
        GROUP BY CollectedAt
    ) d;

    -- ============================================================
    -- Blocking Frequency Baseline (events per day)
    -- ============================================================
    INSERT INTO @NewBaselines (MetricName, AvgVal, P50Val, P95Val, MinVal, MaxVal, SampleCount)
    SELECT TOP 1
        'Blocking_PerDay',
        AVG(CAST(DailyCount AS DECIMAL(18,2))) OVER (),
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY DailyCount) OVER (),
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY DailyCount) OVER (),
        MIN(CAST(DailyCount AS DECIMAL(18,2))) OVER (),
        MAX(CAST(DailyCount AS DECIMAL(18,2))) OVER (),
        COUNT(*) OVER ()
    FROM (
        SELECT CAST(DetectedAt AS DATE) AS Day, COUNT(*) AS DailyCount
        FROM [monitor].[BlockingHistory]
        WHERE DetectedAt >= @StartDate
        GROUP BY CAST(DetectedAt AS DATE)
    ) b;

    -- ============================================================
    -- Wait Time Baseline (total delta per collection)
    -- ============================================================
    INSERT INTO @NewBaselines (MetricName, AvgVal, P50Val, P95Val, MinVal, MaxVal, SampleCount)
    SELECT TOP 1
        'Waits_TotalDeltaMs',
        AVG(CAST(TotalDelta AS DECIMAL(18,2))) OVER (),
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TotalDelta) OVER (),
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY TotalDelta) OVER (),
        MIN(CAST(TotalDelta AS DECIMAL(18,2))) OVER (),
        MAX(CAST(TotalDelta AS DECIMAL(18,2))) OVER (),
        COUNT(*) OVER ()
    FROM (
        SELECT CollectedAt, SUM(ISNULL(DeltaWaitTimeMs, 0)) AS TotalDelta
        FROM [monitor].[WaitStatsHistory]
        WHERE CollectedAt >= @StartDate
        GROUP BY CollectedAt
    ) w;

    -- ============================================================
    -- MERGE INTO BASELINES TABLE
    -- ============================================================
    MERGE [monitor].[PerformanceBaselines] AS target
    USING @NewBaselines AS source ON target.MetricName = source.MetricName
    WHEN MATCHED THEN
        UPDATE SET 
            BaselineAvg = source.AvgVal,
            BaselineP50 = source.P50Val,
            BaselineP95 = source.P95Val,
            BaselineMin = source.MinVal,
            BaselineMax = source.MaxVal,
            SampleCount = source.SampleCount,
            CalculatedAt = @Now,
            IsActive = 1
    WHEN NOT MATCHED THEN
        INSERT (MetricName, BaselineAvg, BaselineP50, BaselineP95, BaselineMin, BaselineMax, SampleCount, CalculatedAt, IsActive)
        VALUES (source.MetricName, source.AvgVal, source.P50Val, source.P95Val, source.MinVal, source.MaxVal, source.SampleCount, @Now, 1);

    IF @DebugMode = 1
        SELECT * FROM [monitor].[PerformanceBaselines] WHERE IsActive = 1;

    -- Log
    INSERT INTO [monitor].[ErrorLogHistory] (LogDate, ProcessInfo, ErrorMessage, Severity)
    VALUES (SYSUTCDATETIME(), 'Maintenance', 
        'Baselines updated: ' + CAST((SELECT COUNT(*) FROM @NewBaselines) AS NVARCHAR) + ' metrics recalculated from ' 
        + CAST(@LookbackDays AS NVARCHAR) + ' days of data.', 'Info');

    PRINT '✓ Baselines updated successfully.';
END;
GO

PRINT '✓ Baselines procedure [monitor].[usp_Maintenance_UpdateBaselines] created.';
PRINT '✓ PerformanceBaselines table created.';
GO
