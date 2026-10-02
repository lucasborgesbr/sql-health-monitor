/*
  SQL Health Monitor - Grafana Integration Queries
  ================================================

  These SQL queries are designed for use with Telegraf's sqlserver input plugin
  or any other collector that sends data to InfluxDB/Prometheus/Grafana.

  IMPORTANT: Run these queries against the SQLHealthMonitor database.

  Setup for Telegraf (telegraf.conf):

  [[inputs.sqlserver]]
    servers = [
      "Server=yourserver;Database=SQLHealthMonitor;appname=telegraf; интеграция=sqlserver",
    ]
    query_version = "18"

  For custom queries, add to telegraf.conf:

  [[inputs.sqlserver.query]]
    measurement_name = "sql_health_monitor"
    query = '''
    -- paste query here
    '''
*/

-- ============================================
-- METRIC CATEGORY: CPU & PERFORMANCE
-- ============================================

-- CPU Usage (SQL Server process)
SELECT
    @@SERVERNAME AS [ServerName],
    'cpu' AS [measurement],
    CAST(SqlCpuPct AS FLOAT) AS [SqlCpuPct],
    CAST(SystemCpuPct AS FLOAT) AS [SystemCpuPct],
    BatchRequests,
    Compilations,
    ReCompilations
FROM [monitor].[CpuHistory]
WHERE CollectedAt >= DATEADD(MINUTE, -5, SYSUTCDATETIME())
ORDER BY CollectedAt DESC;

-- Top Waits (last 1 hour)
SELECT
    @@SERVERNAME AS [ServerName],
    'waits' AS [measurement],
    WaitType,
    CAST(WaitTimeMs AS FLOAT) AS [WaitTimeMs],
    WaitingTasksCount,
    SignalWaitTimeMs,
    CAST(SignalWaitTimeMs * 100.0 / NULLIF(WaitTimeMs, 0) AS FLOAT) AS [SignalWaitPct]
FROM [monitor].[WaitStatsHistory]
WHERE CollectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
  AND WaitTimeMs > 0
ORDER BY WaitTimeMs DESC;

-- ============================================
-- METRIC CATEGORY: MEMORY
-- ============================================

-- Memory Metrics
SELECT
    @@SERVERNAME AS [ServerName],
    'memory' AS [measurement],
    CAST(PageLifeExpectancy AS FLOAT) AS [PageLifeExpectancy],
    CAST(BufferCacheHitRatio AS FLOAT) AS [BufferCacheHitRatio],
    CAST(MemoryGrantsPending AS FLOAT) AS [MemoryGrantsPending],
    CAST(TotalServerMemoryMB AS FLOAT) AS [TotalServerMemoryMB],
    CAST(SqlServerMemoryMB AS FLOAT) AS [SqlServerMemoryMB]
FROM [monitor].[MemoryHistory]
WHERE CollectedAt >= DATEADD(MINUTE, -5, SYSUTCDATETIME())
ORDER BY CollectedAt DESC;

-- ============================================
-- METRIC CATEGORY: DISK
-- ============================================

-- Disk Space & Latency
SELECT
    @@SERVERNAME AS [ServerName],
    'disk' AS [measurement],
    DriveLetter,
    CAST(UsedPct AS FLOAT) AS [UsedPct],
    CAST(FreeSpaceMB AS FLOAT) AS [FreeSpaceMB],
    CAST(TotalSizeMB AS FLOAT) AS [TotalSizeMB],
    CAST(ReadLatencyMs AS FLOAT) AS [ReadLatencyMs],
    CAST(WriteLatencyMs AS FLOAT) AS [WriteLatencyMs],
    CAST(ReadLatencyMs + WriteLatencyMs AS FLOAT) AS [CombinedLatencyMs]
FROM [monitor].[DiskHistory]
WHERE CollectedAt >= DATEADD(MINUTE, -5, SYSUTCDATETIME())
ORDER BY CollectedAt DESC;

-- ============================================
-- METRIC CATEGORY: SESSIONS & CONNECTIONS
-- ============================================

