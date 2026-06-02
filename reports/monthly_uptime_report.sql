/*
    SQL Health Monitor - Monthly Uptime Report Generator
    Generates comprehensive monthly uptime reports with SLA analysis.
    
    Features:
    - Monthly uptime percentage calculation
    - Incident categorization and trends
    - SLA compliance analysis
    - Business impact assessment
    - Recommendations for improvement
*/

USE [SQLHealthMonitor];
GO

-- Create the monthly uptime report procedure
IF OBJECT_ID('monitor.usp_Generate_MonthlyUptimeReport', 'P') IS NOT NULL
    DROP PROCEDURE [monitor].[usp_Generate_MonthlyUptimeReport];
GO

CREATE PROCEDURE [monitor].[usp_Generate_MonthlyUptimeReport]
    @ReportMonth DATE = NULL,
    @ServerName NVARCHAR(128) = @@SERVERNAME,
    @Environment NVARCHAR(50) = 'PRODUCTION'
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @ReportMonth IS NULL
        SET @ReportMonth = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
    
    DECLARE @PeriodStart DATETIME2 = @ReportMonth;
    DECLARE @PeriodEnd DATETIME2 = DATEADD(MONTH, 1, @PeriodStart);
    DECLARE @CurrentTime DATETIME2 = SYSUTCDATETIME();
    
    -- Create temporary tables for report generation
    CREATE TABLE #MonthlySummary (
        Metric NVARCHAR(100),
        Value DECIMAL(18,2),
        Unit NVARCHAR(50)
    );
    
    CREATE TABLE #IncidentBreakdown (
        IncidentType NVARCHAR(50),
        Category NVARCHAR(50),
        Severity NVARCHAR(20),
        Count INT,
        TotalMinutes INT,
        Percentage DECIMAL(5,2)
    );
    
    CREATE TABLE #SLAAnalysis (
        Period NVARCHAR(20),
        TargetUptime DECIMAL(5,2),
        ActualUptime DECIMAL(5,2),
        SLAMet BIT,
        Violations INT,
        CriticalViolations INT,
        PenaltyMinutes INT
    );
    
    CREATE TABLE #Recommendations (
        Category NVARCHAR(100),
        Issue NVARCHAR(500),
        Recommendation NVARCHAR(1000),
        Priority NVARCHAR(20),
        Impact DECIMAL(5,2)
    );
    
    -- 1. Calculate monthly uptime summary
    INSERT INTO #MonthlySummary (Metric, Value, Unit)
    SELECT 
        'Monthly Uptime' AS Metric,
        SUM(UptimeMinutes) * 100.0 / SUM(TotalMinutes) AS Value,
        'Percentage' AS Unit
    FROM monitor.UptimePeriods
    WHERE PeriodStart >= @PeriodStart AND PeriodStart < @PeriodEnd
    AND PeriodType = 'Hourly';
    
    INSERT INTO #MonthlySummary (Metric, Value, Unit)
    SELECT 
        'Total Operating Time' AS Metric,
        SUM(TotalMinutes) / 60.0 AS Value,
        'Hours' AS Unit
    FROM monitor.UptimePeriods
    WHERE PeriodStart >= @PeriodStart AND PeriodStart < @PeriodEnd
    AND PeriodType = 'Hourly';
    
    INSERT INTO #MonthlySummary (Metric, Value, Unit)
    SELECT 
        'Total Downtime' AS Metric,
        SUM(DowntimeMinutes) / 60.0 AS Value,
        'Hours' AS Unit
    FROM monitor.UptimePeriods
    WHERE PeriodStart >= @PeriodStart AND PeriodStart < @PeriodEnd
    AND PeriodType = 'Hourly';
    
    INSERT INTO #MonthlySummary (Metric, Value, Unit)
    SELECT 
        'Total Incidents' AS Metric,
        COUNT(DISTINCT IncidentId) AS Value,
        'Count' AS Unit
    FROM monitor.Incidents
    WHERE DetectedAt >= @PeriodStart AND DetectedAt < @PeriodEnd;
    
    INSERT INTO #MonthlySummary (Metric, Value, Unit)
    SELECT 
        'Critical Incidents' AS Metric,
        COUNT(CASE WHEN Severity = 'Critical' THEN 1 END) AS Value,
        'Count' AS Unit
    FROM monitor.Incidents
    WHERE DetectedAt >= @PeriodStart AND DetectedAt < @PeriodEnd;
    
    -- 2. Incident breakdown by type and category
    INSERT INTO #IncidentBreakdown (IncidentType, Category, Severity, Count, TotalMinutes, Percentage)
    SELECT 
        i.IncidentType,
        i.Category,
        i.Severity,
        COUNT(*) AS Count,
        SUM(DATEDIFF(MINUTE, 
            CASE WHEN i.DetectedAt < @PeriodStart THEN @PeriodStart ELSE i.DetectedAt END,
            CASE 
                WHEN i.ResolvedAt IS NULL THEN @PeriodEnd 
                WHEN i.ResolvedAt > @PeriodEnd THEN @PeriodEnd 
                ELSE i.ResolvedAt 
            END
        )) AS TotalMinutes,
        CAST(SUM(DATEDIFF(MINUTE, 
            CASE WHEN i.DetectedAt < @PeriodStart THEN @PeriodStart ELSE i.DetectedAt END,
            CASE 
                WHEN i.ResolvedAt IS NULL THEN @PeriodEnd 
                WHEN i.ResolvedAt > @PeriodEnd THEN @PeriodEnd 
                ELSE i.ResolvedAt 
            END
        )) * 100.0 / (SELECT SUM(TotalMinutes) FROM monitor.UptimePeriods WHERE PeriodStart >= @PeriodStart AND PeriodStart < @PeriodEnd) AS DECIMAL(5,2))
    FROM monitor.Incidents i
    WHERE i.DetectedAt >= @PeriodStart AND i.DetectedAt < @PeriodEnd
    GROUP BY i.IncidentType, i.Category, i.Severity;
    
    -- 3. SLA analysis
    INSERT INTO #SLAAnalysis (Period, TargetUptime, ActualUptime, SLAMet, Violations, CriticalViolations, PenaltyMinutes)
    SELECT 
        'Monthly' AS Period,
        99.9 AS TargetUptime,
        (SELECT SUM(UptimeMinutes) * 100.0 / SUM(TotalMinutes) 
         FROM monitor.UptimePeriods 
         WHERE PeriodStart >= @PeriodStart AND PeriodStart < @PeriodEnd) AS ActualUptime,
        CASE 
            WHEN (SELECT SUM(UptimeMinutes) * 100.0 / SUM(TotalMinutes) 
                  FROM monitor.UptimePeriods 
                  WHERE PeriodStart >= @PeriodStart AND PeriodStart < @PeriodEnd) >= 99.9 THEN 1 
            ELSE 0 
        END AS SLAMet,
        (SELECT COUNT(*) FROM monitor.SLATracking 
         WHERE PeriodStart >= @PeriodStart AND PeriodStart < @PeriodEnd) AS Violations,
        (SELECT COUNT(*) FROM monitor.SLATracking 
         WHERE PeriodStart >= @PeriodStart AND PeriodStart < @PeriodEnd
         AND CriticalViolations > 0) AS CriticalViolations,
        (SELECT SUM(PenaltyMinutes) FROM monitor.SLATracking 
         WHERE PeriodStart >= @PeriodStart AND PeriodStart < @PeriodEnd) AS PenaltyMinutes
    WHERE NOT EXISTS (SELECT 1 FROM #SLAAnalysis);
    
    -- 4. Generate recommendations based on incident patterns
    -- High downtime recommendations
    INSERT INTO #Recommendations (Category, Issue, Recommendation, Priority, Impact)
    SELECT 
        'Infrastructure' AS Category,
        'High downtime detected: ' + CAST(SUM(DowntimeMinutes) / 60.0 AS NVARCHAR(10)) + ' hours this month' AS Issue,
        'Review server capacity, redundancy, and monitoring coverage. Consider implementing high availability solutions.' AS Recommendation,
        CASE 
            WHEN SUM(DowntimeMinutes) > 720 THEN 'HIGH' -- > 12 hours
            WHEN SUM(DowntimeMinutes) > 360 THEN 'MEDIUM' -- > 6 hours
            ELSE 'LOW'
        END AS Priority,
        CASE 
            WHEN SUM(DowntimeMinutes) > 720 THEN 95.0
            WHEN SUM(DowntimeMinutes) > 360 THEN 75.0
            ELSE 50.0
        END AS Impact
    FROM monitor.UptimePeriods
    WHERE PeriodStart >= @PeriodStart AND PeriodStart < @PeriodEnd
    GROUP BY SUM(DowntimeMinutes);
    
    -- Critical incident recommendations
    INSERT INTO #Recommendations (Category, Issue, Recommendation, Priority, Impact)
    SELECT 
        'Database Administration' AS Category,
        'Multiple critical incidents detected: ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' incidents' AS Issue,
        'Implement proactive monitoring, improve maintenance procedures, and review backup/recovery strategies.' AS Recommendation,
        'HIGH' AS Priority,
        90.0 AS Impact
    FROM monitor.Incidents
    WHERE Severity = 'Critical'
    AND DetectedAt >= @PeriodStart AND DetectedAt < @PeriodEnd
    GROUP BY COUNT(*);
    
    -- Planned maintenance optimization
    INSERT INTO #Recommendations (Category, Issue, Recommendation, Priority, Impact)
    SELECT 
        'Operations' AS Category,
        'Planned maintenance incidents: ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' incidents' AS Issue,
        'Optimize maintenance windows, implement change management processes, and communicate schedules better.' AS Recommendation,
        'MEDIUM' AS Priority,
        60.0 AS Impact
    FROM monitor.Incidents
    WHERE IncidentType = 'Planned'
    AND DetectedAt >= @PeriodStart AND DetectedAt < @PeriodEnd
    GROUP BY COUNT(*);
    
    -- Network-related incident recommendations
    INSERT INTO #Recommendations (Category, Issue, Recommendation, Priority, Impact)
    SELECT 
        'Network' AS Category,
        'Network incidents detected: ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' incidents' AS Issue,
        'Review network infrastructure, implement redundancy, and improve monitoring of network components.' AS Recommendation,
        'MEDIUM' AS Priority,
        70.0 AS Impact
    FROM monitor.Incidents
    WHERE Category = 'Network'
    AND DetectedAt >= @PeriodStart AND DetectedAt < @PeriodEnd
    GROUP BY COUNT(*);
    
    -- Generate the monthly uptime report
    DECLARE @ReportTitle NVARCHAR(500) = 'Monthly Uptime Report - ' + @ServerName + ' - ' + FORMAT(@ReportMonth, 'MMMM yyyy');
    DECLARE @ReportDate DATETIME2 = @CurrentTime;
    
    -- Insert report into reports table
    IF NOT EXISTS (SELECT 1 FROM monitor.Reports WHERE ReportName = 'MonthlyUptimeReport')
    BEGIN
        INSERT INTO monitor.Reports (ReportName, Description, ReportType)
        VALUES ('MonthlyUptimeReport', 'Monthly uptime and SLA compliance report', 'Uptime');
    END
    
    -- Insert report history
    INSERT INTO monitor.ReportHistory (ReportType, Recipients, Language, Success)
    VALUES ('MonthlyUptimeReport', 'Administrative Team', 'EN', 1);
    
    -- Create result tables for the report
    SELECT 
        @ReportTitle AS ReportTitle,
        @ServerName AS ServerName,
        @Environment AS Environment,
        @ReportDate AS ReportDate,
        @PeriodStart AS PeriodStart,
        @PeriodEnd AS PeriodEnd;
    
    SELECT * FROM #MonthlySummary ORDER BY Metric;
    
    SELECT 
        IncidentType,
        Category,
        Severity,
        Count,
        TotalMinutes,
        FORMAT(Percentage, 'N2') + '%' AS Percentage
    FROM #IncidentBreakdown 
    ORDER BY Count DESC, TotalMinutes DESC;
    
    SELECT 
        Period,
        TargetUptime,
        ActualUptime,
        SLAMet,
        Violations,
        CriticalViolations,
        PenaltyMinutes
    FROM #SLAAnalysis;
    
    SELECT 
        Category,
        Issue,
        Recommendation,
        Priority,
        FORMAT(Impact, 'N1') + '%' AS Impact
    FROM #Recommendations 
    ORDER BY 
        CASE Priority 
            WHEN 'HIGH' THEN 1 
            WHEN 'MEDIUM' THEN 2 
            WHEN 'LOW' THEN 3 
            ELSE 4 
        END,
        Impact DESC;
    
    -- Generate executive summary
    DECLARE @OverallUptime DECIMAL(5,2) = (SELECT Value FROM #MonthlySummary WHERE Metric = 'Monthly Uptime');
    DECLARE @TotalDowntimeHours DECIMAL(10,2) = (SELECT Value FROM #MonthlySummary WHERE Metric = 'Total Downtime');
    DECLARE @TotalIncidents INT = (SELECT CAST(Value AS INT) FROM #MonthlySummary WHERE Metric = 'Total Incidents');
    DECLARE @CriticalIncidents INT = (SELECT CAST(Value AS INT) FROM #MonthlySummary WHERE Metric = 'Critical Incidents');
    
    PRINT '=== EXECUTIVE SUMMARY ===';
    PRINT 'Report Period: ' + FORMAT(@PeriodStart, 'yyyy-MM-dd') + ' to ' + FORMAT(@PeriodEnd, 'yyyy-MM-dd');
    PRINT 'Overall Uptime: ' + FORMAT(@OverallUptime, 'N2') + '%';
    PRINT 'Total Downtime: ' + FORMAT(@TotalDowntimeHours, 'N1') + ' hours';
    PRINT 'Total Incidents: ' + CAST(@TotalIncidents AS NVARCHAR(10));
    PRINT 'Critical Incidents: ' + CAST(@CriticalIncidents AS NVARCHAR(10));
    PRINT 'SLA Compliance: ' + CASE WHEN @OverallUptime >= 99.9 THEN 'MET' ELSE 'NOT MET' END;
    
    -- Cleanup
    DROP TABLE #MonthlySummary;
    DROP TABLE #IncidentBreakdown;
    DROP TABLE #SLAAnalysis;
    DROP TABLE #Recommendations;
    
    RETURN 0;
END
GO

PRINT '✓ Monthly uptime report generator created successfully.';
GO