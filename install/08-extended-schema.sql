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
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.DiskHistoryDetailed', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[DiskHistoryDetailed] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.DiskHistoryDetailed', 'DriveLetter') IS NULL
    ALTER TABLE [monitor].[DiskHistoryDetailed] ADD DriveLetter CHAR(3) NULL;
GO

IF COL_LENGTH('monitor.DiskHistoryDetailed', 'TotalSpaceMB') IS NULL
    ALTER TABLE [monitor].[DiskHistoryDetailed] ADD TotalSpaceMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.DiskHistoryDetailed', 'FreeSpaceMB') IS NULL
    ALTER TABLE [monitor].[DiskHistoryDetailed] ADD FreeSpaceMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.DiskHistoryDetailed', 'UsedPct') IS NULL
    ALTER TABLE [monitor].[DiskHistoryDetailed] ADD UsedPct DECIMAL(5,2) NULL;
GO

IF COL_LENGTH('monitor.DiskHistoryDetailed', 'Filesystem') IS NULL
    ALTER TABLE [monitor].[DiskHistoryDetailed] ADD Filesystem NVARCHAR(50) NULL;
GO

IF COL_LENGTH('monitor.DiskHistoryDetailed', 'MountPoint') IS NULL
    ALTER TABLE [monitor].[DiskHistoryDetailed] ADD MountPoint NVARCHAR(255) NULL;
GO

IF COL_LENGTH('monitor.DiskHistoryDetailed', 'AvgWriteLatencyMs') IS NULL
    ALTER TABLE [monitor].[DiskHistoryDetailed] ADD AvgWriteLatencyMs DECIMAL(10,2) NULL;
GO

IF COL_LENGTH('monitor.DiskHistoryDetailed', 'MaxReadLatencyMs') IS NULL
    ALTER TABLE [monitor].[DiskHistoryDetailed] ADD MaxReadLatencyMs DECIMAL(10,2) NULL;
GO

IF COL_LENGTH('monitor.DiskHistoryDetailed', 'MaxWriteLatencyMs') IS NULL
    ALTER TABLE [monitor].[DiskHistoryDetailed] ADD MaxWriteLatencyMs DECIMAL(10,2) NULL;
GO

IF COL_LENGTH('monitor.DiskHistoryDetailed', 'DiskReadsPerSec') IS NULL
    ALTER TABLE [monitor].[DiskHistoryDetailed] ADD DiskReadsPerSec INT NULL;
GO

IF COL_LENGTH('monitor.DiskHistoryDetailed', 'DiskWritesPerSec') IS NULL
    ALTER TABLE [monitor].[DiskHistoryDetailed] ADD DiskWritesPerSec INT NULL;
GO

IF COL_LENGTH('monitor.DiskHistoryDetailed', 'DiskReadMBPerSec') IS NULL
    ALTER TABLE [monitor].[DiskHistoryDetailed] ADD DiskReadMBPerSec DECIMAL(10,2) NULL;
GO

IF COL_LENGTH('monitor.DiskHistoryDetailed', 'DiskWriteMBPerSec') IS NULL
    ALTER TABLE [monitor].[DiskHistoryDetailed] ADD DiskWriteMBPerSec DECIMAL(10,2) NULL;
GO

IF COL_LENGTH('monitor.DiskHistoryDetailed', 'LogFileCount') IS NULL
    ALTER TABLE [monitor].[DiskHistoryDetailed] ADD LogFileCount INT NULL;
GO

IF COL_LENGTH('monitor.DiskHistoryDetailed', 'MaxDataFileSizeMB') IS NULL
    ALTER TABLE [monitor].[DiskHistoryDetailed] ADD MaxDataFileSizeMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.DiskHistoryDetailed', 'MaxLogFileSizeMB') IS NULL
    ALTER TABLE [monitor].[DiskHistoryDetailed] ADD MaxLogFileSizeMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.DiskHistoryDetailed', 'IsWarning') IS NULL
    ALTER TABLE [monitor].[DiskHistoryDetailed] ADD IsWarning BIT NULL DEFAULT 0;
