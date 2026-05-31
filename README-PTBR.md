# SQL Health Monitor

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/powershell/scripting/overview)
[![SQL Server](https://img.shields.io/badge/SQL%20Server-2016%2B-green.svg)](https://www.microsoft.com/sql-server/)

> **Nota:** O README oficial em inglês está disponível em [README.md](README.md)

## 📋 Visão Geral

O SQL Health Monitor é uma solução completa de monitoramento proativo para ambientes SQL Server. Ele oferece monitoramento de saúde em tempo real, alertas inteligentes e capacidades de relatórios detalhados, projetados para ambientes de produção que executam SQL Server 2016 e versões posteriores.

### 🎯 Benefícios Principais

- **16 Coletores de Saúde** - Monitore CPU, memória, disco, waits, blocking, deadlocks, Availability Groups, CDC, top queries, saúde de índices, status de backup, jobs, error log, tempdb e crescimento de banco de dados
- **Motor de Alertas Inteligente** - Limiares configuráveis com notificações em tempo real e períodos de resfriamento inteligentes
- **Motor de Linha de Base Estatística** - Detecção automática de anomalias usando alertas baseados em desvio padrão
- **Relatórios Completos** - Resumos diários de saúde, análises semanais profundas e notificações de alerta
- **Suporte Multi-Instância** - Gestão centralizada de múltiplas instâncias SQL Server com detecção de desvios
- **Suporte Multi-Linguagem** - Suporte integrado em inglês e português (BR)
- **Manutenção Automatizada** - Retenção de dados configurável com limpeza em lote e registro de atividades
- **Indicadores Visuais de Status** - Indicadores de status semáforo (🟢🟡🔴) para avaliação rápida de saúde

## 📋 Sumário

1. [Pré-requisitos & Compatibilidade](#pré-requisitos--compatibilidade)
2. [Guia de Instalação](#guia-de-instalação)
3. [Configuração & Configuração de Alertas](#configuração--configuração-de-alertas)
4. [Estrutura do Projeto & Componentes](#estrutura-do-projeto--componentes)
5. [Exemplos de Uso & Relatórios](#exemplos-de-uso--relatórios)
6. [Personalização Multi-Ambiente](#personalização-multi-ambiente)
7. [Guia de Solução de Problemas](#guia-de-solução-de-problemas)
8. [Contribuição & Licença](#contribuição--licença)
9. [Suporte & Contato](#suporte--contato)

## 🔧 Pré-requisitos & Compatibilidade

### Requisitos do Sistema

| Componente | Versão Mínima | Notas |
|-----------|----------------|-------|
| **SQL Server** | 2016+ | Otimizado para SQL Server 2022 |
| **Windows Server** | 2012 R2+ | Para execução do PowerShell |
| **PowerShell** | 5.1+ | PowerShell 7+ recomendado |
| **SQL Server Agent** | Obrigatório | Para jobs agendados |
| **Database Mail** | Obrigatório | Para notificações por email |

### Dependências de Software

- **Módulo dbatools** (v22.0.0+) - Módulo PowerShell para gerenciamento SQL Server
- **Módulo SqlServer** (v21.1.0+) - Módulo PowerShell para cmdlets SQL Server
- **Microsoft.PowerShell.Management** - Cmdlets de gerenciamento core do PowerShell

### Permissões de Banco de Dados

Permissões necessárias para instalação:
- Função de servidor `sysadmin` (recomendado para funcionalidade completa)
- Função `db_owner` no banco de dados alvo (requisito mínimo)

### Requisitos de Rede

- Porta TCP 1433 (porta padrão do SQL Server) acessível a partir do servidor de execução
- Porta SMTP 587 (ou 25) acessível para notificações por email
- Database Mail configurado com perfil de email válido

## 🚀 Guia de Instalação

### Opção 1: Assistente de Configuração Interativo (Recomendado)

A forma mais fácil de começar com configuração guiada:

```powershell
# 1. Instalar módulo dbatools (se ainda não estiver instalado)
Install-Module dbatools -Scope CurrentUser -Force

# 2. Executar o assistente de configuração interativo
.\powershell\Start-SQLHealthMonitorSetup.ps1
```

O assistente guia você através de:
- Configuração de conexão com validação ao vivo
- Seleção de modo single ou multi-instância
- Configuração de coletores (auto-detecta capacidades AG/CDC)
- Limiares de alerta e configuração de destinatários
- Agendamento de relatórios e preferências de idioma
- Configuração de email (Database Mail ou SMTP)
- Criação de jobs do SQL Agent
- Configuração do motor de linha de base
- Políticas de retenção de dados

**Exporte sua configuração** para replicação:
```powershell
# Exportar respostas para setup não interativo
.\powershell\Start-SQLHealthMonitorSetup.ps1 -ExportAnswers .\my-config.json

# Setup não interativo usando configuração exportada
.\powershell\Start-SQLHealthMonitorSetup.ps1 -NonInteractive -AnswerFile .\my-config.json
```

### Opção 2: Instalação Automatizada

Para implantações scriptadas em múltiplos servidores:

```powershell
# Instalar em servidor único com jobs Agent
Install-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' `
    -EmailProfile 'DBA Mail' `
    -Recipients 'dba-team@company.com' `
    -Language EN

# Instalar sem jobs Agent (agendamento manual)
Install-SQLHealthMonitor -ServerInstance 'SQL-DEV-01' -SkipAgentJobs -Language EN

# Instalar com nome de banco de dados personalizado
Install-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor_Production'
```

### Opção 3: Instalação Manual

Para ambientes que requerem controle granular:

```sql
-- 1. Criar o banco de dados (se não existir)
CREATE DATABASE [SQLHealthMonitor];
GO
USE [SQLHealthMonitor];
GO

-- 2. Executar scripts de instalação na ordem correta
-- install/00-create-schema.sql      (tabelas & schema)
-- install/01-create-collectors.sql  (procedimento master collector)
-- install/02-create-reports.sql     (procedimentos de relatório)
-- install/03-create-alerts.sql      (motor de alertas)
-- install/04-create-jobs.sql        (jobs do SQL Agent)
-- install/05-configure.sql          (configurações, limiares, idiomas)
-- install/06-alert-history.sql      (histórico de alertas + cooldown)
-- install/07-baselines.sql          (motor de linha de base)

-- 3. Implantar todos os scripts de coletor
-- Executar todos os arquivos na pasta collectors/

-- 4. Implantar procedimentos de manutenção
-- maintenance/purge_old_data.sql
-- maintenance/update_baselines.sql
```

### Verificação Pós-Instalação

```powershell
# Testar instalação
.\powershell\Test-Installation.ps1 -ServerInstance 'SQL-PRD-01'

# Executar coleta manual
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType Collection -Verbose

# Testar geração de relatório diário
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType DailyReport -Language EN -DebugMode
```

## ⚙️ Configuração & Configuração de Alertas

### Configuração Principal

Edite o arquivo de configuração em `powershell\config\default.json`:

```json
{
    "Connection": {
        "ServerInstance": "localhost",
        "Database": "SQLHealthMonitor",
        "TrustedConnection": true,
        "ConnectTimeout": 30,
        "CommandTimeout": 300
    },
    "Schedule": {
        "CollectionIntervalMinutes": 15,
        "DailyReportTime": "07:00",
        "WeeklyReportDay": "Monday",
        "WeeklyReportTime": "08:00",
        "AlertCheckIntervalMinutes": 5
    },
    "Email": {
        "Method": "DatabaseMail",
        "DatabaseMailProfile": "SQLHealthMonitor",
        "Recipients": {
            "Daily": ["dba-team@company.com"],
            "Weekly": ["dba-team@company.com", "it-management@company.com"],
            "Alert": ["dba-team@company.com"]
        }
    },
    "Language": "EN"
}
```

### Configuração de Limiares de Alerta

Os limiares de alerta são armazenados na tabela `[monitor].[Thresholds]`:

```sql
-- Visualizar limiares atuais
SELECT MetricName, WarningValue, CriticalValue, Operator, Description
FROM [monitor].[Thresholds]
ORDER BY MetricName;

-- Modificar limiares de CPU
UPDATE [monitor].[Thresholds] 
SET WarningValue = 70, CriticalValue = 90 
WHERE MetricName = 'CPU_SqlPct';

-- Desabilitar alerta específico
UPDATE [monitor].[Thresholds] 
SET IsEnabled = 0 
WHERE MetricName = 'CDC_LatencySeconds';
```

### Limiares Padrão

| Métrica | Alerta | Crítico | Direção | Descrição |
|--------|---------|----------|-----------|-------------|
| CPU_SqlPct | 80% | 95% | >= | Utilização de CPU do SQL Server |
| CPU_SystemPct | 90% | 98% | >= | Utilização total de CPU do sistema |
| Memory_PLE | 300s | 100s | <= | Page Life Expectancy |
| Memory_GrantsPending | 1 | 5 | >= | Memory grants pendentes |
| Disk_UsedPct | 85% | 95% | >= | Porcentagem de espaço em disco utilizado |
| Disk_ReadLatencyMs | 20ms | 50ms | >= | Latência de leitura de disco |
| Disk_WriteLatencyMs | 20ms | 50ms | >= | Latência de escrita de disco |
| AG_SecondsBehind | 30s | 120s | >= | Atraso de replicação do AG |
| AG_LogSendQueueMB | 500MB | 2000MB | >= | Fila de envio de log do AG |
| Blocking_DurationSec | 30s | 120s | >= | Duração de blocking |
| Backup_FullHours | 25h | 48h | >= | Horas desde o último backup full |
| Jobs_FailedCount | 1 | 3 | >= | Contagem de jobs falhados |

### Configuração de Email

#### Configuração do Database Mail

```sql
-- Configurar Database Mail
USE msdb;
GO

EXEC msdb.dbo.sysmail_add_account_sp
    @account_name = 'SQLHealthMonitor',
    @description = 'Notificações do SQL Health Monitor',
    @email_address = 'sqlhealthmonitor@company.com',
    @reply_to_address = 'dba-team@company.com',
    @display_name = 'SQL Health Monitor';

EXEC msdb.dbo.sysmail_add_profile_sp
    @profile_name = 'SQLHealthMonitor',
    @description = 'Perfil para notificações do SQL Health Monitor';

EXEC msdb.dbo.sysmail_add_profileaccount_sp
    @profile_name = 'SQLHealthMonitor',
    @account_name = 'SQLHealthMonitor',
    @sequence_number = 1;
```

#### Configuração SMTP

```json
{
    "Email": {
        "Method": "SMTP",
        "SmtpServer": "smtp.company.com",
        "SmtpPort": 587,
        "SmtpUseSsl": true,
        "SmtpCredential": {
            "Username": "sqlhealthmonitor@company.com",
            "Password": "securepassword"
        }
    }
}
```

## 📁 Estrutura do Projeto & Componentes

```
sql-health-monitor/
├── powershell/                     # Camada de orquestração PowerShell
│   ├── Start-SQLHealthMonitorSetup.ps1    # Assistente de setup interativo
│   ├── Invoke-SQLHealthMonitor.ps1       # Orquestrador principal
│   ├── Send-HealthReport.ps1             # Gerador/enviador de relatórios
│   ├── Install-SQLHealthMonitor.ps1      # Instalador automatizado
│   ├── Deploy-SqlHealthMonitor.ps1       # Helper de implantação
│   ├── Test-Installation.ps1             # Validação pós-instalação
│   ├── SQLHealthMonitor.psd1            # Manifesto do módulo
│   └── config/
│       ├── default.json                 # Configuração padrão
│       └── answer-file-sample.json      # Amostra de respostas
├── collectors/                      # Scripts de coleta T-SQL (16 coletores)
│   ├── collect_cpu.sql                  # Utilização de CPU
│   ├── collect_memory.sql               # Métricas de memória
│   ├── collect_disk.sql                 # Espaço em disco & I/O
│   ├── collect_waits.sql                # Estatísticas de wait
│   ├── collect_blocking.sql             # Detecção de blocking
│   ├── collect_deadlocks.sql            # Análise de deadlocks
│   ├── collect_ag_health.sql            # Availability Groups
│   ├── collect_cdc_health.sql           # Monitoramento de saúde CDC
│   ├── collect_top_queries.sql          # Top queries por recurso
│   ├── collect_index_health.sql        # Fragmentação de índices
│   ├── collect_backup_status.sql        # Verificação de backup
│   ├── collect_jobs.sql                # Jobs do SQL Agent
│   ├── collect_tempdb.sql               # Uso do TempDB
│   ├── collect_errorlog.sql             # Análise de error log
│   ├── collect_log_growth.sql           # Crescimento do transaction log
│   └── collect_database_growth.sql     # Crescimento de arquivos de banco de dados
├── alerts/                         # Motor de alertas
│   ├── alert_engine.sql                # Lógica de avaliação de alertas
│   ├── alert_actions.sql               # Ações de resposta automatizada
│   └── thresholds_default.sql          # Limiares padrão
├── baselines/                      # Linhas de base estatísticas
│   ├── baseline_tables.sql            # DDL para armazenamento de linha de base
│   ├── capture_baseline.sql           # Captura semanal de linha de base
│   └── detect_anomalies.sql           # Detecção de anomalias em tempo real
├── reports/                        # Geração de relatórios
│   ├── daily_health_check.sql         # Relatório diário de saúde
│   ├── weekly_deep_dive.sql           # Relatório de análise semanal
│   ├── recommendations_engine.sql     # Recomendações acionáveis
│   └── templates/                    # Modelos de email HTML
│       ├── daily_en.html              # Modelo de relatório diário (EN)
│       ├── daily_ptbr.html            # Modelo de relatório diário (PT-BR)
│       ├── weekly_en.html             # Modelo de relatório semanal (EN)
│       ├── weekly_ptbr.html           # Modelo de relatório semanal (PT-BR)
│       ├── alert_en.html              # Modelo de alerta (EN)
│       └── alert_ptbr.html            # Modelo de alerta (PT-BR)
├── maintenance/                    # Procedimentos de housekeeping
│   ├── purge_old_data.sql            # Limpeza de retenção de dados
│   ├── retention_config.sql          # Configurações de retenção padrão
│   └── update_baselines.sql          # Atualizações de linha de base legadas
├── multi-instance/                 # Suporte a gestão centralizada
│   ├── cms_tables.sql                # Tabelas CMS para multi-instância
│   ├── register_sample.sql           # Amostra de registro de instância
│   ├── collect_all_instances.sql     # Coleta cross-instância
│   └── compare_instances.sql         # Comparação de saúde entre instâncias
├── config/                         # Configuração do banco de dados
├── views/                          # Views SQL para relatórios
├── docs/                          # Documentação
│   ├── INSTALL.md                   # Guia de instalação
│   ├── CONFIGURATION.md            # Referência de configuração
│   └── CUSTOMIZATION.md            # Guia de customização
└── install/                       # Scripts de instalação (execução ordenada)
    ├── 00-create-schema.sql        # Schema do banco de dados & tabelas
    ├── 01-create-collectors.sql    # Procedimento master collector
    ├── 02-create-reports.sql       # Procedimentos de relatório
    ├── 03-create-alerts.sql        # Configuração do motor de alertas
    ├── 04-create-jobs.sql          # Jobs do SQL Agent
    ├── 05-configure.sql           # Configuração padrão
    ├── 06-alert-history.sql       # Histórico de alertas + cooldown
    └── 07-baselines.sql           # Configuração do motor de linha de base
```

### Componentes Principais

#### Módulo PowerShell
- **Start-SQLHealthMonitorSetup.ps1**: Assistente de setup interativo
- **Invoke-SQLHealthMonitor.ps1**: Orquestrador principal
- **Send-HealthReport.ps1**: Gerador/enviador de relatórios
- **Install-SQLHealthMonitor.ps1**: Script de implantação automatizado

#### Coletores
16 coletores especializados reúnem métricas completas:
- **Métricas de Sistema**: CPU, Memória, I/O de Disco
- **Métricas do SQL Server**: Waits, Blocking, Deadlocks
- **Alta Disponibilidade**: Availability Groups, CDC
- **Performance**: Top Queries, Saúde de Índices
- **Operações**: Status de Backup, Histórico de Jobs, Error Log
- **Capacidade**: TempDB, Crescimento de Banco de Dados, Crescimento de Log

#### Motor de Alertas
- Avaliação em tempo real de limiares
- Períodos de resfriamento configuráveis
- Ações de resposta automatizada
- Rastreamento de histórico de alertas

#### Motor de Relatórios
- **Relatório Diário de Saúde**: Resumo executivo com status semáforo
- **Análise Semanal Profunda**: Análise de tendências e planejamento de capacidade
- **Notificações de Alerta**: Informações detalhadas de alerta com contexto
- **Suporte Multi-Linguagem**: Inglês e Português (BR)

## 💡 Exemplos de Uso & Relatórios

### Uso Básico

```powershell
# Importar o módulo
Import-Module .\powershell\SQLHealthMonitor.psd1

# Coletar todas as métricas de saúde
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType Collection -Verbose

# Gerar relatório diário de saúde
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType DailyReport -Language EN

# Gerar relatório de análise semanal
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType WeeklyReport -Language PTBR

# Verificar alertas
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType Alert
```

### Uso Avançado

```powershell
# Coleta multi-instância a partir do CMS central
Invoke-SQLHealthMonitor -ServerInstance 'SQL-CMS-01' -RunType Collection -AllInstances

# Apenas instâncias de produção
Invoke-SQLHealthMonitor -ServerInstance 'SQL-CMS-01' -RunType Collection -AllInstances -Environment PRD

# Gerar relatórios para todas as instâncias
Invoke-SQLHealthMonitor -ServerInstance 'SQL-CMS-01' -RunType DailyReport -AllInstances -Language EN

# Testar mudanças de configuração sem execução
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType Collection -WhatIf
```

### Uso Direto com SQL

```sql
-- Executar coletores específicos
EXEC [monitor].[usp_Collect_CPU];
EXEC [monitor].[usp_Collect_Memory];
EXEC [monitor].[usp_Collect_Disk];

-- Gerar relatórios diretamente
EXEC [monitor].[usp_Report_DailyHealth] @DebugMode = 1;
EXEC [monitor].[usp_Report_WeeklyDeepDive] @DebugMode = 1;

-- Gerenciar linhas de base
EXEC [monitor].[usp_Baseline_Capture] @LookbackDays = 7;
EXEC [monitor].[usp_Baseline_DetectAnomalies] @LookbackMinutes = 60;

-- Limpar dados antigos
EXEC [monitor].[usp_PurgeHistoricalData] @BatchSize = 10000;
```

### Exemplos de Relatórios

#### Recursos do Relatório Diário de Saúde:
- Pontuação de saúde (0-100) com status semáforo
- Top 5 problemas que requerem atenção
- Detecção de anomalias de linha de base
- Recomendações acionáveis com níveis de prioridade
- Tabela de resumo executivo
- Detalhamento de métricas

#### Recursos da Análise Semanal Profunda:
- Análise de tendências semana a semana
- Projeções de planejamento de capacidade
- Detecção de degradação de performance de queries
- Análise "O Que Mudou"
- Gráficos históricos de performance
- Recomendações estratégicas

### Notificações por Email

```powershell
# Enviar relatório personalizado
Send-HealthReport -ServerInstance 'SQL-PRD-01' -ReportType Daily -Language EN -OutputPath '.\Reports\daily.html'

# Enviar notificação de alerta
Send-HealthReport -ServerInstance 'SQL-PRD-01' -ReportType Alert -Language PTBR -Recipients 'emergency-team@company.com'

### Referência do Módulo PowerShell

#### Invoke-SQLHealthMonitor

Orquestrador principal que une coletores, alertas e relatórios.

| Parâmetro | Tipo | Padrão | Descrição |
|-----------|------|---------|-------------|
| ServerInstance | string | (obrigatório*) | Instância SQL Server (* não obrigatório com -AllInstances se host CMS especificado) |
| Database | string | SQLHealthMonitor | Nome do banco de dados de monitoramento |
| ConfigProfile | string | DEFAULT | Perfil de config no banco de dados |
| RunType | string | (obrigatório) | Collection, DailyReport, WeeklyReport, Alert |
| Language | string | EN | EN ou PTBR |
| ConfigPath | string | .\powershell\config\default.json | Caminho para config JSON |
| AllInstances | switch | false | Percorrer tabela RegisteredServers |
| Environment | string | (todos) | Filtro: DEV, STG, PRD, DR |
| ParallelDegree | int | 4 | Máximo coleções paralelas (multi-instância) |

#### Send-HealthReport

Gera relatórios HTML e envia via Database Mail ou SMTP.

| Parâmetro | Tipo | Padrão | Descrição |
|-----------|------|---------|-------------|
| ServerInstance | string | (obrigatório) | Instância SQL Server |
| ReportType | string | (obrigatório) | Daily, Weekly, Alert |
| Recipients | string[] | da config | Destinatários de email |
| Language | string | EN | EN ou PTBR |
| OutputPath | string | (nenhum) | Salvar HTML localmente |

#### Install-SQLHealthMonitor

Implanta objetos de banco de dados e cria jobs do SQL Agent.

| Parâmetro | Tipo | Padrão | Descrição |
|-----------|------|---------|-------------|
| ServerInstance | string | (obrigatório) | SQL Server alvo |
| Database | string | SQLHealthMonitor | Nome do banco de dados |
| Schedule | string | Hourly | Coleta Hourly ou Daily |
| EmailProfile | string | (nenhum) | Perfil Database Mail |
| Recipients | string[] | (nenhum) | Destinatários de relatório |
| SkipAgentJobs | switch | false | Pular criação de jobs Agent |
| Force | switch | false | Sobrescrever sem perguntar |

## 🌍 Personalização Multi-Ambiente

### Ambiente de Desenvolvimento

```json
{
    "Connection": {
        "ServerInstance": "SQL-DEV-01",
        "Database": "SQLHealthMonitor_DEV"
    },
    "Schedule": {
        "CollectionIntervalMinutes": 30,
        "DailyReportTime": "18:00"
    },
    "Email": {
        "Recipients": {
            "Daily": ["dev-team@company.com"],
            "Weekly": ["dev-team@company.com"],
            "Alert": ["dev-team@company.com"]
        }
    },
    "Collectors": {
        "Enabled": ["CPU", "Memory", "Disk", "Waits", "Blocking", "Jobs"]
    }
}
```

### Ambiente de Homologação

```json
{
    "Connection": {
        "ServerInstance": "SQL-STG-01",
        "Database": "SQLHealthMonitor_STG"
    },
    "Schedule": {
        "CollectionIntervalMinutes": 15,
        "DailyReportTime": "08:00"
    },
    "Email": {
        "Recipients": {
            "Daily": ["stg-team@company.com", "dba-team@company.com"],
            "Weekly": ["stg-team@company.com", "dba-team@company.com", "it-management@company.com"],
            "Alert": ["stg-team@company.com", "dba-team@company.com"]
        }
    },
    "Collectors": {
        "Enabled": ["CPU", "Memory", "Disk", "Waits", "Blocking", "AG", "TopQueries", "IndexHealth", "BackupStatus", "Jobs"]
    }
}
```

### Ambiente de Produção

```json
{
    "Connection": {
        "ServerInstance": "SQL-PRD-01",
        "Database": "SQLHealthMonitor_PRD"
    },
    "Schedule": {
        "CollectionIntervalMinutes": 5,
        "DailyReportTime": "07:00",
        "WeeklyReportDay": "Monday",
        "WeeklyReportTime": "08:00"
    },
    "Email": {
        "Recipients": {
            "Daily": ["dba-team@company.com", "it-management@company.com"],
            "Weekly": ["dba-team@company.com", "it-management@company.com", "executive@company.com"],
            "Alert": ["dba-team@company.com", "emergency-team@company.com"]
        }
    },
    "Collectors": {
        "Enabled": ["CPU", "Memory", "Disk", "Waits", "Blocking", "Deadlocks", "AG", "CDC", "TopQueries", "IndexHealth", "BackupStatus", "Jobs", "ErrorLog", "TempDB", "LogGrowth", "DatabaseGrowth"]
    },
    "Retention": {
        "DetailedDataDays": 90,
        "AggregatedDataDays": 365,
        "ReportHistoryDays": 180
    }
}
```

### Limiares Específicos por Ambiente

```sql
-- Limiares de produção (mais restritivos)
UPDATE [monitor].[Thresholds] SET 
    WarningValue = 70, CriticalValue = 85 
WHERE MetricName = 'CPU_SqlPct' AND Environment = 'PRD';

-- Limiares de desenvolvimento (mais tolerantes)
UPDATE [monitor].[Thresholds] SET 
    WarningValue = 85, CriticalValue = 95 
WHERE MetricName = 'CPU_SqlPct' AND Environment = 'DEV';
```

### Gestão Multi-Instância

```sql
-- Registrar múltiplas instâncias
INSERT INTO [monitor].[RegisteredServers] (ServerName, Environment, Description)
VALUES 
    ('SQL-PRD-01', 'PRD', 'Production Primary'),
    ('SQL-PRD-02', 'PRD', 'Production Secondary'),
    ('SQL-STG-01', 'STG', 'Staging Environment'),
    ('SQL-DEV-01', 'DEV', 'Development Environment');

-- Coletar de todas as instâncias de produção
EXEC [monitor].[usp_CollectAllInstances] @Environment = 'PRD';

-- Comparar saúde entre instâncias
EXEC [monitor].[usp_CompareInstances] @Environment = 'PRD';
```

## 🚨 Guia de Solução de Problemas

### Problemas Comuns de Instalação

#### 1. Erros de Permissão

```powershell
# Executar com privilégios elevados
Start-Process powershell -Verb RunAs

# Ou usar credenciais explícitas
$credential = Get-Credential
Install-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -Credential $credential
```

#### 2. Timeouts de Conexão

```json
{
    "Connection": {
        "ConnectTimeout": 60,
        "CommandTimeout": 600
    }
}
```

#### 3. Configuração do Database Mail

```sql
-- Testar Database Mail
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = 'SQLHealthMonitor',
    @recipients = 'dba@company.com',
    @subject = 'Test Message',
    @body = 'Database Mail test successful';

-- Verificar log do Database Mail
SELECT * FROM msdb.dbo.sysmail_eventlog WHERE event_type = 'error';
```

### Problemas Comuns de Runtime

#### 1. Falhas na Coleta

```sql
-- Verificar histórico de coleta
SELECT * FROM [monitor].[CollectionHistory] ORDER BY CollectedAt DESC;

-- Verificar erros de coletores específicos
SELECT * FROM [monitor].[CollectionErrors] ORDER BY ErrorTime DESC;

-- Testar coletores individuais
EXEC [monitor].[usp_Collect_CPU] @DebugMode = 1;
```

#### 2. Problemas no Motor de Alertas

```sql
-- Verificar histórico de alertas
SELECT * FROM [monitor].[AlertHistory] ORDER BY TriggeredAt DESC;

-- Verificar status de resfriamento
SELECT * FROM [monitor].[AlertCooldown] ORDER BY LastTriggered DESC;

-- Testar motor de alertas manualmente
EXEC [monitor].[usp_RunAlertEngine] @DebugMode = 1;
```

#### 3. Problemas na Geração de Relatórios

```sql
-- Verificar histórico de relatórios
SELECT * FROM [monitor].[ReportHistory] ORDER BY GeneratedAt DESC;

-- Testar geração de relatório com modo debug
EXEC [monitor].[usp_Report_DailyHealth] @DebugMode = 1;

-- Verificar saída HTML diretamente
SELECT HTMLContent FROM [monitor].[ReportHistory] WHERE ReportType = 'Daily' ORDER BY GeneratedAt DESC;
```

#### 4. Problemas de Performance

```sql
-- Verificar coleções de longa duração
SELECT * FROM [monitor].[CollectionHistory] WHERE DurationSeconds > 60 ORDER BY CollectedAt DESC;

-- Verificar tamanhos de tabela
SELECT 
    t.NAME AS TableName,
    s.Name AS SchemaName,
    p.rows AS RowCounts,
    SUM(a.total_pages) * 8 / 1024 AS TotalSpaceMB
FROM sys.tables t
INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
LEFT OUTER JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE t.NAME LIKE 'monitor%'
GROUP BY t.Name, s.Name, p.rows;

-- Otimizar operações de limpeza
EXEC [monitor].[usp_PurgeHistoricalData] @BatchSize = 5000, @MaxDurationMin = 15;
```

### Operações de Modo Debug

```powershell
# Habilitar logging de debug
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType Collection -Verbose

# Testar com WhatIf
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType Collection -WhatIf

# Gerar relatórios de debug
Invoke-SQLHealthMonitor -ServerInstance 'SQL-PRD-01' -RunType DailyReport -DebugMode
```

### Análise de Arquivo de Log

```powershell
# Ver entradas de log recentes
Get-Content ".\SQLHealthMonitor\Logs\SQLHealthMonitor.log" | Select-Object -Last 50

# Filtrar logs de erro
Get-Content ".\SQLHealthMonitor\Logs\SQLHealthMonitor.log" | Where-Object { $_ -match "ERROR" }

# Monitorar logs em tempo real
Get-Content ".\SQLHealthMonitor\Logs\SQLHealthMonitor.log" -Wait
```

## 🤝 Contribuição & Licença

### Diretrizes de Contribuição

Bem-vindas contribuições! Por favor, siga estas diretrizes:

1. **Faça um fork do repositório** e crie uma branch de feature
2. **Siga o estilo de código existente** e convenções de nomenclatura
3. **Teste suas mudanças** thoroughly
4. **Atualize a documentação** para novas features
5. **Submeta um pull request** com descrição clara das mudanças

### Setup de Desenvolvimento

```powershell
# Clonar o repositório
git clone https://github.com/lucasborgesbr/sql-health-monitor.git
cd sql-health-monitor

# Instalar dependências de desenvolvimento
Install-Module dbatools -Scope CurrentUser -Force
Install-Module Pester -Scope CurrentUser -Force

# Executar testes (quando disponíveis)
# Invoke-Pester -Path tests/
```

### Diretrizes de Estilo de Código

- **PowerShell**: Siga [PowerShell Scripting Best Practices](https://docs.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-logging)
- **T-SQL**: Siga [T-SQL Coding Conventions](https://docs.microsoft.com/sql/t-sql/development-recommendations)
- **Comentários**: Use comentários claros e concisos explicando lógica complexa
- **Error Handling**: Implemente tratamento de erros abrangente e logging

### Adicionando Novas Features

1. **Crie um novo coletor** no diretório `collectors/`
2. **Atualize o orquestrador principal** em `Invoke-SQLHealthMonitor.ps1`
3. **Adicione opções de configuração** em `powershell/config/default.json`
4. **Crie testes unitários** para a nova funcionalidade
5. **Atualize a documentação** com exemplos de uso

### Relatando Issues

Ao relatar issues, por favor inclua:

- Detalhes do ambiente (versão do SQL Server, OS, versão do PowerShell)
- Passos para reproduzir o problema
- Comportamento esperado vs real
- Mensagens de erro e stack traces
- Entradas de log relevantes
- Arquivo de configuração (redactar informações sensíveis)

### Licença

Este projeto é licenciado sob a Licença MIT - veja o arquivo [LICENSE](LICENSE) para detalhes.

### Dependências de Terceiros

Este projeto usa os seguintes componentes de terceiros:

- **dbatools** - Módulo PowerShell para gerenciamento SQL Server
- **SqlServer** - Módulo PowerShell para cmdlets SQL Server
- **Pester** - Framework de testes PowerShell

Todos os componentes de terceiros estão sujeitos às suas respectivas licenças.

## 📞 Suporte & Contato

### Documentação

- **Documentação Principal**: [README.md](README.md)
- **Guia de Instalação**: [docs/INSTALL.md](docs/INSTALL.md)
- **Referência de Configuração**: [docs/CONFIGURATION.md](docs/CONFIGURATION.md)
- **Guia de Customização**: [docs/CUSTOMIZATION.md](docs/CUSTOMIZATION.md)

### Suporte da Comunidade

- **GitHub Issues**: [Report bugs or request features](https://github.com/lucasborgesbr/sql-health-monitor/issues)
- **Discussions**: [Join community discussions](https://github.com/lucasborgesbr/sql-health-monitor/discussions)
- **Wiki**: [Contribute to documentation](https://github.com/lucasborgesbr/sql-health-monitor/wiki)

### Suporte Profissional

Para serviços de suporte e consultoria profissional:

- **Email**: lucasborgesbr@gmail.com
- **LinkedIn**: [Lucas Allan Borges](https://linkedin.com/in/lucasallanborges)
- **Repositório**: [https://github.com/lucasborgesbr/sql-health-monitor](https://github.com/lucasborgesbr/sql-health-monitor)

### Release Notes

#### Versão 1.0.0 (Atual)

**Novas Features:**
- 16 coletores de saúde cobrindo todas as principais métricas SQL Server
- Motor de alertas inteligente com limiares configuráveis
- Motor de linha de base estatística com detecção de anomalias
- Relatórios completos (diário e semanal)
- Suporte multi-instância com gestão centralizada
- Suporte multi-linguagem (Inglês e Português-BR)
- Manutenção automatizada e retenção de dados
- Assistente de setup interativo

**Melhorias:**
- Tratamento de erros e logging aprimorados
- Otimização de performance para ambientes grandes
- Modelos e formatação de relatórios melhorados
- Melhor gestão multi-instância

**Correções de Bug:**
- Corrigido memory leak em coleções de longa duração
- Resolvidos problemas de timezone na geração de relatórios
- Melhorado mecanismo de cooldown de alertas
- Aprimorado tratamento de conexão de banco de dados

### Future Roadmap

- **Integração com Machine Learning**: Analytics preditivo para planejamento de capacidade
- **Mobile App**: Dashboards e notificações mobile-friendly
- **API Access**: REST API para integração com outras ferramentas
- **Relatórios Aprimorados**: Construtor de relatórios personalizado e visualização
- **Suporte Cloud**: Suporte para Azure SQL e AWS RDS
- **Remediação Automatizada**: Capacidades self-healing para problemas comuns

---

**SQL Health Monitor** - Monitoramento proativo para ambientes SQL Server

*Created with ❤️ by Lucas Allan Borges - Senior DBA / Database Engineer*