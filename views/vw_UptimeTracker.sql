/*
    SQL Health Monitor - Uptime Tracker Views
    Provides easy access to uptime metrics and incident data.
*/

USE [SQLHealthMonitor];
GO

-- Current uptime status view
IF OBJECT_ID('monitor.vw_CurrentUptimeStatus', 'V') IS NOT NULL
    DROP VIEW [monitor].[vw_CurrentUptimeStatus];
GO

CREATE VIEW [monitor].[vw_CurrentUptimeStatus]
AS
SELECT 
    TOP 1
    up.PeriodStart,
    up.PeriodEnd,
    up.TotalMinutes,
    up.UptimeMinutes,
    up.DowntimeMinutes,
    up.UptimePercentage,
    up.IncidentCount,
    up.CriticalIncidents,
    up.PeriodType,
    sl.TargetUptime,
    sl.ActualUptime,
    sl.Id AS SLATrackingId,
    sl.SLAMet,
    sl.ViolationCount,
    sl.CriticalViolations,
    sl.PenaltyMinutes,
    CONVERT(DATETIME, SWITCHOFFSET(CONVERT(DATETIMEOFFSET, up.PeriodEnd), DATENAME(TZOFFSET, SYSDATETIME()))) AS LocalPeriodEnd,
    DATEDIFF(MINUTE, up.PeriodEnd, SYSUTCDATETIME()) AS MinutesSinceLastUpdate,
    CASE 
        WHEN DATEDIFF(MINUTE, up.PeriodEnd, SYSUTCDATETIME()) > 120 THEN 'STALE'
        WHEN up.UptimePercentage < 99.0 THEN 'CRITICAL'
        WHEN up.UptimePercentage < 99.5 THEN 'WARNING'
        ELSE 'HEALTHY'
    END AS Status,
    CASE 
        WHEN up.UptimePercentage < 99.0 THEN '🔴'
        WHEN up.UptimePercentage < 99.5 THEN '🟡'
        ELSE '🟢'
    END AS StatusIcon
FROM monitor.UptimePeriods up
JOIN monitor.SLATracking sl ON up.PeriodStart = sl.PeriodStart AND up.PeriodEnd = sl.PeriodEnd
WHERE up.PeriodType = 'Hourly'
ORDER BY up.PeriodEnd DESC;
GO

-- Monthly uptime summary view
IF OBJECT_ID('monitor.vw_MonthlyUptimeSummary', 'V') IS NOT NULL
    DROP VIEW [monitor].[vw_MonthlyUptimeSummary];
GO

CREATE VIEW [monitor].[vw_MonthlyUptimeSummary]
AS
SELECT 
    DATEFROMPARTS(YEAR(up.PeriodStart), MONTH(up.PeriodStart), 1) AS MonthStart,
    DATEADD(MONTH, 1, DATEFROMPARTS(YEAR(up.PeriodStart), MONTH(up.PeriodStart), 1)) AS MonthEnd,
    COUNT(*) AS TotalPeriods,
    SUM(up.TotalMinutes) AS TotalMinutes,
    SUM(up.UptimeMinutes) AS UptimeMinutes,
    SUM(up.DowntimeMinutes) AS DowntimeMinutes,
    SUM(up.UptimeMinutes) * 100.0 / SUM(up.TotalMinutes) AS MonthlyUptimePercentage,
    SUM(up.IncidentCount) AS TotalIncidents,
    SUM(up.CriticalIncidents) AS CriticalIncidents,
    AVG(up.UptimePercentage) AS AverageHourlyUptime,
    MAX(up.UptimePercentage) AS PeakUptime,
    MIN(up.UptimePercentage) AS LowestUptime,
    COUNT(sl.Id) AS SLAViolations,
    SUM(sl.PenaltyMinutes) AS TotalPenaltyMinutes,
    CASE 
        WHEN SUM(up.UptimeMinutes) * 100.0 / SUM(up.TotalMinutes) >= 99.9 THEN 'COMPLIANT'
        ELSE 'VIOLATION'
    END AS SLAStatus,
    CONVERT(DATETIME, SWITCHOFFSET(CONVERT(DATETIMEOFFSET, GETDATE()), DATENAME(TZOFFSET, SYSDATETIME()))) AS ReportDate
FROM monitor.UptimePeriods up
JOIN monitor.SLATracking sl ON up.PeriodStart = sl.PeriodStart AND up.PeriodEnd = sl.PeriodEnd
WHERE up.PeriodType = 'Hourly'
GROUP BY DATEFROMPARTS(YEAR(up.PeriodStart), MONTH(up.PeriodStart), 1);
GO

