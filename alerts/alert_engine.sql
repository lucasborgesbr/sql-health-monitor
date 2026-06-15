-- alert_engine.sql - Evaluates current metrics against configured thresholds
-- Returns rows only when thresholds are breached
-- Updated: 2026-06-02 for release-ready version

USE [SQLHealthMonitor];
GO

IF OBJECT_ID('[monitor].[usp_EvaluateAlerts]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_EvaluateAlerts]  AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_EvaluateAlerts]', 'P') IS NULL
    
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
        E
        v
        a
        l
        u
        a
        t
        e
        A
        l
        e
        r
        t
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

ALTER PROCEDURE [monitor].[usp_EvaluateAlerts]
    
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @CurrentTime DATETIME2 = SYSDATETIME();
    
    -- Clear stale alerts (older than cooldown period)
    DELETE FROM [monitor].[AlertHistory]
    WHERE FiredAt < DATEADD(MINUTE, -60, @CurrentTime)
      AND Acknowledged = 1;
    
    -- CPU Alerts
    INSERT INTO [monitor].[AlertHistory] (MetricName, Severity, CurrentValue, ThresholdValue, Message, FiredAt)
    SELECT 
        'CPU_Usage_Pct', 
        CASE WHEN ch.SqlCpuPct >= t.CriticalValue THEN 'Critical' 
             WHEN ch.SqlCpuPct >= t.WarningValue THEN 'Warning' 
             ELSE NULL END,
        ch.SqlCpuPct,
        CASE WHEN ch.SqlCpuPct >= t.CriticalValue THEN t.CriticalValue 
             WHEN ch.SqlCpuPct >= t.WarningValue THEN t.WarningValue 
             ELSE NULL END,
        'CPU usage at ' + CAST(ch.SqlCpuPct AS VARCHAR(10)) + '% exceeds threshold',
        @CurrentTime
    FROM (SELECT TOP 1 SqlCpuPct FROM [monitor].[CPUHistory] ORDER BY CollectedAt DESC) ch
    JOIN [monitor].[Thresholds] t ON t.MetricName = 'CPU_Usage_Pct'
    WHERE ch.SqlCpuPct >= t.WarningValue
      AND NOT EXISTS (
          SELECT 1 FROM [monitor].[AlertHistory] ah 
          WHERE ah.MetricName = 'CPU_Usage_Pct' 
            AND ah.FiredAt > DATEADD(MINUTE, -60, @CurrentTime)
            AND ah.Severity = CASE WHEN ch.SqlCpuPct >= t.CriticalValue THEN 'Critical' ELSE 'Warning' END)
    AND ch.SqlCpuPct >= t.WarningValue;
    
    -- Memory Alerts
    INSERT INTO [monitor].[AlertHistory] (MetricName, Severity, CurrentValue, ThresholdValue, Message, FiredAt)
    SELECT 
        'Memory_Total_Pct', 
        CASE WHEN mh.AvailableMemoryMB <= t.CriticalValue THEN 'Critical' 
             WHEN mh.AvailableMemoryMB <= t.WarningValue THEN 'Warning' 
             ELSE NULL END,
        100 - (mh.AvailableMemoryMB * 100.0 / mh.TotalServerMemoryMB),
        CASE WHEN mh.AvailableMemoryMB <= t.CriticalValue THEN 100 - (t.CriticalValue * 100.0 / mh.TotalServerMemoryMB) 
             WHEN mh.AvailableMemoryMB <= t.WarningValue THEN 100 - (t.WarningValue * 100.0 / mh.TotalServerMemoryMB) 
             ELSE NULL END,
        'Memory usage at ' + CAST(100 - (mh.AvailableMemoryMB * 100.0 / mh.TotalServerMemoryMB) AS VARCHAR(10)) + '% exceeds threshold',
        @CurrentTime
    FROM (SELECT TOP 1 AvailableMemoryMB, TotalServerMemoryMB FROM [monitor].[MemoryHistory] ORDER BY CollectedAt DESC) mh
    JOIN [monitor].[Thresholds] t ON t.MetricName = 'Memory_Total_Pct'
    WHERE (100 - (mh.AvailableMemoryMB * 100.0 / mh.TotalServerMemoryMB)) >= t.WarningValue
      AND NOT EXISTS (
          SELECT 1 FROM [monitor].[AlertHistory] ah 
          WHERE ah.MetricName = 'Memory_Total_Pct' 
            AND ah.FiredAt > DATEADD(MINUTE, -60, @CurrentTime)
            AND ah.Severity = CASE WHEN (100 - (mh.AvailableMemoryMB * 100.0 / mh.TotalServerMemoryMB)) >= t.CriticalValue THEN 'Critical' ELSE 'Warning' END)
    AND (100 - (mh.AvailableMemoryMB * 100.0 / mh.TotalServerMemoryMB)) >= t.WarningValue;
    
    -- Disk Space Alerts
    INSERT INTO [monitor].[AlertHistory] (MetricName, Severity, CurrentValue, ThresholdValue, Message, FiredAt)
    SELECT 
        'Disk_Space_Pct', 
        CASE WHEN dh.UsedPct >= t.CriticalValue THEN 'Critical' 
             WHEN dh.UsedPct >= t.WarningValue THEN 'Warning' 
             ELSE NULL END,
        dh.UsedPct,
        CASE WHEN dh.UsedPct >= t.CriticalValue THEN t.CriticalValue 
             WHEN dh.UsedPct >= t.WarningValue THEN t.WarningValue 
             ELSE NULL END,
        'Disk space at ' + CAST(dh.UsedPct AS VARCHAR(10)) + '% on drive ' + dh.DriveLetter + ' exceeds threshold',
        @CurrentTime
    FROM (SELECT TOP 1 UsedPct, DriveLetter FROM [monitor].[DiskHistory] ORDER BY CollectedAt DESC) dh
    JOIN [monitor].[Thresholds] t ON t.MetricName = 'Disk_Space_Pct'
    WHERE dh.UsedPct >= t.WarningValue
      AND NOT EXISTS (
          SELECT 1 FROM [monitor].[AlertHistory] ah 
          WHERE ah.MetricName = 'Disk_Space_Pct' 
            AND ah.FiredAt > DATEADD(MINUTE, -60, @CurrentTime)
            AND ah.Severity = CASE WHEN dh.UsedPct >= t.CriticalValue THEN 'Critical' ELSE 'Warning' END)
    AND dh.UsedPct >= t.WarningValue;
    
    -- Backup Alerts
    INSERT INTO [monitor].[AlertHistory] (MetricName, Severity, CurrentValue, ThresholdValue, Message, FiredAt)
    SELECT 
        'Backup_Hours_SinceFull', 
        CASE WHEN bh.HoursSinceLastBackup >= t.CriticalValue THEN 'Critical' 
             WHEN bh.HoursSinceLastBackup >= t.WarningValue THEN 'Warning' 
             ELSE NULL END,
        bh.HoursSinceLastBackup,
        CASE WHEN bh.HoursSinceLastBackup >= t.CriticalValue THEN t.CriticalValue 
             WHEN bh.HoursSinceLastBackup >= t.WarningValue THEN t.WarningValue 
             ELSE NULL END,
        'Full backup is ' + CAST(bh.HoursSinceLastBackup AS VARCHAR(10)) + ' hours old',
        @CurrentTime
    FROM (SELECT TOP 1 HoursSinceLastBackup FROM [monitor].[BackupHistory] ORDER BY CollectedAt DESC) bh
    JOIN [monitor].[Thresholds] t ON t.MetricName = 'Backup_Hours_SinceFull'
    WHERE bh.HoursSinceLastBackup >= t.WarningValue
      AND NOT EXISTS (
          SELECT 1 FROM [monitor].[AlertHistory] ah 
          WHERE ah.MetricName = 'Backup_Hours_SinceFull' 
            AND ah.FiredAt > DATEADD(MINUTE, -60, @CurrentTime)
            AND ah.Severity = CASE WHEN bh.HoursSinceLastBackup >= t.CriticalValue THEN 'Critical' ELSE 'Warning' END)
    AND bh.HoursSinceLastBackup >= t.WarningValue;
    
    PRINT '✓ Alert evaluation completed.';
END;
GO

-- Execute alert evaluation
EXEC [monitor].[usp_EvaluateAlerts];
GO

PRINT '✓ Alert engine executed successfully.';
GO
