/*
    SQL Health Monitor - Uptime Tracker Collector
    Detects incidents and calculates uptime percentages for SLA tracking.
    
    Incident Types:
    - Planned: Scheduled maintenance, upgrades, patches
    - Unplanned: Hardware failures, software crashes, network issues  
    - Emergency: Critical failures requiring immediate action
    
    Categories:
    - Database: Failures within SQL Server itself
    - Server: OS/hardware failures
    - Network: Connectivity issues
    - Application: Application-level failures
    
    Severities:
    - Critical: Complete service interruption
    - High: Severe degradation, partial functionality
    - Medium: Noticeable impact, reduced performance
    - Low: Minor issues, minimal impact
*/

USE [SQLHealthMonitor];
GO

-- Create the uptime tracker procedure
IF OBJECT_ID('monitor.usp_Collect_UptimeTracker', 'P') IS NOT NULL
    DROP PROCEDURE [monitor].[usp_Collect_UptimeTracker];
GO

CREATE PROCEDURE [monitor].[usp_Collect_UptimeTracker]
    @ServerName NVARCHAR(128) = @@SERVERNAME,
    @Environment NVARCHAR(50) = 'PRODUCTION'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @CurrentTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @StartTime DATETIME2 = DATEADD(MINUTE, -60, @CurrentTime); -- Last hour
    DECLARE @PeriodStart DATETIME2;
    DECLARE @PeriodEnd DATETIME2;
    
    -- Get the last period end time to avoid duplicates
    SELECT @PeriodEnd = MAX(PeriodEnd)
    FROM monitor.UptimePeriods
    WHERE PeriodType = 'Hourly'
    AND PeriodEnd >= DATEADD(DAY, -7, @CurrentTime);
    
    IF @PeriodEnd IS NULL
        SET @PeriodEnd = DATEADD(HOUR, DATEDIFF(HOUR, 0, @CurrentTime), 0);
    
    SET @PeriodStart = DATEADD(HOUR, -1, @PeriodEnd);
    
    -- Check if we already processed this period
    IF EXISTS (SELECT 1 FROM monitor.UptimePeriods WHERE PeriodStart = @PeriodStart AND PeriodEnd = @PeriodEnd)
    BEGIN
        PRINT 'Uptime period already processed: ' + CONVERT(NVARCHAR(30), @PeriodStart) + ' to ' + CONVERT(NVARCHAR(30), @PeriodEnd);
        RETURN;
    END
    
    -- Create temporary tables for incident detection
    CREATE TABLE #DetectedIncidents (
        IncidentId UNIQUEIDENTIFIER DEFAULT NEWID(),
        IncidentType NVARCHAR(50),
        Category NVARCHAR(50),
        Severity NVARCHAR(20),
        Title NVARCHAR(200),
        Description NVARCHAR(MAX),
        DetectedAt DATETIME2,
        Source NVARCHAR(100),
        SourceDetail NVARCHAR(500)
    );
    
    CREATE TABLE #CriticalEvents (
        EventTime DATETIME2,
        EventType NVARCHAR(100),
        Severity NVARCHAR(20),
        Message NVARCHAR(MAX),
        Source NVARCHAR(100)
    );
    
    -- 1. Detect incidents from recent alerts
    INSERT INTO #DetectedIncidents (IncidentType, Category, Severity, Title, Description, DetectedAt, Source, SourceDetail)
    SELECT 
        CASE 
            WHEN a.MetricName LIKE '%down%' OR a.MetricName LIKE '%fail%' OR a.MetricName LIKE '%crash%' 
                THEN 'Emergency'
            WHEN a.MetricName LIKE '%maintenance%' OR a.MetricName LIKE '%upgrade%'
                THEN 'Planned'
            ELSE 'Unplanned'
        END AS IncidentType,
        CASE 
            WHEN a.MetricName LIKE '%cpu%' OR a.MetricName LIKE '%memory%' OR a.MetricName LIKE '%disk%'
                THEN 'Server'
            WHEN a.MetricName LIKE '%deadlock%' OR a.MetricName LIKE '%blocking%'
                THEN 'Database'
            WHEN a.MetricName LIKE '%network%' OR a.MetricName LIKE '%connection%'
                THEN 'Network'
            ELSE 'Application'
        END AS Category,
        CASE 
            WHEN a.Severity = 'Critical' THEN 'Critical'
            WHEN a.Severity = 'Warning' AND a.CurrentValue > (a.ThresholdValue * 1.5) THEN 'High'
            WHEN a.Severity = 'Warning' THEN 'Medium'
            ELSE 'Low'
        END AS Severity,
        'Alert: ' + a.MetricName + ' - ' + CAST(a.CurrentValue AS NVARCHAR(100)) + ' > ' + CAST(a.ThresholdValue AS NVARCHAR(100)) AS Title,
        'Alert fired: ' + a.Message + ' Current value: ' + CAST(a.CurrentValue AS NVARCHAR(100)) + 
        ', Threshold: ' + CAST(a.ThresholdValue AS NVARCHAR(100)) + ', Severity: ' + a.Severity AS Description,
        a.FiredAt AS DetectedAt,
        'Alert System' AS Source,
        'Metric: ' + a.MetricName + ', Server: ' + @ServerName AS SourceDetail
    FROM monitor.AlertHistory a
    WHERE a.FiredAt BETWEEN @StartTime AND @CurrentTime
    AND a.Acknowledged = 0
    AND a.Severity IN ('Critical', 'Warning');
    
    -- 2. Detect incidents from error log
    INSERT INTO #CriticalEvents (EventTime, EventType, Severity, Message, Source)
    SELECT
        eh.CollectedAt AS EventTime,
        'Error' AS EventType,
        CASE
            WHEN eh.Severity = 'Critical' THEN 'Critical'
            WHEN eh.Severity = 'Error'    THEN 'High'
            ELSE 'Medium'
        END AS Severity,
        eh.ErrorMessage AS Message,
        'Error Log' AS Source
    FROM [monitor].[ErrorLogHistory] eh
    WHERE eh.CollectedAt BETWEEN @StartTime AND @CurrentTime
      AND eh.Severity IN ('Critical', 'Error');
    
    -- 3. Detect incidents from job failures
    INSERT INTO #DetectedIncidents (IncidentType, Category, Severity, Title, Description, DetectedAt, Source, SourceDetail)
    SELECT
        'Unplanned' AS IncidentType,
        'Application' AS Category,
        CASE
            WHEN jh.sql_severity >= 20 THEN 'Critical'
            WHEN jh.sql_severity >= 17 THEN 'High'
            WHEN jh.sql_severity >= 11 THEN 'Medium'
            ELSE 'Low'
        END AS Severity,
        'Job Failure: ' + j.name AS Title,
        'SQL Agent job failed: ' + j.name + ' Step: ' + jh.step_name + ' Message: ' + jh.message AS Description,
        CAST(CONVERT(CHAR(8), jh.run_date) + ' ' +
             STUFF(STUFF(RIGHT('000000' + CAST(jh.run_time AS VARCHAR), 6), 5, 0, ':'), 3, 0, ':')
             AS DATETIME2) AS DetectedAt,
        'SQL Agent' AS Source,
        'Job: ' + j.name + ', Server: ' + @ServerName AS SourceDetail
    FROM msdb.dbo.sysjobhistory jh
    INNER JOIN msdb.dbo.sysjobs j ON jh.job_id = j.job_id
    WHERE jh.run_date >= CONVERT(INT, FORMAT(@StartTime, 'yyyyMMdd'))
    AND jh.run_status = 0 -- Failed
    AND jh.step_id > 0;
    
    -- 4. Detect incidents from availability group failures
    IF EXISTS (SELECT 1 FROM sys.availability_groups)
    BEGIN
        INSERT INTO #DetectedIncidents (IncidentType, Category, Severity, Title, Description, DetectedAt, Source, SourceDetail)
        SELECT 
            'Emergency' AS IncidentType,
            'Database' AS Category,
            'Critical' AS Severity,
            'AG Failure: ' + ag.name AS Title,
            'Availability group ' + ag.name + ' in state ' + ar.replica_state_desc + 
            ' on replica ' + ar.replica_server_name AS Description,
            @CurrentTime AS DetectedAt,
            'AlwaysOn' AS Source,
            'AG: ' + ag.name + ', Replica: ' + ar.replica_server_name AS SourceDetail
        FROM sys.availability_groups ag
        JOIN sys.dm_hadr_availability_replica_states ar ON ag.group_id = ar.group_id
        WHERE ar.replica_state_desc NOT IN ('SYNCHRONIZED', 'SYNCHRONIZING', 'SECONDARY_ALLOW_CONNECTIONS')
        AND ar.replica_state_desc IS NOT NULL;
    END
    
    -- 5. Detect incidents from service availability (SQL Server service stopped)
    INSERT INTO #CriticalEvents (EventTime, EventType, Severity, Message, Source)
    SELECT 
        @CurrentTime AS EventTime,
        'Service Unavailable' AS EventType,
        'Critical' AS Severity,
        'SQL Server service appears to be unavailable or stopped' AS Message,
        'Service Monitor' AS Source
    WHERE NOT EXISTS (SELECT 1 FROM sys.dm_os_system_memory WHERE total_physical_memory_kb > 0);
    
    -- 6. Detect incidents from deadlock traces
    IF EXISTS (SELECT 1 FROM sys.dm_xe_sessions WHERE name = 'system_health')
    BEGIN
        INSERT INTO #DetectedIncidents (IncidentType, Category, Severity, Title, Description, DetectedAt, Source, SourceDetail)
        SELECT 
            'Unplanned' AS IncidentType,
            'Database' AS Category,
            'High' AS Severity,
            'Deadlock Detected' AS Title,
            'Deadlock occurred affecting multiple sessions' AS Description,
            @CurrentTime AS DetectedAt,
            'Deadlock Monitor' AS Source,
            'Server: ' + @ServerName AS SourceDetail
        FROM sys.dm_xe_session_targets t
        JOIN sys.dm_xe_sessions s ON s.address = t.event_session_address
        WHERE s.name = 'system_health'
        AND t.target_name = 'ring_buffer'
        AND CAST(t.target_data AS XML).exist('event[@name="xml_deadlock_report"]') = 1;
    END
    
    -- Process detected incidents and insert into main incidents table
    INSERT INTO monitor.Incidents (
        IncidentId, IncidentType, Category, Severity, Title, Description, 
        DetectedAt, IsResolved, CreatedBy, UpdatedBy
    )
    SELECT 
        di.IncidentId, di.IncidentType, di.Category, di.Severity, di.Title, di.Description,
        di.DetectedAt, 0, 'UptimeTracker', 'UptimeTracker'
    FROM #DetectedIncidents di
    WHERE NOT EXISTS (
        SELECT 1 FROM monitor.Incidents i 
        WHERE i.IncidentId = di.IncidentId 
        AND i.IsResolved = 0
    );
    
    -- Insert incident sources
    INSERT INTO monitor.IncidentSources (IncidentId, SourceType, SourceDetail, DetectionMethod, ConfidenceScore)
    SELECT 
        di.IncidentId, di.Source, di.SourceDetail, 'Auto-Detection', 0.95
    FROM #DetectedIncidents di
    JOIN monitor.Incidents i ON i.IncidentId = di.IncidentId
    WHERE i.IsResolved = 0;
    
    -- Calculate uptime for the period
    DECLARE @TotalMinutes INT = DATEDIFF(MINUTE, @PeriodStart, @PeriodEnd);
    DECLARE @IncidentMinutes INT = 0;
    DECLARE @CriticalIncidents INT = 0;
    
    -- Calculate downtime based on incidents
    SELECT 
        @IncidentMinutes = SUM(DATEDIFF(MINUTE, 
            CASE WHEN i.DetectedAt < @PeriodStart THEN @PeriodStart ELSE i.DetectedAt END,
            CASE 
                WHEN i.ResolvedAt IS NULL THEN @PeriodEnd 
                WHEN i.ResolvedAt > @PeriodEnd THEN @PeriodEnd 
                ELSE i.ResolvedAt 
            END
        ))
    FROM monitor.Incidents i
    WHERE i.IsResolved = 0
    AND i.DetectedAt < @PeriodEnd
    AND (i.ResolvedAt IS NULL OR i.ResolvedAt > @PeriodStart);
    
    SELECT @CriticalIncidents = COUNT(*)
    FROM monitor.Incidents i
    WHERE i.Severity = 'Critical'
    AND i.IsResolved = 0
    AND i.DetectedAt < @PeriodEnd
    AND (i.ResolvedAt IS NULL OR i.ResolvedAt > @PeriodStart);
    
    -- Ensure we don't exceed total minutes
    IF @IncidentMinutes > @TotalMinutes
        SET @IncidentMinutes = @TotalMinutes;
    
    DECLARE @UptimeMinutes INT = @TotalMinutes - @IncidentMinutes;
    DECLARE @UptimePercentage DECIMAL(5,2) = CASE WHEN @TotalMinutes > 0 THEN (@UptimeMinutes * 100.0) / @TotalMinutes ELSE 100.0 END;
    
    -- Insert uptime period record
    INSERT INTO monitor.UptimePeriods (
        PeriodStart, PeriodEnd, TotalMinutes, UptimeMinutes, DowntimeMinutes, 
        UptimePercentage, IncidentCount, CriticalIncidents, PeriodType
    )
    VALUES (
        @PeriodStart, @PeriodEnd, @TotalMinutes, @UptimeMinutes, @IncidentMinutes,
        @UptimePercentage, 
        (SELECT COUNT(*) FROM monitor.Incidents WHERE DetectedAt BETWEEN @PeriodStart AND @PeriodEnd AND IsResolved = 0),
        @CriticalIncidents, 'Hourly'
    );
    
    -- Check SLA compliance (default 99.9% for critical systems)
    DECLARE @TargetUptime DECIMAL(5,2) = 99.9;
    DECLARE @SLAMet BIT = CASE WHEN @UptimePercentage >= @TargetUptime THEN 1 ELSE 0 END;
    DECLARE @ViolationCount INT = CASE WHEN @SLAMet = 0 THEN 1 ELSE 0 END;
    DECLARE @CriticalViolations INT = CASE WHEN @UptimePercentage < 99.0 THEN 1 ELSE 0 END;
    DECLARE @PenaltyMinutes INT = @TotalMinutes - @UptimeMinutes;
    
    -- Insert SLA tracking record
    INSERT INTO monitor.SLATracking (
        PeriodStart, PeriodEnd, TargetUptime, ActualUptime, SLAMet, 
        ViolationCount, CriticalViolations, PenaltyMinutes, PeriodType
    )
    VALUES (
        @PeriodStart, @PeriodEnd, @TargetUptime, @UptimePercentage, @SLAMet,
        @ViolationCount, @CriticalViolations, @PenaltyMinutes, 'Hourly'
    );
    
    -- Generate summary report
    DECLARE @IncidentCount INT = (SELECT COUNT(*) FROM monitor.Incidents WHERE DetectedAt BETWEEN @PeriodStart AND @PeriodEnd);
    
    PRINT '✓ Uptime Tracker completed for period: ' + CONVERT(NVARCHAR(30), @PeriodStart) + ' to ' + CONVERT(NVARCHAR(30), @PeriodEnd);
    PRINT '  - Total Period: ' + CAST(@TotalMinutes AS NVARCHAR(10)) + ' minutes';
    PRINT '  - Uptime: ' + CAST(@UptimeMinutes AS NVARCHAR(10)) + ' minutes (' + CAST(@UptimePercentage AS NVARCHAR(10)) + '%)';
    PRINT '  - Downtime: ' + CAST(@IncidentMinutes AS NVARCHAR(10)) + ' minutes';
    PRINT '  - Incidents Detected: ' + CAST(@IncidentCount AS NVARCHAR(10));
    PRINT '  - Critical Incidents: ' + CAST(@CriticalIncidents AS NVARCHAR(10));
    PRINT '  - SLA Met: ' + CASE WHEN @SLAMet = 1 THEN 'Yes' ELSE 'No' END;
    
    -- Cleanup
    DROP TABLE #DetectedIncidents;
    DROP TABLE #CriticalEvents;
    
    RETURN 0;
END
GO

PRINT '✓ Uptime Tracker collector procedure created successfully.';
GO