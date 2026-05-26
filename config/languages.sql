/*
    SQL Health Monitor - Language Strings (i18n)
    Multi-language support for EN and PT-BR.
    
    String keys follow the pattern: Section.Element
    Used by report generators and alert engine.
    
    Compatibility: SQL Server 2016+
*/

USE [DBA_Monitor];
GO

-- Clear existing language strings (safe for fresh install or reset)
DELETE FROM [monitor].[Languages];
GO

----------------------------------------------------------------------
-- ENGLISH (EN)
----------------------------------------------------------------------

-- Report Titles
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
    ('en', 'Report.DailyTitle',         'Daily SQL Health Report'),
    ('en', 'Report.WeeklyTitle',        'Weekly SQL Deep Dive Report'),
    ('en', 'Report.AlertTitle',         'SQL Health Monitor Alert'),
    ('en', 'Report.GeneratedAt',        'Generated'),
    ('en', 'Report.Period',             'Period'),
    ('en', 'Report.Server',             'Server');
GO

-- Section Headers
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
    ('en', 'Section.Summary',           'Executive Summary'),
    ('en', 'Section.CPU',               'CPU Utilization'),
    ('en', 'Section.Memory',            'Memory Health'),
    ('en', 'Section.Disk',              'Disk Space & I/O'),
    ('en', 'Section.AG',                'Availability Groups'),
    ('en', 'Section.CDC',               'CDC Health'),
    ('en', 'Section.Waits',             'Top Waits'),
    ('en', 'Section.Blocking',          'Blocking Events'),
    ('en', 'Section.Backups',           'Backup Status'),
    ('en', 'Section.Jobs',              'SQL Agent Jobs'),
    ('en', 'Section.TopQueries',        'Top Resource Queries'),
    ('en', 'Section.IndexHealth',       'Index Health'),
    ('en', 'Section.TempDB',            'TempDB Usage'),
    ('en', 'Section.LogGrowth',         'Log File Growth'),
    ('en', 'Section.ErrorLog',          'Error Log Highlights'),
    ('en', 'Section.Deadlocks',         'Deadlocks'),
    ('en', 'Section.DbGrowth',          'Database Growth'),
    ('en', 'Section.Recommendations',   'Recommendations'),
    ('en', 'Section.Trends',            'Trends & Capacity'),
    ('en', 'Section.WeekComparison',    'Week-over-Week Comparison');
GO

-- Status Labels
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
    ('en', 'Status.Healthy',            'All Systems Healthy'),
    ('en', 'Status.Warning',            'Attention Required'),
    ('en', 'Status.Critical',           'Critical Issues Detected'),
    ('en', 'Status.Unknown',            'Status Unknown'),
    ('en', 'Status.OK',                 'OK'),
    ('en', 'Status.Degraded',           'Degraded'),
    ('en', 'Status.Down',              'Down');
GO

-- Severity Labels
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
    ('en', 'Severity.Critical',         'Critical'),
    ('en', 'Severity.Warning',          'Warning'),
    ('en', 'Severity.Info',             'Info'),
    ('en', 'Severity.High',             'High'),
    ('en', 'Severity.Medium',           'Medium'),
    ('en', 'Severity.Low',              'Low');
GO

-- Table Headers
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
    ('en', 'Table.Database',            'Database'),
    ('en', 'Table.Metric',              'Metric'),
    ('en', 'Table.Value',               'Value'),
    ('en', 'Table.Threshold',           'Threshold'),
    ('en', 'Table.Status',              'Status'),
    ('en', 'Table.Duration',            'Duration'),
    ('en', 'Table.WaitType',            'Wait Type'),
    ('en', 'Table.TotalMs',             'Total (ms)'),
    ('en', 'Table.DeltaMs',             'Delta (ms)'),
    ('en', 'Table.Full',                'Full'),
    ('en', 'Table.Diff',                'Diff'),
    ('en', 'Table.Log',                 'Log'),
    ('en', 'Table.LastBackup',          'Last Backup'),
    ('en', 'Table.HoursAgo',            'Hours Ago'),
    ('en', 'Table.JobName',             'Job Name'),
    ('en', 'Table.LastRun',             'Last Run'),
    ('en', 'Table.Result',              'Result'),
    ('en', 'Table.Index',               'Index'),
    ('en', 'Table.Fragmentation',       'Fragmentation'),
    ('en', 'Table.Recommendation',      'Recommendation'),
    ('en', 'Table.Priority',            'Priority'),
    ('en', 'Table.Impact',              'Impact'),
    ('en', 'Table.Context',             'Context'),
    ('en', 'Table.Victim',              'Victim'),
    ('en', 'Table.Winner',              'Winner'),
    ('en', 'Table.Resources',           'Resources'),
    ('en', 'Table.SizeMB',              'Size (MB)'),
    ('en', 'Table.GrowthMB',            'Growth (MB)'),
    ('en', 'Table.GrowthPct',           'Growth (%)'),
    ('en', 'Table.Trend',               'Trend');