GO

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
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.DiskIoWaits', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[DiskIoWaits] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.DiskIoWaits', 'DatabaseName') IS NULL
    ALTER TABLE [monitor].[DiskIoWaits] ADD DatabaseName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.DiskIoWaits', 'FileId') IS NULL
    ALTER TABLE [monitor].[DiskIoWaits] ADD FileId INT NULL;
GO

IF COL_LENGTH('monitor.DiskIoWaits', 'FileGroup') IS NULL
    ALTER TABLE [monitor].[DiskIoWaits] ADD FileGroup NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.DiskIoWaits', 'FileSizeMB') IS NULL
    ALTER TABLE [monitor].[DiskIoWaits] ADD FileSizeMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.DiskIoWaits', 'WaitType') IS NULL
    ALTER TABLE [monitor].[DiskIoWaits] ADD WaitType NVARCHAR(120) NULL;
GO

IF COL_LENGTH('monitor.DiskIoWaits', 'WaitTimeMs') IS NULL
    ALTER TABLE [monitor].[DiskIoWaits] ADD WaitTimeMs BIGINT NULL;
GO

IF COL_LENGTH('monitor.DiskIoWaits', 'WaitingTasksCount') IS NULL
    ALTER TABLE [monitor].[DiskIoWaits] ADD WaitingTasksCount BIGINT NULL;
GO

IF COL_LENGTH('monitor.DiskIoWaits', 'AvgWaitMs') IS NULL
    ALTER TABLE [monitor].[DiskIoWaits] ADD AvgWaitMs DECIMAL(10,2) NULL;
GO

IF COL_LENGTH('monitor.DiskIoWaits', 'LastWaitAt') IS NULL
    ALTER TABLE [monitor].[DiskIoWaits] ADD LastWaitAt DATETIME2 NULL;
GO

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
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.LogGrowthHistory', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[LogGrowthHistory] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.LogGrowthHistory', 'DatabaseName') IS NULL
    ALTER TABLE [monitor].[LogGrowthHistory] ADD DatabaseName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.LogGrowthHistory', 'LogSizeMB') IS NULL
    ALTER TABLE [monitor].[LogGrowthHistory] ADD LogSizeMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.LogGrowthHistory', 'LogUsedPct') IS NULL
    ALTER TABLE [monitor].[LogGrowthHistory] ADD LogUsedPct DECIMAL(5,2) NULL;
GO

IF COL_LENGTH('monitor.LogGrowthHistory', 'LogFreePct') IS NULL
    ALTER TABLE [monitor].[LogGrowthHistory] ADD LogFreePct DECIMAL(5,2) NULL;
GO

IF COL_LENGTH('monitor.LogGrowthHistory', 'LastBackupDate') IS NULL
    ALTER TABLE [monitor].[LogGrowthHistory] ADD LastBackupDate DATETIME2 NULL;
GO

IF COL_LENGTH('monitor.LogGrowthHistory', 'GrowthRateMBPerHour') IS NULL
    ALTER TABLE [monitor].[LogGrowthHistory] ADD GrowthRateMBPerHour DECIMAL(10,2) NULL;
GO

IF COL_LENGTH('monitor.LogGrowthHistory', 'AutoGrowthCount') IS NULL
    ALTER TABLE [monitor].[LogGrowthHistory] ADD AutoGrowthCount INT NULL;
GO

IF COL_LENGTH('monitor.LogGrowthHistory', 'LastAutoGrowthAt') IS NULL
    ALTER TABLE [monitor].[LogGrowthHistory] ADD LastAutoGrowthAt DATETIME2 NULL;
GO

IF COL_LENGTH('monitor.LogGrowthHistory', 'LastAutoGrowthSizeMB') IS NULL
    ALTER TABLE [monitor].[LogGrowthHistory] ADD LastAutoGrowthSizeMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.LogGrowthHistory', 'MinVLFSizeMB') IS NULL
    ALTER TABLE [monitor].[LogGrowthHistory] ADD MinVLFSizeMB DECIMAL(10,2) NULL;
GO

