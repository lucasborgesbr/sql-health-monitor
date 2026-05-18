/*
    SQL Health Monitor - Daily Health Report Generator
    Generates HTML email with daily health summary.
    
    Sends via Database Mail with traffic light indicators.
    Compatibility: SQL Server 2016+
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Report_DailyHealth]
    @OverrideLanguage CHAR(5) = NULL,
    @OverrideRecipients NVARCHAR(500) = NULL,
    @DebugMode BIT = 0  -- 1 = SELECT HTML instead of sending email
AS
BEGIN
    SET NOCOUNT ON;

    -- Get configuration
    DECLARE @Language CHAR(5) = ISNULL(@OverrideLanguage, 
        (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'General' AND SettingName = 'Language'));
    DECLARE @Recipients NVARCHAR(500) = ISNULL(@OverrideRecipients,
        (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'Email' AND SettingName = 'Recipients'));
    DECLARE @CcRecipients NVARCHAR(500) = 
        (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'Email' AND SettingName = 'CcRecipients');
    DECLARE @ProfileName NVARCHAR(128) = 
        (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'Email' AND SettingName = 'ProfileName');
    DECLARE @SubjectPrefix NVARCHAR(50) = 
        (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'Email' AND SettingName = 'SubjectPrefix');
    DECLARE @ServerName NVARCHAR(128) = 
        (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'General' AND SettingName = 'ServerName');

    -- Helper function for language strings
    DECLARE @Title NVARCHAR(200) = (SELECT StringValue FROM [monitor].[Languages] WHERE LanguageCode = @Language AND StringKey = 'report.daily.title');
    
    -- Date range: last 24 hours
    DECLARE @StartDate DATETIME2 = DATEADD(HOUR, -24, SYSUTCDATETIME());
    DECLARE @EndDate DATETIME2 = SYSUTCDATETIME();
    DECLARE @DateStr NVARCHAR(20) = FORMAT(SYSUTCDATETIME(), 'yyyy-MM-dd');

    -- Collect metrics for summary
    DECLARE @CpuAvg INT, @CpuMax INT, @CpuStatus NVARCHAR(10);
    DECLARE @PleMin INT, @PleAvg INT, @MemStatus NVARCHAR(10);
    DECLARE @DiskMaxPct DECIMAL(5,2), @DiskStatus NVARCHAR(10);
    DECLARE @AgMaxLag INT, @AgStatus NVARCHAR(10);
    DECLARE @BlockingCount INT;
    DECLARE @FailedJobs INT;
    DECLARE @ErrorCount INT;
    DECLARE @OverallStatus NVARCHAR(10);

    -- CPU Summary
    SELECT @CpuAvg = AVG(SqlCpuPct), @CpuMax = MAX(SqlCpuPct)
    FROM [monitor].[CpuHistory] WHERE CollectedAt >= @StartDate;
    SET @CpuStatus = CASE WHEN @CpuMax >= 95 THEN 'critical' WHEN @CpuMax >= 80 THEN 'warning' ELSE 'healthy' END;

    -- Memory Summary
    SELECT @PleMin = MIN(PageLifeExpectancy), @PleAvg = AVG(PageLifeExpectancy)
    FROM [monitor].[MemoryHistory] WHERE CollectedAt >= @StartDate;
    SET @MemStatus = CASE WHEN @PleMin <= 100 THEN 'critical' WHEN @PleMin <= 300 THEN 'warning' ELSE 'healthy' END;

    -- Disk Summary
    SELECT @DiskMaxPct = MAX(UsedPct)
    FROM [monitor].[DiskHistory] WHERE CollectedAt >= @StartDate;
    SET @DiskStatus = CASE WHEN @DiskMaxPct >= 95 THEN 'critical' WHEN @DiskMaxPct >= 85 THEN 'warning' ELSE 'healthy' END;

    -- AG Summary
    SELECT @AgMaxLag = MAX(SecondsBehindPrimary)
    FROM [monitor].[AgHealthHistory] WHERE CollectedAt >= @StartDate;
    SET @AgStatus = CASE WHEN @AgMaxLag >= 120 THEN 'critical' WHEN @AgMaxLag >= 30 THEN 'warning' ELSE 'healthy' END;

    -- Blocking count
    SELECT @BlockingCount = COUNT(*) FROM [monitor].[BlockingHistory] WHERE DetectedAt >= @StartDate;

    -- Failed jobs
    SELECT @FailedJobs = COUNT(DISTINCT JobName) FROM [monitor].[JobHistory] 
    WHERE CollectedAt >= @StartDate AND LastRunStatus = 'Failed';

    -- Error count
    SELECT @ErrorCount = COUNT(*) FROM [monitor].[ErrorLogHistory] 
    WHERE CollectedAt >= @StartDate AND Severity IN ('Critical', 'Error');

    -- Overall status
    SET @OverallStatus = CASE 
        WHEN @CpuStatus = 'critical' OR @MemStatus = 'critical' OR @DiskStatus = 'critical' OR @AgStatus = 'critical' THEN 'critical'
        WHEN @CpuStatus = 'warning' OR @MemStatus = 'warning' OR @DiskStatus = 'warning' OR @AgStatus = 'warning' THEN 'warning'
        ELSE 'healthy' END;

    -- Build HTML
    DECLARE @HTML NVARCHAR(MAX) = '';
    DECLARE @StatusEmoji NVARCHAR(10) = CASE @OverallStatus 
        WHEN 'healthy' THEN '&#9989;' WHEN 'warning' THEN '&#9888;' ELSE '&#128308;' END;
    DECLARE @StatusColor NVARCHAR(10) = CASE @OverallStatus 
        WHEN 'healthy' THEN '#059669' WHEN 'warning' THEN '#d97706' ELSE '#dc2626' END;

    SET @HTML = @HTML + '<!DOCTYPE html><html><head><meta charset="utf-8"></head><body style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;margin:0;padding:0;background:#f8fafc;">';
    SET @HTML = @HTML + '<div style="max-width:700px;margin:0 auto;background:white;border-radius:8px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.1);">';
    
    -- Header
    SET @HTML = @HTML + '<div style="background:linear-gradient(135deg,#0f172a,#1e3a5f);padding:24px 32px;color:white;">';
    SET @HTML = @HTML + '<h1 style="margin:0;font-size:22px;font-weight:700;">' + @StatusEmoji + ' ' + @Title + '</h1>';
    SET @HTML = @HTML + '<p style="margin:8px 0 0;opacity:0.8;font-size:13px;">' + @ServerName + ' | ' + @DateStr + '</p>';
    SET @HTML = @HTML + '</div>';

    -- Overall Status Banner
    SET @HTML = @HTML + '<div style="background:' + @StatusColor + ';padding:12px 32px;color:white;font-weight:600;font-size:14px;">';
    SET @HTML = @HTML + CASE @OverallStatus 
        WHEN 'healthy' THEN CASE @Language WHEN 'ptbr' THEN 'Todos os sistemas saudáveis' ELSE 'All Systems Healthy' END
        WHEN 'warning' THEN CASE @Language WHEN 'ptbr' THEN 'Atenção necessária em alguns itens' ELSE 'Attention Needed on Some Items' END
        ELSE CASE @Language WHEN 'ptbr' THEN 'Problemas críticos detectados' ELSE 'Critical Issues Detected' END END;
    SET @HTML = @HTML + '</div>';

    -- Summary Cards
    SET @HTML = @HTML + '<div style="padding:24px 32px;">';
    SET @HTML = @HTML + '<table style="width:100%;border-collapse:collapse;margin-bottom:24px;">';
    SET @HTML = @HTML + '<tr>';
    
    -- CPU Card
    SET @HTML = @HTML + '<td style="padding:12px;text-align:center;border:1px solid #e2e8f0;border-radius:8px;width:25%;">';
    SET @HTML = @HTML + '<div style="font-size:11px;color:#64748b;text-transform:uppercase;letter-spacing:0.5px;">' 
        + CASE @Language WHEN 'ptbr' THEN 'CPU' ELSE 'CPU' END + '</div>';
    SET @HTML = @HTML + '<div style="font-size:24px;font-weight:700;color:' 
        + CASE @CpuStatus WHEN 'healthy' THEN '#059669' WHEN 'warning' THEN '#d97706' ELSE '#dc2626' END 
        + ';">' + ISNULL(CAST(@CpuAvg AS NVARCHAR), 'N/A') + '%</div>';
    SET @HTML = @HTML + '<div style="font-size:10px;color:#94a3b8;">max: ' + ISNULL(CAST(@CpuMax AS NVARCHAR), '-') + '%</div></td>';
    
    -- Memory Card
    SET @HTML = @HTML + '<td style="padding:12px;text-align:center;border:1px solid #e2e8f0;border-radius:8px;width:25%;">';
    SET @HTML = @HTML + '<div style="font-size:11px;color:#64748b;text-transform:uppercase;letter-spacing:0.5px;">'
        + CASE @Language WHEN 'ptbr' THEN 'PLE' ELSE 'PLE' END + '</div>';
    SET @HTML = @HTML + '<div style="font-size:24px;font-weight:700;color:' 
        + CASE @MemStatus WHEN 'healthy' THEN '#059669' WHEN 'warning' THEN '#d97706' ELSE '#dc2626' END 
        + ';">' + ISNULL(CAST(@PleAvg AS NVARCHAR), 'N/A') + 's</div>';
    SET @HTML = @HTML + '<div style="font-size:10px;color:#94a3b8;">min: ' + ISNULL(CAST(@PleMin AS NVARCHAR), '-') + 's</div></td>';
    
    -- Disk Card
    SET @HTML = @HTML + '<td style="padding:12px;text-align:center;border:1px solid #e2e8f0;border-radius:8px;width:25%;">';
    SET @HTML = @HTML + '<div style="font-size:11px;color:#64748b;text-transform:uppercase;letter-spacing:0.5px;">'
        + CASE @Language WHEN 'ptbr' THEN 'DISCO' ELSE 'DISK' END + '</div>';
    SET @HTML = @HTML + '<div style="font-size:24px;font-weight:700;color:' 
        + CASE @DiskStatus WHEN 'healthy' THEN '#059669' WHEN 'warning' THEN '#d97706' ELSE '#dc2626' END 
        + ';">' + ISNULL(CAST(CAST(@DiskMaxPct AS INT) AS NVARCHAR), 'N/A') + '%</div>';
    SET @HTML = @HTML + '<div style="font-size:10px;color:#94a3b8;">max used</div></td>';
    
    -- AG Card
    SET @HTML = @HTML + '<td style="padding:12px;text-align:center;border:1px solid #e2e8f0;border-radius:8px;width:25%;">';
    SET @HTML = @HTML + '<div style="font-size:11px;color:#64748b;text-transform:uppercase;letter-spacing:0.5px;">AG LAG</div>';
    SET @HTML = @HTML + '<div style="font-size:24px;font-weight:700;color:' 
        + CASE @AgStatus WHEN 'healthy' THEN '#059669' WHEN 'warning' THEN '#d97706' ELSE '#dc2626' END 
        + ';">' + ISNULL(CAST(@AgMaxLag AS NVARCHAR), '0') + 's</div>';
    SET @HTML = @HTML + '<div style="font-size:10px;color:#94a3b8;">max lag</div></td>';
    SET @HTML = @HTML + '</tr></table>';

    -- Issues Section
    IF @BlockingCount > 0 OR @FailedJobs > 0 OR @ErrorCount > 0
    BEGIN
        SET @HTML = @HTML + '<h2 style="font-size:16px;color:#0f172a;border-bottom:2px solid #e2e8f0;padding-bottom:8px;">'
            + CASE @Language WHEN 'ptbr' THEN 'Problemas Detectados' ELSE 'Issues Detected' END + '</h2>';
        SET @HTML = @HTML + '<table style="width:100%;border-collapse:collapse;font-size:13px;">';
        
        IF @BlockingCount > 0
            SET @HTML = @HTML + '<tr><td style="padding:8px;border-bottom:1px solid #f1f5f9;">&#128308; '
                + CASE @Language WHEN 'ptbr' THEN 'Bloqueios' ELSE 'Blocking Events' END 
                + '</td><td style="padding:8px;border-bottom:1px solid #f1f5f9;font-weight:700;">' + CAST(@BlockingCount AS NVARCHAR) + '</td></tr>';
        
        IF @FailedJobs > 0
            SET @HTML = @HTML + '<tr><td style="padding:8px;border-bottom:1px solid #f1f5f9;">&#9888; '
                + CASE @Language WHEN 'ptbr' THEN 'Jobs com Falha' ELSE 'Failed Jobs' END 
                + '</td><td style="padding:8px;border-bottom:1px solid #f1f5f9;font-weight:700;">' + CAST(@FailedJobs AS NVARCHAR) + '</td></tr>';
        
        IF @ErrorCount > 0
            SET @HTML = @HTML + '<tr><td style="padding:8px;border-bottom:1px solid #f1f5f9;">&#9888; '
                + CASE @Language WHEN 'ptbr' THEN 'Erros no Log' ELSE 'Error Log Entries' END 
                + '</td><td style="padding:8px;border-bottom:1px solid #f1f5f9;font-weight:700;">' + CAST(@ErrorCount AS NVARCHAR) + '</td></tr>';
        
        SET @HTML = @HTML + '</table>';
    END;

    -- Top Waits Section
    SET @HTML = @HTML + '<h2 style="font-size:16px;color:#0f172a;border-bottom:2px solid #e2e8f0;padding-bottom:8px;margin-top:24px;">'
        + CASE @Language WHEN 'ptbr' THEN 'Top Waits (24h)' ELSE 'Top Waits (24h)' END + '</h2>';
    SET @HTML = @HTML + '<table style="width:100%;border-collapse:collapse;font-size:12px;">';
    SET @HTML = @HTML + '<tr style="background:#0f172a;color:white;"><th style="padding:8px;text-align:left;">Wait Type</th><th style="padding:8px;text-align:right;">Total (ms)</th><th style="padding:8px;text-align:right;">Delta (ms)</th></tr>';
    
    SELECT @HTML = @HTML + '<tr style="background:' + CASE WHEN ROW_NUMBER() OVER (ORDER BY DeltaWaitTimeMs DESC) % 2 = 0 THEN '#f8fafc' ELSE 'white' END + ';">'
        + '<td style="padding:6px 8px;">' + WaitType + '</td>'
        + '<td style="padding:6px 8px;text-align:right;">' + FORMAT(WaitTimeMs, 'N0') + '</td>'
        + '<td style="padding:6px 8px;text-align:right;">' + ISNULL(FORMAT(DeltaWaitTimeMs, 'N0'), '-') + '</td></tr>'
    FROM (
        SELECT TOP 5 WaitType, SUM(WaitTimeMs) AS WaitTimeMs, SUM(DeltaWaitTimeMs) AS DeltaWaitTimeMs
        FROM [monitor].[WaitStatsHistory]
        WHERE CollectedAt >= @StartDate
        GROUP BY WaitType
        ORDER BY SUM(ISNULL(DeltaWaitTimeMs, WaitTimeMs)) DESC
    ) w;
    SET @HTML = @HTML + '</table>';

    -- Backup Status Section
    SET @HTML = @HTML + '<h2 style="font-size:16px;color:#0f172a;border-bottom:2px solid #e2e8f0;padding-bottom:8px;margin-top:24px;">'
        + CASE @Language WHEN 'ptbr' THEN 'Status de Backup' ELSE 'Backup Status' END + '</h2>';
    SET @HTML = @HTML + '<table style="width:100%;border-collapse:collapse;font-size:12px;">';
    SET @HTML = @HTML + '<tr style="background:#0f172a;color:white;"><th style="padding:8px;text-align:left;">'
        + CASE @Language WHEN 'ptbr' THEN 'Banco' ELSE 'Database' END 
        + '</th><th style="padding:8px;text-align:center;">Full</th><th style="padding:8px;text-align:center;">Diff</th><th style="padding:8px;text-align:center;">Log</th></tr>';
    
    SELECT @HTML = @HTML + '<tr><td style="padding:6px 8px;">' + DatabaseName + '</td>'
        + '<td style="padding:6px 8px;text-align:center;">' 
        + CASE WHEN FullHours IS NULL THEN '&#128308; Never'
               WHEN FullHours > 48 THEN '&#128308; ' + CAST(FullHours AS NVARCHAR) + 'h'
               WHEN FullHours > 25 THEN '&#9888; ' + CAST(FullHours AS NVARCHAR) + 'h'
               ELSE '&#9989; ' + CAST(FullHours AS NVARCHAR) + 'h' END + '</td>'
        + '<td style="padding:6px 8px;text-align:center;">' + ISNULL(CAST(DiffHours AS NVARCHAR) + 'h', '-') + '</td>'
        + '<td style="padding:6px 8px;text-align:center;">' 
        + CASE WHEN LogHours IS NULL THEN '-'
               WHEN LogHours > 4 THEN '&#128308; ' + CAST(LogHours AS NVARCHAR) + 'h'
               WHEN LogHours > 1 THEN '&#9888; ' + CAST(LogHours AS NVARCHAR) + 'h'
               ELSE '&#9989; ' + CAST(LogHours AS NVARCHAR) + 'h' END + '</td></tr>'
    FROM (
        SELECT 
            b.DatabaseName,
            MAX(CASE WHEN b.BackupType = 'D' THEN b.HoursSinceLastBackup END) AS FullHours,
            MAX(CASE WHEN b.BackupType = 'I' THEN b.HoursSinceLastBackup END) AS DiffHours,
            MAX(CASE WHEN b.BackupType = 'L' THEN b.HoursSinceLastBackup END) AS LogHours
        FROM [monitor].[BackupHistory] b
        WHERE b.CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[BackupHistory])
        GROUP BY b.DatabaseName
    ) bk;
    SET @HTML = @HTML + '</table>';

    -- Footer
    SET @HTML = @HTML + '</div>';  -- Close padding div
    SET @HTML = @HTML + '<div style="background:#f1f5f9;padding:16px 32px;font-size:11px;color:#64748b;text-align:center;">';
    SET @HTML = @HTML + 'SQL Health Monitor | ' + @ServerName + ' | Generated: ' + FORMAT(SYSUTCDATETIME(), 'yyyy-MM-dd HH:mm:ss') + ' UTC';
    SET @HTML = @HTML + '</div>';
    SET @HTML = @HTML + '</div></body></html>';

    -- Send or debug
    IF @DebugMode = 1
    BEGIN
        SELECT @HTML AS HtmlReport;
        RETURN;
    END;

    -- Send email
    DECLARE @Subject NVARCHAR(200) = @SubjectPrefix + ' ' + 
        CASE @OverallStatus WHEN 'healthy' THEN '&#9989;' WHEN 'warning' THEN '&#9888;' ELSE '&#128308;' END
        + ' ' + @Title + ' - ' + @DateStr;

    EXEC msdb.dbo.sp_send_dbmail
        @profile_name = @ProfileName,
        @recipients = @Recipients,
        @copy_recipients = @CcRecipients,
        @subject = @Subject,
        @body = @HTML,
        @body_format = 'HTML';

    -- Log report
    INSERT INTO [monitor].[ReportHistory] (ReportType, Recipients, Language, Success)
    VALUES ('Daily', @Recipients, @Language, 1);
END;
GO