-- Session Counts
SELECT
    @@SERVERNAME AS [ServerName],
    'sessions' AS [measurement],
    CAST(ActiveSessions AS FLOAT) AS [ActiveSessions],
    CAST(BlockedSessions AS FLOAT) AS [BlockedSessions],
    CAST(WaitingTasks AS FLOAT) AS [WaitingTasks],
    CAST(RunnableTasks AS FLOAT) AS [RunnableTasks],
    CAST(SuspendedTasks AS FLOAT) AS [SuspendedTasks]
FROM [monitor].[SessionHistory]
WHERE CollectedAt >= DATEADD(MINUTE, -5, SYSUTCDATETIME())
ORDER BY CollectedAt DESC;

-- ============================================
-- METRIC CATEGORY: AVAILABILITY GROUPS
-- ============================================

-- AG Health Status
SELECT
    @@SERVERNAME AS [ServerName],
    'ag' AS [measurement],
    AgName,
    ReplicaServer,
    IsPrimaryReplica,
    CAST(SynchronizationHealth AS FLOAT) AS [SynchronizationHealth],
    CAST(BytesSentToReplica AS FLOAT) AS [BytesSentToReplica],
    CAST(BytesReceivedFromReplica AS FLOAT) AS [BytesReceivedFromReplica],
    CAST(SendQueueSizeKB AS FLOAT) AS [SendQueueSizeKB],
    CAST(RedoQueueSizeKB AS FLOAT) AS [RedoQueueSizeKB]
FROM [monitor].[AgHealthHistory]
WHERE CollectedAt >= DATEADD(MINUTE, -5, SYSUTCDATETIME())
ORDER BY CollectedAt DESC;

-- ============================================
-- METRIC CATEGORY: BACKUPS
-- ============================================

-- Backup Status
SELECT
    @@SERVERNAME AS [ServerName],
    'backups' AS [measurement],
    DatabaseName,
    BackupType,
    CAST(HoursSinceLastFullBackup AS FLOAT) AS [HoursSinceLastFullBackup],
    CAST(HoursSinceLastDiffBackup AS FLOAT) AS [HoursSinceLastDiffBackup],
    CAST(HoursSinceLastLogBackup AS FLOAT) AS [HoursSinceLastLogBackup],
    CAST(BackupSizeMB AS FLOAT) AS [BackupSizeMB]
FROM [monitor].[BackupHistory]
WHERE CollectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
ORDER BY DatabaseName, BackupType;

-- ============================================
-- METRIC CATEGORY: JOBS
-- ============================================

-- Job Health
SELECT
    @@SERVERNAME AS [ServerName],
    'jobs' AS [measurement],
    JobName,
    LastRunOutcome,
    CAST(LastRunDurationSec AS FLOAT) AS [LastRunDurationSec],
    CAST(FailedRunCount AS FLOAT) AS [FailedRunCount],
    CAST(AvgDurationSec AS FLOAT) AS [AvgDurationSec]
FROM [monitor].[JobHistory]
WHERE CollectedAt >= DATEADD(HOUR, -24, SYSUTCDATETIME())
ORDER BY FailedRunCount DESC, JobName;

-- ============================================
-- METRIC CATEGORY: ALERTS
-- ============================================

-- Alert Summary (for trend visualization)
SELECT
    @@SERVERNAME AS [ServerName],
    'alerts' AS [measurement],
    AlertName AS [AlertName],
    Severity,
    MetricName,
    ThresholdValue,
    ActualValue,
    FiredAt
FROM [monitor].[AlertHistory]
WHERE FiredAt >= DATEADD(HOUR, -24, SYSUTCDATETIME())
ORDER BY FiredAt DESC;

-- ============================================
-- METRIC CATEGORY: LIVE SESSIONS (Snapshot)
-- ============================================

-- Current Active Sessions (expensive query - use sparingly)
SELECT
    @@SERVERNAME AS [ServerName],
    'live_sessions' AS [measurement],
    SessionId,
    SessionStatus,
    DatabaseName,
    WaitType,
    BlockedBy,
    CAST(CpuTimeMs AS FLOAT) AS [CpuTimeMs],
    CAST(MemoryGrantKB AS FLOAT) AS [MemoryGrantKB],
    CAST(Reads AS FLOAT) AS [Reads],
    CAST(Writes AS FLOAT) AS [Writes],
    CAST(DurationSec AS FLOAT) AS [DurationSec]
