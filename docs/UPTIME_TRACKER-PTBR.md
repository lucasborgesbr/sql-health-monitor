# SQL Health Monitor - Documentação do Uptime Tracker

## Visão Geral

O SQL Health Monitor inclui um sistema completo de monitoramento de uptime que rastreia a disponibilidade do serviço e calcula a conformidade SLA. Este recurso é projetado para ambientes empresariais que precisam rastrear porcentagens de uptime e tendências de incidentes para relatórios de negócios e conformidade.

## Recursos

- **Detecção Automática de Incidentes** - Identifica tempo de inatividade não planejado, manutenção planejada e falhas críticas
- **Rastreamento de Conformidade SLA** - Monitora a porcentagem de uptime em relação aos alvos de negócio
- **Relatórios Mensais** - Resumos mensais detalhados de uptime com análise de tendências
- **Classificação de Incidentes** - Categoriza incidentes por tipo, severidade e impacto nos negócios
- **Dashboard em Tempo Real** - Status atual de uptime e incidentes ativos

## Instalação

```sql
-- Instalar componentes de rastreamento de uptime
:r install/09-uptime-tracker.sql

-- Validar instalação
:r validate_uptime_tracker.sql
```

## Uso

### Operações Básicas

```sql
-- Executar rastreamento de uptime horário
EXEC monitor.usp_Collect_UptimeTracker;

-- Gerar relatório mensal de uptime
EXEC monitor.usp_Generate_MonthlyUptimeReport @ReportMonth = '2026-06-01';

-- Visualizar status atual de uptime
SELECT * FROM monitor.vw_CurrentUptimeStatus;

-- Visualizar resumo mensal
SELECT * FROM monitor.vw_MonthlyUptimeSummary;

-- Visualizar incidentes ativos
SELECT * FROM monitor.vw_ActiveIncidents;
```

### Consultas Avançadas

```sql
-- Visualizar tendências de incidentes
SELECT * FROM monitor.vw_IncidentTrends 
ORDER BY MonthStart DESC, IncidentCount DESC;

-- Visualizar histórico de conformidade SLA
SELECT * FROM monitor.vw_SLAComplianceHistory
ORDER BY MonthStart DESC;

-- Visualizar dashboard de uptime
SELECT * FROM monitor.vw_UptimeDashboard;
```

## Classificação de Incidentes

### Tipos de Incidentes

| Tipo | Descrição | Exemplos |
|------|-----------|----------|
| **Planejado** | Manutenção agendada | Atualizações, patches, migrações |
| **Não Planejado** | Falhas inesperadas | Falhas de hardware, bugs de software |
| **Emergencial** | Falhas críticas que exigem ação imediata | Interrupção completa do serviço |

### Níveis de Severidade

| Nível | Impacto | Tempo de Resposta |
|-------|---------|-------------------|
| **Crítico** | Interrupção completa do serviço | < 15 minutos |
| **Alto** | Degradação severa | < 1 hora |
| **Médio** | Impacto notável | < 4 horas |
| **Baixo** | Impacto mínimo | < 24 horas |

### Categorias

| Categoria | Descrição |
|----------|-----------|
| **Database** | Falhas dentro do SQL Server |
| **Server** | Falhas de SO/hardware |
| **Network** | Problemas de conectividade |
| **Application** | Falhas no nível da aplicação |

## Configuração SLA

### Definindo Alvos SLA

```sql
-- Configurar alvos SLA
INSERT INTO monitor.Settings (Category, SettingName, SettingValue, Description)
VALUES ('SLA', 'TargetUptime', '99.9', 'Porcentagem de uptime alvo');

-- Definir tempos de resposta de incidentes
INSERT INTO monitor.Settings (Category, SettingName, SettingValue, Description)
VALUES ('SLA', 'IncidentResponseTime', '60', 'Tempo de resposta para incidentes críticos (minutos)');

-- Configurar geração de relatórios mensais
INSERT INTO monitor.Settings (Category, SettingName, SettingValue, Description)
VALUES ('SLA', 'UptimeReportDay', '1', 'Dia do mês para gerar relatório de uptime');
```

### Limites SLA

