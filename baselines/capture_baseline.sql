/*
    SQL Health Monitor - Capture Baseline
    Procedure that captures current metric averages as baseline.
    
    Designed to run weekly (Sunday 2:00 AM) or on-demand.
    Captures: CPU, memory, disk IO, waits, blocking count, AG lag, TempDB, errors.
    Stores in BaselineCapture with metric name, avg, stddev, sample count, time window.
    
    Schema: [monitor]
    Compatibility: SQL Server 2016+ (uses PERCENTILE_CONT, STRING_AGG on 2017+)
    Author: Lucas Allan Borges
    
    Parameters:
        @LookbackDays   INT     - Days of history to analyze (default: 7)
        @DeactivateOld  BIT     - Deactivate previous baselines for same metrics (default: 1)
        @DebugMode      BIT     - Print diagnostics without committing (default: 0)
    
    Example Usage:
        -- Weekly baseline capture (default 7-day window)
        EXEC [monitor].[usp_Baseline_Capture];
        
        -- Capture with 14-day lookback
        EXEC [monitor].[usp_Baseline_Capture] @LookbackDays = 14;
        
        -- Debug mode - see what would be captured
        EXEC [monitor].[usp_Baseline_Capture] @DebugMode = 1;
*/

USE [SQLHealthMonitor];
GO