-- Incident trends view
IF OBJECT_ID('monitor.vw_IncidentTrends', 'V') IS NOT NULL
    DROP VIEW [monitor].[vw_IncidentTrends];
GO

CREATE VIEW [monitor].[vw_IncidentTrends]
AS
SELECT 
    DATEFROMPARTS(YEAR(i.DetectedAt), MONTH(i.DetectedAt), 1) AS MonthStart,
    i.IncidentType,
    i.Category,
    i.Severity,
    COUNT(*) AS IncidentCount,
    SUM(DATEDIFF(MINUTE, 
        CASE WHEN i.DetectedAt < DATEFROMPARTS(YEAR(i.DetectedAt), MONTH(i.DetectedAt), 1) 
             THEN DATEFROMPARTS(YEAR(i.DetectedAt), MONTH(i.DetectedAt), 1) 
             ELSE i.DetectedAt END,
        CASE 
            WHEN i.ResolvedAt IS NULL THEN DATEADD(MONTH, 1, DATEFROMPARTS(YEAR(i.DetectedAt), MONTH(i.DetectedAt), 1))
            WHEN i.ResolvedAt > DATEADD(MONTH, 1, DATEFROMPARTS(YEAR(i.DetectedAt), MONTH(i.DetectedAt), 1)) 
                THEN DATEADD(MONTH, 1, DATEFROMPARTS(YEAR(i.DetectedAt), MONTH(i.DetectedAt), 1))
            ELSE i.ResolvedAt 
        END
    )) AS TotalDowntimeMinutes,
    AVG(CASE WHEN i.IsResolved = 1 THEN DATEDIFF(MINUTE, i.DetectedAt, i.ResolvedAt) ELSE NULL END) AS AvgResolutionTimeMinutes,
    CONVERT(DATETIME, SWITCHOFFSET(CONVERT(DATETIMEOFFSET, GETDATE()), DATENAME(TZOFFSET, SYSDATETIME()))) AS ReportDate
FROM monitor.Incidents i
WHERE i.DetectedAt >= DATEADD(MONTH, -6, GETDATE()) -- Last 6 months
GROUP BY DATEFROMPARTS(YEAR(i.DetectedAt), MONTH(i.DetectedAt), 1),
         i.IncidentType, i.Category, i.Severity;
GO

-- SLA compliance history view
IF OBJECT_ID('monitor.vw_SLAComplianceHistory', 'V') IS NOT NULL
    DROP VIEW [monitor].[vw_SLAComplianceHistory];
GO

CREATE VIEW [monitor].[vw_SLAComplianceHistory]
AS
SELECT 
    DATEFROMPARTS(YEAR(sl.PeriodStart), MONTH(sl.PeriodStart), 1) AS MonthStart,
    DATEADD(MONTH, 1, DATEFROMPARTS(YEAR(sl.PeriodStart), MONTH(sl.PeriodStart), 1)) AS MonthEnd,
    COUNT(*) AS TotalPeriods,
    AVG(sl.TargetUptime) AS AvgTargetUptime,
    AVG(sl.ActualUptime) AS AvgActualUptime,
    SUM(CASE WHEN sl.SLAMet = 1 THEN 1 ELSE 0 END) AS CompliantPeriods,
    SUM(CASE WHEN sl.SLAMet = 0 THEN 1 ELSE 0 END) AS ViolatedPeriods,
    SUM(sl.ViolationCount) AS TotalViolations,
    SUM(sl.CriticalViolations) AS CriticalViolations,
    SUM(sl.PenaltyMinutes) AS TotalPenaltyMinutes,
    SUM(sl.PenaltyMinutes) / NULLIF(COUNT(*), 0) AS AvgPenaltyMinutes,
    CASE 
        WHEN SUM(CASE WHEN sl.SLAMet = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) >= 99.0 THEN 'COMPLIANT'
        ELSE 'VIOLATION'
    END AS MonthlySLAStatus,
    CONVERT(DATETIME, SWITCHOFFSET(CONVERT(DATETIMEOFFSET, GETDATE()), DATENAME(TZOFFSET, SYSDATETIME()))) AS ReportDate
FROM monitor.SLATracking sl
WHERE sl.PeriodType = 'Hourly'
AND sl.PeriodStart >= DATEADD(MONTH, -12, GETDATE()) -- Last 12 months
GROUP BY DATEFROMPARTS(YEAR(sl.PeriodStart), MONTH(sl.PeriodStart), 1);
GO

-- Active incidents view
IF OBJECT_ID('monitor.vw_ActiveIncidents', 'V') IS NOT NULL
    DROP VIEW [monitor].[vw_ActiveIncidents];
GO