```sql
-- Adicionar limites SLA ao sistema de alertas
INSERT INTO monitor.Thresholds (MetricName, WarningValue, CriticalValue, Operator, Description)
VALUES 
('SLA_UptimePercentage', 99.5, 99.0, '<', 'Limite de porcentagem de uptime'),
('SLA_DowntimeMinutes', 60, 1440, '>=', 'Limite de tempo de inatividade (minutos)'),
('SLA_IncidentResponseTime', 60, 240, '>=', 'Limite de tempo de resposta (minutos)');
```

## Coleta de Dados

### Coleta Horária

O rastreador de uptime executa automaticamente a cada hora e realiza as seguintes operações:

1. **Detecção de Incidentes** - Varre alertas, logs de erro, falhas de jobs e eventos do sistema
2. **Cálculo de Uptime** - Calcula a porcentagem de uptime para a hora
3. **Rastreamento SLA** - Compara o uptime real com o alvo SLA
4. **Registro de Incidentes** - Registra incidentes detectados com classificação
5. **Armazenamento de Períodos** - Armazena períodos horários, diários e mensais

### Fontes de Dados

O rastreador de uptime coleta dados de múltiplas fontes:

- **Sistema de Alertas** - Alertas críticos e de aviso
- **Log de Erros** - Mensagens de erro do SQL Server
- **Histórico de Jobs** - Falhas de jobs do SQL Agent
- **Grupos de Disponibilidade** - Estados de réplica AlwaysOn
- **Eventos do Sistema** - Disponibilidade de serviço e rastreamento de deadlocks
- **Fontes Customizadas** - Entrada manual de incidentes

## Relatórios

### Relatórios Mensais

O relatório mensal de uptime inclui:

- **Resumo Executivo** - Uptime geral e conformidade SLA
- **Quebra de Incidentes** - Por tipo, categoria e severidade
- **Análise SLA** - Rastreamento de conformidade e violações
- **Recomendações** - Sugestões de melhorias acionáveis
- **Análise de Tendências** - Desempenho histórico e previsão

### Geração de Relatórios

```sql
-- Gerar relatório para mês específico
EXEC monitor.usp_Generate_MonthlyUptimeReport 
    @ReportMonth = '2026-06-01',
    @ServerName = 'SQL-PROD-01',
    @Environment = 'PRODUÇÃO';
```

## Views e Consultas

### Status Atual

```sql
-- Status de uptime em tempo real
SELECT 
    CurrentUptimePercentage,
    CurrentStatusIcon,
    MinutesSinceLastUpdate,
    ActiveIncidents,
    ActiveCriticalIncidents,
    CurrentSLAStatus
FROM monitor.vw_UptimeDashboard;
```

### Análise Histórica

```sql
-- Tendências mensais de uptime
SELECT 
    MonthStart,
    MonthlyUptimePercentage,
    TotalIncidents,
    CriticalIncidents,
    SLAStatus
FROM monitor.vw_MonthlyUptimeSummary
ORDER BY MonthStart DESC;

-- Tendências de classificação de incidentes
SELECT 
    MonthStart,
    IncidentType,
    Category,
    Severity,
    IncidentCount,
    TotalDowntimeMinutes
FROM monitor.vw_IncidentTrends
ORDER BY MonthStart DESC, IncidentCount DESC;
```

## Monitoramento e Alertas

### Integração de Alertas

O rastreador de uptime integra-se com o sistema de alertas existente:

- **Alertas de Uptime** - Disparados quando o uptime cai abaixo dos limites
- **Alertas de Incidentes** - Incidentes críticos geram alertas imediatos
- **Violações SLA** - Violações de conformidade SLA são rastreadas e reportadas
- **Escalonamento** - Escalonamento automático para incidentes críticos

### Configuração de Alertas

```sql
-- Habilitar alertas de uptime
UPDATE monitor.Settings 
SET SettingValue = '1' 
WHERE Category = 'Features' AND SettingName = 'CollectUptimeTracker';

-- Configurar limites de alertas
UPDATE monitor.Thresholds 
SET CriticalValue = 99.0 
WHERE MetricName = 'SLA_UptimePercentage';
```

## Solução de Problemas

### Problemas Comuns

#### 1. Sem Dados de Uptime

