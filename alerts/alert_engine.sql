/*
    SQL Health Monitor - Alert Engine
    Checks all current metrics against thresholds and fires alerts.
    
    Features:
      - Evaluates latest metrics against Thresholds table
      - Respects cooldown (no spam for same alert within X minutes)
      - Logs to AlertHistory
      - Sends email via Database Mail
      - Supports Warning and Critical severity
    
    Compatibility: SQL Server 2016+
*/

USE [DBA_Monitor];
GO

CREATE OR ALTER PROCEDURE [monitor].[usp_AlertEngine_Check]
    @CooldownMinutes INT = 30,
    @DebugMode BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();
    DECLARE @ProfileName NVARCHAR(128) = (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'Email' AND SettingName = 'ProfileName');
    DECLARE @Recipients NVARCHAR(500) = (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'Email' AND SettingName = 'Recipients');
    DECLARE @SubjectPrefix NVARCHAR(50) = (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'Email' AND SettingName = 'SubjectPrefix');
    DECLARE @ServerName NVARCHAR(128) = (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'General' AND SettingName = 'ServerName');
    DECLARE @Language CHAR(5) = (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'General' AND SettingName = 'Language');

    -- Temp table for current metric values
    DECLARE @Metrics TABLE (
        MetricName      NVARCHAR(100),
        CurrentValue    DECIMAL(18,2),
        Context         NVARCHAR(500)  -- Extra info (drive letter, replica name, etc.)
    );

    -- ============================================================
    -- COLLECT CURRENT METRIC VALUES
    -- ============================================================

    -- CPU (latest reading)
    INSERT INTO @Metrics (MetricName, CurrentValue, Context)
    SELECT 'CPU_SqlPct', CAST(SqlCpuPct AS DECIMAL(18,2)), NULL
    FROM [monitor].[CpuHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[CpuHistory]);

    INSERT INTO @Metrics (MetricName, CurrentValue, Context)
    SELECT 'CPU_SystemPct', CAST(SystemCpuPct AS DECIMAL(18,2)), NULL
    FROM [monitor].[CpuHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[CpuHistory]);

    -- Memory
    INSERT INTO @Metrics (MetricName, CurrentValue, Context)
    SELECT 'Memory_PLE', CAST(PageLifeExpectancy AS DECIMAL(18,2)), NULL
    FROM [monitor].[MemoryHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[MemoryHistory]);

    INSERT INTO @Metrics (MetricName, CurrentValue, Context)
    SELECT 'Memory_GrantsPending', CAST(MemoryGrantsPending AS DECIMAL(18,2)), NULL
    FROM [monitor].[MemoryHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[MemoryHistory]);

    INSERT INTO @Metrics (MetricName, CurrentValue, Context)
    SELECT 'Memory_BufferHitRatio', CAST(BufferCacheHitRatio AS DECIMAL(18,2)), NULL
    FROM [monitor].[MemoryHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[MemoryHistory]);

    -- Disk (per drive)
    INSERT INTO @Metrics (MetricName, CurrentValue, Context)
    SELECT 'Disk_UsedPct', CAST(UsedPct AS DECIMAL(18,2)), DriveLetter
    FROM [monitor].[DiskHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[DiskHistory]);

    INSERT INTO @Metrics (MetricName, CurrentValue, Context)
    SELECT 'Disk_ReadLatencyMs', CAST(AvgReadLatencyMs AS DECIMAL(18,2)), DriveLetter
    FROM [monitor].[DiskHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[DiskHistory])
        AND AvgReadLatencyMs IS NOT NULL;

    INSERT INTO @Metrics (MetricName, CurrentValue, Context)
    SELECT 'Disk_WriteLatencyMs', CAST(AvgWriteLatencyMs AS DECIMAL(18,2)), DriveLetter
    FROM [monitor].[DiskHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[DiskHistory])
        AND AvgWriteLatencyMs IS NOT NULL;

    -- AG
    INSERT INTO @Metrics (MetricName, CurrentValue, Context)
    SELECT 'AG_SecondsBehind', CAST(SecondsBehindPrimary AS DECIMAL(18,2)), ReplicaServer
    FROM [monitor].[AgHealthHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[AgHealthHistory])
        AND SecondsBehindPrimary IS NOT NULL;

    INSERT INTO @Metrics (MetricName, CurrentValue, Context)
    SELECT 'AG_LogSendQueueMB', CAST(LogSendQueueSizeKB / 1024.0 AS DECIMAL(18,2)), ReplicaServer
    FROM [monitor].[AgHealthHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[AgHealthHistory])
        AND LogSendQueueSizeKB IS NOT NULL;

    INSERT INTO @Metrics (MetricName, CurrentValue, Context)
    SELECT 'AG_RedoQueueMB', CAST(RedoQueueSizeKB / 1024.0 AS DECIMAL(18,2)), ReplicaServer
    FROM [monitor].[AgHealthHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[AgHealthHistory])
        AND RedoQueueSizeKB IS NOT NULL;

    -- CDC
    INSERT INTO @Metrics (MetricName, CurrentValue, Context)
    SELECT 'CDC_LatencySeconds', CAST(LatencySeconds AS DECIMAL(18,2)), DatabaseName
    FROM [monitor].[CdcHealthHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[CdcHealthHistory])
        AND LatencySeconds IS NOT NULL;

    -- Blocking (current active)
    INSERT INTO @Metrics (MetricName, CurrentValue, Context)
    SELECT 'Blocking_DurationSec', CAST(MAX(BlockingDurationSec) AS DECIMAL(18,2)), NULL
    FROM [monitor].[BlockingHistory]
    WHERE DetectedAt >= DATEADD(MINUTE, -5, @Now);

    -- Backups
    INSERT INTO @Metrics (MetricName, CurrentValue, Context)
    SELECT 'Backup_FullHours', CAST(MAX(HoursSinceLastBackup) AS DECIMAL(18,2)), DatabaseName
    FROM [monitor].[BackupHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[BackupHistory])
        AND BackupType = 'D'
    GROUP BY DatabaseName;

    INSERT INTO @Metrics (MetricName, CurrentValue, Context)
    SELECT 'Backup_LogHours', CAST(MAX(HoursSinceLastBackup) AS DECIMAL(18,2)), DatabaseName
    FROM [monitor].[BackupHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[BackupHistory])
        AND BackupType = 'L'
    GROUP BY DatabaseName;

    -- TempDB
    INSERT INTO @Metrics (MetricName, CurrentValue, Context)
    SELECT 'TempDB_UsedPct', CAST(CAST(UsedSpaceMB AS DECIMAL(18,2)) / NULLIF(TotalSizeMB, 0) * 100 AS DECIMAL(18,2)), NULL
    FROM [monitor].[TempDbHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[TempDbHistory]);

    -- Failed jobs
    INSERT INTO @Metrics (MetricName, CurrentValue, Context)
    SELECT 'Jobs_FailedCount', CAST(COUNT(*) AS DECIMAL(18,2)), NULL
    FROM [monitor].[JobHistory]
    WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[JobHistory])
        AND LastRunStatus = 'Failed';

    -- ============================================================
    -- EVALUATE THRESHOLDS
    -- ============================================================
    DECLARE @Alerts TABLE (
        MetricName      NVARCHAR(100),
        Severity        NVARCHAR(20),
        CurrentValue    DECIMAL(18,2),
        ThresholdValue  DECIMAL(18,2),
        Context         NVARCHAR(500)
    );

    -- Check each metric against thresholds
    INSERT INTO @Alerts (MetricName, Severity, CurrentValue, ThresholdValue, Context)
    SELECT 
        m.MetricName,
        CASE 
            WHEN t.Operator = '>=' AND m.CurrentValue >= t.CriticalValue THEN 'Critical'
            WHEN t.Operator = '<=' AND m.CurrentValue <= t.CriticalValue THEN 'Critical'
            WHEN t.Operator = '>=' AND m.CurrentValue >= t.WarningValue THEN 'Warning'
            WHEN t.Operator = '<=' AND m.CurrentValue <= t.WarningValue THEN 'Warning'
        END AS Severity,
        m.CurrentValue,
        CASE 
            WHEN t.Operator = '>=' AND m.CurrentValue >= t.CriticalValue THEN t.CriticalValue
            WHEN t.Operator = '<=' AND m.CurrentValue <= t.CriticalValue THEN t.CriticalValue
            WHEN t.Operator = '>=' AND m.CurrentValue >= t.WarningValue THEN t.WarningValue
            WHEN t.Operator = '<=' AND m.CurrentValue <= t.WarningValue THEN t.WarningValue
        END AS ThresholdValue,
        m.Context
    FROM @Metrics m
    INNER JOIN [monitor].[Thresholds] t ON m.MetricName = t.MetricName
    WHERE t.IsEnabled = 1
        AND (
            (t.Operator = '>=' AND (m.CurrentValue >= t.WarningValue OR m.CurrentValue >= t.CriticalValue))
            OR (t.Operator = '<=' AND (m.CurrentValue <= t.WarningValue OR m.CurrentValue <= t.CriticalValue))
        );

    -- Remove alerts still in cooldown
    DELETE a
    FROM @Alerts a
    INNER JOIN [monitor].[AlertCooldown] c 
        ON a.MetricName = c.MetricName
        AND c.LastFiredAt >= DATEADD(MINUTE, -@CooldownMinutes, @Now)
        AND c.Severity = a.Severity;

    -- ============================================================
    -- FIRE ALERTS
    -- ============================================================
    IF NOT EXISTS (SELECT 1 FROM @Alerts)
    BEGIN
        IF @DebugMode = 1
            PRINT 'No alerts to fire.';
        RETURN;
    END;

    -- Log alerts to history
    INSERT INTO [monitor].[AlertHistory] (MetricName, Severity, CurrentValue, ThresholdValue, Message, Context, NotificationSent)
    SELECT 
        MetricName, Severity, CurrentValue, ThresholdValue,
        MetricName + ' = ' + CAST(CurrentValue AS NVARCHAR) 
            + ' (threshold: ' + CAST(ThresholdValue AS NVARCHAR) + ')'
            + ISNULL(' [' + Context + ']', ''),
        Context,
        0  -- Will be set to 1 after email is sent
    FROM @Alerts;

    -- Update cooldown
    MERGE [monitor].[AlertCooldown] AS target
    USING (SELECT DISTINCT MetricName, Severity FROM @Alerts) AS source
        ON target.MetricName = source.MetricName
    WHEN MATCHED THEN
        UPDATE SET LastFiredAt = @Now, Severity = source.Severity
    WHEN NOT MATCHED THEN
        INSERT (MetricName, LastFiredAt, Severity)
        VALUES (source.MetricName, @Now, source.Severity);

    -- Build alert email
    DECLARE @AlertHTML NVARCHAR(MAX) = '';
    DECLARE @CritCount INT = (SELECT COUNT(*) FROM @Alerts WHERE Severity = 'Critical');
    DECLARE @WarnCount INT = (SELECT COUNT(*) FROM @Alerts WHERE Severity = 'Warning');

    SET @AlertHTML = '<!DOCTYPE html><html><head><meta charset="utf-8"></head>'
        + '<body style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;margin:0;padding:0;background:#f8fafc;">'
        + '<div style="max-width:600px;margin:0 auto;background:white;border-radius:8px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.1);">';

    -- Header with severity color
    SET @AlertHTML = @AlertHTML + '<div style="background:' 
        + CASE WHEN @CritCount > 0 THEN '#dc2626' ELSE '#d97706' END 
        + ';padding:20px 32px;color:white;">'
        + '<h1 style="margin:0;font-size:20px;">&#128680; '
        + CASE @Language WHEN 'ptbr' THEN 'Alerta SQL Health Monitor' ELSE 'SQL Health Monitor Alert' END + '</h1>'
        + '<p style="margin:6px 0 0;opacity:0.9;font-size:12px;">' + @ServerName + ' | ' + FORMAT(@Now, 'yyyy-MM-dd HH:mm:ss') + ' UTC</p>'
        + '</div>';

    -- Alert table
    SET @AlertHTML = @AlertHTML + '<div style="padding:20px 32px;">'
        + '<table style="width:100%;border-collapse:collapse;font-size:13px;">'
        + '<tr style="background:#0f172a;color:white;">'
        + '<th style="padding:8px;text-align:center;">Severity</th>'
        + '<th style="padding:8px;text-align:left;">Metric</th>'
        + '<th style="padding:8px;text-align:right;">Value</th>'
        + '<th style="padding:8px;text-align:right;">Threshold</th>'
        + '<th style="padding:8px;text-align:left;">Context</th></tr>';

    SELECT @AlertHTML = @AlertHTML + '<tr style="background:' 
        + CASE WHEN Severity = 'Critical' THEN '#fef2f2' ELSE '#fffbeb' END + ';">'
        + '<td style="padding:8px;text-align:center;font-weight:700;color:' 
            + CASE WHEN Severity = 'Critical' THEN '#dc2626' ELSE '#d97706' END + ';">' + Severity + '</td>'
        + '<td style="padding:8px;">' + MetricName + '</td>'
        + '<td style="padding:8px;text-align:right;font-weight:600;">' + CAST(CurrentValue AS NVARCHAR) + '</td>'
        + '<td style="padding:8px;text-align:right;">' + CAST(ThresholdValue AS NVARCHAR) + '</td>'
        + '<td style="padding:8px;">' + ISNULL(Context, '-') + '</td></tr>'
    FROM @Alerts
    ORDER BY CASE Severity WHEN 'Critical' THEN 1 ELSE 2 END, MetricName;

    SET @AlertHTML = @AlertHTML + '</table></div>'
        + '<div style="background:#f1f5f9;padding:12px 32px;font-size:11px;color:#64748b;text-align:center;">'
        + 'Cooldown: ' + CAST(@CooldownMinutes AS NVARCHAR) + ' min | SQL Health Monitor</div>'
        + '</div></body></html>';

    -- Send or debug
    IF @DebugMode = 1
    BEGIN
        SELECT * FROM @Alerts ORDER BY CASE Severity WHEN 'Critical' THEN 1 ELSE 2 END;
        SELECT @AlertHTML AS AlertEmail;
        RETURN;
    END;

    -- Send email
    DECLARE @Subject NVARCHAR(200) = @SubjectPrefix + ' '
        + CASE WHEN @CritCount > 0 THEN '&#128308; CRITICAL' ELSE '&#9888; WARNING' END
        + ' - ' + CAST(@CritCount + @WarnCount AS NVARCHAR) + ' alert(s) - ' + @ServerName;

    EXEC msdb.dbo.sp_send_dbmail
        @profile_name = @ProfileName,
        @recipients = @Recipients,
        @subject = @Subject,
        @body = @AlertHTML,
        @body_format = 'HTML';

    -- Mark alerts as notified
    UPDATE [monitor].[AlertHistory]
    SET NotificationSent = 1
    WHERE FiredAt >= DATEADD(SECOND, -5, @Now)
        AND NotificationSent = 0;
END;
GO

PRINT '✓ Alert engine [monitor].[usp_AlertEngine_Check] created.';
GO
