/*
  SQL Health Monitor - Prometheus Metrics Queries
  =============================================

  These SQL queries output metrics in Prometheus exposition format.
  Use with sql_exporter or prometheus-sql-exporter.

  Example sql_exporter queries.yml:
  ---
  metric_name: sql_health_cpu_pct
  help: SQL Server CPU utilization percentage
  type: gauge
  values:
    - cpu_pct
  query: |
    SELECT CAST(SqlCpuPct AS FLOAT) AS cpu_pct FROM [monitor].[CpuHistory] ORDER BY CollectedAt DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY

  metric_name: sql_health_ple_seconds
  help: Page Life Expectancy in seconds
  type: gauge
  values:
    - ple_seconds
  query: |
    SELECT CAST(PageLifeExpectancy AS FLOAT) AS ple_seconds FROM [monitor].[MemoryHistory] ORDER BY CollectedAt DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY
*/

-- ============================================
-- CPU METRICS
-- ============================================

-- HELP sql_health_cpu_sql_pct SQL Server process CPU utilization percentage
-- TYPE sql_health_cpu_sql_pct gauge
SELECT
    'sql_health_cpu_sql_pct' AS metric_name,
    CAST(SqlCpuPct AS FLOAT) AS value,
    @@SERVERNAME AS server,
    REPLACE(REPLACE(@@SERVERNAME, '\', '-'), '.', '-') AS server_label
FROM [monitor].[CpuHistory]
ORDER BY CollectedAt DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY;

-- HELP sql_health_cpu_system_pct System CPU utilization percentage
-- TYPE sql_health_cpu_system_pct gauge
SELECT
    'sql_health_cpu_system_pct' AS metric_name,
    CAST(SystemCpuPct AS FLOAT) AS value,
    @@SERVERNAME AS server
FROM [monitor].[CpuHistory]
ORDER BY CollectedAt DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY;

-- HELP sql_health_batch_requests Batch requests per second
-- TYPE sql_health_batch_requests gauge
SELECT
    'sql_health_batch_requests' AS metric_name,
    CAST(BatchRequests AS FLOAT) AS value,
    @@SERVERNAME AS server
FROM [monitor].[CpuHistory]
ORDER BY CollectedAt DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY;

-- ============================================
-- MEMORY METRICS
-- ============================================

-- HELP sql_health_ple_seconds Page Life Expectancy in seconds
-- TYPE sql_health_ple_seconds gauge
SELECT
    'sql_health_ple_seconds' AS metric_name,
    CAST(PageLifeExpectancy AS FLOAT) AS value,
    @@SERVERNAME AS server
FROM [monitor].[MemoryHistory]
ORDER BY CollectedAt DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY;

-- HELP sql_health_buffer_cache_hit_ratio Buffer cache hit ratio percentage
-- TYPE sql_health_buffer_cache_hit_ratio gauge
SELECT
    'sql_health_buffer_cache_hit_ratio' AS metric_name,
    CAST(BufferCacheHitRatio AS FLOAT) AS value,
    @@SERVERNAME AS server
FROM [monitor].[MemoryHistory]
ORDER BY CollectedAt DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY;

-- HELP sql_health_memory_grants_pending Number of pending memory grants
-- TYPE sql_health_memory_grants_pending gauge
SELECT
    'sql_health_memory_grants_pending' AS metric_name,
    CAST(MemoryGrantsPending AS FLOAT) AS value,
    @@SERVERNAME AS server
FROM [monitor].[MemoryHistory]
ORDER BY CollectedAt DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY;

-- HELP sql_health_total_server_memory_mb Total server memory in MB
-- TYPE sql_health_total_server_memory_mb gauge
SELECT
    'sql_health_total_server_memory_mb' AS metric_name,
    CAST(TotalServerMemoryMB AS FLOAT) AS value,
    @@SERVERNAME AS server
FROM [monitor].[MemoryHistory]
ORDER BY CollectedAt DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY;

-- HELP sql_health_sql_server_memory_mb SQL Server memory usage in MB
-- TYPE sql_health_sql_server_memory_mb gauge
SELECT
    'sql_health_sql_server_memory_mb' AS metric_name,
    CAST(SqlServerMemoryMB AS FLOAT) AS value,
    @@SERVERNAME AS server
FROM [monitor].[MemoryHistory]
ORDER BY CollectedAt DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY;

-- ============================================
-- DISK METRICS
-- ============================================

-- HELP sql_health_disk_used_pct Disk space used percentage
-- TYPE sql_health_disk_used_pct gauge
SELECT
    'sql_health_disk_used_pct' AS metric_name,
    CAST(UsedPct AS FLOAT) AS value,
    @@SERVERNAME AS server,
    REPLACE(DriveLetter, ':', '') AS drive
FROM [monitor].[DiskHistory]
ORDER BY CollectedAt DESC;

-- HELP sql_health_disk_free_space_mb Free disk space in MB
-- TYPE sql_health_disk_free_space_mb gauge
SELECT
    'sql_health_disk_free_space_mb' AS metric_name,
    CAST(FreeSpaceMB AS FLOAT) AS value,
    @@SERVERNAME AS server,
    REPLACE(DriveLetter, ':', '') AS drive
FROM [monitor].[DiskHistory]
ORDER BY CollectedAt DESC;

-- HELP sql_health_disk_read_latency_ms Average disk read latency in milliseconds
-- TYPE sql_health_disk_read_latency_ms gauge
SELECT
    'sql_health_disk_read_latency_ms' AS metric_name,
    CAST(ReadLatencyMs AS FLOAT) AS value,
    @@SERVERNAME AS server,
    REPLACE(DriveLetter, ':', '') AS drive
FROM [monitor].[DiskHistory]
ORDER BY CollectedAt DESC;

-- HELP sql_health_disk_write_latency_ms Average disk write latency in milliseconds
-- TYPE sql_health_disk_write_latency_ms gauge
SELECT
    'sql_health_disk_write_latency_ms' AS metric_name,
    CAST(WriteLatencyMs AS FLOAT) AS value,
    @@SERVERNAME AS server,
    REPLACE(DriveLetter, ':', '') AS drive
FROM [monitor].[DiskHistory]
ORDER BY CollectedAt DESC;

-- ============================================
-- SESSION METRICS
-- ============================================

-- HELP sql_health_active_sessions Number of active sessions
-- TYPE sql_health_active_sessions gauge
SELECT
    'sql_health_active_sessions' AS metric_name,
    CAST(ActiveSessions AS FLOAT) AS value,
    @@SERVERNAME AS server
FROM [monitor].[SessionHistory]
ORDER BY CollectedAt DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY;

-- HELP sql_health_blocked_sessions Number of blocked sessions
-- TYPE sql_health_blocked_sessions gauge
SELECT
    'sql_health_blocked_sessions' AS metric_name,
    CAST(BlockedSessions AS FLOAT) AS value,
    @@SERVERNAME AS server
FROM [monitor].[SessionHistory]
ORDER BY CollectedAt DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY;

-- HELP sql_health_waiting_tasks Number of waiting tasks
-- TYPE sql_health_waiting_tasks gauge
SELECT
    'sql_health_waiting_tasks' AS metric_name,
    CAST(WaitingTasks AS FLOAT) AS value,
    @@SERVERNAME AS server
FROM [monitor].[SessionHistory]
ORDER BY CollectedAt DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY;

-- ============================================
-- WAIT STATISTICS
-- ============================================

-- HELP sql_health_wait_time_ms Wait time in milliseconds
-- TYPE sql_health_wait_time_ms gauge
SELECT
    'sql_health_wait_time_ms' AS metric_name,
    CAST(WaitTimeMs AS FLOAT) AS value,
    @@SERVERNAME AS server,
    REPLACE(WaitType, ' ', '_') AS wait_type
FROM [monitor].[WaitStatsHistory]
WHERE CollectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
  AND WaitTimeMs > 0
ORDER BY WaitTimeMs DESC;

-- HELP sql_health_waiting_tasks_count Number of tasks waiting
-- TYPE sql_health_waiting_tasks_count gauge
SELECT
    'sql_health_waiting_tasks_count' AS metric_name,
    CAST(WaitingTasksCount AS FLOAT) AS value,
    @@SERVERNAME AS server,
    REPLACE(WaitType, ' ', '_') AS wait_type
FROM [monitor].[WaitStatsHistory]
WHERE CollectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
  AND WaitingTasksCount > 0
ORDER BY WaitTimeMs DESC;

-- ============================================
-- AVAILABILITY GROUP METRICS
-- ============================================

-- HELP sql_health_ag_synchronized Availability group synchronization status (1=synced, 0=not synced)
-- TYPE sql_health_ag_synchronized gauge
SELECT
    'sql_health_ag_synchronized' AS metric_name,
    CAST(IsSynchronized AS FLOAT) AS value,
    @@SERVERNAME AS server,
    AgName AS ag_name,
    REPLACE(REPLACE(ReplicaServer, '\', '-'), '.', '-') AS replica
FROM [monitor].[AgHealthHistory]
ORDER BY CollectedAt DESC;

-- HELP sql_health_ag_sync_health AG synchronization health percentage
-- TYPE sql_health_ag_sync_health gauge
SELECT
    'sql_health_ag_sync_health' AS metric_name,
    CAST(SynchronizationHealth AS FLOAT) AS value,
    @@SERVERNAME AS server,
    AgName AS ag_name,
    REPLACE(REPLACE(ReplicaServer, '\', '-'), '.', '-') AS replica
FROM [monitor].[AgHealthHistory]
ORDER BY CollectedAt DESC;

-- HELP sql_health_ag_send_queue_kb AG send queue size in KB
-- TYPE sql_health_ag_send_queue_kb gauge
SELECT
    'sql_health_ag_send_queue_kb' AS metric_name,
    CAST(SendQueueSizeKB AS FLOAT) AS value,
    @@SERVERNAME AS server,
    AgName AS ag_name,
    REPLACE(REPLACE(ReplicaServer, '\', '-'), '.', '-') AS replica
FROM [monitor].[AgHealthHistory]
ORDER BY CollectedAt DESC;

-- HELP sql_health_ag_redo_queue_kb AG redo queue size in KB
-- TYPE sql_health_ag_redo_queue_kb gauge
SELECT
    'sql_health_ag_redo_queue_kb' AS metric_name,
    CAST(RedoQueueSizeKB AS FLOAT) AS value,
    @@SERVERNAME AS server,
    AgName AS ag_name,
    REPLACE(REPLACE(ReplicaServer, '\', '-'), '.', '-') AS replica
FROM [monitor].[AgHealthHistory]
ORDER BY CollectedAt DESC;

-- ============================================
-- BACKUP METRICS
-- ============================================

-- HELP sql_health_backup_hours_since_full Hours since last full backup
-- TYPE sql_health_backup_hours_since_full gauge
SELECT
    'sql_health_backup_hours_since_full' AS metric_name,
    CAST(HoursSinceLastFullBackup AS FLOAT) AS value,
    @@SERVERNAME AS server,
    DatabaseName AS database_name
FROM [monitor].[BackupHistory]
WHERE BackupType = 'Full'
ORDER BY CollectedAt DESC;

-- HELP sql_health_backup_hours_since_log Hours since last log backup
-- TYPE sql_health_backup_hours_since_log gauge
SELECT
    'sql_health_backup_hours_since_log' AS metric_name,
    CAST(HoursSinceLastLogBackup AS FLOAT) AS value,
    @@SERVERNAME AS server,
    DatabaseName AS database_name
FROM [monitor].[BackupHistory]
WHERE BackupType = 'Log'
ORDER BY CollectedAt DESC;

-- ============================================
-- JOB METRICS
-- ============================================

-- HELP sql_health_job_failed_count Number of failed job runs
-- TYPE sql_health_job_failed_count gauge
SELECT
    'sql_health_job_failed_count' AS metric_name,
    CAST(FailedRunCount AS FLOAT) AS value,
    @@SERVERNAME AS server,
    REPLACE(JobName, ' ', '_') AS job_name
FROM [monitor].[JobHistory]
ORDER BY CollectedAt DESC;

-- HELP sql_health_job_last_outcome Job last run outcome (1=success, 0=failure)
-- TYPE sql_health_job_last_outcome gauge
SELECT
    'sql_health_job_last_outcome' AS metric_name,
    CAST(LastRunOutcome AS FLOAT) AS value,
    @@SERVERNAME AS server,
    REPLACE(JobName, ' ', '_') AS job_name
FROM [monitor].[JobHistory]
ORDER BY CollectedAt DESC;

-- ============================================
-- ALERT METRICS
-- ============================================

-- HELP sql_health_alert_count_total Total alerts in time window
-- TYPE sql_health_alert_count_total counter
SELECT
    'sql_health_alert_count_total' AS metric_name,
    COUNT(*) AS value,
    @@SERVERNAME AS server,
    Severity AS severity,
    AlertName AS alert_name
FROM [monitor].[AlertHistory]
WHERE FiredAt >= DATEADD(HOUR, -24, SYSUTCDATETIME())
GROUP BY Severity, AlertName;

-- ============================================
-- HEALTH CHECK SCORE
-- ============================================

-- HELP sql_health_findings_count Number of health check findings by severity
-- TYPE sql_health_findings_count gauge
SELECT
    'sql_health_findings_critical' AS metric_name,
    COUNT(*) AS value,
    @@SERVERNAME AS server
FROM [monitor].[AlertHistory]
WHERE Severity = 'Critical'
  AND FiredAt >= DATEADD(HOUR, -24, SYSUTCDATETIME())

UNION ALL

SELECT
    'sql_health_findings_warning' AS metric_name,
    COUNT(*) AS value,
    @@SERVERNAME AS server
FROM [monitor].[AlertHistory]
WHERE Severity = 'Warning'
  AND FiredAt >= DATEADD(HOUR, -24, SYSUTCDATETIME())

UNION ALL

SELECT
    'sql_health_findings_info' AS metric_name,
    COUNT(*) AS value,
    @@SERVERNAME AS server
FROM [monitor].[AlertHistory]
WHERE Severity = 'Information'
  AND FiredAt >= DATEADD(HOUR, -24, SYSUTCDATETIME());

-- ============================================
-- SINGLE SNAPSHOT QUERY (for direct Grafana MSSQL)
-- ============================================
/*
Use this single query for Grafana's MSSQL datasource:

SELECT
    @@SERVERNAME AS server,
    GETUTCDATE() AS [time],
    (SELECT TOP 1 SqlCpuPct FROM [monitor].[CpuHistory] ORDER BY CollectedAt DESC) AS cpu_sql_pct,
    (SELECT TOP 1 SystemCpuPct FROM [monitor].[CpuHistory] ORDER BY CollectedAt DESC) AS cpu_system_pct,
    (SELECT TOP 1 PageLifeExpectancy FROM [monitor].[MemoryHistory] ORDER BY CollectedAt DESC) AS ple_seconds,
    (SELECT TOP 1 BufferCacheHitRatio FROM [monitor].[MemoryHistory] ORDER BY CollectedAt DESC) AS buffer_cache_hit_ratio,
    (SELECT TOP 1 MemoryGrantsPending FROM [monitor].[MemoryHistory] ORDER BY CollectedAt DESC) AS memory_grants_pending,
    (SELECT TOP 1 ActiveSessions FROM [monitor].[SessionHistory] ORDER BY CollectedAt DESC) AS active_sessions,
    (SELECT TOP 1 BlockedSessions FROM [monitor].[SessionHistory] ORDER BY CollectedAt DESC) AS blocked_sessions,
    (SELECT COUNT(*) FROM [monitor].[AlertHistory] WHERE Severity = 'Critical' AND FiredAt >= DATEADD(HOUR, -24, GETUTCDATE())) AS alerts_critical_24h,
    (SELECT COUNT(*) FROM [monitor].[AlertHistory] WHERE Severity = 'Warning' AND FiredAt >= DATEADD(HOUR, -24, GETUTCDATE())) AS alerts_warning_24h;
*/