```sql
-- Verificar se o rastreador de uptime está habilitado
SELECT * FROM monitor.Settings 
WHERE Category = 'Features' AND SettingName = 'CollectUptimeTracker';

-- Executar coleta manual
EXEC monitor.usp_Collect_UptimeTracker;

-- Verificar dados recentes
SELECT TOP 10 * FROM monitor.UptimePeriods 
ORDER BY PeriodEnd DESC;
```

#### 2. Detecção Incorreta de Incidentes

```sql
-- Verificar fontes de incidentes
SELECT * FROM monitor.IncidentSources 
WHERE DetectedAt >= DATEADD(DAY, -1, GETDATE());

-- Verificar detalhes dos incidentes
SELECT * FROM monitor.Incidents 
WHERE DetectedAt >= DATEADD(DAY, -1, GETDATE());

-- Verificar histórico de alertas para eventos recentes
SELECT TOP 10 * FROM monitor.AlertHistory 
ORDER BY FiredAt DESC;
```

#### 3. Violações SLA

```sql
-- Verificar conformidade SLA
SELECT * FROM monitor.SLATracking 
WHERE PeriodStart >= DATEADD(MONTH, -1, GETDATE());

-- Revisar configurações SLA
SELECT * FROM monitor.Settings 
WHERE Category = 'SLA';

-- Verificar períodos de uptime para violações
SELECT * FROM monitor.UptimePeriods 
WHERE UptimePercentage < 99.0 
ORDER BY PeriodEnd DESC;
```

### Otimização de Desempenho

#### Manutenção de Índices

```sql
-- Recriar índices para tabelas grandes
ALTER INDEX IX_Incidents_Date ON monitor.Incidents REBUILD;
ALTER INDEX IX_UptimePeriods_Date ON monitor.UptimePeriods REBUILD;
ALTER INDEX IX_SLATracking_Date ON monitor.SLATracking REBUILD;
```

#### Retenção de Dados

```sql
-- Limpar dados antigos (mais de 12 meses)
DELETE FROM monitor.UptimePeriods 
WHERE PeriodStart < DATEADD(MONTH, -12, GETDATE());

DELETE FROM monitor.SLATracking 
WHERE PeriodStart < DATEADD(MONTH, -12, GETDATE());

DELETE FROM monitor.Incidents 
WHERE ResolvedAt < DATEADD(MONTH, -6, GETDATE());
```

## Melhores Práticas

### 1. Manutenção Regular

- Agendar manutenção mensal de índices
- Implementar políticas de retenção de dados
- Revisar regularmente os alvos SLA
- Atualizar classificação de incidentes conforme necessário

### 2. Monitoramento

- Monitorar taxas de sucesso da coleta
- Rastrear eficácia da geração de alertas
- Revisar tempos de resposta de incidentes
- Analisar tendências de uptime para padrões

### 3. Relatórios

- Gerar relatórios mensais para gestão
- Rastrear conformidade SLA ao longo do tempo
- Documentar incidentes principais e causas raiz
- Usar tendências para planejamento de capacidade

### 4. Integração

- Integrar com ferramentas de monitoramento existentes
- Exportar dados para inteligência de negócios
- Configurar notificações automatizadas
- Criar dashboards customizados

## Segurança

### Controle de Acesso

- Limitar acesso a dados de uptime baseado em função
- Implementar logging de auditoria para mudanças
- Usar conexões criptografadas para acesso remoto
- Revisões de segurança regulares

### Proteção de Dados

- Fazer backup regular de dados de uptime
- Implementar procedimentos de recuperação de desastre
- Monitorar acesso não autorizado
- Usar armazenamento seguro para dados sensíveis

## Histórico de Versões

### Versão 1.0.0
- Lançamento inicial com rastreamento de uptime
- Sistema de classificação de incidentes
- Rastreamento de conformidade SLA
- Capacidades de relatório mensal
- Views de dashboard em tempo real

## Suporte

Para problemas ou dúvidas sobre o rastreador de uptime:

1. Verificar a seção de solução de problemas
2. Revisar a documentação do SQL Health Monitor
3. Abrir uma issue no GitHub
4. Contatar o time de desenvolvimento

---

*Esta documentação faz parte do projeto SQL Health Monitor por Lucas Allan Borges*