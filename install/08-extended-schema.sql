/*
    SQL Health Monitor - Extended Schema for Enhanced Collectors
    Creates additional tables for advanced disk, log growth, tempdb, and deadlock monitoring.
    
    Run after: 00-create-schema.sql
    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

----------------------------------------------------------------------
-- ENHANCED DISK MONITORING TABLES
----------------------------------------------------------------------

-- Detailed disk I/O statistics with extended events support
IF OBJECT_ID('monitor.DiskHistoryDetailed', 'U') IS NULL
CREATE TABLE [monitor].[DiskHistoryDetailed] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    DriveLetter     CHAR(3)       NOT NULL,
    TotalSpaceMB    BIGINT        NOT NULL,
    FreeSpaceMB     BIGINT        NOT NULL,
    UsedPct         DECIMAL(5,2)  NOT NULL,
    Filesystem      NVARCHAR(50)  NULL,
    MountPoint      NVARCHAR(255) NULL,
    
    -- Extended I/O Statistics
    AvgReadLatencyMs    DECIMAL(10,2) NULL,
    AvgWriteLatencyMs   DECIMAL(10,2) NULL,
    MaxReadLatencyMs   DECIMAL(10,2) NULL,
    MaxWriteLatencyMs  DECIMAL(10,2) NULL,
    DiskReadsPerSec    INT           NULL,
    DiskWritesPerSec   INT           NULL,
    DiskReadMBPerSec   DECIMAL(10,2) NULL,
    DiskWriteMBPerSec  DECIMAL(10,2) NULL,
    
    -- File-level statistics
    DataFileCount      INT           NULL,
    LogFileCount       INT           NULL,
    MaxDataFileSizeMB  BIGINT        NULL,
    MaxLogFileSizeMB   BIGINT        NULL,
    
    -- Health indicators
    IsCritical         BIT           NOT NULL DEFAULT 0,
    IsWarning          BIT           NOT NULL DEFAULT 0,
    INDEX IX_DiskHistoryDetailed_Date NONCLUSTERED (CollectedAt),
    INDEX IX_DiskHistoryDetailed_Drive NONCLUSTERED (DriveLetter, CollectedAt)
);
GO

-- Disk I/O wait statistics
IF OBJECT_ID('monitor.DiskIoWaits', 'U') IS NULL
CREATE TABLE [monitor].[DiskIoWaits] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    DatabaseName    NVARCHAR(128) NULL,
    FileId          INT           NOT NULL,
    FileGroup       NVARCHAR(128) NULL,
    FileSizeMB      BIGINT        NOT NULL,
    WaitType        NVARCHAR(120) NOT NULL,
    WaitTimeMs      BIGINT        NOT NULL,
    WaitingTasksCount BIGINT      NOT NULL,
    AvgWaitMs       DECIMAL(10,2) NULL,
    LastWaitAt      DATETIME2     NULL,
    INDEX IX_DiskIoWaits_Date NONCLUSTERED (CollectedAt),
    INDEX IX_DiskIoWaits_File NONCLUSTERED (DatabaseName, FileId, CollectedAt)
);
GO

----------------------------------------------------------------------
-- ENHANCED TRANSACTION LOG MONITORING TABLES
----------------------------------------------------------------------

-- Detailed log growth monitoring
IF OBJECT_ID('monitor.LogGrowthHistory', 'U') IS NULL
CREATE TABLE [monitor].[LogGrowthHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    DatabaseName    NVARCHAR(128) NOT NULL,
    LogSizeMB       BIGINT        NOT NULL,
    LogUsedPct      DECIMAL(5,2)  NOT NULL,
    LogFreePct      DECIMAL(5,2)  NOT NULL,
    
    -- Growth tracking
    LastBackupSizeMB BIGINT        NULL,
    LastBackupDate  DATETIME2     NULL,
    GrowthRateMBPerHour DECIMAL(10,2) NULL,
    AutoGrowthCount INT           NULL,
    LastAutoGrowthAt DATETIME2     NULL,
    LastAutoGrowthSizeMB BIGINT   NULL,
    
    -- Virtual log file info
    VLFCount        INT           NULL,
    MinVLFSizeMB    DECIMAL(10,2) NULL,
    MaxVLFSizeMB    DECIMAL(10,2) NULL,
    AvgVLFSizeMB    DECIMAL(10,2) NULL,
    
    -- Log truncation info
    LastTruncationDate DATETIME2  NULL,
    LogTruncationLagMinutes INT    NULL,
    IsLogShipping   BIT           NOT NULL DEFAULT 0,
    IsInStandby     BIT           NOT NULL DEFAULT 0,
    
    -- Health indicators
    IsCritical      BIT           NOT NULL DEFAULT 0,
    IsWarning       BIT           NOT NULL DEFAULT 0,
    INDEX IX_LogGrowthHistory_Date NONCLUSTERED (CollectedAt),
    INDEX IX_LogGrowthHistory_DB NONCLUSTERED (DatabaseName, CollectedAt)
);
GO

-- Log backup history
IF OBJECT_ID('monitor.LogBackupHistory', 'U') IS NULL
CREATE TABLE [monitor].[LogBackupHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    DatabaseName    NVARCHAR(128) NOT NULL,
    BackupStartDate DATETIME2     NOT NULL,
    BackupEndDate   DATETIME2     NULL,
    BackupDurationSec INT         NULL,
    BackupSizeMB    BIGINT        NULL,
    CompressedSizeMB BIGINT       NULL,
    CompressionRatio DECIMAL(5,2) NULL,
    BackupDevice    NVARCHAR(255) NULL,
    BackupSetId     INT           NULL,
    IsSuccessful    BIT           NOT NULL DEFAULT 1,
    ErrorMessage    NVARCHAR(500) NULL,
    INDEX IX_LogBackupHistory_Date NONCLUSTERED (CollectedAt),
    INDEX IX_LogBackupHistory_DB NONCLUSTERED (DatabaseName, BackupStartDate)
);
GO

----------------------------------------------------------------------
-- ENHANCED TEMPDB MONITORING TABLES
----------------------------------------------------------------------

-- Detailed TempDB usage with multiple filegroups
IF OBJECT_ID('monitor.TempDbHistoryDetailed', 'U') IS NULL
CREATE TABLE [monitor].[TempDbHistoryDetailed] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    FileId          INT           NOT NULL,
    FileGroup       NVARCHAR(128) NOT NULL,
    FileName        NVARCHAR(255) NOT NULL,
    FileType        NVARCHAR(10)  NOT NULL,  -- ROWS, LOG
    SizeMB          BIGINT        NOT NULL,
    UsedSpaceMB     BIGINT        NOT NULL,
    FreeSpaceMB     BIGINT        NOT NULL,
    UsedPct         DECIMAL(5,2)  NOT NULL,
    
    -- Object-level usage
    UserObjectsMB   BIGINT        NULL,
    InternalObjectsMB BIGINT      NULL,
    VersionStoreMB  BIGINT        NULL,
    IndexStoreMB    BIGINT        NULL,
    
    -- Auto-growth tracking
    AutoGrowthCount INT           NULL,
    LastAutoGrowthAt DATETIME2     NULL,
    LastAutoGrowthSizeMB BIGINT   NULL,
    MaxAutoGrowthSizeMB BIGINT   NULL,
    
    -- Performance metrics
    AvgReadLatencyMs DECIMAL(10,2) NULL,
    AvgWriteLatencyMs DECIMAL(10,2) NULL,
    FileIOPS        INT           NULL,
    
    -- Health indicators
    IsCritical      BIT           NOT NULL DEFAULT 0,
    IsWarning       BIT           NOT NULL DEFAULT 0,
    INDEX IX_TempDbDetailed_Date NONCLUSTERED (CollectedAt),
    INDEX IX_TempDbDetailed_File NONCLUSTERED (FileId, CollectedAt)
);
GO

-- TempDB object allocation tracking
IF OBJECT_ID('monitor.TempDbObjectUsage', 'U') IS NULL
CREATE TABLE [monitor].[TempDbObjectUsage] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    SessionId       INT           NOT NULL,
    DatabaseId      INT           NOT NULL,
    ObjectId        BIGINT        NOT NULL,
    ObjectName      NVARCHAR(255) NULL,
    ObjectType      NVARCHAR(60)  NOT NULL,  -- USER_TABLE, INDEX, etc.
    FileGroup       NVARCHAR(128) NULL,
    AllocatedPages  BIGINT        NOT NULL,
    UsedPages       BIGINT        NOT NULL,
    SizeKB          BIGINT        NOT NULL,
    IndexId         INT           NULL,
    PartitionId     BIGINT        NULL,
    IndexType       NVARCHAR(60)  NULL,  -- HEAP, CLUSTERED, NONCLUSTERED
    IsTempTable     BIT           NOT NULL DEFAULT 0,
    INDEX IX_TempDbObjectUsage_Date NONCLUSTERED (CollectedAt),
    INDEX IX_TempDbObjectUsage_Session NONCLUSTERED (SessionId, CollectedAt)
);
GO

----------------------------------------------------------------------
-- ENHANCED DEADLOCK MONITORING TABLES
----------------------------------------------------------------------

-- Deadlock events with extended information
IF OBJECT_ID('monitor.DeadlockHistory', 'U') IS NULL
CREATE TABLE [monitor].[DeadlockHistory] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    DeadlockDate    DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    DeadlockGraph   XML           NULL,  -- Full deadlock graph XML
    DeadlockId      UNIQUEIDENTIFIER NULL,  -- Deadlock identifier
    DeadlockCount   INT           NOT NULL DEFAULT 1,
    
    -- Victim information
    VictimSPID      INT           NULL,
    VictimSession   NVARCHAR(128) NULL,
    VictimDatabase  NVARCHAR(128) NULL,
    VictimObject    NVARCHAR(255) NULL,
    VictimWaitType  NVARCHAR(120) NULL,
    VictimWaitDurationMs INT       NULL,
    
    -- Blocking information
    BlockingSPID    INT           NULL,
    BlockingSession NVARCHAR(128) NULL,
    BlockingDatabase NVARCHAR(128) NULL,
    BlockingObject  NVARCHAR(255) NULL,
    BlockingWaitType NVARCHAR(120) NULL,
    BlockingDurationMs INT         NULL,
    
    -- Deadlock summary
    TotalWaitTimeMs INT           NULL,
    DeadlockCycleCount INT         NULL,
    DeadlockResourceType NVARCHAR(60) NULL,  -- KEY, PAGE, OBJECT, etc.
    DeadlockLockMode NVARCHAR(20)  NULL,  -- Shared, Exclusive, Update, etc.
    
    -- Query information
    VictimQueryHash BINARY(8)     NULL,
    VictimQueryText NVARCHAR(MAX) NULL,
    BlockingQueryHash BINARY(8)   NULL,
    BlockingQueryText NVARCHAR(MAX) NULL,
    
    -- Resolution
    ResolutionTime  DATETIME2     NULL,
    ResolutionMethod NVARCHAR(60) NULL,  -- Timeout, Kill, etc.
    
    -- Health indicators
    IsCritical      BIT           NOT NULL DEFAULT 1,
    IsWarning       BIT           NOT NULL DEFAULT 0,
    INDEX IX_DeadlockHistory_Date NONCLUSTERED (DeadlockDate),
    INDEX IX_DeadlockHistory_Victim NONCLUSTERED (VictimSPID, DeadlockDate)
);
GO

-- Deadlock wait statistics
IF OBJECT_ID('monitor.DeadlockWaitStats', 'U') IS NULL
CREATE TABLE [monitor].[DeadlockWaitStats] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    DeadlockId      UNIQUEIDENTIFIER NOT NULL,
    CollectedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    WaitType        NVARCHAR(120) NOT NULL,
    WaitingTasksCount BIGINT      NOT NULL,
    WaitTimeMs      BIGINT        NOT NULL,
    SignalWaitTimeMs BIGINT        NOT NULL,
    ResourceType    NVARCHAR(60)  NULL,
    ResourceName    NVARCHAR(255) NULL,
    DatabaseName    NVARCHAR(128) NULL,
    ObjectName      NVARCHAR(255) NULL,
    IndexName       NVARCHAR(128) NULL,
    INDEX IX_DeadlockWaitStats_DeadlockId NONCLUSTERED (DeadlockId),
    INDEX IX_DeadlockWaitStats_Type NONCLUSTERED (WaitType, CollectedAt)
);
GO

-- Deadlock pattern analysis
IF OBJECT_ID('monitor.DeadlockPatterns', 'U') IS NULL
CREATE TABLE [monitor].[DeadlockPatterns] (
    Id              BIGINT IDENTITY(1,1) PRIMARY KEY,
    PatternHash     BINARY(8)     NOT NULL,
    FirstOccurrence DATETIME2     NOT NULL,
    LastOccurrence  DATETIME2     NOT NULL,
    OccurrenceCount INT           NOT NULL,
    AvgFrequencyHours DECIMAL(10,2) NULL,
    CommonWaitTypes NVARCHAR(500) NULL,
    CommonObjects   NVARCHAR(500) NULL,
    CommonDatabases NVARCHAR(500) NULL,
    Recommendation  NVARCHAR(1000) NULL,
    INDEX IX_DeadlockPatterns_Hash NONCLUSTERED (PatternHash)
);
GO

----------------------------------------------------------------------
-- EXTENDED EVENTS SESSION TRACKING
----------------------------------------------------------------------

-- Extended events session status
IF OBJECT_ID('monitor.XESessionStatus', 'U') IS NULL
CREATE TABLE [monitor].[XESessionStatus] (
    Id              INT IDENTITY(1,1) PRIMARY KEY,
    SessionName     NVARCHAR(128) NOT NULL,
    SessionGuid     UNIQUEIDENTIFIER NOT NULL,
    IsRunning       BIT           NOT NULL DEFAULT 0,
    TargetFile      NVARCHAR(255) NULL,
    TargetFileSizeMB BIGINT        NULL,
    EventCount      BIGINT        NULL,
    MemoryUsedKB    BIGINT        NULL,
    MaxMemoryKB     BIGINT        NULL,
    StartTime       DATETIME2     NULL,
    LastEventTime   DATETIME2     NULL,
    LastChecked     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    INDEX IX_XESessionStatus_Name NONCLUSTERED (SessionName)
);
GO

-- Extended events configuration
IF OBJECT_ID('monitor.XEEventConfig', 'U') IS NULL
CREATE TABLE [monitor].[XEEventConfig] (
    Id              INT IDENTITY(1,1) PRIMARY KEY,
    SessionName     NVARCHAR(128) NOT NULL,
    EventName       NVARCHAR(128) NOT NULL,
    Predicate       NVARCHAR(1000) NULL,
    Actions         NVARCHAR(1000) NULL,
    MapValues      NVARCHAR(1000) NULL,
    IsEnabled       BIT           NOT NULL DEFAULT 1,
    Description     NVARCHAR(500) NULL,
    INDEX IX_XEEventConfig_Session NONCLUSTERED (SessionName, EventName)
);
GO

PRINT '✓ Extended schema for enhanced collectors created.';
PRINT '  → [monitor].[DiskHistoryDetailed] - Enhanced disk I/O monitoring';
PRINT '  → [monitor].[DiskIoWaits] - Disk I/O wait statistics';
PRINT '  → [monitor].[LogGrowthHistory] - Detailed transaction log monitoring';
PRINT '  → [monitor].[LogBackupHistory] - Log backup tracking';
PRINT '  → [monitor].[TempDbHistoryDetailed] - Multi-filegroup TempDB monitoring';
PRINT '  → [monitor].[TempDbObjectUsage] - TempDB object allocation tracking';
PRINT '  → [monitor].[DeadlockHistory] - Comprehensive deadlock monitoring';
PRINT '  → [monitor].[DeadlockWaitStats] - Deadlock wait analysis';
PRINT '  → [monitor].[DeadlockPatterns] - Deadlock pattern detection';
PRINT '  → [monitor].[XESessionStatus] - Extended events session tracking';
PRINT '  → [monitor].[XEEventConfig] - Extended events configuration';
GO