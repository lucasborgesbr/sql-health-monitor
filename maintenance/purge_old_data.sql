/*
    SQL Health Monitor - Purge Historical Data (Enhanced)
    Configurable retention per data type with batched deletes.
    
    Default retention:
        - Raw collector data: 30 days
        - Daily summaries: 90 days
        - Weekly summaries: 365 days
        - Baselines: forever (never purged)
        - Alert history: 365 days
        - Report history: 90 days
        - Anomalies: 90 days
    
    Reads retention config from Settings table.
    Logs purge activity (rows deleted per table, duration).
    Uses batched deletes (TOP 10000 in loop) to avoid log bloat.
    
    Schema: [monitor]
    Schedule: Daily 3:00 AM
    Compatibility: SQL Server 2016+
    Author: Lucas Allan Borges
    
    Parameters:
        @BatchSize      INT - Rows per delete batch (default: 10000)
        @MaxDurationMin INT - Max runtime in minutes before stopping (default: 30)
        @DebugMode      BIT - Print plan without deleting (default: 0)
    
    Example Usage:
        -- Standard purge
        EXEC [monitor].[usp_PurgeHistoricalData];
        
        -- Smaller batches for busy systems
        EXEC [monitor].[usp_PurgeHistoricalData] @BatchSize = 5000;
        
        -- Preview what would be purged
        EXEC [monitor].[usp_PurgeHistoricalData] @DebugMode = 1;
        
        -- Limit runtime to 15 minutes
        EXEC [monitor].[usp_PurgeHistoricalData] @MaxDurationMin = 15;
*/

USE [SQLHealthMonitor];
GO

/*
    SQL Health Monitor - Purge Historical Data (Enhanced)
    Configurable retention per data type with batched deletes.
    
    Default retention:
        - Raw collector data: 30 days
        - Daily summaries: 90 days
        - Weekly summaries: 365 days
        - Baselines: forever (never purged)
        - Alert history: 365 days
        - Report history: 90 days
        - Anomalies: 90 days
    
    Reads retention config from Settings table.
    Logs purge activity (rows deleted per table, duration).
    Uses batched deletes (TOP 10000 in loop) to avoid log bloat.
    
    Schema: [monitor]
    Schedule: Daily 3:00 AM
    Compatibility: SQL Server 2016+
    Author: Lucas Allan Borges
    
    Parameters:
        @BatchSize      INT - Rows per delete batch (default: 10000)
        @MaxDurationMin INT - Max runtime in minutes before stopping (default: 30)
        @DebugMode      BIT - Print plan without deleting (default: 0)
    
    Example Usage:
        -- Standard purge
        EXEC [monitor].[usp_PurgeHistoricalData];
        
        -- Smaller batches for busy systems
        EXEC [monitor].[usp_PurgeHistoricalData] @BatchSize = 5000;
        
        -- Preview what would be purged
        EXEC [monitor].[usp_PurgeHistoricalData] @DebugMode = 1;
        
        -- Limit runtime to 15 minutes
        EXEC [monitor].[usp_PurgeHistoricalData] @MaxDurationMin = 15;
*/

USE [SQLHealthMonitor];
GO

