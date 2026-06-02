# SQL Health Monitor - Guia de Instalação Genérica

## Visão Geral

O SQL Health Monitor é uma solução completa de monitoramento de saúde para instâncias SQL Server, desenvolvida para ser totalmente genérica e portável entre diferentes ambientes clientes. Este guia cobre a instalação, configuração e validação do sistema.

## Pré-requisitos

### Sistema
- **SQL Server**: 2016 ou superior (otimizado para 2022)
- **Windows**: PowerShell 5.1 ou PowerShell 7+
- **Permissões**: sysadmin ou db_owner no banco de dados alvo

### Software Necessário
- **dbatools**: Módulo PowerShell para gerenciamento de SQL Server
- **Database Mail**: Configurado para envio de relatórios (opcional, pode usar SMTP)

### Instalação do dbatools
```powershell
# Instalar dbatools (se não estiver instalado)
Install-Module dbatools -Scope CurrentUser -Force
```

## Estrutura dos Scripts

Os scripts de instalação estão localizados no diretório `scripts/`:

1. **Setup-SQLHealthMonitorDatabase.ps1** - Cria banco de dados, schemas, tabelas e procedimentos
2. **Configure-SQLHealthMonitor.ps1** - Configura alertas, destinatários e parâmetros
3. **Deploy-SQLHealthMonitorJobs.ps1** - Agenda tarefas via SQL Agent
4. **Test-SQLHealthMonitorInstallation.ps1** - Teste básico da instalação
5. **Validate-SQLHealthMonitorSetup.ps1** - Validação completa do setup

## Fluxo de Instalação Recomendado

### Passo 1: Setup do Banco de Dados

```powershell
# Executar o setup do banco de dados
.\scripts\Setup-SQLHealthMonitorDatabase.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor'
```

**Parâmetros:**
- `ServerInstance`: Instância SQL Server (ex: 'SQL-PRD-01', 'localhost')
- `Database`: Nome do banco de dados (padrão: 'SQLHealthMonitor')
- `AuthMethod`: 'Windows' (padrão) ou 'Sql'
- `SqlCredential`: Credencial para autenticação SQL
- `Force`: Sobrescrever banco de dados existente

**Exemplos:**
```powershell
# Autenticação Windows (padrão)
.\scripts\Setup-SQLHealthMonitorDatabase.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor'

# Autenticação SQL
$cred = Get-Credential
.\scripts\Setup-SQLHealthMonitorDatabase.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -AuthMethod 'Sql' -SqlCredential $cred

# Forçar recriação do banco
.\scripts\Setup-SQLHealthMonitorDatabase.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -Force
```

### Passo 2: Configuração do Sistema

```powershell
# Configurar alertas e parâmetros
.\scripts\Configure-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -EmailProfile 'DBA Mail' -EmailRecipients 'dba@company.com'
```

**Parâmetros:**
- `ServerInstance`: Instância SQL Server
- `Database`: Nome do banco de dados
- `ConfigFile`: Arquivo JSON com configurações completas
- `EmailProfile`: Perfil do Database Mail
- `EmailRecipients`: Destinatários de e-mail
- `Language`: 'EN' ou 'PTBR' (padrão: 'EN')
- `CustomThresholds`: Limiares personalizados
- `RetentionSettings`: Configuração de retenção

**Exemplos:**
```powershell
# Configuração básica
.\scripts\Configure-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -EmailProfile 'DBA Mail' -EmailRecipients 'dba@company.com'

# Configuração com limiares personalizados
$thresholds = @{
    CPU_Warning = 80
    CPU_Critical = 95
    Disk_Warning = 85
    Disk_Critical = 95
    PLE_Warning = 300
    PLE_Critical = 100
}
.\scripts\Configure-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -CustomThresholds $thresholds

# Configuração completa via arquivo JSON
.\scripts\Configure-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -ConfigFile '.\config\my-settings.json'
```

### Passo 3: Agendamento de Tarefas

```powershell
# Criar jobs do SQL Agent
.\scripts\Deploy-SQLHealthMonitorJobs.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -EmailProfile 'DBA Mail'
```