IF COL_LENGTH('monitor.LogGrowthHistory', 'MaxVLFSizeMB') IS NULL
    ALTER TABLE [monitor].[LogGrowthHistory] ADD MaxVLFSizeMB DECIMAL(10,2) NULL;
GO

IF COL_LENGTH('monitor.LogGrowthHistory', 'AvgVLFSizeMB') IS NULL
    ALTER TABLE [monitor].[LogGrowthHistory] ADD AvgVLFSizeMB DECIMAL(10,2) NULL;
GO

IF COL_LENGTH('monitor.LogGrowthHistory', 'LogTruncationLagMinutes') IS NULL
    ALTER TABLE [monitor].[LogGrowthHistory] ADD LogTruncationLagMinutes INT NULL;
GO

IF COL_LENGTH('monitor.LogGrowthHistory', 'IsLogShipping') IS NULL
    ALTER TABLE [monitor].[LogGrowthHistory] ADD IsLogShipping BIT NULL DEFAULT 0;
GO

IF COL_LENGTH('monitor.LogGrowthHistory', 'IsInStandby') IS NULL
    ALTER TABLE [monitor].[LogGrowthHistory] ADD IsInStandby BIT NULL DEFAULT 0;
GO

IF COL_LENGTH('monitor.LogGrowthHistory', 'IsWarning') IS NULL
    ALTER TABLE [monitor].[LogGrowthHistory] ADD IsWarning BIT NULL DEFAULT 0;
GO

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
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.LogBackupHistory', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[LogBackupHistory] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.LogBackupHistory', 'DatabaseName') IS NULL
    ALTER TABLE [monitor].[LogBackupHistory] ADD DatabaseName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.LogBackupHistory', 'BackupStartDate') IS NULL
    ALTER TABLE [monitor].[LogBackupHistory] ADD BackupStartDate DATETIME2 NULL;
GO

IF COL_LENGTH('monitor.LogBackupHistory', 'BackupEndDate') IS NULL
    ALTER TABLE [monitor].[LogBackupHistory] ADD BackupEndDate DATETIME2 NULL;
GO

IF COL_LENGTH('monitor.LogBackupHistory', 'BackupDurationSec') IS NULL
    ALTER TABLE [monitor].[LogBackupHistory] ADD BackupDurationSec INT NULL;
GO

IF COL_LENGTH('monitor.LogBackupHistory', 'BackupSizeMB') IS NULL
    ALTER TABLE [monitor].[LogBackupHistory] ADD BackupSizeMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.LogBackupHistory', 'CompressedSizeMB') IS NULL
    ALTER TABLE [monitor].[LogBackupHistory] ADD CompressedSizeMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.LogBackupHistory', 'CompressionRatio') IS NULL
    ALTER TABLE [monitor].[LogBackupHistory] ADD CompressionRatio DECIMAL(5,2) NULL;
GO

IF COL_LENGTH('monitor.LogBackupHistory', 'BackupDevice') IS NULL
    ALTER TABLE [monitor].[LogBackupHistory] ADD BackupDevice NVARCHAR(255) NULL;
GO

IF COL_LENGTH('monitor.LogBackupHistory', 'BackupSetId') IS NULL
    ALTER TABLE [monitor].[LogBackupHistory] ADD BackupSetId INT NULL;
GO

IF COL_LENGTH('monitor.LogBackupHistory', 'IsSuccessful') IS NULL
    ALTER TABLE [monitor].[LogBackupHistory] ADD IsSuccessful BIT NULL DEFAULT 1;
GO

IF COL_LENGTH('monitor.LogBackupHistory', 'ErrorMessage') IS NULL
    ALTER TABLE [monitor].[LogBackupHistory] ADD ErrorMessage NVARCHAR(500) NULL;
GO

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
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.TempDbHistoryDetailed', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[TempDbHistoryDetailed] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.TempDbHistoryDetailed', 'FileId') IS NULL
    ALTER TABLE [monitor].[TempDbHistoryDetailed] ADD FileId INT NULL;
GO

IF COL_LENGTH('monitor.TempDbHistoryDetailed', 'FileGroup') IS NULL
    ALTER TABLE [monitor].[TempDbHistoryDetailed] ADD FileGroup NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.TempDbHistoryDetailed', 'FileName') IS NULL
    ALTER TABLE [monitor].[TempDbHistoryDetailed] ADD FileName NVARCHAR(255) NULL;