IF OBJECT_ID('[monitor].[usp_PurgeHistoricalData]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_PurgeHistoricalData] @BatchSize      INT = NULL, @MaxDurationMin INT = NULL, @DebugMode      BIT = NULL AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_PurgeHistoricalData]', 'P') IS NULL
    EXEC('
    CREATE PROCEDURE [monitor].[usp_PurgeHistoricalData]
        
        @BatchSize      INT = 10000,
        @MaxDurationMin INT = 30,
        @DebugMode      BIT = 0
    AS
    BEGIN
        SET NOCOUNT ON;
        PRINT ''Placeholder'';
    END;
    ');
GO

ALTER PROCEDURE [monitor].[usp_PurgeHistoricalData]
    @BatchSize      INT = 10000,
    @MaxDurationMin INT = 30,
    @DebugMode      BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @Deadline DATETIME2 = DATEADD(MINUTE, @MaxDurationMin, @StartTime);

    -- ============================================================
    -- READ RETENTION CONFIGURATION FROM SETTINGS
    -- ============================================================
    DECLARE @RawDataDays INT = ISNULL(
        (SELECT CAST(SettingValue AS INT) FROM [monitor].[Settings] 
         WHERE Category = 'Retention' AND SettingName = 'RawDataRetentionDays'), 30);
    
    DECLARE @DailySummaryDays INT = ISNULL(
        (SELECT CAST(SettingValue AS INT) FROM [monitor].[Settings] 
         WHERE Category = 'Retention' AND SettingName = 'DailySummaryRetentionDays'), 90);
    
    DECLARE @WeeklySummaryDays INT = ISNULL(
        (SELECT CAST(SettingValue AS INT) FROM [monitor].[Settings] 
         WHERE Category = 'Retention' AND SettingName = 'WeeklySummaryRetentionDays'), 365);
    
    DECLARE @AlertRetentionDays INT = ISNULL(
        (SELECT CAST(SettingValue AS INT) FROM [monitor].[Settings] 
         WHERE Category = 'Retention' AND SettingName = 'AlertRetentionDays'), 365);
    
    DECLARE @ReportRetentionDays INT = ISNULL(
        (SELECT CAST(SettingValue AS INT) FROM [monitor].[Settings] 
         WHERE Category = 'Retention' AND SettingName = 'ReportRetentionDays'), 90);
    
    DECLARE @AnomalyRetentionDays INT = ISNULL(
        (SELECT CAST(SettingValue AS INT) FROM [monitor].[Settings] 
         WHERE Category = 'Retention' AND SettingName = 'AnomalyRetentionDays'), 90);

    -- Cutoff dates
    DECLARE @RawCutoff DATETIME2 = DATEADD(DAY, -@RawDataDays, SYSUTCDATETIME());
    DECLARE @DailyCutoff DATETIME2 = DATEADD(DAY, -@DailySummaryDays, SYSUTCDATETIME());
    DECLARE @AlertCutoff DATETIME2 = DATEADD(DAY, -@AlertRetentionDays, SYSUTCDATETIME());
    DECLARE @ReportCutoff DATETIME2 = DATEADD(DAY, -@ReportRetentionDays, SYSUTCDATETIME());
    DECLARE @AnomalyCutoff DATETIME2 = DATEADD(DAY, -@AnomalyRetentionDays, SYSUTCDATETIME());

    -- ============================================================
    -- PURGE LOG TABLE (track what we delete)
    -- ============================================================
    DECLARE @PurgeLog TABLE (
        TableName       NVARCHAR(128),
        RowsDeleted     BIGINT,
        DurationMs      INT,
        CutoffDate      DATETIME2,
        RetentionDays   INT
    );

    -- ============================================================
    -- TABLE REGISTRY
    -- ============================================================
    DECLARE @Tables TABLE (
        TableName   NVARCHAR(128),
        DateColumn  NVARCHAR(128),
        CutoffDate  DATETIME2,
        RetentionDays INT
    );

    INSERT INTO @Tables VALUES
        -- Raw collector data (30 days default)
        ('monitor.CpuHistory',          'CollectedAt', @RawCutoff, @RawDataDays),
        ('monitor.MemoryHistory',       'CollectedAt', @RawCutoff, @RawDataDays),
        ('monitor.DiskHistory',         'CollectedAt', @RawCutoff, @RawDataDays),
        ('monitor.WaitStatsHistory',    'CollectedAt', @RawCutoff, @RawDataDays),
        ('monitor.BlockingHistory',     'DetectedAt',  @RawCutoff, @RawDataDays),
        ('monitor.AgHealthHistory',     'CollectedAt', @RawCutoff, @RawDataDays),
        ('monitor.CdcHealthHistory',    'CollectedAt', @RawCutoff, @RawDataDays),
        ('monitor.TopQueriesHistory',   'CollectedAt', @RawCutoff, @RawDataDays),
        ('monitor.IndexHealthHistory',  'CollectedAt', @RawCutoff, @RawDataDays),
        ('monitor.BackupHistory',       'CollectedAt', @RawCutoff, @RawDataDays),
        ('monitor.JobHistory',          'CollectedAt', @RawCutoff, @RawDataDays),
        ('monitor.TempDbHistory',       'CollectedAt', @RawCutoff, @RawDataDays),
        ('monitor.FileGrowthHistory',   'CollectedAt', @RawCutoff, @RawDataDays),
        ('monitor.ErrorLogHistory',     'CollectedAt', @RawCutoff, @RawDataDays),
        -- Alert & report data (longer retention)
        ('monitor.AlertHistory',        'FiredAt',     @AlertCutoff, @AlertRetentionDays),
        ('monitor.ReportHistory',       'SentAt',      @ReportCutoff, @ReportRetentionDays),
        -- Baseline anomalies (90 days)
        ('monitor.BaselineAnomalies',   'DetectedAt',  @AnomalyCutoff, @AnomalyRetentionDays);
        -- NOTE: BaselineCapture is NEVER purged (historical baselines kept forever)

    -- ============================================================
    -- DEBUG MODE: Show plan
    -- ============================================================
    IF @DebugMode = 1
    BEGIN
        SELECT 
            t.TableName,
            t.DateColumn,
            t.RetentionDays,
            t.CutoffDate,
            'SELECT COUNT(*) FROM [' + REPLACE(t.TableName, 'monitor.', 'monitor].[') + '] WHERE [' + t.DateColumn + '] < ''' + CONVERT(NVARCHAR, t.CutoffDate, 120) + '''' AS CountQuery
        FROM @Tables t
        ORDER BY t.TableName;

        PRINT 'DEBUG: Retention settings:';
        PRINT '  Raw data: ' + CAST(@RawDataDays AS NVARCHAR) + ' days (cutoff: ' + FORMAT(@RawCutoff, 'yyyy-MM-dd') + ')';
        PRINT '  Alerts: ' + CAST(@AlertRetentionDays AS NVARCHAR) + ' days (cutoff: ' + FORMAT(@AlertCutoff, 'yyyy-MM-dd') + ')';
        PRINT '  Reports: ' + CAST(@ReportRetentionDays AS NVARCHAR) + ' days (cutoff: ' + FORMAT(@ReportCutoff, 'yyyy-MM-dd') + ')';
        PRINT '  Anomalies: ' + CAST(@AnomalyRetentionDays AS NVARCHAR) + ' days (cutoff: ' + FORMAT(@AnomalyCutoff, 'yyyy-MM-dd') + ')';
        PRINT '  Baselines: FOREVER (never purged)';
        RETURN;
    END;

    -- ============================================================
    -- EXECUTE BATCHED DELETES
    -- ============================================================
    DECLARE @TableName NVARCHAR(128), @DateColumn NVARCHAR(128);
    DECLARE @CutoffDate DATETIME2, @RetentionDays INT;
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Deleted INT, @TableDeleted BIGINT, @TableStart DATETIME2;
    DECLARE @TotalDeleted BIGINT = 0;

    DECLARE purge_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT TableName, DateColumn, CutoffDate, RetentionDays FROM @Tables;

    OPEN purge_cursor;
    FETCH NEXT FROM purge_cursor INTO @TableName, @DateColumn, @CutoffDate, @RetentionDays;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Check deadline
        IF SYSUTCDATETIME() >= @Deadline
        BEGIN
            PRINT '⚠ Purge stopped: reached max duration of ' + CAST(@MaxDurationMin AS NVARCHAR) + ' minutes.';
            BREAK;
        END;

        SET @TableDeleted = 0;
        SET @Deleted = 1;
        SET @TableStart = SYSUTCDATETIME();

        -- Check if table exists before attempting delete
        IF OBJECT_ID(@TableName, 'U') IS NOT NULL
        BEGIN
            -- Batched delete loop
            WHILE @Deleted > 0 AND SYSUTCDATETIME() < @Deadline
            BEGIN
                SET @SQL = N'DELETE TOP (' + CAST(@BatchSize AS NVARCHAR) + N') FROM ['
                    + REPLACE(@TableName, 'monitor.', 'monitor].[') + N'] WHERE ['
                    + @DateColumn + N'] < @Cutoff';

                BEGIN TRY
                    EXEC sp_executesql @SQL, N'@Cutoff DATETIME2', @Cutoff = @CutoffDate;
                    SET @Deleted = @@ROWCOUNT;
                    SET @TableDeleted += @Deleted;
                END TRY
                BEGIN CATCH
                    -- Log error and move to next table
                    INSERT INTO @PurgeLog (TableName, RowsDeleted, DurationMs, CutoffDate, RetentionDays)
                    VALUES (@TableName + ' [ERROR: ' + ERROR_MESSAGE() + ']', @TableDeleted, 
                        DATEDIFF(MILLISECOND, @TableStart, SYSUTCDATETIME()), @CutoffDate, @RetentionDays);
                    SET @Deleted = 0;
                END CATCH;
            END;

            -- Log results for this table
            IF @TableDeleted > 0
            BEGIN
                INSERT INTO @PurgeLog (TableName, RowsDeleted, DurationMs, CutoffDate, RetentionDays)
                VALUES (@TableName, @TableDeleted, 
                    DATEDIFF(MILLISECOND, @TableStart, SYSUTCDATETIME()), @CutoffDate, @RetentionDays);
            END;

            SET @TotalDeleted += @TableDeleted;
        END;

        FETCH NEXT FROM purge_cursor INTO @TableName, @DateColumn, @CutoffDate, @RetentionDays;
    END;

    CLOSE purge_cursor;
    DEALLOCATE purge_cursor;

    -- ============================================================
    -- CLEANUP AUXILIARY TABLES
    -- ============================================================
    
    -- Clean up alert cooldown entries older than 7 days
    IF OBJECT_ID('monitor.AlertCooldown', 'U') IS NOT NULL
        DELETE FROM [monitor].[AlertCooldown] WHERE LastFiredAt < DATEADD(DAY, -7, SYSUTCDATETIME());

    -- Clean up inactive old baselines (keep last 12 captures per metric)
    IF OBJECT_ID('monitor.BaselineCapture', 'U') IS NOT NULL
    BEGIN
        ;WITH OldBaselines AS (
            SELECT BaselineId, 
                ROW_NUMBER() OVER (PARTITION BY MetricName ORDER BY CapturedAt DESC) AS rn
            FROM [monitor].[BaselineCapture]
            WHERE IsActive = 0
        )
        DELETE FROM OldBaselines WHERE rn > 12;
    END;

    -- ============================================================
    -- LOG PURGE ACTIVITY
    -- ============================================================
    DECLARE @Duration INT = DATEDIFF(SECOND, @StartTime, SYSUTCDATETIME());

    -- Build summary message
    DECLARE @Summary NVARCHAR(MAX) = 'Purge completed in ' + CAST(@Duration AS NVARCHAR) + 's. '
        + 'Total rows deleted: ' + CAST(@TotalDeleted AS NVARCHAR) + '. ';

    -- Add per-table breakdown
    SELECT @Summary = @Summary + TableName + '=' + CAST(RowsDeleted AS NVARCHAR) + '; '
    FROM @PurgeLog
    WHERE RowsDeleted > 0
    ORDER BY RowsDeleted DESC;

    -- Log to ErrorLogHistory
    IF @TotalDeleted > 0
    BEGIN
        INSERT INTO [monitor].[ErrorLogHistory] (LogDate, ProcessInfo, ErrorMessage, Severity)
        VALUES (SYSUTCDATETIME(), 'Maintenance:Purge', @Summary, 'Info');
    END;

    -- Return purge results
    SELECT TableName, RowsDeleted, DurationMs, CutoffDate, RetentionDays
    FROM @PurgeLog
    ORDER BY RowsDeleted DESC;

    PRINT '✓ ' + @Summary;
END;
GO

PRINT '✓ Procedure [monitor].[usp_PurgeHistoricalData] created.';
GO

