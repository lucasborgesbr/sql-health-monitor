# Grafana Dashboard for SQL Health Monitor

Dashboard JSON e queries para visualização no Grafana.

## Arquivos

| Arquivo | Descrição |
|---------|-----------|
| `dashboards/sql-health-monitor.json` | Dashboard pronto para importar no Grafana |
| `queries/influxdb_queries.sql` | Queries SQL para coleta de dados |
| `telegraf.conf` | Configuração exemplo do Telegraf |

## Opções de Integração

### Opção 1: InfluxDB + Telegraf (Recomendado)

1. **Instale o InfluxDB** v2.x
2. **Instale o Telegraf**
3. **Configure o Telegraf** com o SQL Server input:

```toml
# telegraf.conf

[[outputs.influxdb_v2]]
  urls = ["http://localhost:8086"]
  token = "your-token"
  organization = "your-org"
  bucket = "sql-health"

[[inputs.sqlserver]]
  servers = [
    "Server=SQLSERVER01;Database=SQLHealthMonitor;appname=telegraf;Integrated Security=SSPI;",
  ]
  query_version = "18"
  
  # Queries customizadas
  [[inputs.sqlserver.query]]
    measurement_name = "sql_health"
    query = """SELECT ... suas queries aqui ..."""
```

4. **Importe o dashboard**:
   - No Grafana: Dashboards → Import
   - Carregue o arquivo `sql-health-monitor.json`
   - Selecione o datasource InfluxDB

### Opção 2: Prometheus + sql_exporter

1. **Instale o sql_exporter**
2. **Configure queries** no formato Prometheus:

```yaml
# queries.yml
metrics:
  - name: sql_health_cpu
    help: "SQL Server CPU percentage"
    values:
      - cpu_pct
    query: |
      SELECT SqlCpuPct AS cpu_pct 
      FROM [monitor].[CpuHistory] 
      ORDER BY CollectedAt DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY

  - name: sql_health_ple
    help: "Page Life Expectancy in seconds"
    values:
      - ple_seconds
    query: |
      SELECT PageLifeExpectancy AS ple_seconds 
      FROM [monitor].[MemoryHistory] 
      ORDER BY CollectedAt DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY
```

3. **Adicione ao prometheus.yml**:
```yaml
scrape_configs:
  - job_name: 'sql-health'
    static_configs:
      - targets: ['localhost:9399']
```

### Opção 3: Direct MSSQL (Grafana 10+)

O Grafana 10+ suporta SQL Server diretamente:

1. **Adicione datasource**: SQL Server (mssql)
2. **Crie painéis** com queries direto no Grafana

## Dashboard Painéis

### Overview
- **CPU Usage %** - Utilização do SQL Server
- **Page Life Expectancy** - Tempo de vida das páginas em buffer
- **Blocking Sessions** - Sessões bloqueando outras
- **Hours Since Backup** - Horas desde último backup

### CPU & Performance
- CPU usage histórico
- Batch Requests/sec
- Compilations/Recompilations

### Memory & Buffer
- Page Life Expectancy histórico
- Buffer Cache Hit Ratio
- Memory Grants Pending

### Disk & Storage
- Disk Space % por drive
- Read/Write Latency (ms)
- Combined Latency

### Wait Statistics
- Top 5 Wait Types por tempo
- Tabela de Waits atuais
- Signal Wait %

### Availability & Backups
- Status de AGs
- Histórico de backups
- Tempo desde último backup

### Sessions & Connections
- Active Sessions histórico
- Blocked Sessions
- Waiting Tasks

### Alerts
- Alertas por severidade
- Tendência de alertas

## Variáveis de Template

O dashboard usa variáveis para filtro:

| Variável | Valores | Descrição |
|----------|---------|-----------|
| DS_INFLUXDB | Datasources | Datasource do InfluxDB |

## Customização

### Adicionar Servidor
Edite a variável `ServerName` nas queries do Telegraf.

### Ajustar Thresholds
Os thresholds estão definidos nos painéis. Edite diretamente no JSON ou no Grafana.

### Adicionar Métricas
1. Adicione query no Telegraf
2. Adicione painel no dashboard
3. Referencie a measurement nova

## Troubleshooting

### Sem dados no Dashboard
1. Verifique se o Telegraf está rodando: `telegraf --test`
2. Teste queries direto no InfluxDB
3. Verifique se o bucket/measurement está correto

### Dashboard não carrega
- Grafana 9+ necessário
- Datasource InfluxDB configurado corretamente

## Recursos Adicionais

- [Grafana Dashboards](https://grafana.com/docs/grafana/latest/dashboards/)
- [InfluxDB + Telegraf](https://www.influxdata.com/integration/microsoft-sql-server/)
- [sql_exporter](https://github.com/burningalchemist/sql_exporter)
