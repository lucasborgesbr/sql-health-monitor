# SQL Health Monitor - Phase 1-3 Implementation Summary

## Overview

This document describes the Phase 1-3 features implemented for SQL Health Monitor, focusing on real-time visibility, query analysis, and actionable recommendations.

## Phase 1: Real-Time Visibility

### 1. Live Sessions Collector
**File:** `collectors/collect_live_sessions.sql`

Captures currently running sessions with sp_WhoIsActive-style information:

| Field | Description |
|-------|-------------|
| SessionId | SPID |
| SessionStatus | Running, Sleeping, Dormant |
| QueryText | Current SQL text |
| WaitType | What it's waiting on |
| BlockedBy | Blocking session ID |
| BlockingCount | Sessions blocked by this one |
| CpuTimeMs | CPU used |
| MemoryGrantKB | Memory allocated |
| QueryPlan | Actual execution plan (optional) |

**Usage:**
```sql
EXEC [monitor].[usp_Collect_LiveSessions];           -- Normal collection
EXEC [monitor].[usp_Collect_LiveSessions] @DebugMode = 1;  -- Preview results
EXEC [monitor].[usp_Collect_LiveSessions] @IncludePlans = 1; -- Include plans (expensive)
```

### 2. Per-Database Wait Stats
**File:** `collectors/collect_waits.sql`

Correlates wait types with specific databases.

| Field | Description |
|-------|-------------|
| DatabaseName | Target database |
| WaitType | Type of wait |
| WaitingTasksCount | Sessions waiting |
| WaitTimeMs | Total wait time |

**Benefit:** Pinpoint which database is causing PAGELATCH, LOCK, or I/O waits.

---

## Phase 2: Deadlock & Query Deep Dive

### 3. Deadlock Graph Capture
**File:** `collectors/collect_deadlocks.sql`

Captures deadlock information from Extended Events and patterns.

**Features:**
- system_health XE session parsing
- Blocking chain detection
- Pattern grouping by time
- Deadlock graph XML capture

### 4. Multi-Dimensional Top Queries
**File:** `collect_query_store.sql`

Captures Query Store data across multiple dimensions:

| Dimension | Use Case |
|-----------|----------|
| CPU | Find resource-intensive queries |
| Duration | Find slow queries |
| Reads | Find I/O-heavy queries |
| Writes | Find write-heavy queries |

**Requirements:**
- Query Store must be enabled per database
- SQL Server 2016+ (Enterprise features in older versions)

---

## Phase 3: Index & Query Recommendations

### 5. Index Recommendations
**File:** `collectors/collect_index_recommendations.sql`

Uses SQL Server DMVs to generate actionable index suggestions.

| Recommendation Type | Description |
|--------------------|-------------|
| MISSING_INDEX | Suggested new indexes with CREATE script |
| UNUSED_INDEX | Indexes not used in 30+ days (DROP candidate) |

**Example Output:**
```sql
-- Generated CREATE INDEX statement:
CREATE INDEX [IX_Orders_CustomerId_OrderDate]
ON [Sales].[Orders] ([CustomerID], [OrderDate])
INCLUDE ([TotalAmount], [Status])
-- Impact: 85%, Seeks: 15000
```

**Integration:** Results appear in Weekly Report under "Index Recommendations" section.

### 6. Query Store Integration
**File:** `collectors/collect_query_store.sql`

Collects query performance metrics from Query Store:

| Metric | Description |
|--------|-------------|
| TotalCpuMs | Aggregate CPU across executions |
| AvgDurationMs | Average execution time |
| TotalLogicalReads | Total pages read |
| ExecutionCount | Number of executions |
| StalePlans | Non-forced plans for this query |

**Regressions:** Automatically detects queries that got 2x slower compared to historical average.

---

## Weekly Report Enhancements

The weekly deep dive now includes:

### New Sections

1. **Index Recommendations**
   - Missing indexes with impact scores
   - CREATE INDEX scripts ready to run
   - Filtered by high impact (>30%) and significant seeks (>10)

2. **Top Queries by CPU**
   - Aggregated CPU consumption
   - Sorted by total impact

3. **Top Queries by Duration**
   - Slowest queries
   - Average vs total duration

4. **Top Queries by I/O**
   - Most read-intensive queries
   - Logical reads breakdown

---

## Schema Changes

**New Tables:**
- `monitor.LiveSessionsHistory`
- `monitor.IndexRecommendations`
- `monitor.QueryStoreHistory`
- `monitor.QueryRegressions`
- `monitor.WaitDatabaseHistory`

**Migration Script:** `install/08-phase1-3-migration.sql`

---

## Installation

Run in order:

1. Schema migration (creates tables):
```sql
SQLCMD -S server -d SQLHealthMonitor -i install/08-phase1-3-migration.sql
```

2. Install collectors:
```sql
SQLCMD -S server -d SQLHealthMonitor -i collectors/collect_live_sessions.sql
SQLCMD -S server -d SQLHealthMonitor -i collectors/collect_index_recommendations.sql
SQLCMD -S server -d SQLHealthMonitor -i collectors/collect_query_store.sql
```

---

## Configuration

### Index Recommendations Schedule
By default, index recommendations run daily (expensive operation). Adjust in SQL Agent:

```sql
-- Change to weekly if needed
EXEC [monitor].[usp_Collect_IndexRecommendations];
```

### Query Store Collection
Query Store data is collected every 15 minutes. Requires:
- Query Store enabled on each database
- Sufficient storage for Query Store retention

---

## Next Steps (Phase 4+)

Potential future enhancements:
- Webhook notifications for critical events
- Power BI integration for dashboards
- Automated index implementation with safety checks
- Query plan analysis and optimization hints

---

*Version: 1.0.0*
*Last Updated: 2026-10-01*
