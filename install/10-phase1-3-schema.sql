/*
    SQL Health Monitor - Phase 1-3 Features Schema Migration
    Adds tables for new collectors:
    - LiveSessionsHistory: Current/live session capture
    - IndexRecommendations: Missing/unused index suggestions
    - QueryStoreHistory: Query Store data
    - QueryRegressions: Query performance regression tracking

    Run this script AFTER 00-create-schema.sql
    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

-- ============================================================
-- Live Sessions History
-- ============================================================
IF OBJECT_ID('[monitor].[LiveSessionsHistory]', 'U') IS NULL
BEGIN
    CREATE TABLE [monitor].[LiveSessionsHistory] (
        Id                  BIGINT IDENTITY(1,1) PRIMARY KEY,
        CollectedAt         DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        SessionId           INT NOT NULL,
        SessionStatus       NVARCHAR(30) NULL,
        LoginName          NVARCHAR(128) NULL,
        HostName           NVARCHAR(128) NULL,
        ProgramName        NVARCHAR(128) NULL,
        DatabaseName       NVARCHAR(128) NULL,
        CommandType        NVARCHAR(30) NULL,
        QueryText          NVARCHAR(MAX) NULL,
        QueryHash          BINARY(8) NULL,
        WaitType           NVARCHAR(120) NULL,
        WaitTimeMs         BIGINT NULL,
        BlockedBy          INT NULL,
        BlockingCount      INT NULL,
        CpuTimeMs          BIGINT NULL,
        TotalElapsedTimeMs BIGINT NULL,
        Reads              BIGINT NULL,
        Writes             BIGINT NULL,
        MemoryGrantKB      BIGINT NULL,
        [RowCount]          BIGINT NULL,
        PercentComplete    INT NULL,
        StartTime          DATETIME2 NULL,
        LoginTime          DATETIME2 NULL,
        InputBuffer        NVARCHAR(MAX) NULL,
        QueryPlan          XML NULL,
        INDEX IX_LiveSessions_Date NONCLUSTERED (CollectedAt),
        INDEX IX_LiveSessions_Session NONCLUSTERED (SessionId, CollectedAt),
        INDEX IX_LiveSessions_Wait NONCLUSTERED (WaitType, CollectedAt),
        INDEX IX_LiveSessions_Blocked NONCLUSTERED (BlockedBy, CollectedAt)
    );
    PRINT '+ Table [monitor].[LiveSessionsHistory] created';
END
GO

-- ============================================================
-- Index Recommendations
-- ============================================================
IF OBJECT_ID('[monitor].[IndexRecommendations]', 'U') IS NULL
BEGIN
    CREATE TABLE [monitor].[IndexRecommendations] (
        Id                  BIGINT IDENTITY(1,1) PRIMARY KEY,
        CollectedAt         DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        DatabaseName        NVARCHAR(128) NULL,
        SchemaName         NVARCHAR(128) NULL,
        TableName          NVARCHAR(128) NULL,
        RecommendationType  NVARCHAR(50) NOT NULL,  -- MISSING_INDEX, UNUSED_INDEX, DUPLICATE_INDEX
        ImpactScore        DECIMAL(18,2) NULL,     -- 0-100, higher = more impact
        EqualityColumns    NVARCHAR(MAX) NULL,
        InequalityColumns  NVARCHAR(MAX) NULL,
        IncludeColumns     NVARCHAR(MAX) NULL,
        UserSeeks          BIGINT NULL,
        UserScans          BIGINT NULL,
        AvgTotalUserCost   DECIMAL(18,2) NULL,
        RecommendedAction  NVARCHAR(MAX) NULL,     -- CREATE INDEX or DROP INDEX statement
        IsImplemented      BIT NOT NULL DEFAULT 0,
        ImplementedAt      DATETIME2 NULL,
        INDEX IX_IndexRec_Date NONCLUSTERED (CollectedAt),
        INDEX IX_IndexRec_Type NONCLUSTERED (RecommendationType, CollectedAt),
        INDEX IX_IndexRec_Database NONCLUSTERED (DatabaseName, TableName)
    );
    PRINT '+ Table [monitor].[IndexRecommendations] created';
END
GO

-- ============================================================
-- Query Store History
-- ============================================================
IF OBJECT_ID('[monitor].[QueryStoreHistory]', 'U') IS NULL
BEGIN
    CREATE TABLE [monitor].[QueryStoreHistory] (
        Id                  BIGINT IDENTITY(1,1) PRIMARY KEY,
        CollectedAt         DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        DatabaseName        NVARCHAR(128) NOT NULL,
        QueryId            INT NOT NULL,
        PlanId             INT NOT NULL,
        ObjectId           BIGINT NULL,
        ObjectName         NVARCHAR(128) NULL,
        QueryText          NVARCHAR(MAX) NULL,
        QueryType          NVARCHAR(256) NULL,
        SchemaName         NVARCHAR(128) NULL,
        -- CPU metrics
        TotalCpuMs         DECIMAL(18,2) NULL,
        AvgCpuMs           DECIMAL(18,2) NULL,
        -- Duration metrics
        TotalDurationMs    DECIMAL(18,2) NULL,
        AvgDurationMs      DECIMAL(18,2) NULL,
        -- I/O metrics
        TotalLogicalReads  BIGINT NULL,
        AvgLogicalReads    DECIMAL(18,2) NULL,
        TotalLogicalWrites BIGINT NULL,
        AvgLogicalWrites   DECIMAL(18,2) NULL,
        -- Row metrics
        TotalRowCount      BIGINT NULL,
        AvgRowCount        DECIMAL(18,2) NULL,
        -- Execution stats
        ExecutionCount     BIGINT NULL,
        TotalExecTimeMs    DECIMAL(18,2) NULL,
        AvgExecTimeMs      DECIMAL(18,2) NULL,
        -- Plan info
        StalePlans         INT NULL,
        LastExecutionTime  DATETIME2 NULL,
        FirstExecutionTime DATETIME2 NULL,
        INDEX IX_QSHistory_Date NONCLUSTERED (CollectedAt),
        INDEX IX_QSHistory_Database NONCLUSTERED (DatabaseName, CollectedAt),
        INDEX IX_QSHistory_Query NONCLUSTERED (QueryId, DatabaseName)
    );
    PRINT '+ Table [monitor].[QueryStoreHistory] created';
END
GO

-- ============================================================
-- Query Regressions
-- ============================================================
IF OBJECT_ID('[monitor].[QueryRegressions]', 'U') IS NULL
BEGIN
    CREATE TABLE [monitor].[QueryRegressions] (
        Id                  BIGINT IDENTITY(1,1) PRIMARY KEY,
        CollectedAt         DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        DatabaseName        NVARCHAR(128) NOT NULL,
        QueryId            INT NOT NULL,
        QueryText          NVARCHAR(MAX) NULL,
        PreviousDurationMs DECIMAL(18,2) NULL,
        CurrentDurationMs  DECIMAL(18,2) NULL,
        SlowdownFactor     DECIMAL(10,2) NULL,  -- How many times slower
        PlanChangeDetected BIT NOT NULL DEFAULT 0,
        IsReviewed         BIT NOT NULL DEFAULT 0,
        ReviewedAt         DATETIME2 NULL,
        Notes              NVARCHAR(MAX) NULL,
        INDEX IX_QSRegress_Date NONCLUSTERED (CollectedAt),
        INDEX IX_QSRegress_Query NONCLUSTERED (QueryId, DatabaseName),
        INDEX IX_QSRegress_Factor NONCLUSTERED (SlowdownFactor)
    );
    PRINT '+ Table [monitor].[QueryRegressions] created';
END
GO

PRINT '';
PRINT '========================================================';
PRINT '  Phase 1-3 schema migration completed successfully';
PRINT '========================================================';
PRINT '';
PRINT 'New tables created:';
PRINT '  - monitor.LiveSessionsHistory';
PRINT '  - monitor.IndexRecommendations';
PRINT '  - monitor.QueryStoreHistory';
PRINT '  - monitor.QueryRegressions';
PRINT '';
PRINT 'New collectors to install:';
PRINT '  - collectors/collect_live_sessions.sql';
PRINT '  - collectors/collect_index_recommendations.sql';
PRINT '  - collectors/collect_query_store.sql';
PRINT '';
GO

-- ============================================================
-- Wait Database History (bonus - per database wait stats)
-- ============================================================
IF OBJECT_ID('[monitor].[WaitDatabaseHistory]', 'U') IS NULL
BEGIN
    CREATE TABLE [monitor].[WaitDatabaseHistory] (
        Id                  BIGINT IDENTITY(1,1) PRIMARY KEY,
        CollectedAt         DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        DatabaseId          INT NOT NULL,
        DatabaseName        NVARCHAR(128) NOT NULL,
        WaitType           NVARCHAR(120) NOT NULL,
        WaitingTasksCount  BIGINT NOT NULL,
        WaitTimeMs         BIGINT NOT NULL,
        SignalWaitTimeMs   BIGINT NOT NULL,
        INDEX IX_WaitDb_Date NONCLUSTERED (CollectedAt),
        INDEX IX_WaitDb_Database NONCLUSTERED (DatabaseName, CollectedAt),
        INDEX IX_WaitDb_WaitType NONCLUSTERED (WaitType, CollectedAt)
    );
    PRINT '+ Table [monitor].[WaitDatabaseHistory] created';
END
GO

-- Update waits collector to include per-database breakdown
PRINT '';
PRINT 'Note: Update collect_waits.sql to populate WaitDatabaseHistory';
PRINT '      Use dm_db_session_wait_stats for per-session waits';
PRINT '';
GO