**Parâmetros:**
- `ServerInstance`: Instância SQL Server
- `Database`: Nome do banco de dados
- `ScheduleType`: 'Hourly' ou 'Daily' (padrão: 'Hourly')
- `EmailProfile`: Perfil do Database Mail
- `Language`: 'EN' ou 'PTBR' (padrão: 'EN')
- `SkipCollectionJob`: Pular criação do job de coleta
- `SkipReportJobs`: Pular criação de jobs de relatórios
- `SkipAlertJob`: Pular criação do job de alertas
- `SkipMaintenanceJob`: Pular criação do job de manutenção

**Exemplos:**
```powershell
# Agendamento padrão (15 minutos)
.\scripts\Deploy-SQLHealthMonitorJobs.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -EmailProfile 'DBA Mail'

# Agendamento diário
.\scripts\Deploy-SQLHealthMonitorJobs.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -ScheduleType 'Daily' -EmailProfile 'DBA Mail'

# Criar apenas jobs específicos
.\scripts\Deploy-SQLHealthMonitorJobs.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -SkipCollectionJob -SkipMaintenanceJob
```

### Passo 4: Validação da Instalação

```powershell
# Teste básico da instalação
.\scripts\Test-SQLHealthMonitorInstallation.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor'

# Validação completa
.\scripts\Validate-SQLHealthMonitorSetup.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor'
```

**Tipos de Teste:**
- **Básico**: Verifica objetos e configurações essenciais
- **Comprehensive**: Executa testes funcionais incluindo coleta de dados

## Configuração via Arquivo JSON

Para deployments em massa ou configurações complexas, utilize um arquivo de configuração JSON:

```json
{
  "InstallMode": "SingleInstance",
  "Connection": {
    "ServerInstance": "SQL-PRD-01",
    "AuthMethod": "Windows",
    "Database": "SQLHealthMonitor"
  },
  "Collectors": {
    "EnableAll": true,
    "Disabled": []
  },
  "Alerts": {
    "Enabled": true,
    "UseDefaults": true,
    "Recipients": ["dba@company.com"],
    "CustomThresholds": {
      "CPU_Warning": 80,
      "CPU_Critical": 95,
      "Disk_Warning": 85,
      "Disk_Critical": 95,
      "PLE_Warning": 300,
      "PLE_Critical": 100
    }
  },
  "Reports": {
    "DailyEnabled": true,
    "WeeklyEnabled": true,
    "Recipients": ["dba@company.com", "manager@company.com"],
    "Language": "EN",
    "DailyTime": "07:00",
    "WeeklyDay": "Monday",
    "WeeklyTime": "08:00"
  },
  "Email": {
    "Method": "DatabaseMail",
    "ProfileName": "DBA Mail",
    "SMTP": {
      "Server": "smtp.company.com",
      "Port": 587,
      "UseSSL": true,
      "Username": "alerts@company.com"
    }
  },
  "Scheduling": {
    "CreateAgentJobs": true,
    "CollectionInterval": "15min",
    "AlertInterval": "5min"
  },
  "Retention": {
    "UseDefaults": true,
    "RawDataDays": 30,
    "DailySummaryDays": 90,
    "WeeklySummaryDays": 365,
    "AlertHistoryDays": 365,
    "AnomalyDays": 90
  }
}
```

## Scripts SQL de Suporte

Os scripts SQL estão organizados no diretório `install/`:

- `00-create-schema.sql` - Cria schema e tabelas
- `01-create-collectors.sql` - Procedimentos de coleta
- `02-create-reports.sql` - Procedimentos de relatórios
- `03-create-alerts.sql` - Mecanismo de alertas
- `04-create-jobs.sql` - Configuração de jobs
- `05-configure.sql` - Configuração padrão
- `06-alert-history.sql` - Histórico de alertas
- `07-baselines.sql` - Engine de baselines

## Jobs do SQL Agent Criados

| Job | Schedule | Descrição |
|-----|----------|-----------|
| SQLHealthMonitor - Collection | A cada 15 min | Coleta métricas de saúde |
| SQLHealthMonitor - Daily Report | Diário às 7:00 AM | Envia relatório diário |
| SQLHealthMonitor - Weekly Report | Segunda às 8:00 AM | Envia relatório semanal |
| SQLHealthMonitor - Alert Check | A cada 5 min | Avalia limiares e envia alertas |
| SQLHealthMonitor - Maintenance | Diário às 3:00 AM | Limpeza de dados antigos |

## Personalização

