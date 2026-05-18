/*
    SQL Health Monitor - CDC Health Collector
    Collects CDC capture/cleanup job status and latency.
    
    Schedule: Every 5 minutes
    Compatibility: SQL Server 2016+ with CDC enabled
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_CDC_Health]
AS
BEGIN
    SET NOCOUNT ON;

    -- Only collect for databases with CDC enabled
    INSERT INTO [monitor].[CdcHealthHistory]
        (DatabaseName, CaptureJobStatus, CleanupJobStatus, 
         LatencySeconds, MinLsn, MaxLsn, RetentionMinutes)
    SELECT
        d.name AS DatabaseName,
        CASE 
            WHEN cj.enabled = 1 THEN 
                CASE WHEN ja_cap.run_status = 4 THEN 'Running'
                     WHEN ja_cap.run_status = 1 THEN 'Idle'
                     ELSE 'Stopped' END
            ELSE 'Disabled'
        END AS CaptureJobStatus,
        CASE 
            WHEN clj.enabled = 1 THEN
                CASE WHEN ja_cln.run_status = 4 THEN 'Running'
                     WHEN ja_cln.run_status = 1 THEN 'Idle'
                     ELSE 'Stopped' END
            ELSE 'Disabled'
        END AS CleanupJobStatus,
        DATEDIFF(SECOND, 
            (SELECT MAX(tran_end_time) FROM cdc.lsn_time_mapping WITH (NOLOCK) 
             WHERE tran_id <> 0x00),
            SYSUTCDATETIME()
        ) AS LatencySeconds,
        CONVERT(NVARCHAR(50), sys.fn_cdc_get_min_lsn('dbo_dummy')) AS MinLsn,
        CONVERT(NVARCHAR(50), sys.fn_cdc_get_max_lsn()) AS MaxLsn,
        ct.retention AS RetentionMinutes
    FROM sys.databases d
    INNER JOIN sys.change_tracking_databases ct ON ct.database_id = d.database_id
    LEFT JOIN msdb.dbo.sysjobs cj ON cj.name LIKE 'cdc.' + d.name + '_capture'
    LEFT JOIN msdb.dbo.sysjobs clj ON clj.name LIKE 'cdc.' + d.name + '_cleanup'
    LEFT JOIN msdb.dbo.sysjobactivity ja_cap ON ja_cap.job_id = cj.job_id
        AND ja_cap.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
    LEFT JOIN msdb.dbo.sysjobactivity ja_cln ON ja_cln.job_id = clj.job_id
        AND ja_cln.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
    WHERE d.is_cdc_enabled = 1;
END;
GO
