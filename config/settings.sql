-- settings.sql - Default configuration settings
-- Updated: 2026-06-02 for release-ready version

USE [SQLHealthMonitor];
GO

-- Insert default settings
INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, DataType, Description) VALUES
-- General Settings
('General', 'MonitoringEnabled', '1', 'bit', 'Enable/disable monitoring collection'),
('General', 'MonitoringInterval', '2', 'int', 'Collection interval in minutes'),
('General', 'DataRetentionDays', '30', 'int', 'Keep data for N days'),
('General', 'EmailNotifications', '1', 'bit', 'Enable email notifications'),
('General', 'AlertCooldownMinutes', '60', 'int', 'Cooldown period between alerts'),

-- Alert Settings
('Alerts', 'EmailRecipients', 'dba-team@company.com', 'string', 'Comma-separated email addresses'),
('Alerts', 'CriticalThreshold', '1', 'int', 'Number of critical alerts before notification'),
('Alerts', 'WarningThreshold', '3', 'int', 'Number of warning alerts before notification'),
('Alerts', 'IncludeDetails', '1', 'bit', 'Include detailed information in alerts'),

-- Report Settings
('Reports', 'DailyReportEnabled', '1', 'bit', 'Enable daily health reports'),
('Reports', 'WeeklyReportEnabled', '1', 'bit', 'Enable weekly deep dive reports'),
('Reports', 'ReportLanguage', 'en', 'string', 'Report language (en, ptbr)'),
('Reports', 'ReportFormat', 'html', 'string', 'Report format (html, text)'),
('Reports', 'ReportTime', '06:00', 'string', 'Time to send daily reports'),

-- Performance Settings
('Performance', 'MaxCollectionThreads', '4', 'int', 'Maximum concurrent collection threads'),
('Performance', 'QueryTimeoutSeconds', '30', 'int', 'Timeout for collection queries'),
('Performance', 'BatchSize', '1000', 'int', 'Batch size for data insertion'),

-- Maintenance Settings
('Maintenance', 'AutoCleanupEnabled', '1', 'bit', 'Enable automatic data cleanup'),
('Maintenance', 'CleanupBatchSize', '10000', 'int', 'Batch size for cleanup operations'),
('Maintenance', 'MaintenanceTime', '02:00', 'string', 'Time for maintenance operations');
GO

PRINT '✓ Default settings loaded successfully.';
GO
