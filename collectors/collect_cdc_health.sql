/*
    SQL Health Monitor - CDC Health Collector
    Collects CDC capture/cleanup job status and latency.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+ with CDC enabled
*/

IF OBJECT_ID('[monitor].[usp_Collect_CDC_Health]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_CDC_Health] AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_CDC_Health]', 'P') IS NULL
    EXEC('CREATE PROCEDURE [monitor].[usp_Collect_CDC_Health] AS SET NOCOUNT ON; PRINT ''Placeholder'';');
GO
ALTER PROCEDURE [monitor].[usp_Collect_CDC_Health]
AS
BEGIN
    SET NOCOUNT ON;

    -- Skip entirely if no databases have CDC enabled
    IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE is_cdc_enabled = 1)
    BEGIN
        PRINT 'CDC not enabled on any database — skipping collection.';
        RETURN;
    END

    -- cdc.lsn_time_mapping is per-database and cannot be cross-DB queried directly;
    -- LatencySeconds/MinLsn/MaxLsn are left NULL — populate via dynamic SQL if needed.
    INSERT INTO [monitor].[CdcHealthHistory]
        (DatabaseName, CaptureJobStatus, CleanupJobStatus,
         LatencySeconds, MinLsn, MaxLsn, RetentionMinutes)
    SELECT
        d.name AS DatabaseName,
        CASE
            WHEN cj.enabled = 1 THEN
                CASE WHEN ja_cap.start_execution_date IS NOT NULL AND ja_cap.stop_execution_date IS NULL THEN 'Running'
                     ELSE 'Idle' END
            ELSE 'Disabled'
        END AS CaptureJobStatus,
        CASE
            WHEN clj.enabled = 1 THEN
                CASE WHEN ja_cln.start_execution_date IS NOT NULL AND ja_cln.stop_execution_date IS NULL THEN 'Running'
                     ELSE 'Idle' END
            ELSE 'Disabled'
        END AS CleanupJobStatus,
        NULL AS LatencySeconds,
        NULL AS MinLsn,
        NULL AS MaxLsn,
        NULL AS RetentionMinutes
    FROM sys.databases d
    LEFT JOIN msdb.dbo.sysjobs cj  ON cj.name  = 'cdc.' + d.name + '_capture'
    LEFT JOIN msdb.dbo.sysjobs clj ON clj.name = 'cdc.' + d.name + '_cleanup'
    LEFT JOIN msdb.dbo.sysjobactivity ja_cap ON ja_cap.job_id = cj.job_id
        AND ja_cap.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
    LEFT JOIN msdb.dbo.sysjobactivity ja_cln ON ja_cln.job_id = clj.job_id
        AND ja_cln.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
    WHERE d.is_cdc_enabled = 1;
END;
GO