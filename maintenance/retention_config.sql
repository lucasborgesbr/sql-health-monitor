/*
    SQL Health Monitor - Retention Configuration
    Default INSERT statements for retention settings.
    
    These settings control how long data is kept by usp_PurgeHistoricalData.
    Baselines are NEVER purged (kept forever for historical comparison).
    
    Schema: [monitor]
    Compatibility: SQL Server 2016+
    Author: Lucas Allan Borges
*/

USE [SQLHealthMonitor];
GO

-- ============================================================
-- RETENTION SETTINGS
-- ============================================================

-- Raw collector data: 30 days
IF NOT EXISTS (SELECT 1 FROM [monitor].[Settings] WHERE Category = 'Retention' AND SettingName = 'RawDataRetentionDays')
    INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
    VALUES ('Retention', 'RawDataRetentionDays', '30', 
        'Days to keep raw collector data (CPU, Memory, Disk, Waits, Blocking, AG, CDC, Queries, Index, Backup, Jobs, TempDB, FileGrowth, ErrorLog)', 'int');

-- Daily summaries: 90 days
IF NOT EXISTS (SELECT 1 FROM [monitor].[Settings] WHERE Category = 'Retention' AND SettingName = 'DailySummaryRetentionDays')
    INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
    VALUES ('Retention', 'DailySummaryRetentionDays', '90', 
        'Days to keep daily summary/aggregated data', 'int');

-- Weekly summaries: 365 days
IF NOT EXISTS (SELECT 1 FROM [monitor].[Settings] WHERE Category = 'Retention' AND SettingName = 'WeeklySummaryRetentionDays')
    INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
    VALUES ('Retention', 'WeeklySummaryRetentionDays', '365', 
        'Days to keep weekly summary/aggregated data', 'int');

-- Alert history: 365 days
IF NOT EXISTS (SELECT 1 FROM [monitor].[Settings] WHERE Category = 'Retention' AND SettingName = 'AlertRetentionDays')
    INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
    VALUES ('Retention', 'AlertRetentionDays', '365', 
        'Days to keep alert history records', 'int');

-- Report history: 90 days
IF NOT EXISTS (SELECT 1 FROM [monitor].[Settings] WHERE Category = 'Retention' AND SettingName = 'ReportRetentionDays')
    INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
    VALUES ('Retention', 'ReportRetentionDays', '90', 
        'Days to keep report send history', 'int');

-- Baseline anomalies: 90 days
IF NOT EXISTS (SELECT 1 FROM [monitor].[Settings] WHERE Category = 'Retention' AND SettingName = 'AnomalyRetentionDays')
    INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
    VALUES ('Retention', 'AnomalyRetentionDays', '90', 
        'Days to keep baseline anomaly detection records', 'int');

-- Baselines: FOREVER (documented, no setting needed - never purged)
-- Note: Old inactive baselines are trimmed to last 12 per metric during purge,
-- but active baselines and recent history are always preserved.

-- ============================================================
-- PURGE BATCH SIZE SETTING
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM [monitor].[Settings] WHERE Category = 'Retention' AND SettingName = 'PurgeBatchSize')
    INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
    VALUES ('Retention', 'PurgeBatchSize', '10000', 
        'Number of rows to delete per batch during purge (prevents log bloat)', 'int');

-- Max purge duration
IF NOT EXISTS (SELECT 1 FROM [monitor].[Settings] WHERE Category = 'Retention' AND SettingName = 'PurgeMaxDurationMinutes')
    INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
    VALUES ('Retention', 'PurgeMaxDurationMinutes', '30', 
        'Maximum runtime for purge procedure in minutes (safety limit)', 'int');

GO

PRINT '✓ Retention configuration settings inserted.';
PRINT '  → RawDataRetentionDays: 30';
PRINT '  → DailySummaryRetentionDays: 90';
PRINT '  → WeeklySummaryRetentionDays: 365';
PRINT '  → AlertRetentionDays: 365';
PRINT '  → ReportRetentionDays: 90';
PRINT '  → AnomalyRetentionDays: 90';
PRINT '  → Baselines: FOREVER';
GO
