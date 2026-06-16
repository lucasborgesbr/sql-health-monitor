/*
    SQL Health Monitor - Alert Engine Registration
    Creates the alert engine procedure and supporting objects.
    
    Run after: 02-create-reports.sql
    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

-- Cooldown tracking table
IF OBJECT_ID('monitor.AlertCooldown', 'U') IS NULL
CREATE TABLE [monitor].[AlertCooldown] (
    MetricName      NVARCHAR(100) NOT NULL PRIMARY KEY,
    LastFiredAt     DATETIME2     NOT NULL,
    Severity        NVARCHAR(20)  NOT NULL
);
GO

IF OBJECT_ID('[monitor].[usp_RunAlertEngine]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_RunAlertEngine] @CooldownMinutes INT=NULL, @DebugMode BIT=0 AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_RunAlertEngine]', 'P') IS NULL
    EXEC('
    CREATE PROCEDURE [monitor].[usp_RunAlertEngine]
        
        @CooldownMinutes INT = 30,
        @DebugMode BIT = 0
    AS
    BEGIN
        SET NOCOUNT ON;
        PRINT ''Placeholder - real body injected below'';
    END;
    ');
GO

ALTER PROCEDURE [monitor].[usp_RunAlertEngine]
    @CooldownMinutes INT = 30,
    @DebugMode BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    EXEC [monitor].[usp_EvaluateAlerts];
END;
GO

PRINT '✓ Alert engine registration [monitor].[usp_RunAlertEngine] created.';
PRINT '✓ AlertCooldown table created.';
GO
