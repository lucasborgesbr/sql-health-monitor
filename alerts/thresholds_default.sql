-- thresholds_default.sql - Default alert thresholds
-- Updated: 2026-06-02 for release-ready version

USE [SQLHealthMonitor];
GO

-- Insert default threshold values for all monitored metrics
INSERT INTO [monitor].[Thresholds] (MetricName, WarningValue, CriticalValue, Operator, Description) VALUES
-- CPU Metrics
('CPU_Usage_Pct', 80, 95, '>=', 'CPU usage percentage'),
('CPU_SQL_Pct', 85, 95, '>=', 'SQL Server CPU usage percentage'),
('CPU_System_Pct', 90, 98, '>=', 'System CPU usage percentage'),

-- Memory Metrics
('Memory_Total_Pct', 85, 95, '>=', 'Total memory usage percentage'),
('Memory_BufferCache_Pct', 90, 98, '>=', 'Buffer cache usage percentage'),
('Memory_Grants_Pending', 10, 50, '>=', 'Number of memory grants pending'),
('Memory_PageLifeExpectancy_Min', 600, 300, '<=', 'Page life expectancy in minutes'),

-- Disk Metrics
('Disk_Space_Pct', 85, 95, '>=', 'Disk space usage percentage'),
('Disk_ReadLatency_Ms', 50, 100, '>=', 'Average disk read latency in ms'),
('Disk_WriteLatency_Ms', 50, 100, '>=', 'Average disk write latency in ms'),

-- Wait Statistics
('Wait_PageIo_Sec', 1000, 5000, '>=', 'PAGEIOLATCH wait time in seconds'),
('Wait_SqlQueue_Sec', 500, 2000, '>=', 'SOS_SCHEDULER_YIELD wait time in seconds'),
('Wait_Latch_Sec', 1000, 3000, '>=', 'Latch wait time in seconds'),

-- Blocking
('Blocking_Sessions', 5, 20, '>=', 'Number of blocking sessions'),
('Blocking_Duration_Sec', 60, 300, '>=', 'Blocking duration in seconds'),

-- Backup
('Backup_Hours_SinceFull', 24, 48, '>=', 'Hours since last full backup'),
('Backup_Hours_SinceDiff', 12, 24, '>=', 'Hours since last differential backup'),
('Backup_Failure_Recent', 1, 3, '>=', 'Number of recent backup failures'),

-- Availability Groups
('AG_SecondsBehindPrimary', 30, 120, '>=', 'Seconds behind primary replica'),
('AG_LogSendQueue_KB', 102400, 1048576, '>=', 'Log send queue size in KB'),
('AG_RedoQueue_KB', 102400, 1048576, '>=', 'Redo queue size in KB'),

-- CDC
('CDC_Latency_Seconds', 300, 1800, '>=', 'CDC latency in seconds'),
('CDC_Retention_Minutes', 10080, 20160, '<=', 'CDC retention period in minutes'),

-- Index Health
('Index_Fragmentation_Pct', 30, 60, '>=', 'Index fragmentation percentage'),
('Index_PageCount_Threshold', 1000, 5000, '>=', 'Large index page count threshold'),

-- SQL Agent Jobs
('Job_Failure_Count', 1, 3, '>=', 'Number of failed jobs in last 24 hours'),
('Job_Retry_Count', 2, 5, '>=', 'Number of job retries in last 24 hours'),

-- TempDB
('TempDB_Usage_Pct', 70, 90, '>=', 'TempDB usage percentage'),
('TempDB_VersionStore_MB', 1024, 2048, '>=', 'TempDB version store size in MB'),

-- Deadlocks
('Deadlock_Count_Hour', 1, 5, '>=', 'Number of deadlocks per hour'),
('Deadlock_LockWait_Sec', 10, 30, '>=', 'Average deadlock wait time in seconds');
GO

PRINT '✓ Default thresholds loaded successfully.';
GO
