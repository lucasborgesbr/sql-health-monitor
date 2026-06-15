/*
    SQL Health Monitor - Default Configuration
    Inserts default settings, thresholds, and language strings.
    
    Run after: 00-create-schema.sql
    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

----------------------------------------------------------------------
-- DEFAULT SETTINGS
----------------------------------------------------------------------

-- Clear existing (for re-runs)
DELETE FROM [monitor].[Settings];
GO

INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType) VALUES
-- General
('General', 'Language', 'en', 'Report language: en or ptbr', 'string'),
('General', 'ServerName', @@SERVERNAME, 'Server identifier for reports', 'string'),
('General', 'MonitoringEnabled', '1', 'Master switch for all monitoring', 'bool'),

-- Email
('Email', 'ProfileName',       'DBA_Mail',        'Database Mail profile name (must exist in msdb)', 'string'),
('Email', 'Recipients',        'dba@company.com',  'Default recipients for all reports (semicolon-separated)', 'string'),
('Email', 'Recipients_Daily',  '',                 'Override recipients for daily report. Falls back to Email.Recipients if empty.', 'string'),
('Email', 'Recipients_Weekly', '',                 'Override recipients for weekly report. Falls back to Email.Recipients if empty.', 'string'),
('Email', 'Recipients_Alert',  '',                 'Override recipients for alert emails. Falls back to Email.Recipients if empty.', 'string'),
('Email', 'CcRecipients',      '',                 'CC recipients (all report types)', 'string'),

-- Schedule
('Schedule', 'DailyReportTime', '07:00', 'Time to send daily report (HH:mm)', 'string'),
('Schedule', 'WeeklyReportDay', 'Monday', 'Day for weekly deep dive', 'string'),
('Schedule', 'WeeklyReportTime', '08:00', 'Time for weekly report (HH:mm)', 'string'),

-- Retention
('Retention', 'DataRetentionDays', '90', 'Days to keep collected metrics', 'int'),
('Retention', 'AlertRetentionDays', '365', 'Days to keep alert history', 'int'),
('Retention', 'ReportRetentionDays', '90', 'Days to keep report history', 'int'),

-- Features (enable/disable specific collectors)
('Features', 'CollectCPU', '1', 'Enable CPU collection', 'bool'),
('Features', 'CollectMemory', '1', 'Enable memory collection', 'bool'),
('Features', 'CollectDisk', '1', 'Enable disk collection', 'bool'),
('Features', 'CollectWaits', '1', 'Enable wait stats collection', 'bool'),
('Features', 'CollectBlocking', '1', 'Enable blocking detection', 'bool'),
('Features', 'CollectAG', '1', 'Enable AG health collection', 'bool'),
('Features', 'CollectCDC', '1', 'Enable CDC health collection', 'bool'),
('Features', 'CollectTopQueries', '1', 'Enable top queries collection', 'bool'),
('Features', 'CollectIndexHealth', '1', 'Enable index health collection', 'bool'),
('Features', 'CollectBackups', '1', 'Enable backup status collection', 'bool'),
('Features', 'CollectJobs', '1', 'Enable job history collection', 'bool'),
('Features', 'CollectTempDB', '1', 'Enable TempDB collection', 'bool'),
('Features', 'CollectFileGrowth', '1', 'Enable file growth tracking', 'bool'),
('Features', 'CollectErrorLog', '1', 'Enable error log collection', 'bool'),
('Features', 'CollectLogGrowth', '1', 'Enable log growth tracking', 'bool'),
('Features', 'CollectDeadlocks', '1', 'Enable deadlock detection', 'bool'),
('Features', 'CollectUptimeTracker', '1', 'Enable uptime SLA tracking', 'bool');
GO

----------------------------------------------------------------------
-- DEFAULT THRESHOLDS
----------------------------------------------------------------------

DELETE FROM [monitor].[Thresholds];
GO

INSERT INTO [monitor].[Thresholds] (MetricName, WarningValue, CriticalValue, Operator, Description) VALUES
-- CPU
('CPU_SqlPct', 80, 95, '>=', 'SQL Server CPU utilization percentage'),
('CPU_SystemPct', 90, 98, '>=', 'Total system CPU utilization'),

-- Memory
('Memory_PLE', 300, 100, '<=', 'Page Life Expectancy (seconds)'),
('Memory_GrantsPending', 1, 5, '>=', 'Memory grants pending'),
('Memory_BufferHitRatio', 95, 90, '<=', 'Buffer cache hit ratio percentage'),

-- Disk
('Disk_UsedPct', 85, 95, '>=', 'Disk space used percentage'),
('Disk_ReadLatencyMs', 20, 50, '>=', 'Average read latency (ms)'),
('Disk_WriteLatencyMs', 20, 50, '>=', 'Average write latency (ms)'),

-- AG
('AG_SecondsBehind', 30, 120, '>=', 'Seconds behind primary replica'),
('AG_LogSendQueueMB', 500, 2000, '>=', 'Log send queue size (MB)'),
('AG_RedoQueueMB', 500, 2000, '>=', 'Redo queue size (MB)'),

-- CDC
('CDC_LatencySeconds', 300, 900, '>=', 'CDC capture latency (seconds)'),

-- Blocking
('Blocking_DurationSec', 30, 120, '>=', 'Blocking duration threshold (seconds)'),

-- Backups
('Backup_FullHours', 25, 48, '>=', 'Hours since last full backup'),
('Backup_LogHours', 1, 4, '>=', 'Hours since last log backup'),

-- TempDB
('TempDB_UsedPct', 70, 90, '>=', 'TempDB space used percentage'),

-- Jobs
('Jobs_FailedCount', 1, 3, '>=', 'Failed jobs in last collection'),

-- Uptime/SLA
('SLA_UptimePercentage', 99.5, 99.0, '<', 'Uptime percentage threshold'),
('SLA_DowntimeMinutes', 60, 1440, '>=', 'Downtime threshold (minutes)'),
('SLA_IncidentResponseTime', 60, 240, '>=', 'Incident response time threshold (minutes)');
GO

----------------------------------------------------------------------
-- LANGUAGE STRINGS (EN)
----------------------------------------------------------------------

DELETE FROM [monitor].[Languages];
GO

INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
-- Report headers
('en', 'report.daily.title', 'Daily SQL Health Report'),
('en', 'report.daily.subtitle', 'Server: {server} | Date: {date}'),
('en', 'report.weekly.title', 'Weekly SQL Health Deep Dive'),
('en', 'report.weekly.subtitle', 'Server: {server} | Week: {week}'),

-- Section titles
('en', 'section.summary', 'Executive Summary'),
('en', 'section.cpu', 'CPU Utilization'),
('en', 'section.memory', 'Memory Health'),
('en', 'section.disk', 'Disk Space & I/O'),
('en', 'section.waits', 'Wait Statistics'),
('en', 'section.blocking', 'Blocking Events'),
('en', 'section.ag', 'Availability Groups'),
('en', 'section.cdc', 'CDC Health'),
('en', 'section.queries', 'Top Queries'),
('en', 'section.indexes', 'Index Health'),
('en', 'section.backups', 'Backup Status'),
('en', 'section.jobs', 'SQL Agent Jobs'),
('en', 'section.tempdb', 'TempDB Usage'),
('en', 'section.growth', 'Database Growth'),
('en', 'section.errors', 'Error Log'),
('en', 'section.recommendations', 'Recommendations'),

-- Status labels
('en', 'status.healthy', 'Healthy'),
('en', 'status.warning', 'Warning'),
('en', 'status.critical', 'Critical'),
('en', 'status.unknown', 'Unknown'),

-- Alert messages
('en', 'alert.cpu.high', 'CPU utilization at {value}% (threshold: {threshold}%)'),
('en', 'alert.memory.ple_low', 'Page Life Expectancy at {value}s (threshold: {threshold}s)'),
('en', 'alert.disk.space', 'Drive {drive} at {value}% used (threshold: {threshold}%)'),
('en', 'alert.ag.behind', 'Replica {replica} is {value}s behind primary (threshold: {threshold}s)'),
('en', 'alert.backup.old', 'Database {db}: last full backup {value}h ago (threshold: {threshold}h)'),
('en', 'alert.blocking', 'Blocking detected: SPID {blocker} blocking {blocked} for {value}s'),

-- PT-BR
('ptbr', 'report.daily.title', 'Relatório Diário de Saúde SQL'),
('ptbr', 'report.daily.subtitle', 'Servidor: {server} | Data: {date}'),
('ptbr', 'report.weekly.title', 'Análise Semanal de Saúde SQL'),
('ptbr', 'report.weekly.subtitle', 'Servidor: {server} | Semana: {week}'),

('ptbr', 'section.summary', 'Resumo Executivo'),
('ptbr', 'section.cpu', 'Utilização de CPU'),
('ptbr', 'section.memory', 'Saúde da Memória'),
('ptbr', 'section.disk', 'Espaço em Disco & I/O'),
('ptbr', 'section.waits', 'Estatísticas de Espera'),
('ptbr', 'section.blocking', 'Eventos de Bloqueio'),
('ptbr', 'section.ag', 'Grupos de Disponibilidade'),
('ptbr', 'section.cdc', 'Saúde do CDC'),
('ptbr', 'section.queries', 'Top Queries'),
('ptbr', 'section.indexes', 'Saúde dos Índices'),
('ptbr', 'section.backups', 'Status de Backup'),
('ptbr', 'section.jobs', 'Jobs do SQL Agent'),
('ptbr', 'section.tempdb', 'Uso do TempDB'),
('ptbr', 'section.growth', 'Crescimento de Bancos'),
('ptbr', 'section.errors', 'Log de Erros'),
('ptbr', 'section.recommendations', 'Recomendações'),

('ptbr', 'status.healthy', 'Saudável'),
('ptbr', 'status.warning', 'Atenção'),
('ptbr', 'status.critical', 'Crítico'),
('ptbr', 'status.unknown', 'Desconhecido'),

('ptbr', 'alert.cpu.high', 'Utilização de CPU em {value}% (limite: {threshold}%)'),
('ptbr', 'alert.memory.ple_low', 'Page Life Expectancy em {value}s (limite: {threshold}s)'),
('ptbr', 'alert.disk.space', 'Drive {drive} em {value}% usado (limite: {threshold}%)'),
('ptbr', 'alert.ag.behind', 'Réplica {replica} está {value}s atrás da primária (limite: {threshold}s)'),
('ptbr', 'alert.backup.old', 'Banco {db}: último backup full há {value}h (limite: {threshold}h)'),
('ptbr', 'alert.blocking', 'Bloqueio detectado: SPID {blocker} bloqueando {blocked} por {value}s');
GO

PRINT '✓ Default configuration loaded.';
PRINT '✓ Thresholds configured.';
PRINT '✓ Language strings loaded (EN + PT-BR).';
GO
