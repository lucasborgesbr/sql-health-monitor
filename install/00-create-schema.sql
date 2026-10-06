/*
    SQL Health Monitor - Schema Creation
    Creates the monitoring schema, configuration, and data collection tables.
    
    Target: SQLHealthMonitor database
    Compatibility: SQL Server 2016+
    Author: Lucas Borges
*/

USE [master];
GO

IF DB_ID('SQLHealthMonitor') IS NULL
BEGIN
    CREATE DATABASE [SQLHealthMonitor];
    PRINT 'Created database SQLHealthMonitor.';
END
GO

USE [SQLHealthMonitor];
GO

-- Create schema
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'monitor')
    EXEC('CREATE SCHEMA [monitor]');
GO

----------------------------------------------------------------------
-- VERSION TRACKING
--
-- Answers "what is actually installed on this server", which nothing else in
-- the repository can. Written by install\99-record-version.sql at the end of
-- the chain; read by deploy\Install.ps1 -Mode Status before doing anything.
----------------------------------------------------------------------

IF OBJECT_ID('monitor.SchemaVersion', 'U') IS NULL
CREATE TABLE [monitor].[SchemaVersion] (
    Id               INT IDENTITY(1,1) PRIMARY KEY,
    Version          VARCHAR(20)   NOT NULL,
    PreviousVersion  VARCHAR(20)   NULL,
    InstallMode      VARCHAR(10)   NOT NULL,   -- 'Fresh' | 'Upgrade'
    InstalledAt      DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    InstalledBy      NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
    CommitHash       VARCHAR(40)   NULL,       -- git rev-parse --short HEAD, when available
    LastVerifiedAt   DATETIME2     NULL,       -- last run that reached the end of the chain
    INDEX IX_SchemaVersion_Id (Id DESC)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.SchemaVersion', 'Version') IS NULL
    ALTER TABLE [monitor].[SchemaVersion] ADD Version VARCHAR(20) NULL;
GO

IF COL_LENGTH('monitor.SchemaVersion', 'PreviousVersion') IS NULL
    ALTER TABLE [monitor].[SchemaVersion] ADD PreviousVersion VARCHAR(20) NULL;
GO

IF COL_LENGTH('monitor.SchemaVersion', 'InstallMode') IS NULL
    ALTER TABLE [monitor].[SchemaVersion] ADD InstallMode VARCHAR(10) NULL;
GO

IF COL_LENGTH('monitor.SchemaVersion', 'InstalledBy') IS NULL
    ALTER TABLE [monitor].[SchemaVersion] ADD InstalledBy NVARCHAR(128) NULL DEFAULT SUSER_SNAME();
GO

IF COL_LENGTH('monitor.SchemaVersion', 'CommitHash') IS NULL
    ALTER TABLE [monitor].[SchemaVersion] ADD CommitHash VARCHAR(40) NULL;
GO

IF OBJECT_ID('monitor.AppliedMigrations', 'U') IS NULL
CREATE TABLE [monitor].[AppliedMigrations] (
    FileName     NVARCHAR(255) NOT NULL PRIMARY KEY,
    Version      VARCHAR(20)   NOT NULL,
    AppliedAt    DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    AppliedBy    NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME()
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.AppliedMigrations', 'FileName') IS NULL
    ALTER TABLE [monitor].[AppliedMigrations] ADD FileName NVARCHAR(255) NULL;
GO

IF COL_LENGTH('monitor.AppliedMigrations', 'Version') IS NULL
    ALTER TABLE [monitor].[AppliedMigrations] ADD Version VARCHAR(20) NULL;
GO

IF COL_LENGTH('monitor.AppliedMigrations', 'AppliedAt') IS NULL
    ALTER TABLE [monitor].[AppliedMigrations] ADD AppliedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.AppliedMigrations', 'AppliedBy') IS NULL
    ALTER TABLE [monitor].[AppliedMigrations] ADD AppliedBy NVARCHAR(128) NULL DEFAULT SUSER_SNAME();
GO

IF OBJECT_ID('[monitor].[fn_GetInstalledVersion]', 'FN') IS NOT NULL
    EXEC('ALTER FUNCTION [monitor].[fn_GetInstalledVersion]() RETURNS VARCHAR(20) AS BEGIN RETURN NULL; END;');
GO

IF OBJECT_ID('[monitor].[fn_GetInstalledVersion]', 'FN') IS NULL
    EXEC('CREATE FUNCTION [monitor].[fn_GetInstalledVersion]() RETURNS VARCHAR(20) AS BEGIN RETURN NULL; END;');
GO

ALTER FUNCTION [monitor].[fn_GetInstalledVersion]()
RETURNS VARCHAR(20)
AS
BEGIN
    -- Guarded rather than assuming: the function can be called against a
    -- database whose schema predates the table.
    IF OBJECT_ID('[monitor].[SchemaVersion]', 'U') IS NULL
        RETURN NULL;

    RETURN (SELECT TOP 1 [Version] FROM [monitor].[SchemaVersion] ORDER BY [Id] DESC);
END;
GO

----------------------------------------------------------------------
-- CONFIGURATION TABLES
----------------------------------------------------------------------

-- Central settings
IF OBJECT_ID('monitor.Settings', 'U') IS NULL
CREATE TABLE [monitor].[Settings] (
    SettingId       INT IDENTITY(1,1) PRIMARY KEY,
    Category        NVARCHAR(50)  NOT NULL,
    SettingName     NVARCHAR(100) NOT NULL,
    SettingValue    NVARCHAR(500) NOT NULL,
    Description     NVARCHAR(500) NULL,
    DataType        NVARCHAR(20)  NOT NULL DEFAULT 'string',
    ModifiedDate    DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    ModifiedBy      NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
    CONSTRAINT UQ_Settings_Name UNIQUE (Category, SettingName)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.Settings', 'Category') IS NULL
    ALTER TABLE [monitor].[Settings] ADD Category NVARCHAR(50) NULL;
GO

IF COL_LENGTH('monitor.Settings', 'SettingName') IS NULL
    ALTER TABLE [monitor].[Settings] ADD SettingName NVARCHAR(100) NULL;
GO

IF COL_LENGTH('monitor.Settings', 'SettingValue') IS NULL
    ALTER TABLE [monitor].[Settings] ADD SettingValue NVARCHAR(500) NULL;
GO

IF COL_LENGTH('monitor.Settings', 'Description') IS NULL
    ALTER TABLE [monitor].[Settings] ADD Description NVARCHAR(500) NULL;
GO

IF COL_LENGTH('monitor.Settings', 'DataType') IS NULL
    ALTER TABLE [monitor].[Settings] ADD DataType NVARCHAR(20) NULL DEFAULT 'string';
GO

IF COL_LENGTH('monitor.Settings', 'ModifiedDate') IS NULL
    ALTER TABLE [monitor].[Settings] ADD ModifiedDate DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.Settings', 'ModifiedBy') IS NULL
    ALTER TABLE [monitor].[Settings] ADD ModifiedBy NVARCHAR(128) NULL DEFAULT SUSER_SNAME();
GO

IF OBJECT_ID('monitor.Languages', 'U') IS NULL
CREATE TABLE [monitor].[Languages] (
    LanguageId      INT IDENTITY(1,1) PRIMARY KEY,
    LanguageCode    CHAR(5)       NOT NULL,  -- 'en', 'ptbr'
    StringKey       NVARCHAR(100) NOT NULL,
    StringValue     NVARCHAR(MAX) NOT NULL,
    CONSTRAINT UQ_Languages_Key UNIQUE (LanguageCode, StringKey)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.Languages', 'LanguageCode') IS NULL
    ALTER TABLE [monitor].[Languages] ADD LanguageCode CHAR(5) NULL;
GO

IF COL_LENGTH('monitor.Languages', 'StringValue') IS NULL
    ALTER TABLE [monitor].[Languages] ADD StringValue NVARCHAR(MAX) NULL;
GO

IF OBJECT_ID('monitor.Thresholds', 'U') IS NULL
CREATE TABLE [monitor].[Thresholds] (
    ThresholdId     INT IDENTITY(1,1) PRIMARY KEY,
    MetricName      NVARCHAR(100) NOT NULL,
    WarningValue    DECIMAL(18,2) NULL,
    CriticalValue   DECIMAL(18,2) NULL,
    Operator        CHAR(2)       NOT NULL DEFAULT '>=',  -- >=, <=, ==, !=
    IsEnabled       BIT           NOT NULL DEFAULT 1,
    Description     NVARCHAR(500) NULL,
    CONSTRAINT UQ_Thresholds_Metric UNIQUE (MetricName)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.Thresholds', 'MetricName') IS NULL
    ALTER TABLE [monitor].[Thresholds] ADD MetricName NVARCHAR(100) NULL;
GO

IF COL_LENGTH('monitor.Thresholds', 'WarningValue') IS NULL
    ALTER TABLE [monitor].[Thresholds] ADD WarningValue DECIMAL(18,2) NULL;
GO

IF COL_LENGTH('monitor.Thresholds', 'CriticalValue') IS NULL
    ALTER TABLE [monitor].[Thresholds] ADD CriticalValue DECIMAL(18,2) NULL;
GO

IF COL_LENGTH('monitor.Thresholds', 'Operator') IS NULL
    ALTER TABLE [monitor].[Thresholds] ADD Operator CHAR(2) NULL DEFAULT '>=';
GO

IF COL_LENGTH('monitor.Thresholds', 'Description') IS NULL
    ALTER TABLE [monitor].[Thresholds] ADD Description NVARCHAR(500) NULL;
GO

IF OBJECT_ID('monitor.CpuHistory', 'U') IS NULL
CREATE TABLE [monitor].[CpuHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    SqlCpuPct       TINYINT       NOT NULL,
    SystemCpuPct    TINYINT       NOT NULL,
    IdleCpuPct      TINYINT       NOT NULL,
    INDEX IX_CpuHistory_Date NONCLUSTERED (CollectedAt)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.CpuHistory', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[CpuHistory] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.CpuHistory', 'SqlCpuPct') IS NULL
    ALTER TABLE [monitor].[CpuHistory] ADD SqlCpuPct TINYINT NULL;
GO

IF COL_LENGTH('monitor.CpuHistory', 'SystemCpuPct') IS NULL
    ALTER TABLE [monitor].[CpuHistory] ADD SystemCpuPct TINYINT NULL;
GO

IF COL_LENGTH('monitor.CpuHistory', 'IdleCpuPct') IS NULL
    ALTER TABLE [monitor].[CpuHistory] ADD IdleCpuPct TINYINT NULL;
GO

IF OBJECT_ID('monitor.MemoryHistory', 'U') IS NULL
CREATE TABLE [monitor].[MemoryHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    TotalServerMemoryMB   BIGINT  NOT NULL,
    TargetServerMemoryMB  BIGINT  NOT NULL,
    AvailableMemoryMB     BIGINT  NOT NULL,
    PageLifeExpectancy    INT     NOT NULL,
    BufferCacheHitRatio   DECIMAL(5,2) NULL,
    MemoryGrantsPending   INT     NOT NULL DEFAULT 0,
    INDEX IX_MemoryHistory_Date NONCLUSTERED (CollectedAt)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.MemoryHistory', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[MemoryHistory] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.MemoryHistory', 'TotalServerMemoryMB') IS NULL
    ALTER TABLE [monitor].[MemoryHistory] ADD TotalServerMemoryMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.MemoryHistory', 'TargetServerMemoryMB') IS NULL
    ALTER TABLE [monitor].[MemoryHistory] ADD TargetServerMemoryMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.MemoryHistory', 'AvailableMemoryMB') IS NULL
    ALTER TABLE [monitor].[MemoryHistory] ADD AvailableMemoryMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.MemoryHistory', 'PageLifeExpectancy') IS NULL
    ALTER TABLE [monitor].[MemoryHistory] ADD PageLifeExpectancy INT NULL;
GO

IF COL_LENGTH('monitor.MemoryHistory', 'BufferCacheHitRatio') IS NULL
    ALTER TABLE [monitor].[MemoryHistory] ADD BufferCacheHitRatio DECIMAL(5,2) NULL;
GO

IF COL_LENGTH('monitor.MemoryHistory', 'MemoryGrantsPending') IS NULL
    ALTER TABLE [monitor].[MemoryHistory] ADD MemoryGrantsPending INT NULL DEFAULT 0;
GO

IF OBJECT_ID('monitor.DiskHistory', 'U') IS NULL
CREATE TABLE [monitor].[DiskHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    DriveLetter     CHAR(3)       NOT NULL,
    TotalSpaceMB    BIGINT        NOT NULL,
    FreeSpaceMB     BIGINT        NOT NULL,
    UsedPct         DECIMAL(5,2)  NOT NULL,
    AvgReadLatencyMs  DECIMAL(10,2) NULL,
    AvgWriteLatencyMs DECIMAL(10,2) NULL,
    INDEX IX_DiskHistory_Date NONCLUSTERED (CollectedAt)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.DiskHistory', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[DiskHistory] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.DiskHistory', 'DriveLetter') IS NULL
    ALTER TABLE [monitor].[DiskHistory] ADD DriveLetter CHAR(3) NULL;
GO

IF COL_LENGTH('monitor.DiskHistory', 'TotalSpaceMB') IS NULL
    ALTER TABLE [monitor].[DiskHistory] ADD TotalSpaceMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.DiskHistory', 'FreeSpaceMB') IS NULL
    ALTER TABLE [monitor].[DiskHistory] ADD FreeSpaceMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.DiskHistory', 'UsedPct') IS NULL
    ALTER TABLE [monitor].[DiskHistory] ADD UsedPct DECIMAL(5,2) NULL;
GO

IF COL_LENGTH('monitor.DiskHistory', 'AvgReadLatencyMs') IS NULL
    ALTER TABLE [monitor].[DiskHistory] ADD AvgReadLatencyMs DECIMAL(10,2) NULL;
GO

IF COL_LENGTH('monitor.DiskHistory', 'AvgWriteLatencyMs') IS NULL
    ALTER TABLE [monitor].[DiskHistory] ADD AvgWriteLatencyMs DECIMAL(10,2) NULL;
GO

IF OBJECT_ID('monitor.WaitStatsHistory', 'U') IS NULL
CREATE TABLE [monitor].[WaitStatsHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    WaitType        NVARCHAR(120) NOT NULL,
    WaitingTasksCount BIGINT      NOT NULL,
    WaitTimeMs      BIGINT        NOT NULL,
    SignalWaitTimeMs BIGINT        NOT NULL,
    DeltaWaitTimeMs BIGINT        NULL,  -- Calculated delta from previous snapshot
    INDEX IX_WaitStats_Date NONCLUSTERED (CollectedAt),
    INDEX IX_WaitStats_Type NONCLUSTERED (WaitType, CollectedAt)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.WaitStatsHistory', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[WaitStatsHistory] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.WaitStatsHistory', 'WaitType') IS NULL
    ALTER TABLE [monitor].[WaitStatsHistory] ADD WaitType NVARCHAR(120) NULL;
GO

IF COL_LENGTH('monitor.WaitStatsHistory', 'WaitingTasksCount') IS NULL
    ALTER TABLE [monitor].[WaitStatsHistory] ADD WaitingTasksCount BIGINT NULL;
GO

IF COL_LENGTH('monitor.WaitStatsHistory', 'WaitTimeMs') IS NULL
    ALTER TABLE [monitor].[WaitStatsHistory] ADD WaitTimeMs BIGINT NULL;
GO

IF COL_LENGTH('monitor.WaitStatsHistory', 'SignalWaitTimeMs') IS NULL
    ALTER TABLE [monitor].[WaitStatsHistory] ADD SignalWaitTimeMs BIGINT NULL;
GO

IF COL_LENGTH('monitor.WaitStatsHistory', 'DeltaWaitTimeMs') IS NULL
    ALTER TABLE [monitor].[WaitStatsHistory] ADD DeltaWaitTimeMs BIGINT NULL;
GO

IF OBJECT_ID('monitor.BlockingHistory', 'U') IS NULL
CREATE TABLE [monitor].[BlockingHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    DetectedAt      DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    BlockingSpid    INT           NOT NULL,
    BlockedSpid     INT           NOT NULL,
    BlockingDurationSec INT       NOT NULL,
    BlockingQuery   NVARCHAR(MAX) NULL,
    BlockedQuery    NVARCHAR(MAX) NULL,
    DatabaseName    NVARCHAR(128) NULL,
    WaitType        NVARCHAR(120) NULL,
    INDEX IX_Blocking_Date NONCLUSTERED (DetectedAt)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.BlockingHistory', 'DetectedAt') IS NULL
    ALTER TABLE [monitor].[BlockingHistory] ADD DetectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.BlockingHistory', 'BlockingSpid') IS NULL
    ALTER TABLE [monitor].[BlockingHistory] ADD BlockingSpid INT NULL;
GO

IF COL_LENGTH('monitor.BlockingHistory', 'BlockedSpid') IS NULL
    ALTER TABLE [monitor].[BlockingHistory] ADD BlockedSpid INT NULL;
GO

IF COL_LENGTH('monitor.BlockingHistory', 'BlockingDurationSec') IS NULL
    ALTER TABLE [monitor].[BlockingHistory] ADD BlockingDurationSec INT NULL;
GO

IF COL_LENGTH('monitor.BlockingHistory', 'BlockingQuery') IS NULL
    ALTER TABLE [monitor].[BlockingHistory] ADD BlockingQuery NVARCHAR(MAX) NULL;
GO

IF COL_LENGTH('monitor.BlockingHistory', 'BlockedQuery') IS NULL
    ALTER TABLE [monitor].[BlockingHistory] ADD BlockedQuery NVARCHAR(MAX) NULL;
GO

IF COL_LENGTH('monitor.BlockingHistory', 'DatabaseName') IS NULL
    ALTER TABLE [monitor].[BlockingHistory] ADD DatabaseName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.BlockingHistory', 'WaitType') IS NULL
    ALTER TABLE [monitor].[BlockingHistory] ADD WaitType NVARCHAR(120) NULL;
GO

IF OBJECT_ID('monitor.AgHealthHistory', 'U') IS NULL
CREATE TABLE [monitor].[AgHealthHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    AgName          NVARCHAR(128) NOT NULL,
    ReplicaServer   NVARCHAR(128) NOT NULL,
    DatabaseName    NVARCHAR(128) NOT NULL,
    SyncState       NVARCHAR(60)  NOT NULL,
    SyncHealth      NVARCHAR(60)  NOT NULL,
    LogSendQueueSizeKB   BIGINT   NULL,
    RedoQueueSizeKB      BIGINT   NULL,
    LastCommitTime       DATETIME2 NULL,
    SecondsBehindPrimary INT      NULL,
    INDEX IX_AgHealth_Date NONCLUSTERED (CollectedAt),
    INDEX IX_AgHealth_AG NONCLUSTERED (AgName, CollectedAt)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.AgHealthHistory', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[AgHealthHistory] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.AgHealthHistory', 'AgName') IS NULL
    ALTER TABLE [monitor].[AgHealthHistory] ADD AgName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.AgHealthHistory', 'ReplicaServer') IS NULL
    ALTER TABLE [monitor].[AgHealthHistory] ADD ReplicaServer NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.AgHealthHistory', 'DatabaseName') IS NULL
    ALTER TABLE [monitor].[AgHealthHistory] ADD DatabaseName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.AgHealthHistory', 'SyncState') IS NULL
    ALTER TABLE [monitor].[AgHealthHistory] ADD SyncState NVARCHAR(60) NULL;
GO

IF COL_LENGTH('monitor.AgHealthHistory', 'SyncHealth') IS NULL
    ALTER TABLE [monitor].[AgHealthHistory] ADD SyncHealth NVARCHAR(60) NULL;
GO

IF COL_LENGTH('monitor.AgHealthHistory', 'LogSendQueueSizeKB') IS NULL
    ALTER TABLE [monitor].[AgHealthHistory] ADD LogSendQueueSizeKB BIGINT NULL;
GO

IF COL_LENGTH('monitor.AgHealthHistory', 'RedoQueueSizeKB') IS NULL
    ALTER TABLE [monitor].[AgHealthHistory] ADD RedoQueueSizeKB BIGINT NULL;
GO

IF COL_LENGTH('monitor.AgHealthHistory', 'LastCommitTime') IS NULL
    ALTER TABLE [monitor].[AgHealthHistory] ADD LastCommitTime DATETIME2 NULL;
GO

IF COL_LENGTH('monitor.AgHealthHistory', 'SecondsBehindPrimary') IS NULL
    ALTER TABLE [monitor].[AgHealthHistory] ADD SecondsBehindPrimary INT NULL;
GO

IF OBJECT_ID('monitor.CdcHealthHistory', 'U') IS NULL
CREATE TABLE [monitor].[CdcHealthHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    DatabaseName    NVARCHAR(128) NOT NULL,
    CaptureJobStatus NVARCHAR(20) NOT NULL,
    CleanupJobStatus NVARCHAR(20) NOT NULL,
    LatencySeconds  INT           NULL,
    MinLsn          NVARCHAR(50)  NULL,
    MaxLsn          NVARCHAR(50)  NULL,
    RetentionMinutes INT          NULL,
    INDEX IX_CdcHealth_Date NONCLUSTERED (CollectedAt)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.CdcHealthHistory', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[CdcHealthHistory] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.CdcHealthHistory', 'DatabaseName') IS NULL
    ALTER TABLE [monitor].[CdcHealthHistory] ADD DatabaseName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.CdcHealthHistory', 'CaptureJobStatus') IS NULL
    ALTER TABLE [monitor].[CdcHealthHistory] ADD CaptureJobStatus NVARCHAR(20) NULL;
GO

IF COL_LENGTH('monitor.CdcHealthHistory', 'CleanupJobStatus') IS NULL
    ALTER TABLE [monitor].[CdcHealthHistory] ADD CleanupJobStatus NVARCHAR(20) NULL;
GO

IF COL_LENGTH('monitor.CdcHealthHistory', 'LatencySeconds') IS NULL
    ALTER TABLE [monitor].[CdcHealthHistory] ADD LatencySeconds INT NULL;
GO

IF COL_LENGTH('monitor.CdcHealthHistory', 'MinLsn') IS NULL
    ALTER TABLE [monitor].[CdcHealthHistory] ADD MinLsn NVARCHAR(50) NULL;
GO

IF COL_LENGTH('monitor.CdcHealthHistory', 'MaxLsn') IS NULL
    ALTER TABLE [monitor].[CdcHealthHistory] ADD MaxLsn NVARCHAR(50) NULL;
GO

IF COL_LENGTH('monitor.CdcHealthHistory', 'RetentionMinutes') IS NULL
    ALTER TABLE [monitor].[CdcHealthHistory] ADD RetentionMinutes INT NULL;
GO

IF OBJECT_ID('monitor.TopQueriesHistory', 'U') IS NULL
CREATE TABLE [monitor].[TopQueriesHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    DatabaseName    NVARCHAR(128) NULL,
    QueryHash       BINARY(8)     NULL,
    TotalCpuMs      BIGINT        NOT NULL,
    TotalReads      BIGINT        NOT NULL,
    TotalWrites     BIGINT        NOT NULL,
    ExecutionCount  BIGINT        NOT NULL,
    AvgDurationMs   BIGINT        NOT NULL,
    QueryText       NVARCHAR(MAX) NULL,
    PlanHandle      VARBINARY(64) NULL,
    INDEX IX_TopQueries_Date NONCLUSTERED (CollectedAt)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.TopQueriesHistory', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[TopQueriesHistory] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.TopQueriesHistory', 'DatabaseName') IS NULL
    ALTER TABLE [monitor].[TopQueriesHistory] ADD DatabaseName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.TopQueriesHistory', 'QueryHash') IS NULL
    ALTER TABLE [monitor].[TopQueriesHistory] ADD QueryHash BINARY(8) NULL;
GO

IF COL_LENGTH('monitor.TopQueriesHistory', 'TotalCpuMs') IS NULL
    ALTER TABLE [monitor].[TopQueriesHistory] ADD TotalCpuMs BIGINT NULL;
GO

IF COL_LENGTH('monitor.TopQueriesHistory', 'TotalReads') IS NULL
    ALTER TABLE [monitor].[TopQueriesHistory] ADD TotalReads BIGINT NULL;
GO

IF COL_LENGTH('monitor.TopQueriesHistory', 'TotalWrites') IS NULL
    ALTER TABLE [monitor].[TopQueriesHistory] ADD TotalWrites BIGINT NULL;
GO

IF COL_LENGTH('monitor.TopQueriesHistory', 'ExecutionCount') IS NULL
    ALTER TABLE [monitor].[TopQueriesHistory] ADD ExecutionCount BIGINT NULL;
GO

IF COL_LENGTH('monitor.TopQueriesHistory', 'AvgDurationMs') IS NULL
    ALTER TABLE [monitor].[TopQueriesHistory] ADD AvgDurationMs BIGINT NULL;
GO

IF COL_LENGTH('monitor.TopQueriesHistory', 'QueryText') IS NULL
    ALTER TABLE [monitor].[TopQueriesHistory] ADD QueryText NVARCHAR(MAX) NULL;
GO

IF COL_LENGTH('monitor.TopQueriesHistory', 'PlanHandle') IS NULL
    ALTER TABLE [monitor].[TopQueriesHistory] ADD PlanHandle VARBINARY(64) NULL;
GO

IF OBJECT_ID('monitor.IndexHealthHistory', 'U') IS NULL
CREATE TABLE [monitor].[IndexHealthHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    DatabaseName    NVARCHAR(128) NOT NULL,
    SchemaName      NVARCHAR(128) NOT NULL,
    TableName       NVARCHAR(128) NOT NULL,
    IndexName       NVARCHAR(128) NULL,
    IndexType       NVARCHAR(60)  NOT NULL,
    FragmentationPct DECIMAL(5,2) NOT NULL,
    PageCount       BIGINT        NOT NULL,
    UserSeeks       BIGINT        NULL,
    UserScans       BIGINT        NULL,
    UserLookups     BIGINT        NULL,
    UserUpdates     BIGINT        NULL,
    INDEX IX_IndexHealth_Date NONCLUSTERED (CollectedAt)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.IndexHealthHistory', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[IndexHealthHistory] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.IndexHealthHistory', 'DatabaseName') IS NULL
    ALTER TABLE [monitor].[IndexHealthHistory] ADD DatabaseName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.IndexHealthHistory', 'SchemaName') IS NULL
    ALTER TABLE [monitor].[IndexHealthHistory] ADD SchemaName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.IndexHealthHistory', 'TableName') IS NULL
    ALTER TABLE [monitor].[IndexHealthHistory] ADD TableName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.IndexHealthHistory', 'IndexName') IS NULL
    ALTER TABLE [monitor].[IndexHealthHistory] ADD IndexName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.IndexHealthHistory', 'IndexType') IS NULL
    ALTER TABLE [monitor].[IndexHealthHistory] ADD IndexType NVARCHAR(60) NULL;
GO

IF COL_LENGTH('monitor.IndexHealthHistory', 'FragmentationPct') IS NULL
    ALTER TABLE [monitor].[IndexHealthHistory] ADD FragmentationPct DECIMAL(5,2) NULL;
GO

IF COL_LENGTH('monitor.IndexHealthHistory', 'PageCount') IS NULL
    ALTER TABLE [monitor].[IndexHealthHistory] ADD PageCount BIGINT NULL;
GO

IF COL_LENGTH('monitor.IndexHealthHistory', 'UserSeeks') IS NULL
    ALTER TABLE [monitor].[IndexHealthHistory] ADD UserSeeks BIGINT NULL;
GO

IF COL_LENGTH('monitor.IndexHealthHistory', 'UserScans') IS NULL
    ALTER TABLE [monitor].[IndexHealthHistory] ADD UserScans BIGINT NULL;
GO

IF COL_LENGTH('monitor.IndexHealthHistory', 'UserLookups') IS NULL
    ALTER TABLE [monitor].[IndexHealthHistory] ADD UserLookups BIGINT NULL;
GO

IF COL_LENGTH('monitor.IndexHealthHistory', 'UserUpdates') IS NULL
    ALTER TABLE [monitor].[IndexHealthHistory] ADD UserUpdates BIGINT NULL;
GO

IF OBJECT_ID('monitor.BackupHistory', 'U') IS NULL
CREATE TABLE [monitor].[BackupHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    DatabaseName    NVARCHAR(128) NOT NULL,
    BackupType      CHAR(1)       NOT NULL,  -- D=Full, I=Diff, L=Log
    LastBackupDate  DATETIME2     NULL,
    BackupSizeMB    BIGINT        NULL,
    CompressedSizeMB BIGINT       NULL,
    DurationSeconds INT           NULL,
    HoursSinceLastBackup AS DATEDIFF(HOUR, LastBackupDate, SYSUTCDATETIME()),
    INDEX IX_BackupHistory_Date NONCLUSTERED (CollectedAt)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.BackupHistory', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[BackupHistory] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.BackupHistory', 'DatabaseName') IS NULL
    ALTER TABLE [monitor].[BackupHistory] ADD DatabaseName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.BackupHistory', 'BackupType') IS NULL
    ALTER TABLE [monitor].[BackupHistory] ADD BackupType CHAR(1) NULL;
GO

IF COL_LENGTH('monitor.BackupHistory', 'BackupSizeMB') IS NULL
    ALTER TABLE [monitor].[BackupHistory] ADD BackupSizeMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.BackupHistory', 'CompressedSizeMB') IS NULL
    ALTER TABLE [monitor].[BackupHistory] ADD CompressedSizeMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.BackupHistory', 'DurationSeconds') IS NULL
    ALTER TABLE [monitor].[BackupHistory] ADD DurationSeconds INT NULL;
GO

IF COL_LENGTH('monitor.BackupHistory', 'HoursSinceLastBackup') IS NULL
    ALTER TABLE [monitor].[BackupHistory] ADD HoursSinceLastBackup AS DATEDIFF(HOUR, LastBackupDate, SYSUTCDATETIME());
GO

IF OBJECT_ID('monitor.JobHistory', 'U') IS NULL
CREATE TABLE [monitor].[JobHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    JobName         NVARCHAR(256) NOT NULL,
    LastRunDate     DATETIME2     NULL,
    LastRunStatus   NVARCHAR(20)  NOT NULL,  -- Succeeded, Failed, Retry, Canceled
    LastRunDuration INT           NULL,       -- seconds
    NextRunDate     DATETIME2     NULL,
    IsEnabled       BIT           NOT NULL,
    INDEX IX_JobHistory_Date NONCLUSTERED (CollectedAt)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.JobHistory', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[JobHistory] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.JobHistory', 'JobName') IS NULL
    ALTER TABLE [monitor].[JobHistory] ADD JobName NVARCHAR(256) NULL;
GO

IF COL_LENGTH('monitor.JobHistory', 'LastRunDate') IS NULL
    ALTER TABLE [monitor].[JobHistory] ADD LastRunDate DATETIME2 NULL;
GO

IF COL_LENGTH('monitor.JobHistory', 'LastRunStatus') IS NULL
    ALTER TABLE [monitor].[JobHistory] ADD LastRunStatus NVARCHAR(20) NULL;
GO

IF COL_LENGTH('monitor.JobHistory', 'IsEnabled') IS NULL
    ALTER TABLE [monitor].[JobHistory] ADD IsEnabled BIT NULL;
GO

IF OBJECT_ID('monitor.TempDbHistory', 'U') IS NULL
CREATE TABLE [monitor].[TempDbHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    TotalSizeMB     BIGINT        NOT NULL,
    UsedSpaceMB     BIGINT        NOT NULL,
    FreeSpaceMB     BIGINT        NOT NULL,
    VersionStoreMB  BIGINT        NULL,
    UserObjectsMB   BIGINT        NULL,
    InternalObjectsMB BIGINT      NULL,
    INDEX IX_TempDb_Date NONCLUSTERED (CollectedAt)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.TempDbHistory', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[TempDbHistory] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.TempDbHistory', 'TotalSizeMB') IS NULL
    ALTER TABLE [monitor].[TempDbHistory] ADD TotalSizeMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.TempDbHistory', 'UsedSpaceMB') IS NULL
    ALTER TABLE [monitor].[TempDbHistory] ADD UsedSpaceMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.TempDbHistory', 'FreeSpaceMB') IS NULL
    ALTER TABLE [monitor].[TempDbHistory] ADD FreeSpaceMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.TempDbHistory', 'VersionStoreMB') IS NULL
    ALTER TABLE [monitor].[TempDbHistory] ADD VersionStoreMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.TempDbHistory', 'UserObjectsMB') IS NULL
    ALTER TABLE [monitor].[TempDbHistory] ADD UserObjectsMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.TempDbHistory', 'InternalObjectsMB') IS NULL
    ALTER TABLE [monitor].[TempDbHistory] ADD InternalObjectsMB BIGINT NULL;
GO

IF OBJECT_ID('monitor.FileGrowthHistory', 'U') IS NULL
CREATE TABLE [monitor].[FileGrowthHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    DatabaseName    NVARCHAR(128) NOT NULL,
    FileName        NVARCHAR(128) NOT NULL,
    FileType        NVARCHAR(10)  NOT NULL,  -- ROWS, LOG
    SizeMB          BIGINT        NOT NULL,
    UsedMB          BIGINT        NOT NULL,
    GrowthMB        BIGINT        NULL,      -- Delta from previous collection
    INDEX IX_FileGrowth_Date NONCLUSTERED (CollectedAt)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.FileGrowthHistory', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[FileGrowthHistory] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.FileGrowthHistory', 'DatabaseName') IS NULL
    ALTER TABLE [monitor].[FileGrowthHistory] ADD DatabaseName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.FileGrowthHistory', 'FileName') IS NULL
    ALTER TABLE [monitor].[FileGrowthHistory] ADD FileName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.FileGrowthHistory', 'FileType') IS NULL
    ALTER TABLE [monitor].[FileGrowthHistory] ADD FileType NVARCHAR(10) NULL;
GO

IF COL_LENGTH('monitor.FileGrowthHistory', 'UsedMB') IS NULL
    ALTER TABLE [monitor].[FileGrowthHistory] ADD UsedMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.FileGrowthHistory', 'GrowthMB') IS NULL
    ALTER TABLE [monitor].[FileGrowthHistory] ADD GrowthMB BIGINT NULL;
GO

IF OBJECT_ID('monitor.ErrorLogHistory', 'U') IS NULL
CREATE TABLE [monitor].[ErrorLogHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    LogDate         DATETIME2     NOT NULL,
    ProcessInfo     NVARCHAR(50)  NULL,
    ErrorMessage    NVARCHAR(MAX) NOT NULL,
    Severity        NVARCHAR(20)  NULL,  -- Critical, Error, Warning, Info
    INDEX IX_ErrorLog_Date NONCLUSTERED (CollectedAt),
    INDEX IX_ErrorLog_Severity NONCLUSTERED (Severity, CollectedAt)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.ErrorLogHistory', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[ErrorLogHistory] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.ErrorLogHistory', 'LogDate') IS NULL
    ALTER TABLE [monitor].[ErrorLogHistory] ADD LogDate DATETIME2 NULL;
GO

IF COL_LENGTH('monitor.ErrorLogHistory', 'ProcessInfo') IS NULL
    ALTER TABLE [monitor].[ErrorLogHistory] ADD ProcessInfo NVARCHAR(50) NULL;
GO

IF COL_LENGTH('monitor.ErrorLogHistory', 'ErrorMessage') IS NULL
    ALTER TABLE [monitor].[ErrorLogHistory] ADD ErrorMessage NVARCHAR(MAX) NULL;
GO

IF COL_LENGTH('monitor.ErrorLogHistory', 'Severity') IS NULL
    ALTER TABLE [monitor].[ErrorLogHistory] ADD Severity NVARCHAR(20) NULL;
GO

IF OBJECT_ID('monitor.AlertHistory', 'U') IS NULL
CREATE TABLE [monitor].[AlertHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    FiredAt         DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    MetricName      NVARCHAR(100) NOT NULL,
    Severity        NVARCHAR(20)  NOT NULL,  -- Warning, Critical
    CurrentValue    DECIMAL(18,2) NOT NULL,
    ThresholdValue  DECIMAL(18,2) NOT NULL,
    Message         NVARCHAR(MAX) NULL,
    Acknowledged    BIT           NOT NULL DEFAULT 0,
    AcknowledgedBy  NVARCHAR(128) NULL,
    AcknowledgedAt  DATETIME2     NULL,
    INDEX IX_AlertHistory_Date NONCLUSTERED (FiredAt),
    INDEX IX_AlertHistory_Severity NONCLUSTERED (Severity, FiredAt)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.AlertHistory', 'FiredAt') IS NULL
    ALTER TABLE [monitor].[AlertHistory] ADD FiredAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.AlertHistory', 'MetricName') IS NULL
    ALTER TABLE [monitor].[AlertHistory] ADD MetricName NVARCHAR(100) NULL;
GO

IF COL_LENGTH('monitor.AlertHistory', 'Severity') IS NULL
    ALTER TABLE [monitor].[AlertHistory] ADD Severity NVARCHAR(20) NULL;
GO

IF COL_LENGTH('monitor.AlertHistory', 'ThresholdValue') IS NULL
    ALTER TABLE [monitor].[AlertHistory] ADD ThresholdValue DECIMAL(18,2) NULL;
GO

IF COL_LENGTH('monitor.AlertHistory', 'Message') IS NULL
    ALTER TABLE [monitor].[AlertHistory] ADD Message NVARCHAR(MAX) NULL;
GO

IF COL_LENGTH('monitor.AlertHistory', 'Acknowledged') IS NULL
    ALTER TABLE [monitor].[AlertHistory] ADD Acknowledged BIT NULL DEFAULT 0;
GO

IF COL_LENGTH('monitor.AlertHistory', 'AcknowledgedBy') IS NULL
    ALTER TABLE [monitor].[AlertHistory] ADD AcknowledgedBy NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.AlertHistory', 'AcknowledgedAt') IS NULL
    ALTER TABLE [monitor].[AlertHistory] ADD AcknowledgedAt DATETIME2 NULL;
GO

IF OBJECT_ID('monitor.ReportHistory', 'U') IS NULL
CREATE TABLE [monitor].[ReportHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    SentAt          DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    ReportType      NVARCHAR(50)  NOT NULL,  -- Daily, Weekly, Alert
    Recipients      NVARCHAR(500) NOT NULL,
    Language        CHAR(5)       NOT NULL,
    Success         BIT           NOT NULL DEFAULT 1,
    ErrorMessage    NVARCHAR(MAX) NULL
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.ReportHistory', 'SentAt') IS NULL
    ALTER TABLE [monitor].[ReportHistory] ADD SentAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.ReportHistory', 'ReportType') IS NULL
    ALTER TABLE [monitor].[ReportHistory] ADD ReportType NVARCHAR(50) NULL;
GO

IF COL_LENGTH('monitor.ReportHistory', 'Language') IS NULL
    ALTER TABLE [monitor].[ReportHistory] ADD Language CHAR(5) NULL;
GO

IF COL_LENGTH('monitor.ReportHistory', 'Success') IS NULL
    ALTER TABLE [monitor].[ReportHistory] ADD Success BIT NULL DEFAULT 1;
GO

IF COL_LENGTH('monitor.ReportHistory', 'ErrorMessage') IS NULL
    ALTER TABLE [monitor].[ReportHistory] ADD ErrorMessage NVARCHAR(MAX) NULL;
GO

IF OBJECT_ID('monitor.Recommendations', 'U') IS NULL
CREATE TABLE [monitor].[Recommendations] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    MetricName      NVARCHAR(100) NOT NULL,
    CurrentValue    DECIMAL(18,2) NULL,
    Recommendation  NVARCHAR(MAX) NOT NULL,
    Priority        NVARCHAR(20)  NOT NULL,  -- HIGH, MEDIUM, LOW
    CreatedAt       DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    Acknowledged    BIT           NOT NULL DEFAULT 0,
    AcknowledgedBy  NVARCHAR(128) NULL,
    AcknowledgedAt  DATETIME2     NULL,
    INDEX IX_Recommendations_Date NONCLUSTERED (CreatedAt),
    INDEX IX_Recommendations_Priority NONCLUSTERED (Priority, CreatedAt)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.Recommendations', 'MetricName') IS NULL
    ALTER TABLE [monitor].[Recommendations] ADD MetricName NVARCHAR(100) NULL;
GO

IF COL_LENGTH('monitor.Recommendations', 'CurrentValue') IS NULL
    ALTER TABLE [monitor].[Recommendations] ADD CurrentValue DECIMAL(18,2) NULL;
GO

IF COL_LENGTH('monitor.Recommendations', 'Recommendation') IS NULL
    ALTER TABLE [monitor].[Recommendations] ADD Recommendation NVARCHAR(MAX) NULL;
GO

IF COL_LENGTH('monitor.Recommendations', 'Priority') IS NULL
    ALTER TABLE [monitor].[Recommendations] ADD Priority NVARCHAR(20) NULL;
GO

IF COL_LENGTH('monitor.Recommendations', 'Acknowledged') IS NULL
    ALTER TABLE [monitor].[Recommendations] ADD Acknowledged BIT NULL DEFAULT 0;
GO

IF COL_LENGTH('monitor.Recommendations', 'AcknowledgedBy') IS NULL
    ALTER TABLE [monitor].[Recommendations] ADD AcknowledgedBy NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.Recommendations', 'AcknowledgedAt') IS NULL
    ALTER TABLE [monitor].[Recommendations] ADD AcknowledgedAt DATETIME2 NULL;
GO

IF OBJECT_ID('monitor.Incidents', 'U') IS NULL
CREATE TABLE [monitor].[Incidents] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    IncidentId      UNIQUEIDENTIFIER DEFAULT NEWID() UNIQUE,
    DetectedAt      DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    ResolvedAt      DATETIME2     NULL,
    IncidentType    NVARCHAR(50)  NOT NULL,  -- Planned, Unplanned, Emergency
    Category        NVARCHAR(50)  NOT NULL,  -- Database, Server, Network, Application
    Severity        NVARCHAR(20)  NOT NULL,  -- Critical, High, Medium, Low
    Title           NVARCHAR(200) NOT NULL,
    Description     NVARCHAR(MAX) NOT NULL,
    Impact          NVARCHAR(500) NULL,      -- Business impact description
    DurationMinutes INT           NULL,      -- Calculated field
    IsResolved      BIT           NOT NULL DEFAULT 0,
    CreatedBy       NVARCHAR(128) NOT NULL,
    UpdatedBy       NVARCHAR(128) NULL,
    INDEX IX_Incidents_Date NONCLUSTERED (DetectedAt),
    INDEX IX_Incidents_Type NONCLUSTERED (IncidentType, DetectedAt),
    INDEX IX_Incidents_Severity NONCLUSTERED (Severity, DetectedAt)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.Incidents', 'IncidentId') IS NULL
    ALTER TABLE [monitor].[Incidents] ADD IncidentId UNIQUEIDENTIFIER DEFAULT NEWID();
GO

IF COL_LENGTH('monitor.Incidents', 'DetectedAt') IS NULL
    ALTER TABLE [monitor].[Incidents] ADD DetectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.Incidents', 'ResolvedAt') IS NULL
    ALTER TABLE [monitor].[Incidents] ADD ResolvedAt DATETIME2 NULL;
GO

IF COL_LENGTH('monitor.Incidents', 'IncidentType') IS NULL
    ALTER TABLE [monitor].[Incidents] ADD IncidentType NVARCHAR(50) NULL;
GO

IF COL_LENGTH('monitor.Incidents', 'Description') IS NULL
    ALTER TABLE [monitor].[Incidents] ADD Description NVARCHAR(MAX) NULL;
GO

IF COL_LENGTH('monitor.Incidents', 'Impact') IS NULL
    ALTER TABLE [monitor].[Incidents] ADD Impact NVARCHAR(500) NULL;
GO

IF COL_LENGTH('monitor.Incidents', 'CreatedBy') IS NULL
    ALTER TABLE [monitor].[Incidents] ADD CreatedBy NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.Incidents', 'UpdatedBy') IS NULL
    ALTER TABLE [monitor].[Incidents] ADD UpdatedBy NVARCHAR(128) NULL;
GO

IF OBJECT_ID('monitor.UptimePeriods', 'U') IS NULL
CREATE TABLE [monitor].[UptimePeriods] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    PeriodStart     DATETIME2     NOT NULL,
    PeriodEnd       DATETIME2     NOT NULL,
    TotalMinutes    INT           NOT NULL,
    UptimeMinutes   INT           NOT NULL,
    DowntimeMinutes INT           NOT NULL,
    UptimePercentage DECIMAL(5,2) NOT NULL,
    IncidentCount   INT           NOT NULL DEFAULT 0,
    CriticalIncidents INT          NOT NULL DEFAULT 0,
    CreatedAt       DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    PeriodType      NVARCHAR(20)  NOT NULL,  -- Hourly, Daily, Weekly, Monthly
    INDEX IX_UptimePeriods_Date NONCLUSTERED (PeriodStart),
    INDEX IX_UptimePeriods_Type NONCLUSTERED (PeriodType, PeriodStart)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.UptimePeriods', 'PeriodStart') IS NULL
    ALTER TABLE [monitor].[UptimePeriods] ADD PeriodStart DATETIME2 NULL;
GO

IF COL_LENGTH('monitor.UptimePeriods', 'PeriodEnd') IS NULL
    ALTER TABLE [monitor].[UptimePeriods] ADD PeriodEnd DATETIME2 NULL;
GO

IF COL_LENGTH('monitor.UptimePeriods', 'TotalMinutes') IS NULL
    ALTER TABLE [monitor].[UptimePeriods] ADD TotalMinutes INT NULL;
GO

IF COL_LENGTH('monitor.UptimePeriods', 'UptimeMinutes') IS NULL
    ALTER TABLE [monitor].[UptimePeriods] ADD UptimeMinutes INT NULL;
GO

IF COL_LENGTH('monitor.UptimePeriods', 'DowntimeMinutes') IS NULL
    ALTER TABLE [monitor].[UptimePeriods] ADD DowntimeMinutes INT NULL;
GO

IF COL_LENGTH('monitor.UptimePeriods', 'UptimePercentage') IS NULL
    ALTER TABLE [monitor].[UptimePeriods] ADD UptimePercentage DECIMAL(5,2) NULL;
GO

IF COL_LENGTH('monitor.UptimePeriods', 'IncidentCount') IS NULL
    ALTER TABLE [monitor].[UptimePeriods] ADD IncidentCount INT NULL DEFAULT 0;
GO

IF COL_LENGTH('monitor.UptimePeriods', 'CriticalIncidents') IS NULL
    ALTER TABLE [monitor].[UptimePeriods] ADD CriticalIncidents INT NULL DEFAULT 0;
GO

IF COL_LENGTH('monitor.UptimePeriods', 'CreatedAt') IS NULL
    ALTER TABLE [monitor].[UptimePeriods] ADD CreatedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.UptimePeriods', 'PeriodType') IS NULL
    ALTER TABLE [monitor].[UptimePeriods] ADD PeriodType NVARCHAR(20) NULL;
GO

IF OBJECT_ID('monitor.SLATracking', 'U') IS NULL
CREATE TABLE [monitor].[SLATracking] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    PeriodStart     DATETIME2     NOT NULL,
    PeriodEnd       DATETIME2     NOT NULL,
    TargetUptime    DECIMAL(5,2) NOT NULL,    -- Target SLA percentage
    ActualUptime    DECIMAL(5,2) NOT NULL,
    SLAMet          BIT           NOT NULL,
    ViolationCount  INT           NOT NULL,
    CriticalViolations INT         NOT NULL,
    PenaltyMinutes  INT           NOT NULL,
    CreatedAt       DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    PeriodType      NVARCHAR(20)  NOT NULL,  -- Daily, Weekly, Monthly
    INDEX IX_SLATracking_Date NONCLUSTERED (PeriodStart),
    INDEX IX_SLATracking_Type NONCLUSTERED (PeriodType, PeriodStart)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.SLATracking', 'PeriodStart') IS NULL
    ALTER TABLE [monitor].[SLATracking] ADD PeriodStart DATETIME2 NULL;
GO

IF COL_LENGTH('monitor.SLATracking', 'PeriodEnd') IS NULL
    ALTER TABLE [monitor].[SLATracking] ADD PeriodEnd DATETIME2 NULL;
GO

IF COL_LENGTH('monitor.SLATracking', 'TargetUptime') IS NULL
    ALTER TABLE [monitor].[SLATracking] ADD TargetUptime DECIMAL(5,2) NULL;
GO

IF COL_LENGTH('monitor.SLATracking', 'SLAMet') IS NULL
    ALTER TABLE [monitor].[SLATracking] ADD SLAMet BIT NULL;
GO

IF COL_LENGTH('monitor.SLATracking', 'ViolationCount') IS NULL
    ALTER TABLE [monitor].[SLATracking] ADD ViolationCount INT NULL;
GO

IF COL_LENGTH('monitor.SLATracking', 'CriticalViolations') IS NULL
    ALTER TABLE [monitor].[SLATracking] ADD CriticalViolations INT NULL;
GO

IF COL_LENGTH('monitor.SLATracking', 'PenaltyMinutes') IS NULL
    ALTER TABLE [monitor].[SLATracking] ADD PenaltyMinutes INT NULL;
GO

IF COL_LENGTH('monitor.SLATracking', 'CreatedAt') IS NULL
    ALTER TABLE [monitor].[SLATracking] ADD CreatedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.SLATracking', 'PeriodType') IS NULL
    ALTER TABLE [monitor].[SLATracking] ADD PeriodType NVARCHAR(20) NULL;
GO

IF OBJECT_ID('monitor.IncidentSources', 'U') IS NULL
CREATE TABLE [monitor].[IncidentSources] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    IncidentId      UNIQUEIDENTIFIER NOT NULL,
    SourceType      NVARCHAR(50)  NOT NULL,  -- Alert, ErrorLog, Manual, Auto-detected
    SourceDetail    NVARCHAR(500) NULL,
    DetectionMethod NVARCHAR(100) NOT NULL,  -- Threshold, Pattern, Manual
    ConfidenceScore DECIMAL(5,2)  NULL,      -- 0.00 to 1.00
    CreatedAt       DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    FOREIGN KEY (IncidentId) REFERENCES [monitor].[Incidents](IncidentId)
);
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.IncidentSources', 'IncidentId') IS NULL
    ALTER TABLE [monitor].[IncidentSources] ADD IncidentId UNIQUEIDENTIFIER NULL;
GO

IF COL_LENGTH('monitor.IncidentSources', 'SourceType') IS NULL
    ALTER TABLE [monitor].[IncidentSources] ADD SourceType NVARCHAR(50) NULL;
GO

IF COL_LENGTH('monitor.IncidentSources', 'DetectionMethod') IS NULL
    ALTER TABLE [monitor].[IncidentSources] ADD DetectionMethod NVARCHAR(100) NULL;
GO

