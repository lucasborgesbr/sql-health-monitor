/*
    SQL Health Monitor - Default Settings
    Inserts default configuration values for the monitoring system.
    
    Categories:
      - General: Server name, language, retention
      - Email: Database Mail profile, recipients, formatting
      - Schedule: Report timing
      - Collectors: Collection intervals and behavior
    
    Compatibility: SQL Server 2016+
*/

USE [DBA_Monitor];
GO

-- Clear existing settings (safe for fresh install or reset)
DELETE FROM [monitor].[Settings];
GO

----------------------------------------------------------------------
-- GENERAL SETTINGS
----------------------------------------------------------------------
INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
VALUES
    ('General', 'ServerName',       @@SERVERNAME,   'Display name for this server in reports', 'string'),
    ('General', 'Language',         'en',           'Report language: en or ptbr', 'string'),
    ('General', 'RetentionDays',    '90',           'Days to keep collected monitoring data', 'int'),
    ('General', 'TimeZoneOffset',   '+00:00',       'UTC offset for report timestamps (e.g., -03:00 for BRT)', 'string'),
    ('General', 'Environment',      'Production',   'Environment label: Production, Staging, Development', 'string'),
    ('General', 'Version',          '1.0.0',        'SQL Health Monitor version', 'string');
GO

----------------------------------------------------------------------
-- EMAIL SETTINGS
----------------------------------------------------------------------
INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
VALUES
    ('Email', 'ProfileName',        'DBA_Monitor',          'Database Mail profile name', 'string'),
    ('Email', 'Recipients',         'dba-team@company.com', 'Semicolon-separated email recipients', 'string'),
    ('Email', 'CcRecipients',       '',                     'CC recipients (optional)', 'string'),
    ('Email', 'SubjectPrefix',      '[SQL Monitor]',        'Email subject line prefix', 'string'),
    ('Email', 'IncludeServerName',  '1',                    'Include server name in subject', 'bool'),
    ('Email', 'MaxEmailSizeKB',     '512',                  'Maximum email body size in KB', 'int');
GO

----------------------------------------------------------------------
-- SCHEDULE SETTINGS
----------------------------------------------------------------------
INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
VALUES
    ('Schedule', 'DailyReportTime',     '07:00',    'Time to send daily health report (HH:mm, local)', 'string'),
    ('Schedule', 'WeeklyReportDay',     'Monday',   'Day of week for weekly deep dive report', 'string'),
    ('Schedule', 'WeeklyReportTime',    '08:00',    'Time to send weekly report (HH:mm, local)', 'string'),
    ('Schedule', 'CollectionInterval',  '5',        'Default collection interval in minutes', 'int'),
    ('Schedule', 'AlertCheckInterval',  '5',        'Alert evaluation interval in minutes', 'int');
GO

----------------------------------------------------------------------
-- COLLECTOR SETTINGS
----------------------------------------------------------------------
INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
VALUES
    ('Collectors', 'CPU_Enabled',           '1',    'Enable CPU collection', 'bool'),
    ('Collectors', 'Memory_Enabled',        '1',    'Enable memory collection', 'bool'),
    ('Collectors', 'Disk_Enabled',          '1',    'Enable disk collection', 'bool'),
    ('Collectors', 'WaitStats_Enabled',     '1',    'Enable wait stats collection', 'bool'),
    ('Collectors', 'Blocking_Enabled',      '1',    'Enable blocking detection', 'bool'),
    ('Collectors', 'AG_Enabled',            '1',    'Enable AG health collection', 'bool'),
    ('Collectors', 'CDC_Enabled',           '0',    'Enable CDC health collection (enable if using CDC)', 'bool'),
    ('Collectors', 'TopQueries_Enabled',    '1',    'Enable top queries collection', 'bool'),
    ('Collectors', 'IndexHealth_Enabled',   '1',    'Enable index health collection', 'bool'),
    ('Collectors', 'Backups_Enabled',       '1',    'Enable backup status collection', 'bool'),
    ('Collectors', 'Jobs_Enabled',          '1',    'Enable job history collection', 'bool'),
    ('Collectors', 'TempDB_Enabled',        '1',    'Enable TempDB monitoring', 'bool'),
    ('Collectors', 'LogGrowth_Enabled',     '1',    'Enable log growth tracking', 'bool'),
    ('Collectors', 'ErrorLog_Enabled',      '1',    'Enable error log scanning', 'bool'),
    ('Collectors', 'Deadlocks_Enabled',     '1',    'Enable deadlock collection', 'bool'),
    ('Collectors', 'DbGrowth_Enabled',      '1',    'Enable database growth tracking', 'bool'),
    ('Collectors', 'TopQueries_Count',      '20',   'Number of top queries to capture per collection', 'int'),
    ('Collectors', 'IndexHealth_MinPages',  '1000', 'Minimum page count to evaluate index fragmentation', 'int');
GO

----------------------------------------------------------------------
-- ALERT SETTINGS
----------------------------------------------------------------------
INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
VALUES
    ('Alerts', 'Enabled',               '1',    'Master switch for alert engine', 'bool'),
    ('Alerts', 'CooldownMinutes',       '30',   'Minutes before same alert can fire again', 'int'),
    ('Alerts', 'MaxAlertsPerHour',      '10',   'Maximum alerts per hour (spam protection)', 'int'),
    ('Alerts', 'CriticalToSMS',         '0',    'Send critical alerts via SMS (requires operator)', 'bool'),
    ('Alerts', 'IncludeRecommendation', '1',    'Include fix recommendation in alert email', 'bool');
GO

----------------------------------------------------------------------
-- REPORT SETTINGS
----------------------------------------------------------------------
INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
VALUES
    ('Reports', 'DailyEnabled',         '1',        'Enable daily health report', 'bool'),
    ('Reports', 'WeeklyEnabled',        '1',        'Enable weekly deep dive report', 'bool'),
    ('Reports', 'IncludeTopQueries',    '1',        'Include top queries section in daily report', 'bool'),
    ('Reports', 'IncludeIndexHealth',   '1',        'Include index health section in daily report', 'bool'),
    ('Reports', 'TopWaitsCount',        '10',       'Number of top waits to show in report', 'int'),
    ('Reports', 'DetailLevel',          'Standard', 'Report detail: Summary, Standard, Detailed', 'string');
GO

PRINT '✓ Default settings inserted successfully.';
PRINT '  → Update Email.Recipients and Email.ProfileName for your environment.';
PRINT '  → Set General.Language to ''ptbr'' for Portuguese reports.';
GO