### Adicionando Novos Coletores

1. Crie um novo arquivo em `collectors/collect_your_metric.sql`
2. Adicione o nome do coletor ao arquivo de configuração
3. Mapeie no script principal `Invoke-SQLHealthMonitor.ps1`

### Limiares Personalizados

```sql
-- Adicionar novo limiar
INSERT INTO [monitor].[Thresholds] (MetricName, WarningValue, CriticalValue, Description)
VALUES ('YourMetric', 80, 95, 'Descrição do seu métrico');
```

### Modelos de Relatório Personalizados

Crie novos templates em `reports/templates/` seguindo o padrão:
- `daily_en.html` - Relatório diário em inglês
- `daily_ptbr.html` - Relatório diário em português
- `weekly_en.html` - Relatório semanal em inglês
- `weekly_ptbr.html` - Relatório semanal em português

### Ajuste de Retenção

```sql
-- Alterar retenção de dados brutos para 60 dias
UPDATE [monitor].[Settings] 
SET SettingValue = '60' 
WHERE Category = 'Retention' AND SettingName = 'RawDataRetentionDays';
```

## Troubleshooting

### Problemas Comuns

1. **Permissões Insuficientes**
   - Verifique se a conta de serviço tem permissões sysadmin ou db_owner
   - Teste com `Validate-SQLHealthMonitorSetup.ps1`

2. **Database Mail Não Configurado**
   - Configure Database Mail no SQL Server
   - Ou use configuração SMTP no script de configuração

3. **Falha na Criação de Jobs**
   - Verifique permissões no msdb
   - Execute manualmente os scripts T-SQL

4. **Conexão Falhando**
   - Teste conectividade com `Test-Connection -ComputerName SQL-PRD-01`
   - Verifique firewall e portas

### Logs e Depuração

Os scripts incluem verbose logging. Use o parâmetro `-Verbose` para detalhes:

```powershell
# Executar com logs detalhados
.\scripts\Setup-SQLHealthMonitorDatabase.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -Verbose
```

## Deploy em Massa

Para múltiplos servidores:

```powershell
# Lista de servidores
$servers = @('SQL-PRD-01', 'SQL-PRD-02', 'SQL-STG-01', 'SQL-ETL-01')

# Loop de instalação
$servers | ForEach-Object {
    Write-Host "Instalando em $_..."
    .\scripts\Setup-SQLHealthMonitorDatabase.ps1 -ServerInstance $_ -Database 'SQLHealthMonitor'
    .\scripts\Configure-SQLHealthMonitor.ps1 -ServerInstance $_ -Database 'SQLHealthMonitor' -EmailProfile 'DBA Mail' -EmailRecipients 'dba@company.com'
    .\scripts\Deploy-SQLHealthMonitorJobs.ps1 -ServerInstance $_ -Database 'SQLHealthMonitor' -EmailProfile 'DBA Mail'
}
```

## Suporte e Manutenção

### Backup da Configuração

```sql
-- Exportar configuração atual
SELECT * FROM [monitor].[Settings] WHERE Category IN ('General', 'Email', 'Alerts', 'Retention');
SELECT * FROM [monitor].[Thresholds];
SELECT * FROM [monitor].[Languages];
```

### Atualização do Sistema

1. Faça backup do banco de dados
2. Pare os jobs do SQL Agent
3. Execute scripts de atualização
4. Reinicie os jobs
5. Valide a instalação

### Monitoramento do Sistema

```sql
-- Verificar status dos jobs
SELECT name, enabled, last_run_date, next_run_date 
FROM msdb.dbo.sysjobs 
WHERE name LIKE 'SQLHealthMonitor%';

-- Verificar histórico de alertas
SELECT * FROM [monitor].[AlertHistory] 
ORDER BY AlertDate DESC;

-- Verificar status da coleta
SELECT TOP 10 * FROM [monitor].[MetricData] 
ORDER BY CollectionDate DESC;
```

## Licença e Suporte

**Autor:** Lucas Allan Borges  
**Versão:** 1.0.0  
**Licença:** MIT  

Para suporte e dúvidas, consulte a documentação completa ou entre em contato com o autor.

---

*Este guia cobre a instalação genérica do SQL Health Monitor. Para implementações específicas, adapte os scripts conforme necessário para seu ambiente.*