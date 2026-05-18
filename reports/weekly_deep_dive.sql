/*
    SQL Health Monitor - Weekly Deep Dive Report
    Generates comprehensive HTML email with week-over-week analysis.
    
    Includes: growth trends, capacity planning, performance baselines,
    top queries, index recommendations, AG history, and prioritized recommendations.
    
    Schedule: Monday 8:00 AM
    Compatibility: SQL Server 2016+
*/

USE [DBA_Monitor];
GO

CREATE OR ALTER PROCEDURE [monitor].[usp_Report_WeeklyDeepDive]
    @OverrideLanguage CHAR(5) = NULL,
    @OverrideRecipients NVARCHAR(500) = NULL,
    @DebugMode BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- Configuration
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

    -- Date ranges
    DECLARE @ThisWeekStart DATETIME2 = DATEADD(DAY, -7, SYSUTCDATETIME());
    DECLARE @LastWeekStart DATETIME2 = DATEADD(DAY, -14, SYSUTCDATETIME());
    DECLARE @LastWeekEnd DATETIME2 = DATEADD(DAY, -7, SYSUTCDATETIME());
    DECLARE @Now DATETIME2 = SYSUTCDATETIME();
    DECLARE @WeekStr NVARCHAR(30) = FORMAT(@ThisWeekStart, 'MMM dd') + ' - ' + FORMAT(@Now, 'MMM dd, yyyy');

    -- Language strings
    DECLARE @Title NVARCHAR(200) = (SELECT StringValue FROM [monitor].[Languages] WHERE LanguageCode = @Language AND StringKey = 'report.weekly.title');
    SET @Title = ISNULL(@Title, 'Weekly SQL Health Deep Dive');

    -- ============================================================
    -- COLLECT METRICS FOR COMPARISON
    -- ============================================================
    DECLARE @CpuAvgThis INT, @CpuMaxThis INT, @CpuAvgLast INT, @CpuMaxLast INT;
    SELECT @CpuAvgThis = AVG(SqlCpuPct), @CpuMaxThis = MAX(SqlCpuPct)
    FROM [monitor].[CpuHistory] WHERE CollectedAt >= @ThisWeekStart;
    SELECT @CpuAvgLast = AVG(SqlCpuPct), @CpuMaxLast = MAX(SqlCpuPct)
    FROM [monitor].[CpuHistory] WHERE CollectedAt >= @LastWeekStart AND CollectedAt < @LastWeekEnd;

    DECLARE @PleAvgThis INT, @PleMinThis INT, @PleAvgLast INT, @PleMinLast INT;
    SELECT @PleAvgThis = AVG(PageLifeExpectancy), @PleMinThis = MIN(PageLifeExpectancy)
    FROM [monitor].[MemoryHistory] WHERE CollectedAt >= @ThisWeekStart;
    SELECT @PleAvgLast = AVG(PageLifeExpectancy), @PleMinLast = MIN(PageLifeExpectancy)
    FROM [monitor].[MemoryHistory] WHERE CollectedAt >= @LastWeekStart AND CollectedAt < @LastWeekEnd;

    DECLARE @BlockingThis INT, @BlockingLast INT;
    SELECT @BlockingThis = COUNT(*) FROM [monitor].[BlockingHistory] WHERE DetectedAt >= @ThisWeekStart;
    SELECT @BlockingLast = COUNT(*) FROM [monitor].[BlockingHistory] WHERE DetectedAt >= @LastWeekStart AND DetectedAt < @LastWeekEnd;

    DECLARE @AlertsThis INT, @AlertsLast INT;
    SELECT @AlertsThis = COUNT(*) FROM [monitor].[AlertHistory] WHERE FiredAt >= @ThisWeekStart;
    SELECT @AlertsLast = COUNT(*) FROM [monitor].[AlertHistory] WHERE FiredAt >= @LastWeekStart AND FiredAt < @LastWeekEnd;

    -- ============================================================
    -- BUILD HTML
    -- ============================================================
    DECLARE @HTML NVARCHAR(MAX) = '';

    -- HTML open + header
    SET @HTML = '<!DOCTYPE html><html><head><meta charset="utf-8"></head>'
        + '<body style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;margin:0;padding:0;background:#f8fafc;">'
        + '<div style="max-width:800px;margin:0 auto;background:white;border-radius:8px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.1);">'
        + '<div style="background:linear-gradient(135deg,#1e3a5f,#2563eb);padding:28px 32px;color:white;">'
        + '<h1 style="margin:0;font-size:24px;font-weight:700;">&#128202; ' + @Title + '</h1>'
        + '<p style="margin:8px 0 0;opacity:0.8;font-size:13px;">' + @ServerName + ' | ' + @WeekStr + '</p>'
        + '</div>';

    -- SECTION 1: Executive Summary
    SET @HTML = @HTML + '<div style="padding:24px 32px;">';
    SET @HTML = @HTML + '<h2 style="font-size:18px;color:#0f172a;border-bottom:2px solid #2563eb;padding-bottom:8px;">'
        + CASE @Language WHEN 'ptbr' THEN '&#128200; Resumo Semanal' ELSE '&#128200; Weekly Summary' END + '</h2>';

    SET @HTML = @HTML + '<table style="width:100%;border-collapse:collapse;font-size:13px;margin-bottom:20px;">'
        + '<tr style="background:#0f172a;color:white;">'
        + '<th style="padding:10px;text-align:left;">' + CASE @Language WHEN 'ptbr' THEN 'M&#233;trica' ELSE 'Metric' END + '</th>'
        + '<th style="padding:10px;text-align:center;">' + CASE @Language WHEN 'ptbr' THEN 'Esta Semana' ELSE 'This Week' END + '</th>'
        + '<th style="padding:10px;text-align:center;">' + CASE @Language WHEN 'ptbr' THEN 'Semana Anterior' ELSE 'Last Week' END + '</th>'
        + '<th style="padding:10px;text-align:center;">' + CASE @Language WHEN 'ptbr' THEN 'Tend&#234;ncia' ELSE 'Trend' END + '</th></tr>';

    -- CPU row
    SET @HTML = @HTML + '<tr><td style="padding:8px;">CPU Avg</td>'
        + '<td style="padding:8px;text-align:center;">' + ISNULL(CAST(@CpuAvgThis AS NVARCHAR), 'N/A') + '%</td>'
        + '<td style="padding:8px;text-align:center;">' + ISNULL(CAST(@CpuAvgLast AS NVARCHAR), 'N/A') + '%</td>'
        + '<td style="padding:8px;text-align:center;">' + CASE 
            WHEN @CpuAvgThis > @CpuAvgLast THEN '&#128308; &#8593;'
            WHEN @CpuAvgThis < @CpuAvgLast THEN '&#9989; &#8595;'
            ELSE '&#9898; &#8596;' END + '</td></tr>';

    -- PLE row
    SET @HTML = @HTML + '<tr style="background:#f8fafc;"><td style="padding:8px;">PLE Avg</td>'
        + '<td style="padding:8px;text-align:center;">' + ISNULL(CAST(@PleAvgThis AS NVARCHAR), 'N/A') + 's</td>'
        + '<td style="padding:8px;text-align:center;">' + ISNULL(CAST(@PleAvgLast AS NVARCHAR), 'N/A') + 's</td>'
        + '<td style="padding:8px;text-align:center;">' + CASE 
            WHEN @PleAvgThis < @PleAvgLast THEN '&#128308; &#8595;'
            WHEN @PleAvgThis > @PleAvgLast THEN '&#9989; &#8593;'
            ELSE '&#9898; &#8596;' END + '</td></tr>';

    -- Blocking row
    SET @HTML = @HTML + '<tr><td style="padding:8px;">' + CASE @Language WHEN 'ptbr' THEN 'Bloqueios' ELSE 'Blocking Events' END + '</td>'
        + '<td style="padding:8px;text-align:center;">' + CAST(ISNULL(@BlockingThis, 0) AS NVARCHAR) + '</td>'
        + '<td style="padding:8px;text-align:center;">' + CAST(ISNULL(@BlockingLast, 0) AS NVARCHAR) + '</td>'
        + '<td style="padding:8px;text-align:center;">' + CASE 
            WHEN @BlockingThis > @BlockingLast THEN '&#128308; &#8593;'
            WHEN @BlockingThis < @BlockingLast THEN '&#9989; &#8595;'
            ELSE '&#9898; &#8596;' END + '</td></tr>';

    -- Alerts row
    SET @HTML = @HTML + '<tr style="background:#f8fafc;"><td style="padding:8px;">' + CASE @Language WHEN 'ptbr' THEN 'Alertas' ELSE 'Alerts Fired' END + '</td>'
        + '<td style="padding:8px;text-align:center;">' + CAST(ISNULL(@AlertsThis, 0) AS NVARCHAR) + '</td>'
        + '<td style="padding:8px;text-align:center;">' + CAST(ISNULL(@AlertsLast, 0) AS NVARCHAR) + '</td>'
        + '<td style="padding:8px;text-align:center;">' + CASE 
            WHEN @AlertsThis > @AlertsLast THEN '&#128308; &#8593;'
            WHEN @AlertsThis < @AlertsLast THEN '&#9989; &#8595;'
            ELSE '&#9898; &#8596;' END + '</td></tr>';

    SET @HTML = @HTML + '</table>';

    -- ============================================================
    -- SECTION 2: Disk Growth & Capacity Planning
    -- ============================================================
    SET @HTML = @HTML + '<h2 style="font-size:18px;color:#0f172a;border-bottom:2px solid #2563eb;padding-bottom:8px;margin-top:28px;">'
        + CASE @Language WHEN 'ptbr' THEN '&#128190; Crescimento e Capacidade' ELSE '&#128190; Growth &amp; Capacity Planning' END + '</h2>';

    SET @HTML = @HTML + '<table style="width:100%;border-collapse:collapse;font-size:12px;">'
        + '<tr style="background:#0f172a;color:white;">'
        + '<th style="padding:8px;text-align:left;">Drive</th>'
        + '<th style="padding:8px;text-align:right;">Total (GB)</th>'
        + '<th style="padding:8px;text-align:right;">Used (%)</th>'
        + '<th style="padding:8px;text-align:right;">Growth/Week</th>'
        + '<th style="padding:8px;text-align:right;">Days to 95%</th></tr>';

    SELECT @HTML = @HTML + '<tr style="background:' + CASE WHEN ROW_NUMBER() OVER (ORDER BY d.DriveLetter) % 2 = 0 THEN '#f8fafc' ELSE 'white' END + ';">'
        + '<td style="padding:6px 8px;font-weight:600;">' + d.DriveLetter + '</td>'
        + '<td style="padding:6px 8px;text-align:right;">' + CAST(CAST(d.TotalSpaceMB / 1024.0 AS DECIMAL(10,1)) AS NVARCHAR) + '</td>'
        + '<td style="padding:6px 8px;text-align:right;color:' 
            + CASE WHEN d.UsedPct >= 95 THEN '#dc2626' WHEN d.UsedPct >= 85 THEN '#d97706' ELSE '#059669' END 
            + ';">' + CAST(CAST(d.UsedPct AS DECIMAL(5,1)) AS NVARCHAR) + '%</td>'
        + '<td style="padding:6px 8px;text-align:right;">' 
            + ISNULL(CAST(CAST(d.GrowthMB / 1024.0 AS DECIMAL(10,2)) AS NVARCHAR) + ' GB', '-') + '</td>'
        + '<td style="padding:6px 8px;text-align:right;font-weight:600;color:' 
            + CASE WHEN d.DaysTo95 <= 30 THEN '#dc2626' WHEN d.DaysTo95 <= 90 THEN '#d97706' ELSE '#059669' END 
            + ';">' + CASE WHEN d.DaysTo95 IS NULL OR d.DaysTo95 > 9999 THEN '&#8734;' ELSE CAST(d.DaysTo95 AS NVARCHAR) END + '</td></tr>'
    FROM (
        SELECT 
            curr.DriveLetter, curr.TotalSpaceMB, curr.UsedPct,
            (curr.TotalSpaceMB - curr.FreeSpaceMB) - ISNULL((prev.TotalSpaceMB - prev.FreeSpaceMB), (curr.TotalSpaceMB - curr.FreeSpaceMB)) AS GrowthMB,
            CASE 
                WHEN ((curr.TotalSpaceMB - curr.FreeSpaceMB) - ISNULL((prev.TotalSpaceMB - prev.FreeSpaceMB), (curr.TotalSpaceMB - curr.FreeSpaceMB))) <= 0 THEN NULL
                ELSE CAST(((curr.TotalSpaceMB * 0.95) - (curr.TotalSpaceMB - curr.FreeSpaceMB)) 
                    / NULLIF(((curr.TotalSpaceMB - curr.FreeSpaceMB) - ISNULL((prev.TotalSpaceMB - prev.FreeSpaceMB), (curr.TotalSpaceMB - curr.FreeSpaceMB))) / 7.0, 0) AS INT)
            END AS DaysTo95
        FROM (
            SELECT DriveLetter, AVG(TotalSpaceMB) AS TotalSpaceMB, AVG(FreeSpaceMB) AS FreeSpaceMB, AVG(UsedPct) AS UsedPct
            FROM [monitor].[DiskHistory] WHERE CollectedAt >= DATEADD(HOUR, -6, SYSUTCDATETIME())
            GROUP BY DriveLetter
        ) curr
        LEFT JOIN (
            SELECT DriveLetter, AVG(TotalSpaceMB) AS TotalSpaceMB, AVG(FreeSpaceMB) AS FreeSpaceMB
            FROM [monitor].[DiskHistory] WHERE CollectedAt >= @LastWeekStart AND CollectedAt < DATEADD(HOUR, 6, @LastWeekStart)
            GROUP BY DriveLetter
        ) prev ON curr.DriveLetter = prev.DriveLetter
    ) d;

    SET @HTML = @HTML + '</table>';

    -- ============================================================
    -- SECTION 3: Database File Growth
    -- ============================================================
    SET @HTML = @HTML + '<h2 style="font-size:18px;color:#0f172a;border-bottom:2px solid #2563eb;padding-bottom:8px;margin-top:28px;">'
        + CASE @Language WHEN 'ptbr' THEN '&#128196; Crescimento de Arquivos' ELSE '&#128196; Database File Growth' END + '</h2>';

    SET @HTML = @HTML + '<table style="width:100%;border-collapse:collapse;font-size:12px;">'
        + '<tr style="background:#0f172a;color:white;">'
        + '<th style="padding:8px;text-align:left;">Database</th>'
        + '<th style="padding:8px;text-align:left;">File</th>'
        + '<th style="padding:8px;text-align:center;">Type</th>'
        + '<th style="padding:8px;text-align:right;">Size (MB)</th>'
        + '<th style="padding:8px;text-align:right;">Growth (MB)</th></tr>';

    SELECT @HTML = @HTML + '<tr style="background:' + CASE WHEN ROW_NUMBER() OVER (ORDER BY fg.DatabaseName, fg.FileName) % 2 = 0 THEN '#f8fafc' ELSE 'white' END + ';">'
        + '<td style="padding:6px 8px;">' + fg.DatabaseName + '</td>'
        + '<td style="padding:6px 8px;">' + fg.FileName + '</td>'
        + '<td style="padding:6px 8px;text-align:center;">' + fg.FileType + '</td>'
        + '<td style="padding:6px 8px;text-align:right;">' + CAST(fg.CurrentSizeMB AS NVARCHAR) + '</td>'
        + '<td style="padding:6px 8px;text-align:right;color:' + CASE WHEN fg.TotalGrowth > 0 THEN '#d97706' ELSE '#059669' END + ';">'
        + CASE WHEN fg.TotalGrowth > 0 THEN '+' ELSE '' END + CAST(ISNULL(fg.TotalGrowth, 0) AS NVARCHAR) + '</td></tr>'
    FROM (
        SELECT TOP 15
            f.DatabaseName, f.FileName, f.FileType,
            MAX(f.SizeMB) AS CurrentSizeMB,
            SUM(ISNULL(f.GrowthMB, 0)) AS TotalGrowth
        FROM [monitor].[FileGrowthHistory] f
        WHERE f.CollectedAt >= @ThisWeekStart
        GROUP BY f.DatabaseName, f.FileName, f.FileType
        ORDER BY SUM(ISNULL(f.GrowthMB, 0)) DESC
    ) fg;

    SET @HTML = @HTML + '</table>';

    -- ============================================================
    -- SECTION 4: Top 10 Queries of the Week
    -- ============================================================
    SET @HTML = @HTML + '<h2 style="font-size:18px;color:#0f172a;border-bottom:2px solid #2563eb;padding-bottom:8px;margin-top:28px;">'
        + CASE @Language WHEN 'ptbr' THEN '&#128269; Top 10 Queries da Semana' ELSE '&#128269; Top 10 Queries of the Week' END + '</h2>';

    SET @HTML = @HTML + '<table style="width:100%;border-collapse:collapse;font-size:11px;">'
        + '<tr style="background:#0f172a;color:white;">'
        + '<th style="padding:8px;text-align:center;">#</th>'
        + '<th style="padding:8px;text-align:left;">Database</th>'
        + '<th style="padding:8px;text-align:right;">CPU (ms)</th>'
        + '<th style="padding:8px;text-align:right;">Reads</th>'
        + '<th style="padding:8px;text-align:right;">Execs</th>'
        + '<th style="padding:8px;text-align:right;">Avg Dur (ms)</th>'
        + '<th style="padding:8px;text-align:left;">Query (truncated)</th></tr>';

    SELECT @HTML = @HTML + '<tr style="background:' + CASE WHEN q.RowNum % 2 = 0 THEN '#f8fafc' ELSE 'white' END + ';">'
        + '<td style="padding:6px 8px;text-align:center;font-weight:600;">' + CAST(q.RowNum AS NVARCHAR) + '</td>'
        + '<td style="padding:6px 8px;">' + ISNULL(q.DatabaseName, '-') + '</td>'
        + '<td style="padding:6px 8px;text-align:right;">' + FORMAT(q.TotalCpuMs, 'N0') + '</td>'
        + '<td style="padding:6px 8px;text-align:right;">' + FORMAT(q.TotalReads, 'N0') + '</td>'
        + '<td style="padding:6px 8px;text-align:right;">' + FORMAT(q.ExecutionCount, 'N0') + '</td>'
        + '<td style="padding:6px 8px;text-align:right;">' + FORMAT(q.AvgDurationMs, 'N0') + '</td>'
        + '<td style="padding:6px 8px;font-size:10px;">' + LEFT(ISNULL(REPLACE(REPLACE(q.QueryText, '<', '&lt;'), '>', '&gt;'), ''), 80) + '</td></tr>'
    FROM (
        SELECT 
            ROW_NUMBER() OVER (ORDER BY SUM(TotalCpuMs) DESC) AS RowNum,
            DatabaseName,
            SUM(TotalCpuMs) AS TotalCpuMs,
            SUM(TotalReads) AS TotalReads,
            SUM(ExecutionCount) AS ExecutionCount,
            AVG(AvgDurationMs) AS AvgDurationMs,
            MAX(QueryText) AS QueryText
        FROM [monitor].[TopQueriesHistory]
        WHERE CollectedAt >= @ThisWeekStart
        GROUP BY DatabaseName, QueryHash
    ) q
    WHERE q.RowNum <= 10;

    SET @HTML = @HTML + '</table>';

    -- ============================================================
    -- SECTION 5: Index Recommendations
    -- ============================================================
    SET @HTML = @HTML + '<h2 style="font-size:18px;color:#0f172a;border-bottom:2px solid #2563eb;padding-bottom:8px;margin-top:28px;">'
        + CASE @Language WHEN 'ptbr' THEN '&#128736; Recomendações de Índice' ELSE '&#128736; Index Recommendations' END + '</h2>';

    SET @HTML = @HTML + '<table style="width:100%;border-collapse:collapse;font-size:12px;">'
        + '<tr style="background:#0f172a;color:white;">'
        + '<th style="padding:8px;text-align:left;">Database.Table</th>'
        + '<th style="padding:8px;text-align:left;">Index</th>'
        + '<th style="padding:8px;text-align:center;">Frag %</th>'
        + '<th style="padding:8px;text-align:right;">Pages</th>'
        + '<th style="padding:8px;text-align:center;">' + CASE @Language WHEN 'ptbr' THEN 'Ação' ELSE 'Action' END + '</th></tr>';

    SELECT @HTML = @HTML + '<tr style="background:' + CASE WHEN ROW_NUMBER() OVER (ORDER BY ix.FragPct DESC) % 2 = 0 THEN '#f8fafc' ELSE 'white' END + ';">'
        + '<td style="padding:6px 8px;">' + ix.DatabaseName + '.' + ix.TableName + '</td>'
        + '<td style="padding:6px 8px;">' + ISNULL(ix.IndexName, 'HEAP') + '</td>'
        + '<td style="padding:6px 8px;text-align:center;color:' 
            + CASE WHEN ix.FragPct >= 30 THEN '#dc2626' ELSE '#d97706' END + ';font-weight:600;">'
            + CAST(CAST(ix.FragPct AS DECIMAL(5,1)) AS NVARCHAR) + '%</td>'
        + '<td style="padding:6px 8px;text-align:right;">' + FORMAT(ix.PageCount, 'N0') + '</td>'
        + '<td style="padding:6px 8px;text-align:center;font-weight:600;color:' 
            + CASE WHEN ix.FragPct >= 30 THEN '#dc2626' ELSE '#d97706' END + ';">'
            + CASE WHEN ix.FragPct >= 30 THEN 'REBUILD' ELSE 'REORGANIZE' END + '</td></tr>'
    FROM (
        SELECT TOP 20
            DatabaseName, TableName, IndexName, 
            MAX(FragmentationPct) AS FragPct,
            MAX(PageCount) AS PageCount
        FROM [monitor].[IndexHealthHistory]
        WHERE CollectedAt >= @ThisWeekStart
            AND FragmentationPct >= 10
            AND PageCount >= 1000
        GROUP BY DatabaseName, TableName, IndexName
        ORDER BY MAX(FragmentationPct) DESC
    ) ix;

    SET @HTML = @HTML + '</table>';

    -- ============================================================
    -- SECTION 6: AG Sync History
    -- ============================================================
    SET @HTML = @HTML + '<h2 style="font-size:18px;color:#0f172a;border-bottom:2px solid #2563eb;padding-bottom:8px;margin-top:28px;">'
        + CASE @Language WHEN 'ptbr' THEN '&#128279; Histórico AG' ELSE '&#128279; Availability Group History' END + '</h2>';

    SET @HTML = @HTML + '<table style="width:100%;border-collapse:collapse;font-size:12px;">'
        + '<tr style="background:#0f172a;color:white;">'
        + '<th style="padding:8px;text-align:left;">AG Name</th>'
        + '<th style="padding:8px;text-align:left;">Replica</th>'
        + '<th style="padding:8px;text-align:center;">Avg Lag (s)</th>'
        + '<th style="padding:8px;text-align:center;">Max Lag (s)</th>'
        + '<th style="padding:8px;text-align:right;">Avg Send Queue (MB)</th>'
        + '<th style="padding:8px;text-align:right;">Avg Redo Queue (MB)</th></tr>';

    SELECT @HTML = @HTML + '<tr style="background:' + CASE WHEN ROW_NUMBER() OVER (ORDER BY ag.AgName, ag.ReplicaServer) % 2 = 0 THEN '#f8fafc' ELSE 'white' END + ';">'
        + '<td style="padding:6px 8px;">' + ag.AgName + '</td>'
        + '<td style="padding:6px 8px;">' + ag.ReplicaServer + '</td>'
        + '<td style="padding:6px 8px;text-align:center;color:' 
            + CASE WHEN ag.AvgLag >= 120 THEN '#dc2626' WHEN ag.AvgLag >= 30 THEN '#d97706' ELSE '#059669' END + ';">'
            + CAST(ag.AvgLag AS NVARCHAR) + '</td>'
        + '<td style="padding:6px 8px;text-align:center;color:' 
            + CASE WHEN ag.MaxLag >= 120 THEN '#dc2626' WHEN ag.MaxLag >= 30 THEN '#d97706' ELSE '#059669' END + ';font-weight:600;">'
            + CAST(ag.MaxLag AS NVARCHAR) + '</td>'
        + '<td style="padding:6px 8px;text-align:right;">' + CAST(CAST(ag.AvgSendQueueMB AS DECIMAL(10,1)) AS NVARCHAR) + '</td>'
        + '<td style="padding:6px 8px;text-align:right;">' + CAST(CAST(ag.AvgRedoQueueMB AS DECIMAL(10,1)) AS NVARCHAR) + '</td></tr>'
    FROM (
        SELECT 
            AgName, ReplicaServer,
            AVG(ISNULL(SecondsBehindPrimary, 0)) AS AvgLag,
            MAX(ISNULL(SecondsBehindPrimary, 0)) AS MaxLag,
            AVG(ISNULL(LogSendQueueSizeKB, 0) / 1024.0) AS AvgSendQueueMB,
            AVG(ISNULL(RedoQueueSizeKB, 0) / 1024.0) AS AvgRedoQueueMB
        FROM [monitor].[AgHealthHistory]
        WHERE CollectedAt >= @ThisWeekStart
        GROUP BY AgName, ReplicaServer
    ) ag;

    SET @HTML = @HTML + '</table>';

    -- ============================================================
    -- SECTION 7: Performance Baseline Deviations
    -- ============================================================
    SET @HTML = @HTML + '<h2 style="font-size:18px;color:#0f172a;border-bottom:2px solid #2563eb;padding-bottom:8px;margin-top:28px;">'
        + CASE @Language WHEN 'ptbr' THEN '&#128200; Desvios do Baseline' ELSE '&#128200; Baseline Deviations' END + '</h2>';

    -- Check if baselines table exists and has data
    IF OBJECT_ID('monitor.PerformanceBaselines', 'U') IS NOT NULL
    BEGIN
        SET @HTML = @HTML + '<table style="width:100%;border-collapse:collapse;font-size:12px;">'
            + '<tr style="background:#0f172a;color:white;">'
            + '<th style="padding:8px;text-align:left;">Metric</th>'
            + '<th style="padding:8px;text-align:center;">Baseline</th>'
            + '<th style="padding:8px;text-align:center;">Current Avg</th>'
            + '<th style="padding:8px;text-align:center;">Deviation</th></tr>';

        SELECT @HTML = @HTML + '<tr style="background:' + CASE WHEN ROW_NUMBER() OVER (ORDER BY b.MetricName) % 2 = 0 THEN '#f8fafc' ELSE 'white' END + ';">'
            + '<td style="padding:6px 8px;">' + b.MetricName + '</td>'
            + '<td style="padding:6px 8px;text-align:center;">' + CAST(CAST(b.BaselineValue AS DECIMAL(10,2)) AS NVARCHAR) + '</td>'
            + '<td style="padding:6px 8px;text-align:center;">' + CAST(CAST(b.CurrentValue AS DECIMAL(10,2)) AS NVARCHAR) + '</td>'
            + '<td style="padding:6px 8px;text-align:center;color:' 
                + CASE WHEN ABS(b.DeviationPct) >= 50 THEN '#dc2626' WHEN ABS(b.DeviationPct) >= 25 THEN '#d97706' ELSE '#059669' END + ';font-weight:600;">'
                + CASE WHEN b.DeviationPct > 0 THEN '+' ELSE '' END + CAST(CAST(b.DeviationPct AS DECIMAL(5,1)) AS NVARCHAR) + '%</td></tr>'
        FROM (
            SELECT 
                pb.MetricName,
                pb.BaselineAvg AS BaselineValue,
                CASE pb.MetricName
                    WHEN 'CPU_Avg' THEN (SELECT AVG(CAST(SqlCpuPct AS DECIMAL(10,2))) FROM [monitor].[CpuHistory] WHERE CollectedAt >= @ThisWeekStart)
                    WHEN 'PLE_Avg' THEN (SELECT AVG(CAST(PageLifeExpectancy AS DECIMAL(10,2))) FROM [monitor].[MemoryHistory] WHERE CollectedAt >= @ThisWeekStart)
                    WHEN 'DiskUsed_Max' THEN (SELECT MAX(UsedPct) FROM [monitor].[DiskHistory] WHERE CollectedAt >= @ThisWeekStart)
                    ELSE NULL
                END AS CurrentValue,
                CASE 
                    WHEN pb.BaselineAvg = 0 THEN 0
                    ELSE ((CASE pb.MetricName
                        WHEN 'CPU_Avg' THEN (SELECT AVG(CAST(SqlCpuPct AS DECIMAL(10,2))) FROM [monitor].[CpuHistory] WHERE CollectedAt >= @ThisWeekStart)
                        WHEN 'PLE_Avg' THEN (SELECT AVG(CAST(PageLifeExpectancy AS DECIMAL(10,2))) FROM [monitor].[MemoryHistory] WHERE CollectedAt >= @ThisWeekStart)
                        WHEN 'DiskUsed_Max' THEN (SELECT MAX(UsedPct) FROM [monitor].[DiskHistory] WHERE CollectedAt >= @ThisWeekStart)
                        ELSE NULL
                    END) - pb.BaselineAvg) / pb.BaselineAvg * 100
                END AS DeviationPct
            FROM [monitor].[PerformanceBaselines] pb
            WHERE pb.IsActive = 1
        ) b
        WHERE b.CurrentValue IS NOT NULL
            AND ABS(b.DeviationPct) >= 10;

        SET @HTML = @HTML + '</table>';
    END
    ELSE
    BEGIN
        SET @HTML = @HTML + '<p style="color:#64748b;font-style:italic;">'
            + CASE @Language WHEN 'ptbr' THEN 'Baselines ainda não calculados. Execute usp_Maintenance_UpdateBaselines.' 
                ELSE 'Baselines not yet calculated. Run usp_Maintenance_UpdateBaselines.' END + '</p>';
    END;

    -- ============================================================
    -- SECTION 8: Recommendations
    -- ============================================================
    SET @HTML = @HTML + '<h2 style="font-size:18px;color:#0f172a;border-bottom:2px solid #2563eb;padding-bottom:8px;margin-top:28px;">'
        + CASE @Language WHEN 'ptbr' THEN '&#9889; Recomendações' ELSE '&#9889; Recommendations' END + '</h2>';

    DECLARE @RecHTML NVARCHAR(MAX) = '';
    DECLARE @RecCount INT = 0;

    -- High priority: Disk space critical
    IF EXISTS (SELECT 1 FROM [monitor].[DiskHistory] WHERE CollectedAt >= DATEADD(HOUR, -6, SYSUTCDATETIME()) AND UsedPct >= 90)
    BEGIN
        SET @RecHTML = @RecHTML + '<tr><td style="padding:8px;color:#dc2626;font-weight:700;">P1</td>'
            + '<td style="padding:8px;">' + CASE @Language WHEN 'ptbr' THEN 'Disco com uso acima de 90%. Ação imediata necessária.' 
                ELSE 'Disk usage above 90%. Immediate action required.' END + '</td></tr>';
        SET @RecCount += 1;
    END;

    -- High priority: Indexes needing rebuild
    IF EXISTS (SELECT 1 FROM [monitor].[IndexHealthHistory] WHERE CollectedAt >= @ThisWeekStart AND FragmentationPct >= 30 AND PageCount >= 1000)
    BEGIN
        DECLARE @RebuildCount INT = (SELECT COUNT(DISTINCT IndexName) FROM [monitor].[IndexHealthHistory] 
            WHERE CollectedAt >= @ThisWeekStart AND FragmentationPct >= 30 AND PageCount >= 1000);
        SET @RecHTML = @RecHTML + '<tr><td style="padding:8px;color:#d97706;font-weight:700;">P2</td>'
            + '<td style="padding:8px;">' + CAST(@RebuildCount AS NVARCHAR) + ' '
            + CASE @Language WHEN 'ptbr' THEN 'índices precisam de REBUILD (fragmentação > 30%).' 
                ELSE 'indexes need REBUILD (fragmentation > 30%).' END + '</td></tr>';
        SET @RecCount += 1;
    END;

    -- Medium: CPU trending up
    IF @CpuAvgThis > ISNULL(@CpuAvgLast, 0) * 1.2 AND @CpuAvgThis > 50
    BEGIN
        SET @RecHTML = @RecHTML + '<tr><td style="padding:8px;color:#d97706;font-weight:700;">P2</td>'
            + '<td style="padding:8px;">' + CASE @Language WHEN 'ptbr' THEN 'CPU com tendência de alta (+20% vs semana anterior). Investigar top queries.' 
                ELSE 'CPU trending up (+20% vs last week). Investigate top queries.' END + '</td></tr>';
        SET @RecCount += 1;
    END;

    -- Medium: PLE dropping
    IF @PleAvgThis < ISNULL(@PleAvgLast, 9999) * 0.7 AND @PleAvgThis < 1000
    BEGIN
        SET @RecHTML = @RecHTML + '<tr><td style="padding:8px;color:#d97706;font-weight:700;">P2</td>'
            + '<td style="padding:8px;">' + CASE @Language WHEN 'ptbr' THEN 'PLE caindo significativamente. Considerar aumento de memória ou otimização de queries.' 
                ELSE 'PLE dropping significantly. Consider memory increase or query optimization.' END + '</td></tr>';
        SET @RecCount += 1;
    END;

    -- Medium: Blocking increase
    IF @BlockingThis > ISNULL(@BlockingLast, 0) * 2 AND @BlockingThis > 10
    BEGIN
        SET @RecHTML = @RecHTML + '<tr><td style="padding:8px;color:#d97706;font-weight:700;">P2</td>'
            + '<td style="padding:8px;">' + CASE @Language WHEN 'ptbr' THEN 'Bloqueios dobraram vs semana anterior. Revisar queries e isolation levels.' 
                ELSE 'Blocking events doubled vs last week. Review queries and isolation levels.' END + '</td></tr>';
        SET @RecCount += 1;
    END;

    -- Low: Backup gaps
    IF EXISTS (SELECT 1 FROM [monitor].[BackupHistory] b WHERE b.CollectedAt >= DATEADD(HOUR, -6, SYSUTCDATETIME()) AND b.BackupType = 'D' AND b.HoursSinceLastBackup > 25)
    BEGIN
        SET @RecHTML = @RecHTML + '<tr><td style="padding:8px;color:#2563eb;font-weight:700;">P3</td>'
            + '<td style="padding:8px;">' + CASE @Language WHEN 'ptbr' THEN 'Alguns bancos com backup full atrasado (>25h). Verificar jobs de backup.' 
                ELSE 'Some databases with stale full backup (>25h). Check backup jobs.' END + '</td></tr>';
        SET @RecCount += 1;
    END;

    IF @RecCount = 0
    BEGIN
        SET @HTML = @HTML + '<p style="color:#059669;font-weight:600;">&#9989; '
            + CASE @Language WHEN 'ptbr' THEN 'Nenhuma recomendação crítica esta semana. Bom trabalho!' 
                ELSE 'No critical recommendations this week. Good job!' END + '</p>';
    END
    ELSE
    BEGIN
        SET @HTML = @HTML + '<table style="width:100%;border-collapse:collapse;font-size:13px;">'
            + '<tr style="background:#0f172a;color:white;">'
            + '<th style="padding:8px;text-align:center;">' + CASE @Language WHEN 'ptbr' THEN 'Prioridade' ELSE 'Priority' END + '</th>'
            + '<th style="padding:8px;text-align:left;">' + CASE @Language WHEN 'ptbr' THEN 'Recomendação' ELSE 'Recommendation' END + '</th></tr>'
            + @RecHTML + '</table>';
    END;

    -- ============================================================
    -- FOOTER & SEND
    -- ============================================================
    SET @HTML = @HTML + '</div>';  -- Close padding div
    SET @HTML = @HTML + '<div style="background:#f1f5f9;padding:16px 32px;font-size:11px;color:#64748b;text-align:center;">'
        + 'SQL Health Monitor - Weekly Deep Dive | ' + @ServerName + ' | Generated: ' + FORMAT(SYSUTCDATETIME(), 'yyyy-MM-dd HH:mm:ss') + ' UTC'
        + '</div></div></body></html>';

    -- Debug or send
    IF @DebugMode = 1
    BEGIN
        SELECT @HTML AS HtmlReport;
        RETURN;
    END;

    -- Send email
    DECLARE @Subject NVARCHAR(200) = @SubjectPrefix + ' &#128202; ' + @Title + ' - ' + @WeekStr;

    EXEC msdb.dbo.sp_send_dbmail
        @profile_name = @ProfileName,
        @recipients = @Recipients,
        @copy_recipients = @CcRecipients,
        @subject = @Subject,
        @body = @HTML,
        @body_format = 'HTML';

    -- Log report
    INSERT INTO [monitor].[ReportHistory] (ReportType, Recipients, Language, Success)
    VALUES ('Weekly', @Recipients, @Language, 1);
END;
GO

PRINT '✓ Weekly Deep Dive report [monitor].[usp_Report_WeeklyDeepDive] created.';
GO
