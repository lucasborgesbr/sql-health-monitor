/*
    SQL Health Monitor - Detect Anomalies
    Compares current collector data against baselines.
    Flags when current value > baseline_avg + (N * stddev).
    
    N is configurable per metric via BaselineConfig table.
    Returns anomalies with severity (warning/critical based on deviation multiplier).
    
    Schema: [monitor]
    Compatibility: SQL Server 2016+
    Author: Lucas Allan Borges
    
    Parameters:
        @LookbackMinutes INT    - Minutes of recent data to evaluate (default: 60)
        @PersistResults  BIT    - Write anomalies to BaselineAnomalies table (default: 1)
        @DebugMode       BIT    - Return all comparisons, not just anomalies (default: 0)
    
    Example Usage:
        -- Check for anomalies in last hour
        EXEC [monitor].[usp_Baseline_DetectAnomalies];
        
        -- Check last 30 minutes, don't persist
        EXEC [monitor].[usp_Baseline_DetectAnomalies] @LookbackMinutes = 30, @PersistResults = 0;
        
        -- Debug: see all metric comparisons
        EXEC [monitor].[usp_Baseline_DetectAnomalies] @DebugMode = 1;
*/

USE [DBA_Monitor];
GO

CREATE OR ALTER PROCEDURE [monitor].[usp_Baseline_DetectAnomalies]
    @LookbackMinutes INT = 60,
    @PersistResults  BIT = 1,
    @DebugMode       BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Since DATETIME2 = DATEADD(MINUTE, -@LookbackMinutes, SYSUTCDATETIME());
    DECLARE @Now DATETIME2 = SYSUTCDATETIME();

    -- ============================================================
    -- COLLECT CURRENT VALUES
    -- ============================================================
    DECLARE @CurrentMetrics TABLE (
        MetricName      NVARCHAR(100),
        CurrentValue    DECIMAL(18,4)
    );

    -- CPU Average
    INSERT INTO @CurrentMetrics (MetricName, CurrentValue)
    SELECT 'CPU_Avg', AVG(CAST(SqlCpuPct AS DECIMAL(18,4)))
    FROM [monitor].[CpuHistory]
    WHERE CollectedAt >= @Since
    HAVING COUNT(*) > 0;

    -- CPU Max
    INSERT INTO @CurrentMetrics (MetricName, CurrentValue)
    SELECT 'CPU_Max', MAX(CAST(SqlCpuPct AS DECIMAL(18,4)))
    FROM [monitor].[CpuHistory]
    WHERE CollectedAt >= @Since
    HAVING COUNT(*) > 0;

    -- PLE Average
    INSERT INTO @CurrentMetrics (MetricName, CurrentValue)
    SELECT 'PLE_Avg', AVG(CAST(PageLifeExpectancy AS DECIMAL(18,4)))
    FROM [monitor].[MemoryHistory]
    WHERE CollectedAt >= @Since
    HAVING COUNT(*) > 0;

    -- Memory Grants Pending
    INSERT INTO @CurrentMetrics (MetricName, CurrentValue)
    SELECT 'Memory_Grants_Pending', AVG(CAST(MemoryGrantsPending AS DECIMAL(18,4)))
    FROM [monitor].[MemoryHistory]
    WHERE CollectedAt >= @Since
    HAVING COUNT(*) > 0;

    -- Disk Used % Max
    INSERT INTO @CurrentMetrics (MetricName, CurrentValue)
    SELECT 'Disk_UsedPct_Max', MAX(UsedPct)
    FROM [monitor].[DiskHistory]
    WHERE CollectedAt >= @Since
    HAVING COUNT(*) > 0;

    -- Disk Read Latency
    INSERT INTO @CurrentMetrics (MetricName, CurrentValue)
    SELECT 'Disk_ReadLatency_Avg', AVG(AvgReadLatencyMs)
    FROM [monitor].[DiskHistory]
    WHERE CollectedAt >= @Since AND AvgReadLatencyMs IS NOT NULL
    HAVING COUNT(*) > 0;

    -- Disk Write Latency
    INSERT INTO @CurrentMetrics (MetricName, CurrentValue)
    SELECT 'Disk_WriteLatency_Avg', AVG(AvgWriteLatencyMs)
    FROM [monitor].[DiskHistory]
    WHERE CollectedAt >= @Since AND AvgWriteLatencyMs IS NOT NULL
    HAVING COUNT(*) > 0;

    -- Wait Stats Total Delta
    INSERT INTO @CurrentMetrics (MetricName, CurrentValue)
    SELECT 'Waits_TotalDelta_Ms', AVG(TotalDelta)
    FROM (
        SELECT CollectedAt, SUM(ISNULL(DeltaWaitTimeMs, 0)) AS TotalDelta
        FROM [monitor].[WaitStatsHistory]
        WHERE CollectedAt >= @Since
        GROUP BY CollectedAt
    ) w
    HAVING COUNT(*) > 0;

    -- Blocking Count (total in window)
    INSERT INTO @CurrentMetrics (MetricName, CurrentValue)
    SELECT 'Blocking_Count', CAST(COUNT(*) AS DECIMAL(18,4))
    FROM [monitor].[BlockingHistory]
    WHERE DetectedAt >= @Since;

    -- AG Lag Max
    INSERT INTO @CurrentMetrics (MetricName, CurrentValue)
    SELECT 'AG_Lag_Max', MAX(CAST(ISNULL(SecondsBehindPrimary, 0) AS DECIMAL(18,4)))
    FROM [monitor].[AgHealthHistory]
    WHERE CollectedAt >= @Since
    HAVING COUNT(*) > 0;

    -- TempDB Used %
    INSERT INTO @CurrentMetrics (MetricName, CurrentValue)
    SELECT 'TempDB_UsedPct', AVG(CAST(UsedSpaceMB AS DECIMAL(18,4)) / NULLIF(CAST(TotalSizeMB AS DECIMAL(18,4)), 0) * 100.0)
    FROM [monitor].[TempDbHistory]
    WHERE CollectedAt >= @Since AND TotalSizeMB > 0
    HAVING COUNT(*) > 0;

    -- Error Log Count (in window, normalized to daily rate)
    INSERT INTO @CurrentMetrics (MetricName, CurrentValue)
    SELECT 'ErrorLog_Count', 
        CAST(COUNT(*) AS DECIMAL(18,4)) * (1440.0 / @LookbackMinutes) -- Normalize to daily rate
    FROM [monitor].[ErrorLogHistory]
    WHERE CollectedAt >= @Since AND Severity IN ('Critical', 'Error');

    -- ============================================================
    -- COMPARE AGAINST BASELINES
    -- ============================================================
    DECLARE @Anomalies TABLE (
        MetricName          NVARCHAR(100),
        CurrentValue        DECIMAL(18,4),
        BaselineAvg         DECIMAL(18,4),
        BaselineStdDev      DECIMAL(18,4),
        DeviationMultiplier DECIMAL(8,2),
        Severity            NVARCHAR(20),
        Direction           NVARCHAR(10),
        Message             NVARCHAR(500)
    );

    INSERT INTO @Anomalies (MetricName, CurrentValue, BaselineAvg, BaselineStdDev, DeviationMultiplier, Severity, Direction, Message)
    SELECT 
        cm.MetricName,
        cm.CurrentValue,
        bc.AvgValue,
        bc.StdDevValue,
        -- Calculate how many stddevs away
        CASE 
            WHEN bc.StdDevValue = 0 THEN 
                CASE WHEN cm.CurrentValue <> bc.AvgValue THEN 99.99 ELSE 0 END
            ELSE 
                ABS(cm.CurrentValue - bc.AvgValue) / bc.StdDevValue
        END AS DeviationMultiplier,
        -- Determine severity
        CASE 
            WHEN bc.StdDevValue = 0 AND cm.CurrentValue <> bc.AvgValue THEN 'Critical'
            WHEN bc.StdDevValue > 0 AND ABS(cm.CurrentValue - bc.AvgValue) / bc.StdDevValue >= cfg.CriticalMultiplier THEN 'Critical'
            WHEN bc.StdDevValue > 0 AND ABS(cm.CurrentValue - bc.AvgValue) / bc.StdDevValue >= cfg.WarningMultiplier THEN 'Warning'
            ELSE NULL
        END AS Severity,
        -- Direction of deviation
        CASE WHEN cm.CurrentValue > bc.AvgValue THEN 'ABOVE' ELSE 'BELOW' END AS Direction,
        -- Human-readable message
        cm.MetricName + ': current=' + CAST(CAST(cm.CurrentValue AS DECIMAL(10,2)) AS NVARCHAR) 
            + ' vs baseline=' + CAST(CAST(bc.AvgValue AS DECIMAL(10,2)) AS NVARCHAR)
            + ' (±' + CAST(CAST(bc.StdDevValue AS DECIMAL(10,2)) AS NVARCHAR) + ')'
            + ' → ' + CAST(CAST(
                CASE WHEN bc.StdDevValue = 0 THEN 99.99
                     ELSE ABS(cm.CurrentValue - bc.AvgValue) / bc.StdDevValue END
            AS DECIMAL(5,2)) AS NVARCHAR) + ' σ deviation'
    FROM @CurrentMetrics cm
    INNER JOIN (
        -- Get active baseline for each metric
        SELECT MetricName, AvgValue, StdDevValue
        FROM [monitor].[BaselineCapture]
        WHERE IsActive = 1
    ) bc ON cm.MetricName = bc.MetricName
    INNER JOIN [monitor].[BaselineConfig] cfg 
        ON cm.MetricName = cfg.MetricName AND cfg.IsEnabled = 1
    WHERE 
        -- Apply direction filter
        (
            (cfg.Direction = 'ABOVE' AND cm.CurrentValue > bc.AvgValue)
            OR (cfg.Direction = 'BELOW' AND cm.CurrentValue < bc.AvgValue)
            OR (cfg.Direction = 'BOTH')
        )
        -- Only include if exceeds warning threshold
        AND (
            (bc.StdDevValue = 0 AND cm.CurrentValue <> bc.AvgValue)
            OR (bc.StdDevValue > 0 AND ABS(cm.CurrentValue - bc.AvgValue) / bc.StdDevValue >= cfg.WarningMultiplier)
        );

    -- Remove rows where severity couldn't be determined
    DELETE FROM @Anomalies WHERE Severity IS NULL;

    -- ============================================================
    -- DEBUG MODE: Show all comparisons
    -- ============================================================
    IF @DebugMode = 1
    BEGIN
        SELECT 
            cm.MetricName,
            cm.CurrentValue,
            bc.AvgValue AS BaselineAvg,
            bc.StdDevValue AS BaselineStdDev,
            CASE 
                WHEN bc.StdDevValue = 0 THEN NULL
                ELSE CAST(ABS(cm.CurrentValue - bc.AvgValue) / bc.StdDevValue AS DECIMAL(8,2))
            END AS DeviationSigma,
            cfg.WarningMultiplier,
            cfg.CriticalMultiplier,
            cfg.Direction AS ConfigDirection,
            CASE 
                WHEN a.Severity IS NOT NULL THEN '⚠️ ' + a.Severity
                ELSE '✓ Normal'
            END AS Status
        FROM @CurrentMetrics cm
        LEFT JOIN (
            SELECT MetricName, AvgValue, StdDevValue
            FROM [monitor].[BaselineCapture] WHERE IsActive = 1
        ) bc ON cm.MetricName = bc.MetricName
        LEFT JOIN [monitor].[BaselineConfig] cfg ON cm.MetricName = cfg.MetricName
        LEFT JOIN @Anomalies a ON cm.MetricName = a.MetricName
        ORDER BY 
            CASE WHEN a.Severity = 'Critical' THEN 1 WHEN a.Severity = 'Warning' THEN 2 ELSE 3 END,
            cm.MetricName;
        RETURN;
    END;

    -- ============================================================
    -- PERSIST ANOMALIES
    -- ============================================================
    IF @PersistResults = 1 AND EXISTS (SELECT 1 FROM @Anomalies)
    BEGIN
        INSERT INTO [monitor].[BaselineAnomalies] 
            (MetricName, CurrentValue, BaselineAvg, BaselineStdDev, DeviationMultiplier, Severity, Direction, Message)
        SELECT MetricName, CurrentValue, BaselineAvg, BaselineStdDev, DeviationMultiplier, Severity, Direction, Message
        FROM @Anomalies;
    END;

    -- ============================================================
    -- RETURN RESULTS
    -- ============================================================
    SELECT 
        MetricName,
        CurrentValue,
        BaselineAvg,
        BaselineStdDev,
        DeviationMultiplier,
        Severity,
        Direction,
        Message
    FROM @Anomalies
    ORDER BY 
        CASE Severity WHEN 'Critical' THEN 1 WHEN 'Warning' THEN 2 ELSE 3 END,
        DeviationMultiplier DESC;

    -- Summary print
    DECLARE @WarnCount INT = (SELECT COUNT(*) FROM @Anomalies WHERE Severity = 'Warning');
    DECLARE @CritCount INT = (SELECT COUNT(*) FROM @Anomalies WHERE Severity = 'Critical');

    IF @WarnCount + @CritCount = 0
        PRINT '✓ No anomalies detected. All metrics within baseline thresholds.';
    ELSE
        PRINT '⚠ Anomalies detected: ' + CAST(@CritCount AS NVARCHAR) + ' critical, ' 
            + CAST(@WarnCount AS NVARCHAR) + ' warning.';
END;
GO

PRINT '✓ Procedure [monitor].[usp_Baseline_DetectAnomalies] created.';
GO
