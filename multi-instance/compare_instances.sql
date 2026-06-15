/*
    SQL Health Monitor - Compare Instances
    Compares health across registered instances.
    Identifies worst-performing instance and detects drift between nodes.
    
    Schema: [monitor]
    Compatibility: SQL Server 2016+
    Author: Lucas Allan Borges
    
    Parameters:
        @Environment    NVARCHAR(20) - Filter by environment (NULL = all)
        @LookbackHours  INT          - Hours of snapshot data to analyze (default: 24)
        @DriftThreshold DECIMAL(5,2) - % deviation to flag as drift (default: 25.0)
        @DebugMode      BIT          - Verbose output (default: 0)
    
    Example Usage:
        -- Compare all production instances
        EXEC [monitor].[usp_CompareInstances] @Environment = 'PRD';
        
        -- Compare all with tighter drift threshold
        EXEC [monitor].[usp_CompareInstances] @DriftThreshold = 15.0;
        
        -- Last 4 hours only
        EXEC [monitor].[usp_CompareInstances] @LookbackHours = 4;
*/

USE [SQLHealthMonitor];
GO

/*
    SQL Health Monitor - Compare Instances
    Compares health across registered instances.
    Identifies worst-performing instance and detects drift between nodes.
    
    Schema: [monitor]
    Compatibility: SQL Server 2016+
    Author: Lucas Allan Borges
    
    Parameters:
        @Environment    NVARCHAR(20) - Filter by environment (NULL = all)
        @LookbackHours  INT          - Hours of snapshot data to analyze (default: 24)
        @DriftThreshold DECIMAL(5,2) - % deviation to flag as drift (default: 25.0)
        @DebugMode      BIT          - Verbose output (default: 0)
    
    Example Usage:
        -- Compare all production instances
        EXEC [monitor].[usp_CompareInstances] @Environment = 'PRD';
        
        -- Compare all with tighter drift threshold
        EXEC [monitor].[usp_CompareInstances] @DriftThreshold = 15.0;
        
        -- Last 4 hours only
        EXEC [monitor].[usp_CompareInstances] @LookbackHours = 4;
*/

USE [SQLHealthMonitor];
GO

