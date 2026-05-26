/*
    SQL Health Monitor - CMS (Central Management Server) Tables
    RegisteredServers table for multi-instance monitoring.
    
    Schema: [monitor]
    Compatibility: SQL Server 2016+
    Author: Lucas Allan Borges
*/

USE [DBA_Monitor];
GO

----------------------------------------------------------------------
-- REGISTERED SERVERS TABLE
----------------------------------------------------------------------
IF OBJECT_ID('monitor.RegisteredServers', 'U') IS NULL
CREATE TABLE [monitor].[RegisteredServers] (
    ServerId            INT IDENTITY(1,1) PRIMARY KEY,
    InstanceName        NVARCHAR(256)   NOT NULL,
    DisplayName         NVARCHAR(128)   NULL,
    Environment         NVARCHAR(20)    NOT NULL DEFAULT 'PRD',  -- DEV, STG, PRD, DR
    AgRole              NVARCHAR(20)    NULL,                    -- PRIMARY, SECONDARY, STANDALONE
    ServerRole          NVARCHAR(50)    NULL,                    -- OLTP, REPORTING, ETL, MIXED
    ConnectionString    NVARCHAR(500)   NULL,                    -- Optional override
    IsActive            BIT             NOT NULL DEFAULT 1,
    IsPrimary           BIT             NOT NULL DEFAULT 0,      -- Is this the CMS host?
    MonitorDatabase     NVARCHAR(128)   NOT NULL DEFAULT 'DBA_Monitor',
    Notes               NVARCHAR(500)   NULL,
    RegisteredAt        DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    RegisteredBy        NVARCHAR(128)   NOT NULL DEFAULT SUSER_SNAME(),
    LastCollectedAt     DATETIME2       NULL,
    LastCollectionStatus NVARCHAR(20)   NULL,  -- Success, Failed, Timeout
    CONSTRAINT UQ_RegisteredServers_Instance UNIQUE (InstanceName)
);
GO

----------------------------------------------------------------------
-- INSTANCE HEALTH SNAPSHOT (for cross-instance comparison)
----------------------------------------------------------------------
IF OBJECT_ID('monitor.InstanceHealthSnapshot', 'U') IS NULL
CREATE TABLE [monitor].[InstanceHealthSnapshot] (
    SnapshotId      BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    InstanceName    NVARCHAR(256)   NOT NULL,
    HealthScore     INT             NULL,       -- 0-100
    CpuAvg          INT             NULL,
    CpuMax          INT             NULL,
    PleAvg          INT             NULL,
    DiskMaxUsedPct  DECIMAL(5,2)    NULL,
    AgMaxLagSec     INT             NULL,
    BlockingCount   INT             NULL,
    AlertCount      INT             NULL,
    OverallStatus   NVARCHAR(10)    NULL,       -- healthy, warning, critical
    INDEX IX_InstanceHealth_Date NONCLUSTERED (CollectedAt DESC),
    INDEX IX_InstanceHealth_Instance NONCLUSTERED (InstanceName, CollectedAt DESC)
);
GO

----------------------------------------------------------------------
-- INSTANCE DRIFT DETECTION TABLE
----------------------------------------------------------------------
IF OBJECT_ID('monitor.InstanceDrift', 'U') IS NULL
CREATE TABLE [monitor].[InstanceDrift] (
    DriftId         BIGINT IDENTITY(1,1) PRIMARY KEY,
    DetectedAt      DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME(),
    InstanceName    NVARCHAR(256)   NOT NULL,
    DriftType       NVARCHAR(50)    NOT NULL,   -- Config, Performance, Health
    MetricName      NVARCHAR(100)   NOT NULL,
    InstanceValue   NVARCHAR(200)   NOT NULL,
    ClusterAvg      NVARCHAR(200)   NULL,
    DeviationPct    DECIMAL(10,2)   NULL,
    Severity        NVARCHAR(20)    NOT NULL DEFAULT 'Info',
    Message         NVARCHAR(500)   NULL,
    INDEX IX_InstanceDrift_Date NONCLUSTERED (DetectedAt DESC)
);
GO

PRINT '✓ Multi-instance CMS tables created:';
PRINT '  → [monitor].[RegisteredServers] - Instance registry';
PRINT '  → [monitor].[InstanceHealthSnapshot] - Cross-instance health data';
PRINT '  → [monitor].[InstanceDrift] - Drift detection log';
GO