CREATE VIEW [monitor].[vw_ActiveIncidents]
AS
SELECT 
    i.IncidentId,
    i.DetectedAt,
    i.ResolvedAt,
    i.IncidentType,
    i.Category,
    i.Severity,
    i.Title,
    i.Description,
    i.Impact,
    i.DurationMinutes,
    i.IsResolved,
    i.CreatedBy,
    i.UpdatedBy,
    CONVERT(DATETIME, SWITCHOFFSET(CONVERT(DATETIMEOFFSET, i.DetectedAt), DATENAME(TZOFFSET, SYSDATETIME()))) AS LocalDetectedAt,
    CONVERT(DATETIME, SWITCHOFFSET(CONVERT(DATETIMEOFFSET, 
        CASE WHEN i.ResolvedAt IS NULL THEN SYSUTCDATETIME() ELSE i.ResolvedAt END), 
        DATENAME(TZOFFSET, SYSDATETIME()))) AS LocalResolvedAt,
    DATEDIFF(MINUTE, i.DetectedAt, 
        CASE WHEN i.ResolvedAt IS NULL THEN SYSUTCDATETIME() ELSE i.ResolvedAt END) AS CurrentDurationMinutes,
    CASE 
        WHEN i.IsResolved = 1 THEN 'RESOLVED'
        WHEN DATEDIFF(MINUTE, i.DetectedAt, SYSUTCDATETIME()) > 1440 THEN 'OVERDUE' -- > 24 hours
        WHEN i.Severity = 'Critical' THEN 'CRITICAL'
        WHEN i.Severity = 'High' THEN 'HIGH'
        WHEN i.Severity = 'Medium' THEN 'MEDIUM'
        ELSE 'LOW'
    END AS Status,
    CASE 
        WHEN i.IsResolved = 1 THEN '✅'
        WHEN i.Severity = 'Critical' THEN '🔴'
        WHEN i.Severity = 'High' THEN '🟠'
        WHEN i.Severity = 'Medium' THEN '🟡'
        ELSE '🟢'
    END AS StatusIcon,
    CONVERT(DATETIME, SWITCHOFFSET(CONVERT(DATETIMEOFFSET, GETDATE()), DATENAME(TZOFFSET, SYSDATETIME()))) AS ReportDate
FROM monitor.Incidents i
WHERE i.DetectedAt >= DATEADD(DAY, -30, GETDATE()); -- Last 30 days
GO

-- Uptime dashboard view
IF OBJECT_ID('monitor.vw_UptimeDashboard', 'V') IS NOT NULL
    DROP VIEW [monitor].[vw_UptimeDashboard];
GO

CREATE VIEW [monitor].[vw_UptimeDashboard]
AS
SELECT 
    -- Current status
    (SELECT TOP 1 UptimePercentage FROM monitor.vw_CurrentUptimeStatus) AS CurrentUptimePercentage,
    (SELECT TOP 1 StatusIcon FROM monitor.vw_CurrentUptimeStatus) AS CurrentStatusIcon,
    (SELECT TOP 1 MinutesSinceLastUpdate FROM monitor.vw_CurrentUptimeStatus) AS MinutesSinceLastUpdate,
    
    -- Monthly summary
    (SELECT TOP 1 MonthlyUptimePercentage FROM monitor.vw_MonthlyUptimeSummary) AS MonthlyUptimePercentage,
    (SELECT TOP 1 TotalIncidents FROM monitor.vw_MonthlyUptimeSummary) AS MonthlyTotalIncidents,
    (SELECT TOP 1 CriticalIncidents FROM monitor.vw_MonthlyUptimeSummary) AS MonthlyCriticalIncidents,
    
    -- Active incidents
    (SELECT COUNT(*) FROM monitor.vw_ActiveIncidents WHERE IsResolved = 0) AS ActiveIncidents,
    (SELECT COUNT(*) FROM monitor.vw_ActiveIncidents WHERE IsResolved = 0 AND Severity = 'Critical') AS ActiveCriticalIncidents,
    
    -- SLA compliance
    (SELECT TOP 1 SLAStatus FROM monitor.vw_MonthlyUptimeSummary) AS CurrentSLAStatus,
    (SELECT AVG(AvgActualUptime) FROM monitor.vw_SLAComplianceHistory) AS YearlyAverageUptime,
    
    -- Server info
    @@SERVERNAME AS ServerName,
    CONVERT(DATETIME, SWITCHOFFSET(CONVERT(DATETIMEOFFSET, GETDATE()), DATENAME(TZOFFSET, SYSDATETIME()))) AS ReportDate;
GO

PRINT '✓ Uptime tracker views created successfully.';
GO