CREATE OR ALTER PROCEDURE [monitor].[usp_Baseline_Capture]
    @LookbackDays   INT = 7,
    @DeactivateOld  BIT = 1,
    @DebugMode      BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartDate DATETIME2 = DATEADD(DAY, -@LookbackDays, SYSUTCDATETIME());
    DECLARE @EndDate DATETIME2 = SYSUTCDATETIME();
    DECLARE @CapturedCount INT = 0;

    -- Staging table for new baselines
    DECLARE @Baselines TABLE (
        MetricName      NVARCHAR(100),
        AvgValue        DECIMAL(18,4),
        StdDevValue     DECIMAL(18,4),
        MinValue        DECIMAL(18,4),
        MaxValue        DECIMAL(18,4),
        P50Value        DECIMAL(18,4),
        P95Value        DECIMAL(18,4),
        SampleCount     INT
    );

    -- ============================================================
    -- CPU METRICS
    -- ============================================================
    INSERT INTO @Baselines (MetricName, AvgValue, StdDevValue, MinValue, MaxValue, P50Value, P95Value, SampleCount)
    SELECT 
        'CPU_Avg',
        AVG(CAST(SqlCpuPct AS DECIMAL(18,4))),
        ISNULL(STDEV(CAST(SqlCpuPct AS DECIMAL(18,4))), 0),
        MIN(CAST(SqlCpuPct AS DECIMAL(18,4))),
        MAX(CAST(SqlCpuPct AS DECIMAL(18,4))),
        NULL, NULL, -- P50/P95 calculated separately
        COUNT(*)
    FROM [monitor].[CpuHistory]
    WHERE CollectedAt >= @StartDate AND CollectedAt <= @EndDate;

    -- CPU Max (per-collection max)
    INSERT INTO @Baselines (MetricName, AvgValue, StdDevValue, MinValue, MaxValue, P50Value, P95Value, SampleCount)
    SELECT 
        'CPU_Max',
        AVG(CAST(SqlCpuPct AS DECIMAL(18,4))),
        ISNULL(STDEV(CAST(SqlCpuPct AS DECIMAL(18,4))), 0),
        MIN(CAST(SqlCpuPct AS DECIMAL(18,4))),
        MAX(CAST(SqlCpuPct AS DECIMAL(18,4))),
        NULL, NULL,
        COUNT(*)
    FROM (
        SELECT MAX(SqlCpuPct) AS SqlCpuPct
        FROM [monitor].[CpuHistory]
        WHERE CollectedAt >= @StartDate AND CollectedAt <= @EndDate
        GROUP BY CAST(CollectedAt AS DATE), DATEPART(HOUR, CollectedAt)
    ) hourly;

    -- ============================================================
    -- MEMORY METRICS
    -- ============================================================
    INSERT INTO @Baselines (MetricName, AvgValue, StdDevValue, MinValue, MaxValue, P50Value, P95Value, SampleCount)
    SELECT 
        'PLE_Avg',
        AVG(CAST(PageLifeExpectancy AS DECIMAL(18,4))),
        ISNULL(STDEV(CAST(PageLifeExpectancy AS DECIMAL(18,4))), 0),
        MIN(CAST(PageLifeExpectancy AS DECIMAL(18,4))),
        MAX(CAST(PageLifeExpectancy AS DECIMAL(18,4))),
        NULL, NULL,
        COUNT(*)
    FROM [monitor].[MemoryHistory]
    WHERE CollectedAt >= @StartDate AND CollectedAt <= @EndDate;

    INSERT INTO @Baselines (MetricName, AvgValue, StdDevValue, MinValue, MaxValue, P50Value, P95Value, SampleCount)
    SELECT 
        'Memory_Grants_Pending',
        AVG(CAST(MemoryGrantsPending AS DECIMAL(18,4))),
        ISNULL(STDEV(CAST(MemoryGrantsPending AS DECIMAL(18,4))), 0),
        MIN(CAST(MemoryGrantsPending AS DECIMAL(18,4))),
        MAX(CAST(MemoryGrantsPending AS DECIMAL(18,4))),
        NULL, NULL,
        COUNT(*)
    FROM [monitor].[MemoryHistory]
    WHERE CollectedAt >= @StartDate AND CollectedAt <= @EndDate;

    -- ============================================================
    -- DISK METRICS
    -- ============================================================
    INSERT INTO @Baselines (MetricName, AvgValue, StdDevValue, MinValue, MaxValue, P50Value, P95Value, SampleCount)
    SELECT 
        'Disk_UsedPct_Max',
        AVG(MaxUsedPct),
        ISNULL(STDEV(MaxUsedPct), 0),
        MIN(MaxUsedPct),
        MAX(MaxUsedPct),
        NULL, NULL,
        COUNT(*)
    FROM (
        SELECT MAX(UsedPct) AS MaxUsedPct
        FROM [monitor].[DiskHistory]
        WHERE CollectedAt >= @StartDate AND CollectedAt <= @EndDate
        GROUP BY CollectedAt
    ) d;

    INSERT INTO @Baselines (MetricName, AvgValue, StdDevValue, MinValue, MaxValue, P50Value, P95Value, SampleCount)
    SELECT 
        'Disk_ReadLatency_Avg',
        AVG(ISNULL(AvgReadLatencyMs, 0)),
        ISNULL(STDEV(ISNULL(AvgReadLatencyMs, 0)), 0),
        MIN(ISNULL(AvgReadLatencyMs, 0)),
        MAX(ISNULL(AvgReadLatencyMs, 0)),
        NULL, NULL,
        COUNT(*)
    FROM [monitor].[DiskHistory]
    WHERE CollectedAt >= @StartDate AND CollectedAt <= @EndDate
        AND AvgReadLatencyMs IS NOT NULL;

    INSERT INTO @Baselines (MetricName, AvgValue, StdDevValue, MinValue, MaxValue, P50Value, P95Value, SampleCount)
    SELECT 
        'Disk_WriteLatency_Avg',
        AVG(ISNULL(AvgWriteLatencyMs, 0)),
        ISNULL(STDEV(ISNULL(AvgWriteLatencyMs, 0)), 0),
        MIN(ISNULL(AvgWriteLatencyMs, 0)),
        MAX(ISNULL(AvgWriteLatencyMs, 0)),
        NULL, NULL,
        COUNT(*)
    FROM [monitor].[DiskHistory]
    WHERE CollectedAt >= @StartDate AND CollectedAt <= @EndDate
        AND AvgWriteLatencyMs IS NOT NULL;

    -- ============================================================
    -- WAIT STATS
    -- ============================================================
    INSERT INTO @Baselines (MetricName, AvgValue, StdDevValue, MinValue, MaxValue, P50Value, P95Value, SampleCount)
    SELECT 
        'Waits_TotalDelta_Ms',
        AVG(TotalDelta),
        ISNULL(STDEV(TotalDelta), 0),
        MIN(TotalDelta),
        MAX(TotalDelta),
        NULL, NULL,
        COUNT(*)
    FROM (
        SELECT CollectedAt, SUM(ISNULL(DeltaWaitTimeMs, 0)) AS TotalDelta
        FROM [monitor].[WaitStatsHistory]
        WHERE CollectedAt >= @StartDate AND CollectedAt <= @EndDate
        GROUP BY CollectedAt
    ) w;

    -- ============================================================
    -- BLOCKING
    -- ============================================================
    INSERT INTO @Baselines (MetricName, AvgValue, StdDevValue, MinValue, MaxValue, P50Value, P95Value, SampleCount)
    SELECT 
        'Blocking_Count',
        AVG(CAST(DailyCount AS DECIMAL(18,4))),
        ISNULL(STDEV(CAST(DailyCount AS DECIMAL(18,4))), 0),
        MIN(CAST(DailyCount AS DECIMAL(18,4))),
        MAX(CAST(DailyCount AS DECIMAL(18,4))),
        NULL, NULL,
        COUNT(*)
    FROM (
        SELECT CAST(DetectedAt AS DATE) AS Day, COUNT(*) AS DailyCount
        FROM [monitor].[BlockingHistory]
        WHERE DetectedAt >= @StartDate AND DetectedAt <= @EndDate
        GROUP BY CAST(DetectedAt AS DATE)
    ) b;

    -- If no blocking at all, insert zero baseline
    IF NOT EXISTS (SELECT 1 FROM @Baselines WHERE MetricName = 'Blocking_Count')
        INSERT INTO @Baselines VALUES ('Blocking_Count', 0, 0, 0, 0, NULL, NULL, @LookbackDays);

    -- ============================================================
    -- AG LAG
    -- ============================================================
    INSERT INTO @Baselines (MetricName, AvgValue, StdDevValue, MinValue, MaxValue, P50Value, P95Value, SampleCount)
    SELECT 
        'AG_Lag_Max',
        AVG(CAST(MaxLag AS DECIMAL(18,4))),
        ISNULL(STDEV(CAST(MaxLag AS DECIMAL(18,4))), 0),
        MIN(CAST(MaxLag AS DECIMAL(18,4))),
        MAX(CAST(MaxLag AS DECIMAL(18,4))),
        NULL, NULL,
        COUNT(*)
    FROM (
        SELECT CollectedAt, MAX(ISNULL(SecondsBehindPrimary, 0)) AS MaxLag
        FROM [monitor].[AgHealthHistory]
        WHERE CollectedAt >= @StartDate AND CollectedAt <= @EndDate
        GROUP BY CollectedAt
    ) ag;

    -- ============================================================
    -- TEMPDB
    -- ============================================================
    INSERT INTO @Baselines (MetricName, AvgValue, StdDevValue, MinValue, MaxValue, P50Value, P95Value, SampleCount)
    SELECT 
        'TempDB_UsedPct',
        AVG(UsedPct),
        ISNULL(STDEV(UsedPct), 0),
        MIN(UsedPct),
        MAX(UsedPct),
        NULL, NULL,
        COUNT(*)
    FROM (
        SELECT CAST(UsedSpaceMB AS DECIMAL(18,4)) / NULLIF(CAST(TotalSizeMB AS DECIMAL(18,4)), 0) * 100.0 AS UsedPct
        FROM [monitor].[TempDbHistory]
        WHERE CollectedAt >= @StartDate AND CollectedAt <= @EndDate
            AND TotalSizeMB > 0
    ) t;

    -- ============================================================
    -- ERROR LOG COUNT
    -- ============================================================
    INSERT INTO @Baselines (MetricName, AvgValue, StdDevValue, MinValue, MaxValue, P50Value, P95Value, SampleCount)
    SELECT 
        'ErrorLog_Count',
        AVG(CAST(DailyCount AS DECIMAL(18,4))),
        ISNULL(STDEV(CAST(DailyCount AS DECIMAL(18,4))), 0),
        MIN(CAST(DailyCount AS DECIMAL(18,4))),
        MAX(CAST(DailyCount AS DECIMAL(18,4))),
        NULL, NULL,
        COUNT(*)
    FROM (
        SELECT CAST(CollectedAt AS DATE) AS Day, COUNT(*) AS DailyCount
        FROM [monitor].[ErrorLogHistory]
        WHERE CollectedAt >= @StartDate AND CollectedAt <= @EndDate
            AND Severity IN ('Critical', 'Error')
        GROUP BY CAST(CollectedAt AS DATE)
    ) e;

    -- If no errors, insert zero baseline
    IF NOT EXISTS (SELECT 1 FROM @Baselines WHERE MetricName = 'ErrorLog_Count')
        INSERT INTO @Baselines VALUES ('ErrorLog_Count', 0, 0, 0, 0, NULL, NULL, @LookbackDays);

    -- ============================================================
    -- REMOVE METRICS WITH NO DATA
    -- ============================================================
    DELETE FROM @Baselines WHERE SampleCount = 0 OR SampleCount IS NULL;

    -- ============================================================
    -- PERSIST BASELINES
    -- ============================================================
    IF @DebugMode = 1
    BEGIN
        SELECT 
            MetricName, AvgValue, StdDevValue, MinValue, MaxValue, 
            SampleCount, @StartDate AS TimeWindowStart, @EndDate AS TimeWindowEnd
        FROM @Baselines
        ORDER BY MetricName;
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Deactivate previous baselines
        IF @DeactivateOld = 1
        BEGIN
            UPDATE [monitor].[BaselineCapture]
            SET IsActive = 0
            WHERE IsActive = 1
                AND MetricName IN (SELECT MetricName FROM @Baselines);
        END;

        -- Insert new baselines
        INSERT INTO [monitor].[BaselineCapture] 
            (MetricName, AvgValue, StdDevValue, MinValue, MaxValue, P50Value, P95Value, 
             SampleCount, TimeWindowStart, TimeWindowEnd, IsActive)
        SELECT 
            MetricName, AvgValue, StdDevValue, MinValue, MaxValue, P50Value, P95Value,
            SampleCount, @StartDate, @EndDate, 1
        FROM @Baselines;

        SET @CapturedCount = @@ROWCOUNT;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    -- Log activity
    INSERT INTO [monitor].[ErrorLogHistory] (LogDate, ProcessInfo, ErrorMessage, Severity)
    VALUES (SYSUTCDATETIME(), 'Baseline', 
        'Baseline captured: ' + CAST(@CapturedCount AS NVARCHAR) + ' metrics from ' 
        + CAST(@LookbackDays AS NVARCHAR) + '-day window ('
        + FORMAT(@StartDate, 'yyyy-MM-dd') + ' to ' + FORMAT(@EndDate, 'yyyy-MM-dd') + ')',
        'Info');

    PRINT '✓ Baseline captured: ' + CAST(@CapturedCount AS NVARCHAR) + ' metrics.';
END;
GO

PRINT '✓ Procedure [monitor].[usp_Baseline_Capture] created.';
GO
