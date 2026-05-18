/*
    SQL Health Monitor - Alert Engine Registration
    Creates the alert engine procedure and supporting objects.
    
    Run after: 02-create-reports.sql
    Compatibility: SQL Server 2016+
*/

USE [DBA_Monitor];
GO

-- Cooldown tracking table
IF OBJECT_ID('monitor.AlertCooldown', 'U') IS NULL
CREATE TABLE [monitor].[AlertCooldown] (
    MetricName      NVARCHAR(100) NOT NULL PRIMARY KEY,
    LastFiredAt     DATETIME2     NOT NULL,
    Severity        NVARCHAR(20)  NOT NULL
);
GO

CREATE OR ALTER PROCEDURE [monitor].[usp_RunAlertEngine]
    @CooldownMinutes INT = 30,  -- Don't re-fire same alert within this window
    @DebugMode BIT = 0          -- 1 = print alerts without sending email
AS
BEGIN
    SET NOCOUNT ON;

    -- Delegates to the full alert engine procedure
    EXEC [monitor].[usp_AlertEngine_Check]
        @CooldownMinutes = @CooldownMinutes,
        @DebugMode = @DebugMode;
END;
GO

PRINT '✓ Alert engine registration [monitor].[usp_RunAlertEngine] created.';
PRINT '✓ AlertCooldown table created.';
GO