GO

IF COL_LENGTH('monitor.TempDbHistoryDetailed', 'FileType') IS NULL
    ALTER TABLE [monitor].[TempDbHistoryDetailed] ADD FileType NVARCHAR(10) NULL;
GO

IF COL_LENGTH('monitor.TempDbHistoryDetailed', 'UsedSpaceMB') IS NULL
    ALTER TABLE [monitor].[TempDbHistoryDetailed] ADD UsedSpaceMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.TempDbHistoryDetailed', 'FreeSpaceMB') IS NULL
    ALTER TABLE [monitor].[TempDbHistoryDetailed] ADD FreeSpaceMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.TempDbHistoryDetailed', 'UsedPct') IS NULL
    ALTER TABLE [monitor].[TempDbHistoryDetailed] ADD UsedPct DECIMAL(5,2) NULL;
GO

IF COL_LENGTH('monitor.TempDbHistoryDetailed', 'InternalObjectsMB') IS NULL
    ALTER TABLE [monitor].[TempDbHistoryDetailed] ADD InternalObjectsMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.TempDbHistoryDetailed', 'VersionStoreMB') IS NULL
    ALTER TABLE [monitor].[TempDbHistoryDetailed] ADD VersionStoreMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.TempDbHistoryDetailed', 'IndexStoreMB') IS NULL
    ALTER TABLE [monitor].[TempDbHistoryDetailed] ADD IndexStoreMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.TempDbHistoryDetailed', 'LastAutoGrowthAt') IS NULL
    ALTER TABLE [monitor].[TempDbHistoryDetailed] ADD LastAutoGrowthAt DATETIME2 NULL;
GO

IF COL_LENGTH('monitor.TempDbHistoryDetailed', 'LastAutoGrowthSizeMB') IS NULL
    ALTER TABLE [monitor].[TempDbHistoryDetailed] ADD LastAutoGrowthSizeMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.TempDbHistoryDetailed', 'MaxAutoGrowthSizeMB') IS NULL
    ALTER TABLE [monitor].[TempDbHistoryDetailed] ADD MaxAutoGrowthSizeMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.TempDbHistoryDetailed', 'AvgWriteLatencyMs') IS NULL
    ALTER TABLE [monitor].[TempDbHistoryDetailed] ADD AvgWriteLatencyMs DECIMAL(10,2) NULL;
GO

IF COL_LENGTH('monitor.TempDbHistoryDetailed', 'FileIOPS') IS NULL
    ALTER TABLE [monitor].[TempDbHistoryDetailed] ADD FileIOPS INT NULL;
GO

IF COL_LENGTH('monitor.TempDbHistoryDetailed', 'IsWarning') IS NULL
    ALTER TABLE [monitor].[TempDbHistoryDetailed] ADD IsWarning BIT NULL DEFAULT 0;
GO

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
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.TempDbObjectUsage', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[TempDbObjectUsage] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.TempDbObjectUsage', 'SessionId') IS NULL
    ALTER TABLE [monitor].[TempDbObjectUsage] ADD SessionId INT NULL;
GO

IF COL_LENGTH('monitor.TempDbObjectUsage', 'DatabaseId') IS NULL
    ALTER TABLE [monitor].[TempDbObjectUsage] ADD DatabaseId INT NULL;
GO

IF COL_LENGTH('monitor.TempDbObjectUsage', 'ObjectId') IS NULL
    ALTER TABLE [monitor].[TempDbObjectUsage] ADD ObjectId BIGINT NULL;
GO

IF COL_LENGTH('monitor.TempDbObjectUsage', 'ObjectName') IS NULL
    ALTER TABLE [monitor].[TempDbObjectUsage] ADD ObjectName NVARCHAR(255) NULL;
GO

IF COL_LENGTH('monitor.TempDbObjectUsage', 'ObjectType') IS NULL
    ALTER TABLE [monitor].[TempDbObjectUsage] ADD ObjectType NVARCHAR(60) NULL;