IF OBJECT_ID('[monitor].[usp_CompareInstances]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_CompareInstances] @Environment    NVARCHAR(20) = NULL, @LookbackHours  INT = NULL, @DriftThreshold DECIMAL(5 = NULL, 2) = NULL, @DebugMode      BIT = NULL AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_CompareInstances]', 'P') IS NULL
    EXEC('
    CREATE PROCEDURE [monitor].[usp_CompareInstances]
        
        @Environment    NVARCHAR(20) = NULL,
        @LookbackHours  INT = 24,
        @DriftThreshold DECIMAL(5,2) = 25.0,
        @DebugMode      BIT = 0
    AS
    BEGIN
        SET NOCOUNT ON;
        PRINT ''Placeholder'';
    END;
    ');
GO

ALTER PROCEDURE [monitor].[usp_CompareInstances]
    @Environment    NVARCHAR(20) = NULL,
    @LookbackHours  INT = 24,
    @DriftThreshold DECIMAL(5,2) = 25.0,
    @DebugMode      BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Since DATETIME2 = DATEADD(HOUR, -@LookbackHours, SYSUTCDATETIME());

    -- ============================================================
    -- RESULT SET 1: INSTANCE HEALTH RANKING
    -- ============================================================
    SELECT 
        ROW_NUMBER() OVER (ORDER BY 
            CASE OverallStatus WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END,
            HealthScore ASC
        ) AS Rank,
        ihs.InstanceName,
        rs.Environment,
        rs.AgRole,
        rs.ServerRole,
        ihs.HealthScore,
        ihs.OverallStatus,
        ihs.CpuAvg,
        ihs.CpuMax,
        ihs.PleAvg,
        ihs.DiskMaxUsedPct,
        ihs.AgMaxLagSec,
        ihs.BlockingCount,
        ihs.AlertCount,
        ihs.CollectedAt AS LastSnapshot
    FROM [monitor].[InstanceHealthSnapshot] ihs
    INNER JOIN [monitor].[RegisteredServers] rs ON ihs.InstanceName = rs.InstanceName
    WHERE ihs.CollectedAt >= @Since
        AND rs.IsActive = 1
        AND (@Environment IS NULL OR rs.Environment = @Environment)
        -- Get latest snapshot per instance
        AND ihs.CollectedAt = (
            SELECT MAX(CollectedAt) 
            FROM [monitor].[InstanceHealthSnapshot] sub 
            WHERE sub.InstanceName = ihs.InstanceName AND sub.CollectedAt >= @Since
        )
    ORDER BY 
        CASE OverallStatus WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END,
        HealthScore ASC;

    -- ============================================================
    -- RESULT SET 2: CLUSTER AVERAGES & WORST INSTANCE
    -- ============================================================
    ;WITH LatestSnapshots AS (
        SELECT ihs.*
        FROM [monitor].[InstanceHealthSnapshot] ihs
        INNER JOIN [monitor].[RegisteredServers] rs ON ihs.InstanceName = rs.InstanceName
        WHERE ihs.CollectedAt >= @Since
            AND rs.IsActive = 1
            AND (@Environment IS NULL OR rs.Environment = @Environment)
            AND ihs.CollectedAt = (
                SELECT MAX(CollectedAt) 
                FROM [monitor].[InstanceHealthSnapshot] sub 
                WHERE sub.InstanceName = ihs.InstanceName AND sub.CollectedAt >= @Since
            )
    )
    SELECT 
        COUNT(*) AS InstanceCount,
        AVG(HealthScore) AS AvgHealthScore,
        MIN(HealthScore) AS WorstHealthScore,
        (SELECT TOP 1 InstanceName FROM LatestSnapshots ORDER BY HealthScore ASC) AS WorstInstance,
        (SELECT TOP 1 OverallStatus FROM LatestSnapshots ORDER BY HealthScore ASC) AS WorstStatus,
        MAX(HealthScore) AS BestHealthScore,
        (SELECT TOP 1 InstanceName FROM LatestSnapshots ORDER BY HealthScore DESC) AS BestInstance,
        AVG(CpuAvg) AS ClusterCpuAvg,
        MAX(CpuMax) AS ClusterCpuMax,
        AVG(PleAvg) AS ClusterPleAvg,
        MAX(DiskMaxUsedPct) AS ClusterDiskMaxPct,
        MAX(AgMaxLagSec) AS ClusterMaxAgLag,
        SUM(BlockingCount) AS ClusterTotalBlocking,
        SUM(AlertCount) AS ClusterTotalAlerts
    FROM LatestSnapshots;

    -- ============================================================
    -- RESULT SET 3: DRIFT DETECTION
    -- ============================================================
    DECLARE @Drift TABLE (
        InstanceName    NVARCHAR(256),
        MetricName      NVARCHAR(100),
        InstanceValue   DECIMAL(18,2),
        ClusterAvg      DECIMAL(18,2),
        DeviationPct    DECIMAL(10,2),
        Severity        NVARCHAR(20)
    );

    -- Calculate cluster averages
    DECLARE @ClusterCpuAvg DECIMAL(18,2), @ClusterPleAvg DECIMAL(18,2), @ClusterDiskAvg DECIMAL(18,2);

    ;WITH LatestSnapshots AS (
        SELECT ihs.*
        FROM [monitor].[InstanceHealthSnapshot] ihs
        INNER JOIN [monitor].[RegisteredServers] rs ON ihs.InstanceName = rs.InstanceName
        WHERE ihs.CollectedAt >= @Since
            AND rs.IsActive = 1
            AND (@Environment IS NULL OR rs.Environment = @Environment)
            AND ihs.CollectedAt = (
                SELECT MAX(CollectedAt) 
                FROM [monitor].[InstanceHealthSnapshot] sub 
                WHERE sub.InstanceName = ihs.InstanceName AND sub.CollectedAt >= @Since
            )
    )
    SELECT 
        @ClusterCpuAvg = AVG(CAST(CpuAvg AS DECIMAL(18,2))),
        @ClusterPleAvg = AVG(CAST(PleAvg AS DECIMAL(18,2))),
        @ClusterDiskAvg = AVG(DiskMaxUsedPct)
    FROM LatestSnapshots;

    -- Detect CPU drift
    INSERT INTO @Drift (InstanceName, MetricName, InstanceValue, ClusterAvg, DeviationPct, Severity)
    SELECT 
        ihs.InstanceName, 'CPU Avg', CAST(ihs.CpuAvg AS DECIMAL(18,2)), @ClusterCpuAvg,
        CASE WHEN @ClusterCpuAvg = 0 THEN 0 
             ELSE ((CAST(ihs.CpuAvg AS DECIMAL(18,2)) - @ClusterCpuAvg) / NULLIF(@ClusterCpuAvg, 0)) * 100 END,
        CASE 
            WHEN @ClusterCpuAvg > 0 AND ABS((CAST(ihs.CpuAvg AS DECIMAL(18,2)) - @ClusterCpuAvg) / NULLIF(@ClusterCpuAvg, 0)) * 100 >= @DriftThreshold * 2 THEN 'Critical'
            WHEN @ClusterCpuAvg > 0 AND ABS((CAST(ihs.CpuAvg AS DECIMAL(18,2)) - @ClusterCpuAvg) / NULLIF(@ClusterCpuAvg, 0)) * 100 >= @DriftThreshold THEN 'Warning'
            ELSE 'Info'
        END
    FROM [monitor].[InstanceHealthSnapshot] ihs
    INNER JOIN [monitor].[RegisteredServers] rs ON ihs.InstanceName = rs.InstanceName
    WHERE ihs.CollectedAt >= @Since
        AND rs.IsActive = 1
        AND (@Environment IS NULL OR rs.Environment = @Environment)
        AND ihs.CollectedAt = (
            SELECT MAX(CollectedAt) FROM [monitor].[InstanceHealthSnapshot] sub 
            WHERE sub.InstanceName = ihs.InstanceName AND sub.CollectedAt >= @Since
        )
        AND @ClusterCpuAvg > 0
        AND ABS((CAST(ihs.CpuAvg AS DECIMAL(18,2)) - @ClusterCpuAvg) / NULLIF(@ClusterCpuAvg, 0)) * 100 >= @DriftThreshold;

    -- Detect PLE drift
    INSERT INTO @Drift (InstanceName, MetricName, InstanceValue, ClusterAvg, DeviationPct, Severity)
    SELECT 
        ihs.InstanceName, 'PLE Avg', CAST(ihs.PleAvg AS DECIMAL(18,2)), @ClusterPleAvg,
        CASE WHEN @ClusterPleAvg = 0 THEN 0 
             ELSE ((CAST(ihs.PleAvg AS DECIMAL(18,2)) - @ClusterPleAvg) / NULLIF(@ClusterPleAvg, 0)) * 100 END,
        CASE 
            WHEN @ClusterPleAvg > 0 AND ABS((CAST(ihs.PleAvg AS DECIMAL(18,2)) - @ClusterPleAvg) / NULLIF(@ClusterPleAvg, 0)) * 100 >= @DriftThreshold * 2 THEN 'Critical'
            WHEN @ClusterPleAvg > 0 AND ABS((CAST(ihs.PleAvg AS DECIMAL(18,2)) - @ClusterPleAvg) / NULLIF(@ClusterPleAvg, 0)) * 100 >= @DriftThreshold THEN 'Warning'
            ELSE 'Info'
        END
    FROM [monitor].[InstanceHealthSnapshot] ihs
    INNER JOIN [monitor].[RegisteredServers] rs ON ihs.InstanceName = rs.InstanceName
    WHERE ihs.CollectedAt >= @Since
        AND rs.IsActive = 1
        AND (@Environment IS NULL OR rs.Environment = @Environment)
        AND ihs.CollectedAt = (
            SELECT MAX(CollectedAt) FROM [monitor].[InstanceHealthSnapshot] sub 
            WHERE sub.InstanceName = ihs.InstanceName AND sub.CollectedAt >= @Since
        )
        AND @ClusterPleAvg > 0
        AND ABS((CAST(ihs.PleAvg AS DECIMAL(18,2)) - @ClusterPleAvg) / NULLIF(@ClusterPleAvg, 0)) * 100 >= @DriftThreshold;

    -- Detect Disk drift
    INSERT INTO @Drift (InstanceName, MetricName, InstanceValue, ClusterAvg, DeviationPct, Severity)
    SELECT 
        ihs.InstanceName, 'Disk Max %', ihs.DiskMaxUsedPct, @ClusterDiskAvg,
        CASE WHEN @ClusterDiskAvg = 0 THEN 0 
             ELSE ((ihs.DiskMaxUsedPct - @ClusterDiskAvg) / NULLIF(@ClusterDiskAvg, 0)) * 100 END,
        CASE 
            WHEN @ClusterDiskAvg > 0 AND ABS((ihs.DiskMaxUsedPct - @ClusterDiskAvg) / NULLIF(@ClusterDiskAvg, 0)) * 100 >= @DriftThreshold * 2 THEN 'Critical'
            WHEN @ClusterDiskAvg > 0 AND ABS((ihs.DiskMaxUsedPct - @ClusterDiskAvg) / NULLIF(@ClusterDiskAvg, 0)) * 100 >= @DriftThreshold THEN 'Warning'
            ELSE 'Info'
        END
    FROM [monitor].[InstanceHealthSnapshot] ihs
    INNER JOIN [monitor].[RegisteredServers] rs ON ihs.InstanceName = rs.InstanceName
    WHERE ihs.CollectedAt >= @Since
        AND rs.IsActive = 1
        AND (@Environment IS NULL OR rs.Environment = @Environment)
        AND ihs.CollectedAt = (
            SELECT MAX(CollectedAt) FROM [monitor].[InstanceHealthSnapshot] sub 
            WHERE sub.InstanceName = ihs.InstanceName AND sub.CollectedAt >= @Since
        )
        AND @ClusterDiskAvg > 0
        AND ABS((ihs.DiskMaxUsedPct - @ClusterDiskAvg) / NULLIF(@ClusterDiskAvg, 0)) * 100 >= @DriftThreshold;

    -- Output drift results
    SELECT InstanceName, MetricName, InstanceValue, ClusterAvg, DeviationPct, Severity
    FROM @Drift
    WHERE Severity IN ('Warning', 'Critical')
    ORDER BY 
        CASE Severity WHEN 'Critical' THEN 1 ELSE 2 END,
        ABS(DeviationPct) DESC;

    -- Persist drift to history
    INSERT INTO [monitor].[InstanceDrift] (InstanceName, DriftType, MetricName, InstanceValue, ClusterAvg, DeviationPct, Severity, Message)
    SELECT 
        InstanceName, 'Performance', MetricName, 
        CAST(InstanceValue AS NVARCHAR(200)), 
        CAST(ClusterAvg AS NVARCHAR(200)),
        DeviationPct, Severity,
        MetricName + ' on ' + InstanceName + ': ' + CAST(CAST(InstanceValue AS DECIMAL(10,1)) AS NVARCHAR) 
            + ' vs cluster avg ' + CAST(CAST(ClusterAvg AS DECIMAL(10,1)) AS NVARCHAR)
            + ' (' + CASE WHEN DeviationPct > 0 THEN '+' ELSE '' END + CAST(CAST(DeviationPct AS DECIMAL(5,1)) AS NVARCHAR) + '%)'
    FROM @Drift
    WHERE Severity IN ('Warning', 'Critical');

    -- ============================================================
    -- RESULT SET 4: HEALTH TREND (last N snapshots per instance)
    -- ============================================================
    IF @DebugMode = 1
    BEGIN
        SELECT 
            ihs.InstanceName,
            ihs.CollectedAt,
            ihs.HealthScore,
            ihs.OverallStatus,
            ihs.CpuAvg,
            ihs.PleAvg,
            ihs.DiskMaxUsedPct
        FROM [monitor].[InstanceHealthSnapshot] ihs
        INNER JOIN [monitor].[RegisteredServers] rs ON ihs.InstanceName = rs.InstanceName
        WHERE ihs.CollectedAt >= @Since
            AND rs.IsActive = 1
            AND (@Environment IS NULL OR rs.Environment = @Environment)
        ORDER BY ihs.InstanceName, ihs.CollectedAt DESC;
    END;

    -- Summary
    DECLARE @DriftCount INT = (SELECT COUNT(*) FROM @Drift WHERE Severity IN ('Warning', 'Critical'));
    IF @DriftCount > 0
        PRINT '⚠ Drift detected: ' + CAST(@DriftCount AS NVARCHAR) + ' metric(s) deviating beyond ' + CAST(CAST(@DriftThreshold AS INT) AS NVARCHAR) + '% threshold.';
    ELSE
        PRINT '✓ All instances within acceptable drift thresholds.';
END;
GO

PRINT '✓ Procedure [monitor].[usp_CompareInstances] created.';
GO

    @Environment    NVARCHAR(20) = NULL,
    @LookbackHours  INT = 24,
    @DriftThreshold DECIMAL(5,2) = 25.0,
    @DebugMode      BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Since DATETIME2 = DATEADD(HOUR, -@LookbackHours, SYSUTCDATETIME());

    -- ============================================================
    -- RESULT SET 1: INSTANCE HEALTH RANKING
    -- ============================================================
    SELECT 
        ROW_NUMBER() OVER (ORDER BY 
            CASE OverallStatus WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END,
            HealthScore ASC
        ) AS Rank,
        ihs.InstanceName,
        rs.Environment,
        rs.AgRole,
        rs.ServerRole,
        ihs.HealthScore,
        ihs.OverallStatus,
        ihs.CpuAvg,
        ihs.CpuMax,
        ihs.PleAvg,
        ihs.DiskMaxUsedPct,
        ihs.AgMaxLagSec,
        ihs.BlockingCount,
        ihs.AlertCount,
        ihs.CollectedAt AS LastSnapshot
    FROM [monitor].[InstanceHealthSnapshot] ihs
    INNER JOIN [monitor].[RegisteredServers] rs ON ihs.InstanceName = rs.InstanceName
    WHERE ihs.CollectedAt >= @Since
        AND rs.IsActive = 1
        AND (@Environment IS NULL OR rs.Environment = @Environment)
        -- Get latest snapshot per instance
        AND ihs.CollectedAt = (
            SELECT MAX(CollectedAt) 
            FROM [monitor].[InstanceHealthSnapshot] sub 
            WHERE sub.InstanceName = ihs.InstanceName AND sub.CollectedAt >= @Since
        )
    ORDER BY 
        CASE OverallStatus WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END,
        HealthScore ASC;

    -- ============================================================
    -- RESULT SET 2: CLUSTER AVERAGES & WORST INSTANCE
    -- ============================================================
    ;WITH LatestSnapshots AS (
        SELECT ihs.*
        FROM [monitor].[InstanceHealthSnapshot] ihs
        INNER JOIN [monitor].[RegisteredServers] rs ON ihs.InstanceName = rs.InstanceName
        WHERE ihs.CollectedAt >= @Since
            AND rs.IsActive = 1
            AND (@Environment IS NULL OR rs.Environment = @Environment)
            AND ihs.CollectedAt = (
                SELECT MAX(CollectedAt) 
                FROM [monitor].[InstanceHealthSnapshot] sub 
                WHERE sub.InstanceName = ihs.InstanceName AND sub.CollectedAt >= @Since
            )
    )
    SELECT 
        COUNT(*) AS InstanceCount,
        AVG(HealthScore) AS AvgHealthScore,
        MIN(HealthScore) AS WorstHealthScore,
        (SELECT TOP 1 InstanceName FROM LatestSnapshots ORDER BY HealthScore ASC) AS WorstInstance,
        (SELECT TOP 1 OverallStatus FROM LatestSnapshots ORDER BY HealthScore ASC) AS WorstStatus,
        MAX(HealthScore) AS BestHealthScore,
        (SELECT TOP 1 InstanceName FROM LatestSnapshots ORDER BY HealthScore DESC) AS BestInstance,
        AVG(CpuAvg) AS ClusterCpuAvg,
        MAX(CpuMax) AS ClusterCpuMax,
        AVG(PleAvg) AS ClusterPleAvg,
        MAX(DiskMaxUsedPct) AS ClusterDiskMaxPct,
        MAX(AgMaxLagSec) AS ClusterMaxAgLag,
        SUM(BlockingCount) AS ClusterTotalBlocking,
        SUM(AlertCount) AS ClusterTotalAlerts
    FROM LatestSnapshots;

    -- ============================================================
    -- RESULT SET 3: DRIFT DETECTION
    -- ============================================================
    DECLARE @Drift TABLE (
        InstanceName    NVARCHAR(256),
        MetricName      NVARCHAR(100),
        InstanceValue   DECIMAL(18,2),
        ClusterAvg      DECIMAL(18,2),
        DeviationPct    DECIMAL(10,2),
        Severity        NVARCHAR(20)
    );

    -- Calculate cluster averages
    DECLARE @ClusterCpuAvg DECIMAL(18,2), @ClusterPleAvg DECIMAL(18,2), @ClusterDiskAvg DECIMAL(18,2);

    ;WITH LatestSnapshots AS (
        SELECT ihs.*
        FROM [monitor].[InstanceHealthSnapshot] ihs
        INNER JOIN [monitor].[RegisteredServers] rs ON ihs.InstanceName = rs.InstanceName
        WHERE ihs.CollectedAt >= @Since
            AND rs.IsActive = 1
            AND (@Environment IS NULL OR rs.Environment = @Environment)
            AND ihs.CollectedAt = (
                SELECT MAX(CollectedAt) 
                FROM [monitor].[InstanceHealthSnapshot] sub 
                WHERE sub.InstanceName = ihs.InstanceName AND sub.CollectedAt >= @Since
            )
    )
    SELECT 
        @ClusterCpuAvg = AVG(CAST(CpuAvg AS DECIMAL(18,2))),
        @ClusterPleAvg = AVG(CAST(PleAvg AS DECIMAL(18,2))),
        @ClusterDiskAvg = AVG(DiskMaxUsedPct)
    FROM LatestSnapshots;

    -- Detect CPU drift
    INSERT INTO @Drift (InstanceName, MetricName, InstanceValue, ClusterAvg, DeviationPct, Severity)
    SELECT 
        ihs.InstanceName, 'CPU Avg', CAST(ihs.CpuAvg AS DECIMAL(18,2)), @ClusterCpuAvg,
        CASE WHEN @ClusterCpuAvg = 0 THEN 0 
             ELSE ((CAST(ihs.CpuAvg AS DECIMAL(18,2)) - @ClusterCpuAvg) / NULLIF(@ClusterCpuAvg, 0)) * 100 END,
        CASE 
            WHEN @ClusterCpuAvg > 0 AND ABS((CAST(ihs.CpuAvg AS DECIMAL(18,2)) - @ClusterCpuAvg) / NULLIF(@ClusterCpuAvg, 0)) * 100 >= @DriftThreshold * 2 THEN 'Critical'
            WHEN @ClusterCpuAvg > 0 AND ABS((CAST(ihs.CpuAvg AS DECIMAL(18,2)) - @ClusterCpuAvg) / NULLIF(@ClusterCpuAvg, 0)) * 100 >= @DriftThreshold THEN 'Warning'
            ELSE 'Info'
        END
    FROM [monitor].[InstanceHealthSnapshot] ihs
    INNER JOIN [monitor].[RegisteredServers] rs ON ihs.InstanceName = rs.InstanceName
    WHERE ihs.CollectedAt >= @Since
        AND rs.IsActive = 1
        AND (@Environment IS NULL OR rs.Environment = @Environment)
        AND ihs.CollectedAt = (
            SELECT MAX(CollectedAt) FROM [monitor].[InstanceHealthSnapshot] sub 
            WHERE sub.InstanceName = ihs.InstanceName AND sub.CollectedAt >= @Since
        )
        AND @ClusterCpuAvg > 0
        AND ABS((CAST(ihs.CpuAvg AS DECIMAL(18,2)) - @ClusterCpuAvg) / NULLIF(@ClusterCpuAvg, 0)) * 100 >= @DriftThreshold;

    -- Detect PLE drift
    INSERT INTO @Drift (InstanceName, MetricName, InstanceValue, ClusterAvg, DeviationPct, Severity)
    SELECT 
        ihs.InstanceName, 'PLE Avg', CAST(ihs.PleAvg AS DECIMAL(18,2)), @ClusterPleAvg,
        CASE WHEN @ClusterPleAvg = 0 THEN 0 
             ELSE ((CAST(ihs.PleAvg AS DECIMAL(18,2)) - @ClusterPleAvg) / NULLIF(@ClusterPleAvg, 0)) * 100 END,
        CASE 
            WHEN @ClusterPleAvg > 0 AND ABS((CAST(ihs.PleAvg AS DECIMAL(18,2)) - @ClusterPleAvg) / NULLIF(@ClusterPleAvg, 0)) * 100 >= @DriftThreshold * 2 THEN 'Critical'
            WHEN @ClusterPleAvg > 0 AND ABS((CAST(ihs.PleAvg AS DECIMAL(18,2)) - @ClusterPleAvg) / NULLIF(@ClusterPleAvg, 0)) * 100 >= @DriftThreshold THEN 'Warning'
            ELSE 'Info'
        END
    FROM [monitor].[InstanceHealthSnapshot] ihs
    INNER JOIN [monitor].[RegisteredServers] rs ON ihs.InstanceName = rs.InstanceName
    WHERE ihs.CollectedAt >= @Since
        AND rs.IsActive = 1
        AND (@Environment IS NULL OR rs.Environment = @Environment)
        AND ihs.CollectedAt = (
            SELECT MAX(CollectedAt) FROM [monitor].[InstanceHealthSnapshot] sub 
            WHERE sub.InstanceName = ihs.InstanceName AND sub.CollectedAt >= @Since
        )
        AND @ClusterPleAvg > 0
        AND ABS((CAST(ihs.PleAvg AS DECIMAL(18,2)) - @ClusterPleAvg) / NULLIF(@ClusterPleAvg, 0)) * 100 >= @DriftThreshold;

    -- Detect Disk drift
    INSERT INTO @Drift (InstanceName, MetricName, InstanceValue, ClusterAvg, DeviationPct, Severity)
    SELECT 
        ihs.InstanceName, 'Disk Max %', ihs.DiskMaxUsedPct, @ClusterDiskAvg,
        CASE WHEN @ClusterDiskAvg = 0 THEN 0 
             ELSE ((ihs.DiskMaxUsedPct - @ClusterDiskAvg) / NULLIF(@ClusterDiskAvg, 0)) * 100 END,
        CASE 
            WHEN @ClusterDiskAvg > 0 AND ABS((ihs.DiskMaxUsedPct - @ClusterDiskAvg) / NULLIF(@ClusterDiskAvg, 0)) * 100 >= @DriftThreshold * 2 THEN 'Critical'
            WHEN @ClusterDiskAvg > 0 AND ABS((ihs.DiskMaxUsedPct - @ClusterDiskAvg) / NULLIF(@ClusterDiskAvg, 0)) * 100 >= @DriftThreshold THEN 'Warning'
            ELSE 'Info'
        END
    FROM [monitor].[InstanceHealthSnapshot] ihs
    INNER JOIN [monitor].[RegisteredServers] rs ON ihs.InstanceName = rs.InstanceName
    WHERE ihs.CollectedAt >= @Since
        AND rs.IsActive = 1
        AND (@Environment IS NULL OR rs.Environment = @Environment)
        AND ihs.CollectedAt = (
            SELECT MAX(CollectedAt) FROM [monitor].[InstanceHealthSnapshot] sub 
            WHERE sub.InstanceName = ihs.InstanceName AND sub.CollectedAt >= @Since
        )
        AND @ClusterDiskAvg > 0
        AND ABS((ihs.DiskMaxUsedPct - @ClusterDiskAvg) / NULLIF(@ClusterDiskAvg, 0)) * 100 >= @DriftThreshold;

    -- Output drift results
    SELECT InstanceName, MetricName, InstanceValue, ClusterAvg, DeviationPct, Severity
    FROM @Drift
    WHERE Severity IN ('Warning', 'Critical')
    ORDER BY 
        CASE Severity WHEN 'Critical' THEN 1 ELSE 2 END,
        ABS(DeviationPct) DESC;

    -- Persist drift to history
    INSERT INTO [monitor].[InstanceDrift] (InstanceName, DriftType, MetricName, InstanceValue, ClusterAvg, DeviationPct, Severity, Message)
    SELECT 
        InstanceName, 'Performance', MetricName, 
        CAST(InstanceValue AS NVARCHAR(200)), 
        CAST(ClusterAvg AS NVARCHAR(200)),
        DeviationPct, Severity,
        MetricName + ' on ' + InstanceName + ': ' + CAST(CAST(InstanceValue AS DECIMAL(10,1)) AS NVARCHAR) 
            + ' vs cluster avg ' + CAST(CAST(ClusterAvg AS DECIMAL(10,1)) AS NVARCHAR)
            + ' (' + CASE WHEN DeviationPct > 0 THEN '+' ELSE '' END + CAST(CAST(DeviationPct AS DECIMAL(5,1)) AS NVARCHAR) + '%)'
    FROM @Drift
    WHERE Severity IN ('Warning', 'Critical');

    -- ============================================================
    -- RESULT SET 4: HEALTH TREND (last N snapshots per instance)
    -- ============================================================
    IF @DebugMode = 1
    BEGIN
        SELECT 
            ihs.InstanceName,
            ihs.CollectedAt,
            ihs.HealthScore,
            ihs.OverallStatus,
            ihs.CpuAvg,
            ihs.PleAvg,
            ihs.DiskMaxUsedPct
        FROM [monitor].[InstanceHealthSnapshot] ihs
        INNER JOIN [monitor].[RegisteredServers] rs ON ihs.InstanceName = rs.InstanceName
        WHERE ihs.CollectedAt >= @Since
            AND rs.IsActive = 1
            AND (@Environment IS NULL OR rs.Environment = @Environment)
        ORDER BY ihs.InstanceName, ihs.CollectedAt DESC;
    END;

    -- Summary
    DECLARE @DriftCount INT = (SELECT COUNT(*) FROM @Drift WHERE Severity IN ('Warning', 'Critical'));
    IF @DriftCount > 0
        PRINT '⚠ Drift detected: ' + CAST(@DriftCount AS NVARCHAR) + ' metric(s) deviating beyond ' + CAST(CAST(@DriftThreshold AS INT) AS NVARCHAR) + '% threshold.';
    ELSE
        PRINT '✓ All instances within acceptable drift thresholds.';
END;
GO

PRINT '✓ Procedure [monitor].[usp_CompareInstances] created.';
GO
