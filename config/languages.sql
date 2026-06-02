-- languages.sql - Multi-language support configuration (EN + PT-BR)
-- Updated: 2026-06-02 for release-ready version

USE [SQLHealthMonitor];
GO

-- Insert English language strings
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
('en', 'HealthStatus_OK', 'OK'),
('en', 'HealthStatus_Warning', 'Warning'),
('en', 'HealthStatus_Critical', 'Critical'),
('en', 'HealthStatus_Alert', 'Alert'),
('en', 'MonitorTitle_Daily', 'Daily Health Report'),
('en', 'MonitorTitle_Weekly', 'Weekly Deep Dive'),
('en', 'MonitorTitle_Alert', 'Health Alert'),
('en', 'Metric_CPU', 'CPU Usage'),
('en', 'Metric_Memory', 'Memory Usage'),
('en', 'Metric_Disk', 'Disk Space'),
('en', 'Metric_Backup', 'Backup Status'),
('en', 'Metric_AG', 'Availability Group'),
('en', 'Metric_WaitStats', 'Wait Statistics'),
('en', 'Metric_Blocking', 'Blocking Sessions'),
('en', 'Metric_Index', 'Index Health'),
('en', 'Metric_Jobs', 'SQL Agent Jobs'),
('en', 'Metric_TempDB', 'TempDB Usage'),
('en', 'Metric_Deadlocks', 'Deadlocks');
GO

-- Insert Portuguese (Brazil) language strings
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
('ptbr', 'HealthStatus_OK', 'OK'),
('ptbr', 'HealthStatus_Warning', 'Atenção'),
('ptbr', 'HealthStatus_Critical', 'Crítico'),
('ptbr', 'HealthStatus_Alert', 'Alerta'),
('ptbr', 'MonitorTitle_Daily', 'Relatório Diário de Saúde'),
('ptbr', 'MonitorTitle_Weekly', 'Análise Semanal Profunda'),
('ptbr', 'MonitorTitle_Alert', 'Alerta de Saúde'),
('ptbr', 'Metric_CPU', 'Uso de CPU'),
('ptbr', 'Metric_Memory', 'Uso de Memória'),
('ptbr', 'Metric_Disk', 'Espaço em Disco'),
('ptbr', 'Metric_Backup', 'Status do Backup'),
('ptbr', 'Metric_AG', 'Grupo de Disponibilidade'),
('ptbr', 'Metric_WaitStats', 'Estatísticas de Espera'),
('ptbr', 'Metric_Blocking', 'Sessões Bloqueadas'),
('ptbr', 'Metric_Index', 'Saúde de Índices'),
('ptbr', 'Metric_Jobs', 'Jobs do SQL Agent'),
('ptbr', 'Metric_TempDB', 'Uso do TempDB'),
('ptbr', 'Metric_Deadlocks', 'Deadlocks');
GO

PRINT '✓ Language packs loaded successfully.';
GO