GO

IF COL_LENGTH('monitor.TempDbObjectUsage', 'AllocatedPages') IS NULL
    ALTER TABLE [monitor].[TempDbObjectUsage] ADD AllocatedPages BIGINT NULL;
GO

IF COL_LENGTH('monitor.TempDbObjectUsage', 'UsedPages') IS NULL
    ALTER TABLE [monitor].[TempDbObjectUsage] ADD UsedPages BIGINT NULL;
GO

IF COL_LENGTH('monitor.TempDbObjectUsage', 'SizeKB') IS NULL
    ALTER TABLE [monitor].[TempDbObjectUsage] ADD SizeKB BIGINT NULL;
GO

IF COL_LENGTH('monitor.TempDbObjectUsage', 'IndexId') IS NULL
    ALTER TABLE [monitor].[TempDbObjectUsage] ADD IndexId INT NULL;
GO

IF COL_LENGTH('monitor.TempDbObjectUsage', 'PartitionId') IS NULL
    ALTER TABLE [monitor].[TempDbObjectUsage] ADD PartitionId BIGINT NULL;
GO

IF COL_LENGTH('monitor.TempDbObjectUsage', 'IndexType') IS NULL
    ALTER TABLE [monitor].[TempDbObjectUsage] ADD IndexType NVARCHAR(60) NULL;
GO

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
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.DeadlockHistory', 'DeadlockDate') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD DeadlockDate DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.DeadlockHistory', 'DeadlockGraph') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD DeadlockGraph XML NULL;
GO

IF COL_LENGTH('monitor.DeadlockHistory', 'VictimSession') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD VictimSession NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.DeadlockHistory', 'VictimDatabase') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD VictimDatabase NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.DeadlockHistory', 'VictimObject') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD VictimObject NVARCHAR(255) NULL;
GO

IF COL_LENGTH('monitor.DeadlockHistory', 'VictimWaitType') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD VictimWaitType NVARCHAR(120) NULL;
GO

IF COL_LENGTH('monitor.DeadlockHistory', 'VictimWaitDurationMs') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD VictimWaitDurationMs INT NULL;
GO

IF COL_LENGTH('monitor.DeadlockHistory', 'BlockingSession') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD BlockingSession NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.DeadlockHistory', 'BlockingDatabase') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD BlockingDatabase NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.DeadlockHistory', 'BlockingObject') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD BlockingObject NVARCHAR(255) NULL;
GO

IF COL_LENGTH('monitor.DeadlockHistory', 'BlockingWaitType') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD BlockingWaitType NVARCHAR(120) NULL;
GO

IF COL_LENGTH('monitor.DeadlockHistory', 'BlockingDurationMs') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD BlockingDurationMs INT NULL;
GO

IF COL_LENGTH('monitor.DeadlockHistory', 'DeadlockCycleCount') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD DeadlockCycleCount INT NULL;
GO

IF COL_LENGTH('monitor.DeadlockHistory', 'DeadlockResourceType') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD DeadlockResourceType NVARCHAR(60) NULL;
GO

IF COL_LENGTH('monitor.DeadlockHistory', 'VictimQueryText') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD VictimQueryText NVARCHAR(MAX) NULL;
GO

IF COL_LENGTH('monitor.DeadlockHistory', 'BlockingQueryHash') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD BlockingQueryHash BINARY(8) NULL;
GO

IF COL_LENGTH('monitor.DeadlockHistory', 'BlockingQueryText') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD BlockingQueryText NVARCHAR(MAX) NULL;
GO

IF COL_LENGTH('monitor.DeadlockHistory', 'ResolutionMethod') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD ResolutionMethod NVARCHAR(60) NULL;
GO

IF COL_LENGTH('monitor.DeadlockHistory', 'IsWarning') IS NULL
    ALTER TABLE [monitor].[DeadlockHistory] ADD IsWarning BIT NULL DEFAULT 0;
GO

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
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.DeadlockWaitStats', 'DeadlockId') IS NULL
    ALTER TABLE [monitor].[DeadlockWaitStats] ADD DeadlockId UNIQUEIDENTIFIER NULL;
