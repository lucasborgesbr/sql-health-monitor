/*
    SQL Health Monitor - Master Collector Procedure
    Orchestrates all individual collectors in sequence with error handling.
    
    Run after: 00-create-schema.sql, 05-configure.sql
    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

IF OBJECT_ID('[monitor].[usp_RunAllCollectors]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_RunAllCollectors] @ForceRun BIT = 0 AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_RunAllCollectors]', 'P') IS NULL
    EXEC('
    CREATE PROCEDURE [monitor].[usp_RunAllCollectors]
        
        @ForceRun BIT = 0
    AS
    BEGIN
        SET NOCOUNT ON;
        PRINT ''Placeholder - real body injected below'';
    END;
    ');
GO

ALTER PROCEDURE [monitor].[usp_RunAllCollectors]
    @ForceRun BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    -- Check master switch
    IF @ForceRun = 0
    BEGIN
        DECLARE @Enabled BIT = ISNULL(
            (SELECT CAST(SettingValue AS BIT) FROM [monitor].[Settings] 
             WHERE Category = 'General' AND SettingName = 'MonitoringEnabled'), 1);
        IF @Enabled = 0
        BEGIN
            PRINT 'Monitoring is disabled. Use @ForceRun = 1 to override.';
            RETURN;
        END;
    END;

    DECLARE @CollectorName NVARCHAR(128);
    DECLARE @StartTime DATETIME2;
    DECLARE @ErrorMsg NVARCHAR(4000);
    DECLARE @ErrorCount INT = 0;
    DECLARE @SuccessCount INT = 0;

    -- Collector registry: name + feature flag
    DECLARE @Collectors TABLE (
        SortOrder   INT IDENTITY(1,1),
        ProcName    NVARCHAR(128) NOT NULL,
        FeatureFlag NVARCHAR(50)  NOT NULL
    );

    INSERT INTO @Collectors (ProcName, FeatureFlag) VALUES
        ('monitor.usp_Collect_CPU',         'CollectCPU'),
        ('monitor.usp_Collect_Memory',      'CollectMemory'),
        ('monitor.usp_Collect_Disk',        'CollectDisk'),
        ('monitor.usp_Collect_Waits',       'CollectWaits'),
        ('monitor.usp_Collect_Blocking',    'CollectBlocking'),
        ('monitor.usp_Collect_AG_Health',   'CollectAG'),
        ('monitor.usp_Collect_CDC_Health',  'CollectCDC'),
        ('monitor.usp_Collect_TopQueries',  'CollectTopQueries'),
        ('monitor.usp_Collect_IndexHealth', 'CollectIndexHealth'),
        ('monitor.usp_Collect_BackupStatus','CollectBackups'),
        ('monitor.usp_Collect_JobHistory', 'CollectJobs'),
        ('monitor.usp_Collect_TempDB',      'CollectTempDB'),
        ('monitor.usp_Collect_DatabaseGrowth','CollectFileGrowth'),
        ('monitor.usp_Collect_ErrorLog',    'CollectErrorLog'),
        ('monitor.usp_Collect_LogGrowth',   'CollectLogGrowth'),  -- Enhanced log growth
        ('monitor.usp_Collect_Deadlocks',   'CollectDeadlocks'),  -- Enhanced deadlock detection
        ('monitor.usp_Collect_UptimeTracker', 'CollectUptimeTracker');  -- Uptime SLA tracking

    -- Execute each collector
    DECLARE @CurrentOrder INT = 1;
    DECLARE @MaxOrder INT = (SELECT MAX(SortOrder) FROM @Collectors);
    DECLARE @FeatureEnabled BIT;
    DECLARE @ProcName NVARCHAR(128);

    WHILE @CurrentOrder <= @MaxOrder
    BEGIN
        SELECT @ProcName = ProcName, @CollectorName = FeatureFlag
        FROM @Collectors WHERE SortOrder = @CurrentOrder;

        -- Check feature flag
        SET @FeatureEnabled = ISNULL(
            (SELECT CAST(SettingValue AS BIT) FROM [monitor].[Settings] 
             WHERE Category = 'Features' AND SettingName = @CollectorName), 1);

        IF @FeatureEnabled = 1
        BEGIN
            SET @StartTime = SYSUTCDATETIME();
            BEGIN TRY
                EXEC @ProcName;
                SET @SuccessCount += 1;
            END TRY
            BEGIN CATCH
                SET @ErrorMsg = CONCAT('Collector [', @ProcName, '] failed: ', 
                    ERROR_MESSAGE(), ' (Error ', ERROR_NUMBER(), ', Line ', ERROR_LINE(), ')');
                
                -- Log error to ErrorLogHistory for visibility
                INSERT INTO [monitor].[ErrorLogHistory] (LogDate, ProcessInfo, ErrorMessage, Severity)
                VALUES (SYSUTCDATETIME(), 'SQL Health Monitor', @ErrorMsg, 'Error');

                PRINT @ErrorMsg;
                SET @ErrorCount += 1;
            END CATCH;
        END;

        SET @CurrentOrder += 1;
    END;

    PRINT CONCAT('Collection complete. Success: ', @SuccessCount, ', Errors: ', @ErrorCount);
END;
GO

PRINT '✓ Master collector procedure [monitor].[usp_RunAllCollectors] created.';
GO