FROM [monitor].[LiveSessionsHistory]
WHERE CollectedAt >= DATEADD(MINUTE, -5, SYSUTCDATETIME())
  AND SessionStatus IN ('running', 'suspended', 'runnable')
ORDER BY CpuTimeMs DESC;

-- ============================================
-- METRIC CATEGORY: QUERY STORE (if available)
-- ============================================

-- Top Queries by CPU
SELECT
    @@SERVERNAME AS [ServerName],
    'query_store_cpu' AS [measurement],
    DatabaseName,
    QueryId,
    CAST(TotalCpuMs AS FLOAT) AS [TotalCpuMs],
    CAST(AvgCpuMs AS FLOAT) AS [AvgCpuMs],
    CAST(ExecutionCount AS FLOAT) AS [ExecutionCount],
    CAST(TotalLogicalReads AS FLOAT) AS [TotalLogicalReads]
FROM [monitor].[QueryStoreHistory]
WHERE CollectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
  AND Dimension = 'CPU'
ORDER BY TotalCpuMs DESC;

-- ============================================
-- METRIC CATEGORY: INDEX RECOMMENDATIONS
-- ============================================

-- Index Recommendations Summary
SELECT
    @@SERVERNAME AS [ServerName],
    'index_recs' AS [measurement],
    DatabaseName,
    SchemaName,
    TableName,
    RecommendationType,
    CAST(ImpactScore AS FLOAT) AS [ImpactScore],
    CAST(UniqueCompiles AS FLOAT) AS [UniqueCompiles],
    CAST(LastUserSeek AS FLOAT) AS [LastUserSeek]
FROM [monitor].[IndexRecommendations]
WHERE CollectedAt >= DATEADD(HOUR, -24, SYSUTCDATETIME())
  AND ImpactScore > 30
ORDER BY ImpactScore DESC;

-- ============================================
-- PROMETHEUS FORMAT EXAMPLE
-- ============================================
/*
For Prometheus exporters, format output as:

# HELP sql_cpu_sql_pct SQL Server CPU utilization percentage
# TYPE sql_cpu_sql_pct gauge
sql_cpu_sql_pct{server="YOURSERVER"} 15.5

# HELP sql_ple_seconds Page Life Expectancy in seconds
# TYPE sql_ple_seconds gauge
sql_ple_seconds{server="YOURSERVER"} 450.0

# HELP sql_sessions_active Number of active sessions
# TYPE sql_sessions_active gauge
sql_sessions_active{server="YOURSERVER"} 45

# HELP sql_disk_used_pct Disk space used percentage
# TYPE sql_disk_used_pct gauge
sql_disk_used_pct{server="YOURSERVER",drive="C"} 65.2
*/

-- ============================================
-- COMPLETE HEALTH CHECK (Single Query)
-- ============================================
/*
Use this single query for a comprehensive health snapshot:

SELECT
    @@SERVERNAME AS server,
    'health_snapshot' AS measurement,
    GETUTCDATE() AS timestamp,
    (SELECT SqlCpuPct FROM [monitor].[CpuHistory] ORDER BY CollectedAt DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY) AS cpu_sql_pct,
    (SELECT SystemCpuPct FROM [monitor].[CpuHistory] ORDER BY CollectedAt DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY) AS cpu_system_pct,
    (SELECT PageLifeExpectancy FROM [monitor].[MemoryHistory] ORDER BY CollectedAt DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY) AS ple_seconds,
    (SELECT COUNT(*) FROM [monitor].[LiveSessionsHistory] WHERE CollectedAt >= DATEADD(MINUTE, -5, GETUTCDATE()) AND BlockedBy > 0) AS blocked_sessions,
    (SELECT COUNT(*) FROM [monitor].[AlertHistory] WHERE FiredAt >= DATEADD(HOUR, -1, GETUTCDATE()) AND Severity = 'Critical') AS critical_alerts_1h,
    (SELECT COUNT(*) FROM [monitor].[AlertHistory] WHERE FiredAt >= DATEADD(HOUR, -1, GETUTCDATE()) AND Severity = 'Warning') AS warning_alerts_1h,
    (SELECT COUNT(*) FROM [monitor].[LiveSessionsHistory] WHERE CollectedAt >= DATEADD(MINUTE, -5, GETUTCDATE()) AND SessionStatus IN ('running', 'suspended')) AS active_sessions;
*/