GO

IF COL_LENGTH('monitor.DeadlockWaitStats', 'CollectedAt') IS NULL
    ALTER TABLE [monitor].[DeadlockWaitStats] ADD CollectedAt DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

IF COL_LENGTH('monitor.DeadlockWaitStats', 'WaitType') IS NULL
    ALTER TABLE [monitor].[DeadlockWaitStats] ADD WaitType NVARCHAR(120) NULL;
GO

IF COL_LENGTH('monitor.DeadlockWaitStats', 'WaitingTasksCount') IS NULL
    ALTER TABLE [monitor].[DeadlockWaitStats] ADD WaitingTasksCount BIGINT NULL;
GO

IF COL_LENGTH('monitor.DeadlockWaitStats', 'WaitTimeMs') IS NULL
    ALTER TABLE [monitor].[DeadlockWaitStats] ADD WaitTimeMs BIGINT NULL;
GO

IF COL_LENGTH('monitor.DeadlockWaitStats', 'SignalWaitTimeMs') IS NULL
    ALTER TABLE [monitor].[DeadlockWaitStats] ADD SignalWaitTimeMs BIGINT NULL;
GO

IF COL_LENGTH('monitor.DeadlockWaitStats', 'ResourceType') IS NULL
    ALTER TABLE [monitor].[DeadlockWaitStats] ADD ResourceType NVARCHAR(60) NULL;
GO

IF COL_LENGTH('monitor.DeadlockWaitStats', 'ResourceName') IS NULL
    ALTER TABLE [monitor].[DeadlockWaitStats] ADD ResourceName NVARCHAR(255) NULL;
GO

IF COL_LENGTH('monitor.DeadlockWaitStats', 'DatabaseName') IS NULL
    ALTER TABLE [monitor].[DeadlockWaitStats] ADD DatabaseName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.DeadlockWaitStats', 'ObjectName') IS NULL
    ALTER TABLE [monitor].[DeadlockWaitStats] ADD ObjectName NVARCHAR(255) NULL;
GO

IF COL_LENGTH('monitor.DeadlockWaitStats', 'IndexName') IS NULL
    ALTER TABLE [monitor].[DeadlockWaitStats] ADD IndexName NVARCHAR(128) NULL;
GO

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
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.DeadlockPatterns', 'PatternHash') IS NULL
    ALTER TABLE [monitor].[DeadlockPatterns] ADD PatternHash BINARY(8) NULL;
GO

IF COL_LENGTH('monitor.DeadlockPatterns', 'FirstOccurrence') IS NULL
    ALTER TABLE [monitor].[DeadlockPatterns] ADD FirstOccurrence DATETIME2 NULL;
GO

IF COL_LENGTH('monitor.DeadlockPatterns', 'LastOccurrence') IS NULL
    ALTER TABLE [monitor].[DeadlockPatterns] ADD LastOccurrence DATETIME2 NULL;
GO

IF COL_LENGTH('monitor.DeadlockPatterns', 'OccurrenceCount') IS NULL
    ALTER TABLE [monitor].[DeadlockPatterns] ADD OccurrenceCount INT NULL;
GO

IF COL_LENGTH('monitor.DeadlockPatterns', 'AvgFrequencyHours') IS NULL
    ALTER TABLE [monitor].[DeadlockPatterns] ADD AvgFrequencyHours DECIMAL(10,2) NULL;
GO

IF COL_LENGTH('monitor.DeadlockPatterns', 'CommonWaitTypes') IS NULL
    ALTER TABLE [monitor].[DeadlockPatterns] ADD CommonWaitTypes NVARCHAR(500) NULL;
GO

IF COL_LENGTH('monitor.DeadlockPatterns', 'CommonObjects') IS NULL
    ALTER TABLE [monitor].[DeadlockPatterns] ADD CommonObjects NVARCHAR(500) NULL;
GO

IF COL_LENGTH('monitor.DeadlockPatterns', 'CommonDatabases') IS NULL
    ALTER TABLE [monitor].[DeadlockPatterns] ADD CommonDatabases NVARCHAR(500) NULL;
