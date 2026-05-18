/*
    SQL Health Monitor - Purge Old Data
    Retention cleanup based on Settings table configuration.
    
    Deletes data older than configured retention periods.
    Uses batched deletes to avoid log bloat.
    
    Schedule: Daily 3:00 AM
    Compatibility: SQL Server 2016+
*/

USE [DBA_Monitor];
GO

CREATE OR ALTER PROCEDURE [monitor].[usp_Maintenance_PurgeOldData]
    @BatchSize INT = 10000,
    @DebugMode BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DataRetentionDays INT = ISNULL(
        (SELECT CAST(SettingValue AS INT) FROM [monitor].[Settings] WHERE Category = 'Retention' AND SettingName = 'DataRetentionDays'), 90);
    DECLARE @AlertRetentionDays INT = ISNULL(
        (SELECT CAST(SettingValue AS INT) FROM [monitor].[Settings] WHERE Category = 'Retention' AND SettingName = 'AlertRetentionDays'), 365);
    DECLARE @ReportRetentionDays INT = ISNULL(
        (SELECT CAST(SettingValue AS INT) FROM [monitor].[Settings] WHERE Category = 'Retention' AND SettingName = 'ReportRetentionDays'), 90);

    DECLARE @DataCutoff DATETIME2 = DATEADD(DAY, -@DataRetentionDays, SYSUTCDATETIME());
    DECLARE @AlertCutoff DATETIME2 = DATEADD(DAY, -@AlertRetentionDays, SYSUTCDATETIME());
    DECLARE @ReportCutoff DATETIME2 = DATEADD(DAY, -@ReportRetentionDays, SYSUTCDATETIME());

    DECLARE @TotalDeleted BIGINT = 0;
    DECLARE @Deleted INT = 1;
    DECLARE @TableName NVARCHAR(128);

    -- Table registry with date column names
    DECLARE @Tables TABLE (
        TableName   NVARCHAR(128),
        DateColumn  NVARCHAR(128),
        CutoffDate  DATETIME2
    );

    INSERT INTO @Tables VALUES
        ('monitor.CpuHistory',          'CollectedAt', @DataCutoff),
        ('monitor.MemoryHistory',       'CollectedAt', @DataCutoff),
        ('monitor.DiskHistory',         'CollectedAt', @DataCutoff),
        ('monitor.WaitStatsHistory',    'CollectedAt', @DataCutoff),
        ('monitor.BlockingHistory',     'DetectedAt',  @DataCutoff),
        ('monitor.AgHealthHistory',     'CollectedAt', @DataCutoff),
        ('monitor.CdcHealthHistory',    'CollectedAt', @DataCutoff),
        ('monitor.TopQueriesHistory',   'CollectedAt', @DataCutoff),
        ('monitor.IndexHealthHistory',  'CollectedAt', @DataCutoff),
        ('monitor.BackupHistory',       'CollectedAt', @DataCutoff),
        ('monitor.JobHistory',          'CollectedAt', @DataCutoff),
        ('monitor.TempDbHistory',       'CollectedAt', @DataCutoff),
        ('monitor.FileGrowthHistory',   'CollectedAt', @DataCutoff),
        ('monitor.ErrorLogHistory',     'CollectedAt', @DataCutoff),
        ('monitor.AlertHistory',        'FiredAt',     @AlertCutoff),
        ('monitor.ReportHistory',       'SentAt',      @ReportCutoff);

    -- Process each table
    DECLARE @DateColumn NVARCHAR(128);
    DECLARE @CutoffDate DATETIME2;
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @TableDeleted BIGINT;

    DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT TableName, DateColumn, CutoffDate FROM @Tables;

    OPEN table_cursor;
    FETCH NEXT FROM table_cursor INTO @TableName, @DateColumn, @CutoffDate;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @TableDeleted = 0;
        SET @Deleted = 1;

        -- Batched delete loop
        WHILE @Deleted > 0
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
                IF @DebugMode = 1
                    PRINT 'Error purging ' + @TableName + ': ' + ERROR_MESSAGE();
                SET @Deleted = 0;
            END CATCH;
        END;

        SET @TotalDeleted += @TableDeleted;

        IF @DebugMode = 1 AND @TableDeleted > 0
            PRINT 'Purged ' + CAST(@TableDeleted AS NVARCHAR) + ' rows from ' + @TableName;

        FETCH NEXT FROM table_cursor INTO @TableName, @DateColumn, @CutoffDate;
    END;

    CLOSE table_cursor;
    DEALLOCATE table_cursor;

    -- Clean up cooldown entries older than 7 days
    DELETE FROM [monitor].[AlertCooldown] WHERE LastFiredAt < DATEADD(DAY, -7, SYSUTCDATETIME());

    IF @DebugMode = 1
        PRINT 'Total rows purged: ' + CAST(@TotalDeleted AS NVARCHAR);

    -- Log maintenance action
    IF @TotalDeleted > 0
    BEGIN
        INSERT INTO [monitor].[ErrorLogHistory] (LogDate, ProcessInfo, ErrorMessage, Severity)
        VALUES (SYSUTCDATETIME(), 'Maintenance', 
            'Purge completed: ' + CAST(@TotalDeleted AS NVARCHAR) + ' rows deleted. Retention: Data=' 
            + CAST(@DataRetentionDays AS NVARCHAR) + 'd, Alerts=' + CAST(@AlertRetentionDays AS NVARCHAR) + 'd', 'Info');
    END;
END;
GO

PRINT '✓ Purge procedure [monitor].[usp_Maintenance_PurgeOldData] created.';
GO
