/*
    1.1.4 - one-time data changes

    1. Backfill WaitStatsHistory.DeltaWaitTimeMs. Before 1.1.4 the collector
       stored NULL, so every report summed the cumulative counters. Delta is
       the difference to the previous snapshot of the same wait type; a counter
       reset (restart / DBCC SQLPERF clear) uses the current value, and the first
       snapshot of each type stays NULL, as the collector does.
    2. Disk_UsedPct defaults moved from 85/95 to 80/90. Only rows still at the
       old defaults are updated; a value the operator changed is left alone.
*/
USE [SQLHealthMonitor];
GO

SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM [monitor].[AppliedMigrations]
               WHERE FileName = N'V1_1_4__waits-delta-backfill-and-disk-thresholds.sql')
BEGIN
    -- 1. Backfill in daily slices to keep the log and locks small.
    DECLARE @Day DATE = (SELECT CAST(MIN(CollectedAt) AS DATE) FROM [monitor].[WaitStatsHistory]);
    DECLARE @Last DATE = (SELECT CAST(MAX(CollectedAt) AS DATE) FROM [monitor].[WaitStatsHistory]);

    WHILE @Day IS NOT NULL AND @Day <= @Last
    BEGIN
        ;WITH d AS (
            SELECT Id, DeltaWaitTimeMs, WaitTimeMs,
                   LAG(WaitTimeMs) OVER (PARTITION BY WaitType ORDER BY CollectedAt, Id) AS PrevWaitTimeMs
            FROM [monitor].[WaitStatsHistory]
            WHERE CollectedAt >= DATEADD(DAY, -1, @Day)
              AND CollectedAt <  DATEADD(DAY,  1, @Day)
        )
        UPDATE w
        SET DeltaWaitTimeMs = CASE WHEN d.WaitTimeMs >= d.PrevWaitTimeMs
                                   THEN d.WaitTimeMs - d.PrevWaitTimeMs
                                   ELSE d.WaitTimeMs END
        FROM [monitor].[WaitStatsHistory] w
        INNER JOIN d ON d.Id = w.Id
        WHERE w.DeltaWaitTimeMs IS NULL
          AND d.PrevWaitTimeMs IS NOT NULL
          AND w.CollectedAt >= @Day AND w.CollectedAt < DATEADD(DAY, 1, @Day);

        SET @Day = DATEADD(DAY, 1, @Day);
    END

    -- 2. Disk thresholds, only if still at the old defaults.
    UPDATE [monitor].[Thresholds]
    SET WarningValue = 80, CriticalValue = 90
    WHERE MetricName = N'Disk_UsedPct' AND WarningValue = 85 AND CriticalValue = 95;
END
GO
