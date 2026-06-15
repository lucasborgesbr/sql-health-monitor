/*
    SQL Health Monitor - Alert History & Cooldown Tables
    Creates the AlertHistory and AlertCooldown tables used by the alert engine.
    
    Note: AlertHistory is already created in 00-create-schema.sql.
    This script ensures the AlertCooldown table exists and adds any
    missing columns for enhanced alert tracking.
    
    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

----------------------------------------------------------------------
-- ALERT COOLDOWN TABLE
----------------------------------------------------------------------
IF OBJECT_ID('monitor.AlertCooldown', 'U') IS NULL
CREATE TABLE [monitor].[AlertCooldown] (
    Id              INT IDENTITY(1,1) PRIMARY KEY,
    MetricName      NVARCHAR(100) NOT NULL,
    Severity        NVARCHAR(20)  NOT NULL DEFAULT 'Warning',
    LastFiredAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    FireCount       INT           NOT NULL DEFAULT 1,
    CONSTRAINT UQ_AlertCooldown_Metric UNIQUE (MetricName)
);
GO

----------------------------------------------------------------------
-- ENHANCE ALERT HISTORY (add columns if missing)
----------------------------------------------------------------------

-- Add Context column for additional alert details
IF NOT EXISTS (
    SELECT 1 FROM sys.columns 
    WHERE object_id = OBJECT_ID('monitor.AlertHistory') AND name = 'Context'
)
BEGIN
    ALTER TABLE [monitor].[AlertHistory] ADD Context NVARCHAR(500) NULL;
END;
GO

-- Add NotificationSent column to track email delivery
IF NOT EXISTS (
    SELECT 1 FROM sys.columns 
    WHERE object_id = OBJECT_ID('monitor.AlertHistory') AND name = 'NotificationSent'
)
BEGIN
    ALTER TABLE [monitor].[AlertHistory] ADD NotificationSent BIT NOT NULL DEFAULT 0;
END;
GO

-- Add ResolvedAt column for alert lifecycle tracking
IF NOT EXISTS (
    SELECT 1 FROM sys.columns 
    WHERE object_id = OBJECT_ID('monitor.AlertHistory') AND name = 'ResolvedAt'
)
BEGIN
    ALTER TABLE [monitor].[AlertHistory] ADD ResolvedAt DATETIME2 NULL;
END;
GO

-- Add Resolution column for notes on how alert was resolved
IF NOT EXISTS (
    SELECT 1 FROM sys.columns 
    WHERE object_id = OBJECT_ID('monitor.AlertHistory') AND name = 'Resolution'
)
BEGIN
    ALTER TABLE [monitor].[AlertHistory] ADD Resolution NVARCHAR(500) NULL;
END;
GO

----------------------------------------------------------------------
-- ALERT HISTORY SUMMARY VIEW
----------------------------------------------------------------------
IF OBJECT_ID('[monitor].[vw_AlertHistorySummary]', 'V') IS NOT NULL
    EXEC('ALTER VIEW [monitor].[vw_AlertHistorySummary] AS SELECT 1 AS Dummy;');
GO

IF OBJECT_ID('[monitor].[vw_AlertHistorySummary]', 'V') IS NULL
    EXEC('CREATE VIEW [monitor].[vw_AlertHistorySummary] AS SELECT 1 AS Dummy;');
GO

ALTER VIEW [monitor].[vw_AlertHistorySummary]
AS
SELECT
    MetricName,
    Severity,
    COUNT(*) AS TotalFired,
    MAX(FiredAt) AS LastFired,
    MIN(FiredAt) AS FirstFired,
    AVG(CurrentValue) AS AvgValue,
    MAX(CurrentValue) AS MaxValue,
    SUM(CASE WHEN Acknowledged = 1 THEN 1 ELSE 0 END) AS AcknowledgedCount,
    SUM(CASE WHEN ResolvedAt IS NOT NULL THEN 1 ELSE 0 END) AS ResolvedCount
FROM [monitor].[AlertHistory]
GROUP BY MetricName, Severity;
GO

----------------------------------------------------------------------
-- ACKNOWLEDGE ALERT PROCEDURE
----------------------------------------------------------------------
IF OBJECT_ID('[monitor].[usp_Alert_Acknowledge]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Alert_Acknowledge] @AlertId BIGINT=NULL, @AcknowledgedBy NVARCHAR(128)=NULL AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Alert_Acknowledge]', 'P') IS NULL
    EXEC('
    CREATE PROCEDURE [monitor].[usp_Alert_Acknowledge]
        @AlertId BIGINT,
        @AcknowledgedBy NVARCHAR(128) = NULL
    AS
    BEGIN
        SET NOCOUNT ON;
        PRINT ''Placeholder'';
    END;
    ');
GO

ALTER PROCEDURE [monitor].[usp_Alert_Acknowledge]
    @AlertId BIGINT,
    @AcknowledgedBy NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE [monitor].[AlertHistory]
    SET Acknowledged = 1,
        AcknowledgedBy = ISNULL(@AcknowledgedBy, SUSER_SNAME()),
        AcknowledgedAt = SYSUTCDATETIME()
    WHERE Id = @AlertId
        AND Acknowledged = 0;

    IF @@ROWCOUNT = 0
        PRINT 'Alert not found or already acknowledged.';
    ELSE
        PRINT 'Alert acknowledged successfully.';
END;
GO

----------------------------------------------------------------------
-- RESOLVE ALERT PROCEDURE
----------------------------------------------------------------------
IF OBJECT_ID('[monitor].[usp_Alert_Resolve]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Alert_Resolve] @AlertId BIGINT=NULL, @Resolution NVARCHAR(500)=NULL AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Alert_Resolve]', 'P') IS NULL
    EXEC('
    CREATE PROCEDURE [monitor].[usp_Alert_Resolve]
        @AlertId BIGINT,
        @Resolution NVARCHAR(500) = NULL
    AS
    BEGIN
        SET NOCOUNT ON;
        PRINT ''Placeholder'';
    END;
    ');
GO

ALTER PROCEDURE [monitor].[usp_Alert_Resolve]
    @AlertId BIGINT,
    @Resolution NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE [monitor].[AlertHistory]
    SET ResolvedAt = SYSUTCDATETIME(),
        Resolution = @Resolution,
        Acknowledged = 1,
        AcknowledgedBy = ISNULL(AcknowledgedBy, SUSER_SNAME()),
        AcknowledgedAt = ISNULL(AcknowledgedAt, SYSUTCDATETIME())
    WHERE Id = @AlertId
        AND ResolvedAt IS NULL;

    IF @@ROWCOUNT = 0
        PRINT 'Alert not found or already resolved.';
    ELSE
        PRINT 'Alert resolved successfully.';
END;
GO

PRINT '✓ Alert history tables and procedures created.';
PRINT '  → [monitor].[AlertCooldown] - Prevents alert spam';
PRINT '  → [monitor].[AlertHistory] - Enhanced with Context, NotificationSent, ResolvedAt';
PRINT '  → [monitor].[vw_AlertHistorySummary] - Alert analytics view';
PRINT '  → [monitor].[usp_Alert_Acknowledge] - Mark alerts as seen';
PRINT '  → [monitor].[usp_Alert_Resolve] - Mark alerts as resolved';
GO
