/*
    SQL Health Monitor - Update Performance Baselines
    Recalculates performance baselines from historical data.

    Baselines are used by the weekly report and anomaly detection to identify deviations.
    Uses the last 4 weeks of data for stable baselines.

    Schedule: Sunday 2:00 AM
    Compatibility: SQL Server 2012+
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

IF OBJECT_ID('[monitor].[usp_Maintenance_UpdateBaselines]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Maintenance_UpdateBaselines] @LookbackDays INT = 28, @DebugMode BIT = 0 AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Maintenance_UpdateBaselines]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_Maintenance_UpdateBaselines] @LookbackDays INT = 28, @DebugMode BIT = 0 AS SET NOCOUNT ON; PRINT ''Placeholder'';');
GO

ALTER PROCEDURE [monitor].[usp_Maintenance_UpdateBaselines]
    @LookbackDays INT = 28,
    @DebugMode    BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartDate DATETIME2 = DATEADD(DAY, -@LookbackDays, SYSUTCDATETIME());
    DECLARE @Now       DATETIME2 = SYSUTCDATETIME();

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
    ;WITH src AS (
        SELECT CAST(SqlCpuPct AS DECIMAL(18,2)) AS val
        FROM [monitor].[CpuHistory]
        WHERE CollectedAt >= @StartDate
    ),
    stats AS (
        SELECT COUNT(*) AS cnt, AVG(val) AS avg_val, MIN(val) AS min_val, MAX(val) AS max_val
        FROM src
    ),
    ranked AS (
        SELECT val, ROW_NUMBER() OVER (ORDER BY val) AS rn, s.cnt
        FROM src CROSS JOIN stats s
    )
    INSERT INTO @NewBaselines (MetricName, AvgVal, P50Val, P95Val, MinVal, MaxVal, SampleCount)
    SELECT TOP 1
        'CPU_Avg', s.avg_val,
        (SELECT TOP 1 val FROM ranked ORDER BY ABS(CAST(rn AS FLOAT) - (s.cnt + 1.0) / 2)),
        (SELECT TOP 1 val FROM ranked ORDER BY ABS(CAST(rn AS FLOAT) - s.cnt * 0.95)),
        s.min_val, s.max_val, s.cnt
    FROM stats s;

    -- ============================================================
    -- PLE Baseline
    -- ============================================================
    ;WITH src AS (
        SELECT CAST(PageLifeExpectancy AS DECIMAL(18,2)) AS val
        FROM [monitor].[MemoryHistory]
        WHERE CollectedAt >= @StartDate
    ),
    stats AS (
        SELECT COUNT(*) AS cnt, AVG(val) AS avg_val, MIN(val) AS min_val, MAX(val) AS max_val
        FROM src
    ),
    ranked AS (
        SELECT val, ROW_NUMBER() OVER (ORDER BY val) AS rn, s.cnt
        FROM src CROSS JOIN stats s
    )
    INSERT INTO @NewBaselines (MetricName, AvgVal, P50Val, P95Val, MinVal, MaxVal, SampleCount)
    SELECT TOP 1
        'PLE_Avg', s.avg_val,
        (SELECT TOP 1 val FROM ranked ORDER BY ABS(CAST(rn AS FLOAT) - (s.cnt + 1.0) / 2)),
        (SELECT TOP 1 val FROM ranked ORDER BY ABS(CAST(rn AS FLOAT) - s.cnt * 0.95)),
        s.min_val, s.max_val, s.cnt
    FROM stats s;

    -- ============================================================
    -- Disk Used % Baseline (max across drives per collection)
    -- ============================================================
    ;WITH src AS (
        SELECT CAST(MaxUsedPct AS DECIMAL(18,2)) AS val
        FROM (
            SELECT CollectedAt, MAX(UsedPct) AS MaxUsedPct
            FROM [monitor].[DiskHistory]
            WHERE CollectedAt >= @StartDate
            GROUP BY CollectedAt
        ) d
    ),
    stats AS (
        SELECT COUNT(*) AS cnt, AVG(val) AS avg_val, MIN(val) AS min_val, MAX(val) AS max_val
        FROM src
    ),
    ranked AS (
        SELECT val, ROW_NUMBER() OVER (ORDER BY val) AS rn, s.cnt
        FROM src CROSS JOIN stats s
    )
    INSERT INTO @NewBaselines (MetricName, AvgVal, P50Val, P95Val, MinVal, MaxVal, SampleCount)
    SELECT TOP 1
        'DiskUsed_Max', s.avg_val,
        (SELECT TOP 1 val FROM ranked ORDER BY ABS(CAST(rn AS FLOAT) - (s.cnt + 1.0) / 2)),
        (SELECT TOP 1 val FROM ranked ORDER BY ABS(CAST(rn AS FLOAT) - s.cnt * 0.95)),
        s.min_val, s.max_val, s.cnt
    FROM stats s;

    -- ============================================================
    -- Blocking Frequency Baseline (events per day)
    -- ============================================================
    ;WITH src AS (
        SELECT CAST(DailyCount AS DECIMAL(18,2)) AS val
        FROM (
            SELECT CAST(DetectedAt AS DATE) AS Day, COUNT(*) AS DailyCount
            FROM [monitor].[BlockingHistory]
            WHERE DetectedAt >= @StartDate
            GROUP BY CAST(DetectedAt AS DATE)
        ) b
    ),
    stats AS (
        SELECT COUNT(*) AS cnt, AVG(val) AS avg_val, MIN(val) AS min_val, MAX(val) AS max_val
        FROM src
    ),
    ranked AS (
        SELECT val, ROW_NUMBER() OVER (ORDER BY val) AS rn, s.cnt
        FROM src CROSS JOIN stats s
    )
    INSERT INTO @NewBaselines (MetricName, AvgVal, P50Val, P95Val, MinVal, MaxVal, SampleCount)
    SELECT TOP 1
        'Blocking_PerDay', s.avg_val,
        (SELECT TOP 1 val FROM ranked ORDER BY ABS(CAST(rn AS FLOAT) - (s.cnt + 1.0) / 2)),
        (SELECT TOP 1 val FROM ranked ORDER BY ABS(CAST(rn AS FLOAT) - s.cnt * 0.95)),
        s.min_val, s.max_val, s.cnt
    FROM stats s;

    -- ============================================================
    -- Wait Time Baseline (total delta per collection)
    -- ============================================================
    ;WITH src AS (
        SELECT CAST(TotalDelta AS DECIMAL(18,2)) AS val
        FROM (
            SELECT CollectedAt, SUM(ISNULL(DeltaWaitTimeMs, 0)) AS TotalDelta
            FROM [monitor].[WaitStatsHistory]
            WHERE CollectedAt >= @StartDate
            GROUP BY CollectedAt
        ) w
    ),
    stats AS (
        SELECT COUNT(*) AS cnt, AVG(val) AS avg_val, MIN(val) AS min_val, MAX(val) AS max_val
        FROM src
    ),
    ranked AS (
        SELECT val, ROW_NUMBER() OVER (ORDER BY val) AS rn, s.cnt
        FROM src CROSS JOIN stats s
    )
    INSERT INTO @NewBaselines (MetricName, AvgVal, P50Val, P95Val, MinVal, MaxVal, SampleCount)
    SELECT TOP 1
        'Waits_TotalDeltaMs', s.avg_val,
        (SELECT TOP 1 val FROM ranked ORDER BY ABS(CAST(rn AS FLOAT) - (s.cnt + 1.0) / 2)),
        (SELECT TOP 1 val FROM ranked ORDER BY ABS(CAST(rn AS FLOAT) - s.cnt * 0.95)),
        s.min_val, s.max_val, s.cnt
    FROM stats s;

    -- ============================================================
    -- MERGE INTO BASELINES TABLE
    -- ============================================================
    MERGE [monitor].[PerformanceBaselines] AS target
    USING @NewBaselines AS source ON target.MetricName = source.MetricName
    WHEN MATCHED THEN
        UPDATE SET
            BaselineAvg  = source.AvgVal,
            BaselineP50  = source.P50Val,
            BaselineP95  = source.P95Val,
            BaselineMin  = source.MinVal,
            BaselineMax  = source.MaxVal,
            SampleCount  = source.SampleCount,
            CalculatedAt = @Now,
            IsActive     = 1
    WHEN NOT MATCHED THEN
        INSERT (MetricName, BaselineAvg, BaselineP50, BaselineP95, BaselineMin, BaselineMax, SampleCount, CalculatedAt, IsActive)
        VALUES (source.MetricName, source.AvgVal, source.P50Val, source.P95Val, source.MinVal, source.MaxVal, source.SampleCount, @Now, 1);

    IF @DebugMode = 1
        SELECT * FROM [monitor].[PerformanceBaselines] WHERE IsActive = 1 ORDER BY MetricName;

    INSERT INTO [monitor].[ErrorLogHistory] (LogDate, ProcessInfo, ErrorMessage, Severity)
    VALUES (@Now, 'Maintenance',
        'Baselines updated: ' + CAST((SELECT COUNT(*) FROM @NewBaselines) AS NVARCHAR(10))
        + ' metrics recalculated from ' + CAST(@LookbackDays AS NVARCHAR(10)) + ' days of data.',
        'Info');

    PRINT 'Baselines updated successfully.';
END;
GO

PRINT 'usp_Maintenance_UpdateBaselines deployed.';
GO
