/*
    SQL Health Monitor - Master Reports Registration
    Creates wrapper procedure to execute report generation.
    
    Run after: 01-create-collectors.sql
    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

IF OBJECT_ID('[monitor].[usp_RunReport]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_RunReport] @ReportType NVARCHAR(50)=NULL, @OverrideLanguage CHAR(5)=NULL, @OverrideRecipients NVARCHAR(500)=NULL, @DebugMode BIT=0 AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_RunReport]', 'P') IS NULL
    EXEC('
    CREATE PROCEDURE [monitor].[usp_RunReport]
        
        @ReportType NVARCHAR(50) = ''Daily'',
        @OverrideLanguage CHAR(5) = NULL,
        @OverrideRecipients NVARCHAR(500) = NULL,
        @DebugMode BIT = 0
    AS
    BEGIN
        SET NOCOUNT ON;
        PRINT ''Placeholder - real body injected below'';
    END;
    ');
GO

ALTER PROCEDURE [monitor].[usp_RunReport]
    @ReportType NVARCHAR(50) = 'Daily',
    @OverrideLanguage CHAR(5) = NULL,
    @OverrideRecipients NVARCHAR(500) = NULL,
    @DebugMode BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ErrorMsg NVARCHAR(4000);

    BEGIN TRY
        IF @ReportType = 'Daily'
        BEGIN
            EXEC [monitor].[usp_Report_DailyHealth]
                @OverrideLanguage = @OverrideLanguage,
                @OverrideRecipients = @OverrideRecipients,
                @DebugMode = @DebugMode;
        END
        ELSE IF @ReportType = 'Weekly'
        BEGIN
            EXEC [monitor].[usp_Report_WeeklyDeepDive]
                @OverrideLanguage = @OverrideLanguage,
                @OverrideRecipients = @OverrideRecipients,
                @DebugMode = @DebugMode;
        END
        ELSE
        BEGIN
            RAISERROR('Invalid report type: %s. Valid values: Daily, Weekly', 16, 1, @ReportType);
            RETURN;
        END;
    END TRY
    BEGIN CATCH
        SET @ErrorMsg = CONCAT('Report [', @ReportType, '] failed: ', ERROR_MESSAGE());
        
        -- Log failure
        INSERT INTO [monitor].[ReportHistory] (ReportType, Recipients, Language, Success, ErrorMessage)
        VALUES (@ReportType, 
                ISNULL(@OverrideRecipients, (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'Email' AND SettingName = 'Recipients')),
                ISNULL(@OverrideLanguage, (SELECT SettingValue FROM [monitor].[Settings] WHERE Category = 'General' AND SettingName = 'Language')),
                0, @ErrorMsg);

        -- Re-raise
        THROW;
    END CATCH;
END;
GO

PRINT '✓ Report runner procedure [monitor].[usp_RunReport] created.';
GO