GO

-- Alert Messages
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
    ('en', 'Alert.Fired',               'Alert fired'),
    ('en', 'Alert.Resolved',            'Alert resolved'),
    ('en', 'Alert.Cooldown',            'Cooldown'),
    ('en', 'Alert.NoAlerts',            'No active alerts'),
    ('en', 'Alert.Acknowledged',        'Acknowledged');
GO

-- Recommendations
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
    ('en', 'Rec.IndexRebuild',          'Index fragmentation >90%% — rebuild recommended'),
    ('en', 'Rec.IndexReorg',            'Index fragmentation >30%% — reorganize recommended'),
    ('en', 'Rec.BackupOverdue',         'No full backup in over {0} hours — immediate backup recommended'),
    ('en', 'Rec.LogGrowth',             'Log file grew {0}%% in 7 days — investigate transaction log usage'),
    ('en', 'Rec.DiskSpace',             'Disk {0} at {1}%% capacity — plan expansion or cleanup'),
    ('en', 'Rec.HighCPU',               'Sustained CPU above {0}%% — review top queries'),
    ('en', 'Rec.MemoryPressure',        'PLE below {0}s — consider adding memory or optimizing queries'),
    ('en', 'Rec.AGLag',                 'AG replica {0} is {1}s behind — check network/redo throughput'),
    ('en', 'Rec.Deadlocks',             '{0} deadlocks detected — review locking patterns'),
    ('en', 'Rec.TempDBPressure',        'TempDB at {0}%% — check version store and temp table usage');
GO

-- Time/Period Labels
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
    ('en', 'Time.Last24h',              'Last 24 hours'),
    ('en', 'Time.Last7d',               'Last 7 days'),
    ('en', 'Time.Last30d',              'Last 30 days'),
    ('en', 'Time.Today',                'Today'),
    ('en', 'Time.ThisWeek',             'This Week'),
    ('en', 'Time.Hours',                'hours'),
    ('en', 'Time.Minutes',              'minutes'),
    ('en', 'Time.Seconds',              'seconds');
GO

----------------------------------------------------------------------
-- PORTUGUESE - BRAZIL (PTBR)
----------------------------------------------------------------------

-- Report Titles
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
    ('ptbr', 'Report.DailyTitle',       'Relatório Diário de Saúde SQL'),
    ('ptbr', 'Report.WeeklyTitle',      'Relatório Semanal de Análise SQL'),
    ('ptbr', 'Report.AlertTitle',       'Alerta SQL Health Monitor'),
    ('ptbr', 'Report.GeneratedAt',      'Gerado em'),
    ('ptbr', 'Report.Period',           'Período'),
    ('ptbr', 'Report.Server',           'Servidor');
GO

-- Section Headers
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
    ('ptbr', 'Section.Summary',         'Resumo Executivo'),
    ('ptbr', 'Section.CPU',             'Utilização de CPU'),
    ('ptbr', 'Section.Memory',          'Saúde da Memória'),
    ('ptbr', 'Section.Disk',            'Espaço em Disco & I/O'),
    ('ptbr', 'Section.AG',              'Grupos de Disponibilidade'),
    ('ptbr', 'Section.CDC',             'Saúde do CDC'),
    ('ptbr', 'Section.Waits',           'Principais Esperas'),
    ('ptbr', 'Section.Blocking',        'Eventos de Bloqueio'),
    ('ptbr', 'Section.Backups',         'Status de Backup'),
    ('ptbr', 'Section.Jobs',            'Jobs do SQL Agent'),
    ('ptbr', 'Section.TopQueries',      'Queries Mais Pesadas'),
    ('ptbr', 'Section.IndexHealth',     'Saúde dos Índices'),
    ('ptbr', 'Section.TempDB',          'Uso do TempDB'),
    ('ptbr', 'Section.LogGrowth',       'Crescimento de Log'),
    ('ptbr', 'Section.ErrorLog',        'Destaques do Error Log'),
    ('ptbr', 'Section.Deadlocks',       'Deadlocks'),
    ('ptbr', 'Section.DbGrowth',        'Crescimento de Bancos'),
    ('ptbr', 'Section.Recommendations', 'Recomendações'),
    ('ptbr', 'Section.Trends',          'Tendências & Capacidade'),
    ('ptbr', 'Section.WeekComparison',  'Comparativo Semanal');
GO

-- Status Labels
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
    ('ptbr', 'Status.Healthy',          'Todos os Sistemas Saudáveis'),
    ('ptbr', 'Status.Warning',          'Atenção Necessária'),
    ('ptbr', 'Status.Critical',         'Problemas Críticos Detectados'),
    ('ptbr', 'Status.Unknown',          'Status Desconhecido'),
    ('ptbr', 'Status.OK',               'OK'),
    ('ptbr', 'Status.Degraded',         'Degradado'),
    ('ptbr', 'Status.Down',             'Indisponível');
GO

