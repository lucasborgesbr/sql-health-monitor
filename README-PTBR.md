# SQL Health Monitor

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![SQL Server](https://img.shields.io/badge/SQL%20Server-2012%2B-green.svg)](https://www.microsoft.com/sql-server/)

> **English version:** [README.md](README.md)

## Visão Geral

O SQL Health Monitor é uma solução de monitoramento proativo para SQL Server construída inteiramente em T-SQL. Toda a coleta, alertas, relatórios e envio de email rodam dentro do SQL Server via SQL Agent Jobs e Database Mail — sem scripts externos, sem arquivos no servidor, sem dependências de PowerShell em runtime.

O PowerShell é usado **apenas** para deploy (`deploy/Install.ps1` executa os arquivos `.sql` via `sqlcmd`).

### Funcionalidades

- **18 Coletores** — CPU, memória, disco, waits, blocking, deadlocks, Availability Groups, CDC, top queries, saúde de índices, status de backups, histórico de jobs, TempDB, crescimento de log, crescimento de banco, error log, crescimento de arquivos, rastreamento de uptime SLA
- **Engine de Alertas** — thresholds configuráveis com período de cooldown e histórico
- **Engine de Baseline Estatística** — detecção de anomalias por desvio padrão
- **Relatórios HTML via Database Mail** — health check diário e análise semanal; HTML construído em procedures T-SQL, enviado via `sp_send_dbmail`
- **Rastreamento de Uptime / SLA** — classificação de incidentes, conformidade com SLA, relatórios mensais
- **Suporte Multi-Instância** — gerenciamento centralizado com detecção de drift
- **Multi-Idioma** — inglês e português (BR)

## Pré-requisitos

| Componente | Requisito |
|------------|-----------|
| SQL Server | 2012+ (otimizado para 2022) |
| SQL Server Agent | Obrigatório para os jobs agendados |
| Database Mail | Obrigatório para envio de relatórios e alertas |
| Permissões | `sysadmin` recomendado; `db_owner` mínimo |

> **PowerShell** (5.1+) e **sqlcmd** são necessários apenas durante o deploy. Nenhum módulo PowerShell (`dbatools`, `SqlServer`) é exigido.

## Instalação

### Opção 1 — Script de deploy (recomendado)

```powershell
# Windows auth
.\deploy\Install.ps1 -ServerInstance "SQLSERVER01"

# SQL auth
.\deploy\Install.ps1 -ServerInstance "SQLSERVER01" -SqlAuth -Login "sa" -Password "P@ss"
```

O script executa cada arquivo `.sql` em ordem via `sqlcmd` e reporta sucesso/falha por arquivo.

### Opção 2 — Manual (sqlcmd)

> **Importante:** Execute todos os comandos `sqlcmd` a partir do **diretório raiz do repositório**. Os scripts de instalação usam diretivas `:r` que resolvem caminhos relativos ao diretório de trabalho atual.

```bash
cd C:\caminho\para\sql-health-monitor

sqlcmd -S SQLSERVER01 -E -b -i install\00-create-schema.sql
sqlcmd -S SQLSERVER01 -E -b -i install\01-create-collectors.sql
sqlcmd -S SQLSERVER01 -E -b -i install\02-create-reports.sql
sqlcmd -S SQLSERVER01 -E -b -i install\03-create-alerts.sql
sqlcmd -S SQLSERVER01 -E -b -i install\04-create-jobs.sql
sqlcmd -S SQLSERVER01 -E -b -i install\05-configure.sql
sqlcmd -S SQLSERVER01 -E -b -i install\06-alert-history.sql
sqlcmd -S SQLSERVER01 -E -b -i install\07-baselines.sql
sqlcmd -S SQLSERVER01 -E -b -i install\08-extended-schema.sql
sqlcmd -S SQLSERVER01 -E -b -i install\09-uptime-tracker.sql

-- Coletores
sqlcmd -S SQLSERVER01 -E -b -i collectors\collect_cpu.sql
-- ... (repetir para cada arquivo em collectors/)

-- Relatórios (HTML builders primeiro, depois as procedures de relatório)
sqlcmd -S SQLSERVER01 -E -b -i reports\html_builder_daily.sql
sqlcmd -S SQLSERVER01 -E -b -i reports\html_builder_weekly.sql
sqlcmd -S SQLSERVER01 -E -b -i reports\daily_health_check.sql
sqlcmd -S SQLSERVER01 -E -b -i reports\weekly_deep_dive.sql
```

### Pós-instalação: configurar email

```sql
USE [SQLHealthMonitor];

-- Define o nome do perfil do Database Mail
UPDATE monitor.Settings SET SettingValue = 'SeuPerfilDeMail'
WHERE Category = 'Email' AND SettingName = 'ProfileName';

-- Define os destinatários
UPDATE monitor.Settings SET SettingValue = 'dba@empresa.com.br'
WHERE Category = 'Email' AND SettingName = 'Recipients';

-- Opcional: listas separadas por tipo de relatório
UPDATE monitor.Settings SET SettingValue = 'dba@empresa.com.br'
WHERE Category = 'Email' AND SettingName = 'Recipients_Daily';

UPDATE monitor.Settings SET SettingValue = 'dba@empresa.com.br;gestao@empresa.com.br'
WHERE Category = 'Email' AND SettingName = 'Recipients_Weekly';
```

Teste antes do primeiro agendamento:
```sql
-- Preview do HTML no SSMS sem enviar email
EXEC [SQLHealthMonitor].[monitor].[usp_RunReport] @ReportType = 'Daily', @DebugMode = 1;
```

## Desinstalação

```powershell
.\deploy\Uninstall.ps1 -ServerInstance "SQLSERVER01"
```

Remove os 6 SQL Agent Jobs e dropa o banco `SQLHealthMonitor`. Solicita confirmação.

## Configuração

Toda a configuração fica na tabela `[monitor].[Settings]`. Nenhum arquivo JSON ou de configuração necessário.

```sql
-- Ver todas as configurações
SELECT Category, SettingName, SettingValue, Description
FROM [monitor].[Settings]
ORDER BY Category, SettingName;
```

### Configurações principais

| Categoria | Nome | Padrão | Descrição |
|-----------|------|--------|-----------|
| General | Language | en | Idioma dos relatórios: `en` ou `ptbr` |
| General | ServerName | @@SERVERNAME | Rótulo do servidor nos emails |
| General | MonitoringEnabled | 1 | Switch geral de monitoramento |
| Email | ProfileName | DBA_Mail | Nome do perfil do Database Mail |
| Email | Recipients | dba@company.com | Destinatários padrão (todos os relatórios) |
| Email | Recipients_Daily | *(vazio)* | Override para relatório diário |
| Email | Recipients_Weekly | *(vazio)* | Override para relatório semanal |
| Email | Recipients_Alert | *(vazio)* | Override para emails de alerta |
| Retention | DataRetentionDays | 90 | Dias de retenção das métricas coletadas |
| Features | CollectCPU | 1 | Habilitar/desabilitar coletores individuais |

### Thresholds de alerta

```sql
-- Ver thresholds
SELECT MetricName, WarningValue, CriticalValue, Operator, Description
FROM [monitor].[Thresholds] ORDER BY MetricName;

-- Ajustar threshold de CPU
UPDATE [monitor].[Thresholds]
SET WarningValue = 70, CriticalValue = 90
WHERE MetricName = 'CPU_SqlPct';

-- Desabilitar um alerta específico
UPDATE [monitor].[Thresholds] SET IsEnabled = 0 WHERE MetricName = 'CDC_LatencySeconds';
```

### Thresholds padrão

| Métrica | Warning | Critical | Direção |
|---------|---------|----------|---------|
| CPU_SqlPct | 80% | 95% | >= |
| CPU_SystemPct | 90% | 98% | >= |
| Memory_PLE | 300s | 100s | <= |
| Memory_GrantsPending | 1 | 5 | >= |
| Disk_UsedPct | 85% | 95% | >= |
| Disk_ReadLatencyMs | 20ms | 50ms | >= |
| Disk_WriteLatencyMs | 20ms | 50ms | >= |
| AG_SecondsBehind | 30s | 120s | >= |
| Blocking_DurationSec | 30s | 120s | >= |
| Backup_FullHours | 25h | 48h | >= |
| Jobs_FailedCount | 1 | 3 | >= |

### Configuração do Database Mail (se ainda não estiver configurado)

```sql
USE msdb;

EXEC sysmail_add_account_sp
    @account_name    = 'DBA_Mail',
    @email_address   = 'sqlmonitor@empresa.com.br',
    @display_name    = 'SQL Health Monitor',
    @mailserver_name = 'smtp.empresa.com.br';

EXEC sysmail_add_profile_sp   @profile_name = 'DBA_Mail';
EXEC sysmail_add_profileaccount_sp @profile_name = 'DBA_Mail', @account_name = 'DBA_Mail', @sequence_number = 1;

-- Teste
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = 'DBA_Mail',
    @recipients   = 'dba@empresa.com.br',
    @subject      = 'Teste',
    @body         = 'Database Mail funcionando.';
```

## Estrutura do Projeto

```
sql-health-monitor/
├── deploy/                          # Scripts de deploy (PowerShell chamando sqlcmd)
│   ├── Install.ps1                  # Executa todos os .sql em ordem
│   └── Uninstall.ps1                # Remove jobs e dropa o banco
│
├── install/                         # Scripts T-SQL de instalação (execução em ordem)
│   ├── 00-create-schema.sql         # Banco, schema, tabelas, índices
│   ├── 01-create-collectors.sql     # Procedure master de coleta
│   ├── 02-create-reports.sql        # Runner de relatórios (usp_RunReport)
│   ├── 03-create-alerts.sql         # Engine de alertas
│   ├── 04-create-jobs.sql           # SQL Agent Jobs (6 jobs)
│   ├── 05-configure.sql             # Configurações e thresholds padrão
│   ├── 06-alert-history.sql         # Histórico de alertas + cooldown
│   ├── 07-baselines.sql             # Engine de baseline
│   ├── 08-extended-schema.sql       # Schema estendido de monitoramento
│   ├── 09-uptime-tracker.sql        # Rastreamento SLA de uptime
│   └── Uninstall.sql                # Remove jobs + dropa o banco
│
├── collectors/                      # 18 procedures T-SQL de coleta
│
├── reports/                         # Procedures de relatório
│   ├── html_builder_daily.sql       # usp_BuildDailyHtml  — renderizador HTML puro (sem queries a tabelas permanentes)
│   ├── html_builder_weekly.sql      # usp_BuildWeeklyHtml — renderizador HTML puro (sem queries a tabelas permanentes)
│   ├── daily_health_check.sql       # usp_GenerateDailyReport  — coleta dados + chama builder + envia email
│   └── weekly_deep_dive.sql         # usp_GenerateWeeklyReport — coleta dados + chama builder + envia email
│
├── alerts/                          # Engine de alertas
├── baselines/                       # Engine de baseline estatística
├── maintenance/                     # Retenção de dados e manutenção
├── views/                           # Views SQL para consulta
├── multi-instance/                  # Gerenciamento centralizado multi-servidor
│   ├── cms_tables.sql                # Servidores registrados + link com CMS
│   ├── collect_all_instances.sql    # Coleta cross-instance
│   ├── compare_instances.sql        # Detecção de drift
│   └── register_sample.sql
│
├── linux-adaptation/                # Linux SQL Server: coletores + shell helpers
│   ├── collect_cpu_linux.sql
│   ├── collect_disk_linux.sql
│   ├── collect_errorlog_linux.sql
│   ├── collect_job_history_linux.sql
│   ├── install-linux.sh              # Helper de deploy no Linux
│   ├── run-collector.sh              # Executor por coletor no Linux
│   ├── validate-installation.sh
│   ├── ADAPTATION-SUMMARY.md
│   ├── Linux-Compatibility-Report.md
│   └── Linux-Implementation-Guide.md
│
├── views/                           # Views SQL para consulta direta
│   ├── vw_CurrentHealth.sql
│   └── vw_UptimeTracker.sql
│
├── config/                           # Configuração estática
│   ├── settings.sql                  # Metadados de config (runtime fica em [monitor].[Settings])
│   ├── languages.sql                  # Strings de UI: en, ptbr
│   └── default.json                  # Legado — referência da era PS, substituído pela tabela Settings
│
└── validate_installation.sql         # Validação pré-instalação
    validate_uptime_tracker.sql        # Validação pós-instalação do uptime
```

### Arquitetura dos relatórios

```
SQL Agent Job
    └─> usp_RunReport @ReportType='Daily'
            └─> usp_GenerateDailyReport
                    ├─ consulta tabelas de métricas → variáveis escalares
                    ├─ popula temp tables (#ReportRecommendations, #ReportTopWaits, #ReportAnomalies)
                    ├─ EXEC usp_BuildDailyHtml (lê temp tables, retorna @HtmlBody OUTPUT)
                    └─ msdb.dbo.sp_send_dbmail → email entregue
```

`usp_BuildDailyHtml` / `usp_BuildWeeklyHtml` contêm apenas construção de string HTML — sem queries a tabelas permanentes. Isso separa layout de coleta de dados e facilita a customização dos templates.

## SQL Agent Jobs

| Job | Agendamento | Procedure |
|-----|-------------|-----------|
| SQL Health Monitor - Collectors | A cada 5 min | `usp_RunAllCollectors` |
| SQL Health Monitor - Alert Engine | A cada 5 min | `usp_RunAlertEngine` |
| SQL Health Monitor - Daily Report | Diário 07:00 | `usp_RunReport @ReportType='Daily'` |
| SQL Health Monitor - Weekly Report | Segunda 08:00 | `usp_RunReport @ReportType='Weekly'` |
| SQL Health Monitor - Purge Old Data | Diário 03:00 | `usp_Maintenance_PurgeOldData` |
| SQL Health Monitor - Update Baselines | Domingo 02:00 | `usp_Maintenance_UpdateBaselines` |

## Uso

### Executar coletores manualmente

```sql
EXEC [SQLHealthMonitor].[monitor].[usp_RunAllCollectors];
EXEC [SQLHealthMonitor].[monitor].[usp_Collect_CPU];
```

### Gerar relatórios

```sql
-- Preview do HTML no SSMS (sem enviar email)
EXEC [monitor].[usp_RunReport] @ReportType = 'Daily',  @DebugMode = 1;
EXEC [monitor].[usp_RunReport] @ReportType = 'Weekly', @DebugMode = 1;

-- Enviar para endereço específico sem alterar configurações
EXEC [monitor].[usp_RunReport]
    @ReportType         = 'Daily',
    @OverrideRecipients = 'plantao@empresa.com.br';
```

### Rastreamento de Uptime / SLA

```sql
EXEC [monitor].[usp_Generate_MonthlyUptimeReport] @ReportMonth = '2026-06-01';
SELECT * FROM [monitor].[vw_UptimeDashboard];
SELECT * FROM [monitor].[vw_SLAComplianceHistory];
```

## Resolução de Problemas

```sql
-- Email não enviado: verificar perfil
SELECT SettingValue FROM monitor.Settings WHERE Category = 'Email' AND SettingName = 'ProfileName';
SELECT * FROM msdb.dbo.sysmail_eventlog WHERE event_type = 'error' ORDER BY log_date DESC;

-- Falha em relatório: ver histórico e modo debug
SELECT ReportType, Success, ErrorMessage FROM [monitor].[ReportHistory] ORDER BY GeneratedAt DESC;
EXEC [monitor].[usp_RunReport] @ReportType = 'Daily', @DebugMode = 1;

-- Falha em coletor
SELECT * FROM [monitor].[CollectionHistory] ORDER BY CollectedAt DESC;
```

## Contribuindo

1. Fork do repositório, crie uma branch de feature
2. Novos coletores em `collectors/`, seguindo a convenção de nomenclatura
3. Atualize `install/01-create-collectors.sql` para registrar a nova procedure
4. Teste com `@DebugMode = 1`
5. Abra um pull request

Mantenha toda a lógica em T-SQL. Para coleta de dados do SO, adapte em `linux-adaptation/`.

## Licença

Licença MIT — veja [LICENSE](LICENSE).

## Contato

- **Autor**: Lucas Allan Borges
- **Email**: lucasborgesbr@gmail.com
- **GitHub**: https://github.com/lucasborgesbr/sql-health-monitor
- **LinkedIn**: https://linkedin.com/in/lucasallanborges

---

*SQL Health Monitor — Monitoramento nativo em T-SQL para SQL Server.*
