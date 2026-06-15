/*
    SQL Health Monitor - Baselines Installation Script
    Creates baseline tables, configuration, and procedures.
    
    Run order: After 06-alert-history.sql
    Schema: [monitor]
    Compatibility: SQL Server 2016+
    Author: Lucas Allan Borges
*/

USE [SQLHealthMonitor];
GO

PRINT '=== Installing Baseline Engine (07-baselines.sql) ===';
GO

----------------------------------------------------------------------
-- BASELINE CAPTURE TABLE
----------------------------------------------------------------------
IF OBJECT_ID('monitor.BaselineCapture', 'U') IS NULL
CREATE TABLE [monitor].[BaselineCapture] (
    BaselineId      BIGINT IDENTITY(1,1) PRIMARY KEY,
    MetricName      NVARCHAR(100)   NOT NULL,
    AvgValue        DECIMAL(18,4)   NOT NULL,
    StdDevValue     DECIMAL(18,4)   NOT NULL DEFAULT 0,
    MinValue        DECIMAL(18,4)   NULL,
    MaxValue        DECIMAL(18,4)   NULL,
    P50Value        DECIMAL(18,4)   NULL,
    P95Value        DECIMAL(18,4)   NULL,
    SampleCount     INT             NOT NULL,
    TimeWindowStart DATETIME2       NOT NULL,
    TimeWindowEnd   DATETIME2       NOT NULL,
    CapturedAt      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    CapturedBy      NVARCHAR(128)   NOT NULL DEFAULT SUSER_SNAME(),
    IsActive        BIT             NOT NULL DEFAULT 1,
    INDEX IX_BaselineCapture_Metric NONCLUSTERED (MetricName, CapturedAt DESC),
    INDEX IX_BaselineCapture_Active NONCLUSTERED (IsActive, MetricName, AvgValue, StdDevValue)
);
GO

----------------------------------------------------------------------
-- BASELINE CONFIGURATION TABLE
----------------------------------------------------------------------
IF OBJECT_ID('monitor.BaselineConfig', 'U') IS NULL
CREATE TABLE [monitor].[BaselineConfig] (
    ConfigId        INT IDENTITY(1,1) PRIMARY KEY,
    MetricName      NVARCHAR(100)   NOT NULL,
    WarningMultiplier   DECIMAL(5,2) NOT NULL DEFAULT 2.0,
    CriticalMultiplier  DECIMAL(5,2) NOT NULL DEFAULT 3.0,
    Direction       NVARCHAR(10)    NOT NULL DEFAULT 'ABOVE',
    IsEnabled       BIT             NOT NULL DEFAULT 1,
    Description     NVARCHAR(500)   NULL,
    ModifiedDate    DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_BaselineConfig_Metric UNIQUE (MetricName)
);
GO

----------------------------------------------------------------------
-- BASELINE ANOMALIES TABLE
----------------------------------------------------------------------
IF OBJECT_ID('monitor.BaselineAnomalies', 'U') IS NULL
CREATE TABLE [monitor].[BaselineAnomalies] (
    AnomalyId       BIGINT IDENTITY(1,1) PRIMARY KEY,
    DetectedAt      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    MetricName      NVARCHAR(100)   NOT NULL,
    CurrentValue    DECIMAL(18,4)   NOT NULL,
    BaselineAvg     DECIMAL(18,4)   NOT NULL,
    BaselineStdDev  DECIMAL(18,4)   NOT NULL,
    DeviationMultiplier DECIMAL(8,2) NOT NULL,
    Severity        NVARCHAR(20)    NOT NULL,
    Direction       NVARCHAR(10)    NOT NULL,
    Message         NVARCHAR(500)   NULL,
    Acknowledged    BIT             NOT NULL DEFAULT 0,
    INDEX IX_BaselineAnomalies_Date NONCLUSTERED (DetectedAt DESC),
    INDEX IX_BaselineAnomalies_Metric NONCLUSTERED (MetricName, DetectedAt DESC),
    INDEX IX_BaselineAnomalies_Severity NONCLUSTERED (Severity, DetectedAt DESC)
);
GO

----------------------------------------------------------------------
-- SEED DEFAULT BASELINE CONFIGURATION
----------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM [monitor].[BaselineConfig])
BEGIN
    INSERT INTO [monitor].[BaselineConfig] (MetricName, WarningMultiplier, CriticalMultiplier, Direction, Description)
    VALUES
        ('CPU_Avg',             2.0, 3.0, 'ABOVE', 'Average SQL CPU utilization'),
        ('CPU_Max',             1.5, 2.5, 'ABOVE', 'Peak SQL CPU utilization'),
        ('PLE_Avg',             2.0, 3.0, 'BELOW', 'Page Life Expectancy average'),
        ('Memory_Grants_Pending', 2.0, 3.0, 'ABOVE', 'Memory grants pending count'),
        ('Disk_UsedPct_Max',    1.5, 2.0, 'ABOVE', 'Maximum disk usage percentage'),
        ('Disk_ReadLatency_Avg', 2.0, 3.0, 'ABOVE', 'Average disk read latency (ms)'),
        ('Disk_WriteLatency_Avg', 2.0, 3.0, 'ABOVE', 'Average disk write latency (ms)'),
        ('Waits_TotalDelta_Ms', 2.0, 3.0, 'ABOVE', 'Total wait time delta per collection'),
        ('Blocking_Count',      2.0, 3.0, 'ABOVE', 'Blocking events count per period'),
        ('AG_Lag_Max',          2.0, 3.0, 'ABOVE', 'Maximum AG replication lag (seconds)'),
        ('TempDB_UsedPct',      2.0, 3.0, 'ABOVE', 'TempDB used space percentage'),
        ('ErrorLog_Count',      2.0, 3.0, 'ABOVE', 'Error/Critical log entries count');
    
    PRINT '  → Default baseline configuration seeded (12 metrics).';
END;
GO

----------------------------------------------------------------------
-- CAPTURE BASELINE PROCEDURE
----------------------------------------------------------------------
:r ..\baselines\capture_baseline.sql
GO

----------------------------------------------------------------------
-- DETECT ANOMALIES PROCEDURE
----------------------------------------------------------------------
:r ..\baselines\detect_anomalies.sql
GO

PRINT '✓ Baseline Engine installation complete.';
PRINT '  → [monitor].[BaselineCapture] - Stores periodic baselines';
PRINT '  → [monitor].[BaselineConfig] - Per-metric anomaly thresholds';
PRINT '  → [monitor].[BaselineAnomalies] - Detected anomalies log';
PRINT '  → [monitor].[usp_Baseline_Capture] - Weekly baseline capture';
PRINT '  → [monitor].[usp_Baseline_DetectAnomalies] - Real-time anomaly detection';
GO
