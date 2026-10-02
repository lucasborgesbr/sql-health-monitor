# Grafana Dashboards

SQL Health Monitor supports two Grafana integration options:

## Option 1: Direct MSSQL (Recommended for single instance)

Uses Grafana's built-in MSSQL datasource for direct SQL Server queries.

### Setup

1. **Add MSSQL Datasource in Grafana:**
   ```
   Settings → Connections → Data sources → Add data source → Microsoft SQL Server
   ```

2. **Configuration:**
   - Host: `sqlserver:1433` (or your server)
   - Database: `SQLHealthMonitor`
   - Authentication: Windows Authentication or SQL Authentication
   - TLS/SSL: Enable if required

3. **Import Dashboard:**
   ```
   Dashboards → Import → Upload sql-health-monitor-direct.json
   ```

4. **Set Variables:**
   - `DS_MSSQL`: Select your MSSQL datasource

### Files
- `sql-health-monitor-direct.json` - Full dashboard with all panels
- Uses `$__timeFilter()` macro for time-based filtering

---

## Option 2: Prometheus (Recommended for multi-instance)

Exports metrics in Prometheus exposition format for scraping.

### Prerequisites

You need one of:
- [sql_exporter](https://github.com/burningalchemist/sql_exporter) - Go-based exporter
- [prometheus-sql-exporter](https://github.com/trevorallan/prometheus-sql-exporter) - Python-based
- [mSSQL_exporter](https://github.com/dbhi/mssql_exporter) - Prometheus exporter for MSSQL

### Setup

1. **Configure Exporter:**
   Use `queries/prometheus_queries.sql` as reference for metric definitions.

   Example `queries.yml` for sql_exporter:
   ```yaml
   queries:
     - name: "sql_health_metrics"
       help: "SQL Health Monitor metrics"
       values:
         - cpu_pct
         - ple_seconds
         - blocked_sessions
         - active_sessions
       query: |
         SELECT
           (SELECT TOP 1 SqlCpuPct FROM [SQLHealthMonitor].[monitor].[CpuHistory] ORDER BY CollectedAt DESC) AS cpu_pct,
           (SELECT TOP 1 PageLifeExpectancy FROM [SQLHealthMonitor].[monitor].[MemoryHistory] ORDER BY CollectedAt DESC) AS ple_seconds,
           (SELECT TOP 1 BlockedSessions FROM [SQLHealthMonitor].[monitor].[SessionHistory] ORDER BY CollectedAt DESC) AS blocked_sessions,
           (SELECT TOP 1 ActiveSessions FROM [SQLHealthMonitor].[monitor].[SessionHistory] ORDER BY CollectedAt DESC) AS active_sessions
   ```

2. **Add Prometheus Datasource:**
   ```
   Settings → Connections → Data sources → Add data source → Prometheus
   ```

3. **Import Dashboard:**
   ```
   Dashboards → Import → Upload sql-health-monitor-prometheus.json
   ```

4. **Set Variables:**
   - `DS_PROMETHEUS`: Select your Prometheus datasource
   - `server`: Filter by instance (auto-populated from labels)

### Available Prometheus Metrics

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `sql_health_cpu_sql_pct` | gauge | server | SQL Server CPU % |
| `sql_health_cpu_system_pct` | gauge | server | System CPU % |
| `sql_health_ple_seconds` | gauge | server | Page Life Expectancy |
| `sql_health_buffer_cache_hit_ratio` | gauge | server | Buffer cache hit ratio |
| `sql_health_memory_grants_pending` | gauge | server | Pending memory grants |
| `sql_health_total_server_memory_mb` | gauge | server | Total server memory MB |
| `sql_health_sql_server_memory_mb` | gauge | server | SQL Server memory MB |
| `sql_health_disk_used_pct` | gauge | server, drive | Disk usage % |
| `sql_health_disk_free_space_mb` | gauge | server, drive | Free disk space MB |
| `sql_health_disk_read_latency_ms` | gauge | server, drive | Read latency ms |
| `sql_health_disk_write_latency_ms` | gauge | server, drive | Write latency ms |
| `sql_health_active_sessions` | gauge | server | Active sessions |
| `sql_health_blocked_sessions` | gauge | server | Blocked sessions |
| `sql_health_waiting_tasks` | gauge | server | Waiting tasks |
| `sql_health_wait_time_ms` | gauge | server, wait_type | Wait time ms |
| `sql_health_waiting_tasks_count` | gauge | server, wait_type | Tasks waiting |
| `sql_health_ag_synchronized` | gauge | server, ag_name, replica | AG sync status |
| `sql_health_ag_sync_health` | gauge | server, ag_name, replica | AG health % |
| `sql_health_ag_send_queue_kb` | gauge | server, ag_name, replica | AG send queue KB |
| `sql_health_ag_redo_queue_kb` | gauge | server, ag_name, replica | AG redo queue KB |
| `sql_health_backup_hours_since_full` | gauge | server, database | Hours since full backup |
| `sql_health_backup_hours_since_log` | gauge | server, database | Hours since log backup |
| `sql_health_job_failed_count` | gauge | server, job_name | Failed job runs |
| `sql_health_job_last_outcome` | gauge | server, job_name | Last job outcome (0/1) |
| `sql_health_alert_count_total` | counter | server, severity, alert_name | Total alerts |
| `sql_health_findings_critical` | gauge | server | Critical findings 24h |
| `sql_health_findings_warning` | gauge | server | Warning findings 24h |
| `sql_health_findings_info` | gauge | server | Info findings 24h |

---

## Comparison

| Feature | Direct MSSQL | Prometheus |
|---------|--------------|------------|
| Setup complexity | Low | Medium |
| Multi-instance support | Manual per server | Built-in (label filtering) |
| Performance | Direct query | Scraped metrics |
| Historical data | From SQL tables | From Prometheus |
| Alerting integration | Grafana alerts | Native Prometheus alerts |
| Resource usage | Per-query | Exporter sidecar |

---

## Prometheus Scrape Config

Example `prometheus.yml`:
```yaml
scrape_configs:
  - job_name: 'sql-health-monitor'
    static_configs:
      - targets: ['sql-exporter:9399']
    metrics_path: /metrics
    scrape_interval: 60s
```

Or for multiple instances:
```yaml
scrape_configs:
  - job_name: 'sql-health-monitor'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        action: keep
        regex: sql-exporter
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_port]
        action: keep
        regex: "9399"
```