-- Severity Labels
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
    ('ptbr', 'Severity.Critical',       'Crítico'),
    ('ptbr', 'Severity.Warning',        'Alerta'),
    ('ptbr', 'Severity.Info',           'Informativo'),
    ('ptbr', 'Severity.High',           'Alta'),
    ('ptbr', 'Severity.Medium',         'Média'),
    ('ptbr', 'Severity.Low',            'Baixa');
GO

-- Table Headers
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
    ('ptbr', 'Table.Database',          'Banco de Dados'),
    ('ptbr', 'Table.Metric',            'Métrica'),
    ('ptbr', 'Table.Value',             'Valor'),
    ('ptbr', 'Table.Threshold',         'Limite'),
    ('ptbr', 'Table.Status',            'Status'),
    ('ptbr', 'Table.Duration',          'Duração'),
    ('ptbr', 'Table.WaitType',          'Tipo de Espera'),
    ('ptbr', 'Table.TotalMs',           'Total (ms)'),
    ('ptbr', 'Table.DeltaMs',           'Delta (ms)'),
    ('ptbr', 'Table.Full',              'Full'),
    ('ptbr', 'Table.Diff',              'Diff'),
    ('ptbr', 'Table.Log',               'Log'),
    ('ptbr', 'Table.LastBackup',        'Último Backup'),
    ('ptbr', 'Table.HoursAgo',         'Horas Atrás'),
    ('ptbr', 'Table.JobName',           'Nome do Job'),
    ('ptbr', 'Table.LastRun',           'Última Execução'),
    ('ptbr', 'Table.Result',            'Resultado'),
    ('ptbr', 'Table.Index',             'Índice'),
    ('ptbr', 'Table.Fragmentation',     'Fragmentação'),
    ('ptbr', 'Table.Recommendation',    'Recomendação'),
    ('ptbr', 'Table.Priority',          'Prioridade'),
    ('ptbr', 'Table.Impact',            'Impacto'),
    ('ptbr', 'Table.Context',           'Contexto'),
    ('ptbr', 'Table.Victim',            'Vítima'),
    ('ptbr', 'Table.Winner',            'Vencedor'),
    ('ptbr', 'Table.Resources',         'Recursos'),
    ('ptbr', 'Table.SizeMB',            'Tamanho (MB)'),
    ('ptbr', 'Table.GrowthMB',          'Crescimento (MB)'),
    ('ptbr', 'Table.GrowthPct',         'Crescimento (%)'),
    ('ptbr', 'Table.Trend',             'Tendência');
GO

-- Alert Messages
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
    ('ptbr', 'Alert.Fired',             'Alerta disparado'),
    ('ptbr', 'Alert.Resolved',          'Alerta resolvido'),
    ('ptbr', 'Alert.Cooldown',          'Cooldown'),
    ('ptbr', 'Alert.NoAlerts',          'Nenhum alerta ativo'),
    ('ptbr', 'Alert.Acknowledged',      'Reconhecido');
GO

-- Recommendations
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
    ('ptbr', 'Rec.IndexRebuild',        'Fragmentação do índice >90%% — rebuild recomendado'),
    ('ptbr', 'Rec.IndexReorg',          'Fragmentação do índice >30%% — reorganize recomendado'),
    ('ptbr', 'Rec.BackupOverdue',       'Sem backup full há mais de {0} horas — backup imediato recomendado'),
    ('ptbr', 'Rec.LogGrowth',           'Arquivo de log cresceu {0}%% em 7 dias — investigar uso do transaction log'),
    ('ptbr', 'Rec.DiskSpace',           'Disco {0} em {1}%% de capacidade — planejar expansão ou limpeza'),
    ('ptbr', 'Rec.HighCPU',             'CPU sustentada acima de {0}%% — revisar queries mais pesadas'),
    ('ptbr', 'Rec.MemoryPressure',      'PLE abaixo de {0}s — considerar mais memória ou otimizar queries'),
    ('ptbr', 'Rec.AGLag',               'Réplica AG {0} está {1}s atrasada — verificar rede/throughput de redo'),
    ('ptbr', 'Rec.Deadlocks',           '{0} deadlocks detectados — revisar padrões de lock'),
    ('ptbr', 'Rec.TempDBPressure',      'TempDB em {0}%% — verificar version store e uso de tabelas temporárias');
GO

-- Time/Period Labels
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue) VALUES
    ('ptbr', 'Time.Last24h',            'Últimas 24 horas'),
    ('ptbr', 'Time.Last7d',             'Últimos 7 dias'),
    ('ptbr', 'Time.Last30d',            'Últimos 30 dias'),
    ('ptbr', 'Time.Today',              'Hoje'),
    ('ptbr', 'Time.ThisWeek',           'Esta Semana'),
    ('ptbr', 'Time.Hours',              'horas'),
    ('ptbr', 'Time.Minutes',            'minutos'),
    ('ptbr', 'Time.Seconds',            'segundos');
GO

PRINT '✓ Language strings inserted for EN and PT-BR.';
GO
