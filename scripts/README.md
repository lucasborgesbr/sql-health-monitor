# SQL Health Monitor - Scripts de Instalação Genérica

Este diretório contém scripts PowerShell genéricos para instalação, configuração e validação do SQL Health Monitor. Todos os scripts são projetados para serem portáteis e sem dependências hardcode de ambientes específicos.

## Estrutura dos Scripts

### Scripts Principais

1. **Install-SQLHealthMonitor.ps1** - Script principal que orquestra toda a instalação
2. **Setup-SQLHealthMonitorDatabase.ps1** - Cria banco de dados, schemas, tabelas e procedimentos
3. **Configure-SQLHealthMonitor.ps1** - Configura alertas, destinatários e parâmetros
4. **Deploy-SQLHealthMonitorJobs.ps1** - Agenda tarefas via SQL Agent
5. **Test-SQLHealthMonitorInstallation.ps1** - Teste básico da instalação
6. **Validate-SQLHealthMonitorSetup.ps1** - Validação completa do setup

### Configuração

- **config/example-config.json** - Arquivo de configuração JSON completo
- **config/default.json** - Configuração padrão do sistema
- **config/answer-file-sample.json** - Amostra de arquivo de respostas

## Uso Rápido

### Instalação Completa (Recomendado)

```powershell
# Instalação completa com parâmetros básicos
.\Install-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor'

# Instalação com arquivo de configuração
.\Install-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -ConfigFile '.\config\example-config.json'

# Instalação com autenticação SQL
$cred = Get-Credential
.\Install-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -AuthMethod 'Sql' -SqlCredential $cred
```

### Instalação Passo a Passo

#### 1. Setup do Banco de Dados

```powershell
.\Setup-SQLHealthMonitorDatabase.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor'
```

#### 2. Configuração do Sistema

```powershell
.\Configure-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -EmailProfile 'DBA Mail' -EmailRecipients 'dba@company.com'
```

#### 3. Agendamento de Tarefas

```powershell
.\Deploy-SQLHealthMonitorJobs.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -EmailProfile 'DBA Mail'
```

#### 4. Validação

```powershell
.\Validate-SQLHealthMonitorSetup.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor'
```

## Parâmetros Comuns

### ServerInstance
- **Descrição**: Instância SQL Server
- **Exemplos**: 'SQL-PRD-01', 'localhost', 'SERVER\INSTANCE'

### Database
- **Descrição**: Nome do banco de dados
- **Padrão**: 'SQLHealthMonitor'

### AuthMethod
- **Opções**: 'Windows' (padrão), 'Sql'
- **Descrição**: Método de autenticação

### Language
- **Opções**: 'EN', 'PTBR'
- **Padrão**: 'EN'
- **Descrição**: Idioma dos relatórios

### EmailProfile
- **Descrição**: Nome do perfil do Database Mail
- **Exemplo**: 'DBA Mail'

### EmailRecipients
- **Descrição**: Destinatários de e-mail
- **Formato**: Array de strings ou string separada por vírgulas
- **Exemplo**: 'dba@company.com,manager@company.com'

## Configuração JSON

Para deployments complexos, utilize arquivos de configuração JSON:

```json
{
  "Connection": {
    "ServerInstance": "SQL-PRD-01",
    "AuthMethod": "Windows",
    "Database": "SQLHealthMonitor"
  },
  "Alerts": {
    "Enabled": true,
    "Recipients": ["dba@company.com"],
    "CustomThresholds": {
      "CPU_Warning": 80,
      "CPU_Critical": 95
    }
  },
  "Email": {
    "Method": "DatabaseMail",
    "ProfileName": "DBA Mail"
  },
  "Scheduling": {
    "CreateAgentJobs": true,
    "CollectionInterval": "15min"
  }
}
```

## Modo WhatIf

Todos os scripts suportam o parâmetro `-WhatIf` para pré-visualizar ações:

```powershell
# Pré-visualizar instalação completa
.\Install-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -WhatIf

# Pré-visualizar setup do banco de dados
.\Setup-SQLHealthMonitorDatabase.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -WhatIf
```

## Deploy em Massa

Para múltiplos servidores:

```powershell
# Lista de servidores
$servers = @('SQL-PRD-01', 'SQL-PRD-02', 'SQL-STG-01')

# Instalação em massa
$servers | ForEach-Object {
    Write-Host "Instalando em $_..."
    .\Install-SQLHealthMonitor.ps1 -ServerInstance $_ -Database 'SQLHealthMonitor' -EmailProfile 'DBA Mail' -EmailRecipients 'dba@company.com'
}
```

## Validação e Testes

### Teste Básico
```powershell
.\Test-SQLHealthMonitorInstallation.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor'
```

### Validação Completa
```powershell
.\Validate-SQLHealthMonitorSetup.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor'
```

## Personalização

### Adicionando Novos Coletores
1. Crie scripts em `../collectors/`
2. Adicione ao arquivo de configuração
3. Atualize o script principal se necessário

### Limiares Personalizados
```powershell
# Via parâmetro
$thresholds = @{
    CPU_Warning = 80
    CPU_Critical = 95
    Disk_Warning = 85
}
.\Configure-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -CustomThresholds $thresholds
```

### Configuração de Retenção
```powershell
# Via parâmetro
$retention = @{
    RawDataDays = 30
    DailySummaryDays = 90
    AlertHistoryDays = 365
}
.\Configure-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -RetentionSettings $retention
```

## Troubleshooting

### Logs Detalhados
Use o parâmetro `-Verbose` para logs detalhados:

```powershell
.\Install-SQLHealthMonitor.ps1 -ServerInstance 'SQL-PRD-01' -Database 'SQLHealthMonitor' -Verbose
```

### Erros Comuns

1. **Permissões**: Verifique permissões sysadmin ou db_owner
2. **Database Mail**: Configure ou use SMTP
3. **Conexão**: Teste conectividade com `Test-Connection`
4. **Módulos**: Instale dbatools com `Install-Module dbatools`

### Validação de Pré-requisitos
```powershell
# Testar conectividade
Test-Connection -ComputerName SQL-PRD-01

# Verificar dbatools
Get-Module dbatools -ListAvailable

# Testar autenticação
$sqlParams = @{
    SqlInstance = 'SQL-PRD-01'
    Database = 'master'
}
Connect-DbaInstance @sqlParams
```

## Suporte

Para dúvidas específicas:
- Consulte o guia completo em `../docs/INSTALLATION-GUIDE.md`
- Verifique logs de instalação
- Teste componentes individualmente com scripts passo a passo

---

*Todos os scripts são genéricos e podem ser adaptados para qualquer ambiente específico removendo ou ajustando parâmetros conforme necessário.*