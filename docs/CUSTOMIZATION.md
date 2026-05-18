# Customization Guide

## Adding Custom Collectors

### 1. Create the Collector Procedure

Follow the naming convention `[monitor].[usp_Collect_YourMetric]`:

```sql
CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_YourMetric]
AS
BEGIN
    SET NOCOUNT ON;

    -- Your collection logic here
    INSERT INTO [monitor].[YourMetricHistory] (MetricColumn1, MetricColumn2)
    SELECT value1, value2
    FROM your_source;
END;
GO
```

### 2. Create the History Table

```sql
IF OBJECT_ID('monitor.YourMetricHistory', 'U') IS NULL
CREATE TABLE [monitor].[YourMetricHistory] (
    Id          BIGINT IDENTITY(1,1) PRIMARY KEY,
    CollectedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    -- Your columns here
    INDEX IX_YourMetric_Date NONCLUSTERED (CollectedAt)
);
GO
```

### 3. Register the Feature Flag

```sql
INSERT INTO [monitor].[Settings] (Category, SettingName, SettingValue, Description, DataType)
VALUES ('Features', 'CollectYourMetric', '1', 'Enable your custom metric', 'bool');
```

### 4. Add to Master Collector

Update `install/01-create-collectors.sql` to include your new collector in the `@Collectors` table:

```sql
INSERT INTO @Collectors (ProcName, FeatureFlag) VALUES
    -- ... existing collectors ...
    ('monitor.usp_Collect_YourMetric', 'CollectYourMetric');
```

### 5. Add Retention Support

The purge procedure automatically handles any table with a `CollectedAt` column. To add your table, update `maintenance/purge_old_data.sql`:

```sql
INSERT INTO @Tables VALUES
    ('monitor.YourMetricHistory', 'CollectedAt', @DataCutoff);
```

## Adding Custom Thresholds

### 1. Define the Threshold

```sql
INSERT INTO [monitor].[Thresholds] (MetricName, WarningValue, CriticalValue, Operator, Description)
VALUES ('YourMetric_Name', 80, 95, '>=', 'Description of your metric threshold');
```

### 2. Feed the Alert Engine

The alert engine reads from `@Metrics` table variable. Add your metric collection in `alerts/alert_engine.sql`:

```sql
-- Your custom metric
INSERT INTO @Metrics (MetricName, CurrentValue, Context)
SELECT 'YourMetric_Name', CAST(your_value AS DECIMAL(18,2)), 'optional context'
FROM [monitor].[YourMetricHistory]
WHERE CollectedAt = (SELECT MAX(CollectedAt) FROM [monitor].[YourMetricHistory]);
```

## Adding Custom Alert Actions

Edit `alerts/alert_actions.sql` to add automated responses:

```sql
-- In usp_AlertAction_Execute, add a new IF block:
IF @MetricName = 'YourMetric_Name' AND @Severity = 'Critical'
BEGIN
    -- Your automated action here
    -- Examples: kill session, shrink file, send extra notification
    SET @ActionTaken = 'Description of what was done';
END;
```

## Adding a New Language

### 1. Add All String Keys

```sql
-- Copy from English and translate
INSERT INTO [monitor].[Languages] (LanguageCode, StringKey, StringValue)
SELECT 'es', StringKey, StringValue  -- Spanish example
FROM [monitor].[Languages]
WHERE LanguageCode = 'en';

-- Then update the StringValue for each key
UPDATE [monitor].[Languages] SET StringValue = 'Informe Diario de Salud SQL'
WHERE LanguageCode = 'es' AND StringKey = 'report.daily.title';
-- ... repeat for all keys
```

### 2. Required String Keys

| Key | Purpose |
|-----|---------|
| `report.daily.title` | Daily report title |
| `report.daily.subtitle` | Daily report subtitle |
| `report.weekly.title` | Weekly report title |
| `report.weekly.subtitle` | Weekly report subtitle |
| `section.*` | Section headers |
| `status.*` | Status labels |
| `alert.*` | Alert message templates |

### 3. Update Report Procedures

The report procedures use `CASE @Language WHEN 'ptbr' THEN ... ELSE ...` for inline strings. For a new language, add another `WHEN` clause:

```sql
CASE @Language 
    WHEN 'ptbr' THEN 'Texto em português'
    WHEN 'es' THEN 'Texto en español'
    ELSE 'English text' 
END
```

## Customizing Email Templates

### HTML Structure

Reports generate inline-styled HTML for maximum email client compatibility. Key style variables:

| Element | Color | Usage |
|---------|-------|-------|
| Header gradient | `#0f172a → #1e3a5f` | Daily report header |
| Header gradient | `#1e3a5f → #2563eb` | Weekly report header |
| Healthy | `#059669` | Green status |
| Warning | `#d97706` | Amber status |
| Critical | `#dc2626` | Red status |
| Table header | `#0f172a` | Dark table headers |
| Alt row | `#f8fafc` | Zebra striping |

### Adding Sections to Reports

In `reports/daily_health_check.sql` or `reports/weekly_deep_dive.sql`, add a new section:

```sql
-- Section header
SET @HTML = @HTML + '<h2 style="font-size:16px;color:#0f172a;border-bottom:2px solid #e2e8f0;padding-bottom:8px;margin-top:24px;">'
    + 'Your Section Title</h2>';

-- Table with data
SET @HTML = @HTML + '<table style="width:100%;border-collapse:collapse;font-size:12px;">';
-- ... your table rows ...
SET @HTML = @HTML + '</table>';
```

## Modifying Collection Frequency

SQL Agent job schedules are set in `install/04-create-jobs.sql`. To change frequency:

```sql
-- Example: Change collectors to every 10 minutes instead of 5
EXEC msdb.dbo.sp_update_jobschedule
    @job_name = N'SQL Health Monitor - Collectors',
    @name = N'Every 5 Minutes',
    @freq_subday_interval = 10;  -- Changed from 5 to 10
```

## Performance Considerations

- **Index Health collector** is the heaviest (scans `sys.dm_db_index_physical_stats`). Consider running it less frequently on large databases by creating a separate job with a longer interval.
- **Top Queries collector** captures from `sys.dm_exec_query_stats`. On busy servers, consider increasing the collection interval.
- **Purge batch size** defaults to 10,000 rows per delete. Increase for faster cleanup on large datasets, decrease if log growth is a concern.

```sql
-- Run purge with larger batches
EXEC [monitor].[usp_Maintenance_PurgeOldData] @BatchSize = 50000;
```