GO

IF COL_LENGTH('monitor.DeadlockPatterns', 'Recommendation') IS NULL
    ALTER TABLE [monitor].[DeadlockPatterns] ADD Recommendation NVARCHAR(1000) NULL;
GO

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
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.XESessionStatus', 'SessionName') IS NULL
    ALTER TABLE [monitor].[XESessionStatus] ADD SessionName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.XESessionStatus', 'SessionGuid') IS NULL
    ALTER TABLE [monitor].[XESessionStatus] ADD SessionGuid UNIQUEIDENTIFIER NULL;
GO

IF COL_LENGTH('monitor.XESessionStatus', 'IsRunning') IS NULL
    ALTER TABLE [monitor].[XESessionStatus] ADD IsRunning BIT NULL DEFAULT 0;
GO

IF COL_LENGTH('monitor.XESessionStatus', 'TargetFile') IS NULL
    ALTER TABLE [monitor].[XESessionStatus] ADD TargetFile NVARCHAR(255) NULL;
GO

IF COL_LENGTH('monitor.XESessionStatus', 'TargetFileSizeMB') IS NULL
    ALTER TABLE [monitor].[XESessionStatus] ADD TargetFileSizeMB BIGINT NULL;
GO

IF COL_LENGTH('monitor.XESessionStatus', 'EventCount') IS NULL
    ALTER TABLE [monitor].[XESessionStatus] ADD EventCount BIGINT NULL;
GO

IF COL_LENGTH('monitor.XESessionStatus', 'MemoryUsedKB') IS NULL
    ALTER TABLE [monitor].[XESessionStatus] ADD MemoryUsedKB BIGINT NULL;
GO

IF COL_LENGTH('monitor.XESessionStatus', 'MaxMemoryKB') IS NULL
    ALTER TABLE [monitor].[XESessionStatus] ADD MaxMemoryKB BIGINT NULL;
GO

IF COL_LENGTH('monitor.XESessionStatus', 'StartTime') IS NULL
    ALTER TABLE [monitor].[XESessionStatus] ADD StartTime DATETIME2 NULL;
GO

IF COL_LENGTH('monitor.XESessionStatus', 'LastEventTime') IS NULL
    ALTER TABLE [monitor].[XESessionStatus] ADD LastEventTime DATETIME2 NULL;
GO

IF COL_LENGTH('monitor.XESessionStatus', 'LastChecked') IS NULL
    ALTER TABLE [monitor].[XESessionStatus] ADD LastChecked DATETIME2 NULL DEFAULT SYSUTCDATETIME();
GO

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
-- Column reconciliation: an installation that predates any of
-- these columns still has the table, so the CREATE above is skipped
-- whole and its shape would never change.
IF COL_LENGTH('monitor.XEEventConfig', 'SessionName') IS NULL
    ALTER TABLE [monitor].[XEEventConfig] ADD SessionName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.XEEventConfig', 'EventName') IS NULL
    ALTER TABLE [monitor].[XEEventConfig] ADD EventName NVARCHAR(128) NULL;
GO

IF COL_LENGTH('monitor.XEEventConfig', 'Predicate') IS NULL
    ALTER TABLE [monitor].[XEEventConfig] ADD Predicate NVARCHAR(1000) NULL;
GO

IF COL_LENGTH('monitor.XEEventConfig', 'Actions') IS NULL
    ALTER TABLE [monitor].[XEEventConfig] ADD Actions NVARCHAR(1000) NULL;
GO

IF COL_LENGTH('monitor.XEEventConfig', 'MapValues') IS NULL
    ALTER TABLE [monitor].[XEEventConfig] ADD MapValues NVARCHAR(1000) NULL;
GO

IF COL_LENGTH('monitor.XEEventConfig', 'IsEnabled') IS NULL
    ALTER TABLE [monitor].[XEEventConfig] ADD IsEnabled BIT NULL DEFAULT 1;
GO

IF COL_LENGTH('monitor.XEEventConfig', 'Description') IS NULL
    ALTER TABLE [monitor].[XEEventConfig] ADD Description NVARCHAR(500) NULL;
GO

