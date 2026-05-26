/*
    SQL Health Monitor - Default Threshold Values
    Inserts default alert thresholds for all monitored metrics.
    
    Operator logic:
      '>=' = alert fires when value >= threshold (high is bad)
      '<=' = alert fires when value <= threshold (low is bad)
    
    Customize values after installation to match your environment.
    Compatibility: SQL Server 2016+
*/

USE [DBA_Monitor];
GO

-- Clear existing defaults (safe for fresh install or reset)
DELETE FROM [monitor].[Thresholds];
GO

----------------------------------------------------------------------
-- CPU THRESHOLDS
----------------------------------------------------------------------
INSERT INTO [monitor].[Thresholds] (MetricName, WarningValue, CriticalValue, Operator, IsEnabled, Description)
VALUES
    ('CPU_SqlPct',          80.00, 95.00, '>=', 1, 'SQL Server CPU utilization percentage'),
    ('CPU_SystemPct',       85.00, 95.00, '>=', 1, 'Total system CPU utilization percentage');
GO

----------------------------------------------------------------------
-- MEMORY THRESHOLDS
----------------------------------------------------------------------
INSERT INTO [monitor].[Thresholds] (MetricName, WarningValue, CriticalValue, Operator, IsEnabled, Description)
VALUES
    ('Memory_PLE',          600.00, 300.00, '<=', 1, 'Page Life Expectancy in seconds (low = memory pressure)'),
    ('Memory_GrantsPending', 2.00,   5.00,  '>=', 1, 'Pending memory grants (queries waiting for memory)'),
    ('Memory_BufferHitRatio', 95.00, 90.00, '<=', 1, 'Buffer cache hit ratio percentage');
GO

----------------------------------------------------------------------
-- DISK THRESHOLDS
----------------------------------------------------------------------
INSERT INTO [monitor].[Thresholds] (MetricName, WarningValue, CriticalValue, Operator, IsEnabled, Description)
VALUES
    ('Disk_UsedPct',        85.00, 95.00, '>=', 1, 'Disk space used percentage'),
    ('Disk_ReadLatencyMs',  20.00, 50.00, '>=', 1, 'Average read latency in milliseconds'),
    ('Disk_WriteLatencyMs', 20.00, 50.00, '>=', 1, 'Average write latency in milliseconds');
GO

----------------------------------------------------------------------
-- AVAILABILITY GROUP THRESHOLDS
----------------------------------------------------------------------
INSERT INTO [monitor].[Thresholds] (MetricName, WarningValue, CriticalValue, Operator, IsEnabled, Description)
VALUES
    ('AG_SecondsBehind',    30.00,  120.00, '>=', 1, 'Seconds behind primary replica'),
    ('AG_LogSendQueueMB',  500.00, 2000.00, '>=', 1, 'Log send queue size in MB'),
    ('AG_RedoQueueMB',     500.00, 2000.00, '>=', 1, 'Redo queue size in MB');
GO

----------------------------------------------------------------------
-- CDC THRESHOLDS
----------------------------------------------------------------------
INSERT INTO [monitor].[Thresholds] (MetricName, WarningValue, CriticalValue, Operator, IsEnabled, Description)
VALUES
    ('CDC_LatencySeconds',  300.00, 900.00, '>=', 1, 'CDC capture latency in seconds');
GO

----------------------------------------------------------------------
-- BLOCKING THRESHOLDS
----------------------------------------------------------------------
INSERT INTO [monitor].[Thresholds] (MetricName, WarningValue, CriticalValue, Operator, IsEnabled, Description)
VALUES
    ('Blocking_DurationSec', 30.00, 120.00, '>=', 1, 'Blocking duration in seconds');
GO

----------------------------------------------------------------------
-- BACKUP THRESHOLDS
----------------------------------------------------------------------
INSERT INTO [monitor].[Thresholds] (MetricName, WarningValue, CriticalValue, Operator, IsEnabled, Description)
VALUES
    ('Backup_FullHours',    25.00, 48.00, '>=', 1, 'Hours since last full backup'),
    ('Backup_LogHours',     2.00,   4.00, '>=', 1, 'Hours since last log backup');
GO

----------------------------------------------------------------------
-- TEMPDB THRESHOLDS
----------------------------------------------------------------------
INSERT INTO [monitor].[Thresholds] (MetricName, WarningValue, CriticalValue, Operator, IsEnabled, Description)
VALUES
    ('TempDB_UsedPct',      75.00, 90.00, '>=', 1, 'TempDB space used percentage');
GO

----------------------------------------------------------------------
-- JOB THRESHOLDS
----------------------------------------------------------------------
INSERT INTO [monitor].[Thresholds] (MetricName, WarningValue, CriticalValue, Operator, IsEnabled, Description)
VALUES
    ('Jobs_FailedCount',    1.00, 3.00, '>=', 1, 'Number of failed SQL Agent jobs');
GO

----------------------------------------------------------------------
-- DEADLOCK THRESHOLDS
----------------------------------------------------------------------
INSERT INTO [monitor].[Thresholds] (MetricName, WarningValue, CriticalValue, Operator, IsEnabled, Description)
VALUES
    ('Deadlocks_Count',     3.00, 10.00, '>=', 1, 'Deadlock count in last collection window');
GO

----------------------------------------------------------------------
-- DATABASE GROWTH THRESHOLDS
----------------------------------------------------------------------
INSERT INTO [monitor].[Thresholds] (MetricName, WarningValue, CriticalValue, Operator, IsEnabled, Description)
VALUES
    ('DbGrowth_DataPctWeek',  20.00, 50.00, '>=', 1, 'Data file growth percentage over 7 days'),
    ('DbGrowth_LogPctWeek',   30.00, 50.00, '>=', 1, 'Log file growth percentage over 7 days');
GO

PRINT '✓ Default thresholds inserted successfully.';
GO
