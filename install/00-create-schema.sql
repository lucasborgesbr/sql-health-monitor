/*
    SQL Health Monitor - Schema Creation
    Creates the monitoring schema, configuration, and data collection tables.
    
    Target: DBA_Monitor database
    Compatibility: SQL Server 2016+
    Author: Lucas Borges
*/

USE [DBA_Monitor];
GO

-- Create schema
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'monitor')
    EXEC('CREATE SCHEMA [monitor]');
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
GO

-- Language strings for multi-language reports
IF OBJECT_ID('monitor.Languages', 'U') IS NULL
CREATE TABLE [monitor].[Languages] (
    LanguageId      INT IDENTITY(1,1) PRIMARY KEY,
    LanguageCode    CHAR(5)       NOT NULL,  -- 'en', 'ptbr'
    StringKey       NVARCHAR(100) NOT NULL,
    StringValue     NVARCHAR(MAX) NOT NULL,
    CONSTRAINT UQ_Languages_Key UNIQUE (LanguageCode, StringKey)
);
GO

-- Alert thresholds
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
GO

----------------------------------------------------------------------
-- DATA COLLECTION TABLES
----------------------------------------------------------------------

-- CPU utilization history
IF OBJECT_ID('monitor.CpuHistory', 'U') IS NULL
CREATE TABLE [monitor].[CpuHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    SqlCpuPct       TINYINT       NOT NULL,
    SystemCpuPct    TINYINT       NOT NULL,
    IdleCpuPct      TINYINT       NOT NULL,
    INDEX IX_CpuHistory_Date NONCLUSTERED (CollectedAt)
);
GO

-- Memory metrics
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
GO

-- Disk space and IO
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
GO

-- Wait stats (delta snapshots)
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
GO

-- Blocking events
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
GO

-- AG health
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
GO

-- CDC health
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
GO

-- Top queries
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
GO

-- Index health
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
GO

-- Backup status
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
GO

-- SQL Agent job history
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
GO

-- TempDB usage
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
GO

-- Database file growth
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
GO

-- Error log entries
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
GO

-- Alert history (fired alerts)
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
GO

-- Report history (sent reports)
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
GO

PRINT '✓ Schema [monitor] created successfully.';
PRINT '✓ All monitoring tables created.';
GO
