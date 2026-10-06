/*
    SQL Health Monitor - Baseline Procedures (2017+)
    ===============================================

    The baseline capture and anomaly-detection procedures depend on
    STRING_AGG (2017+) and PERCENTILE_CONT (2016+). This script is only
    run on SQL Server 2017 or later, gated by Install.ps1.

    See 07-baselines.sql for the schema and configuration that this
    builds on (the table and config seeding are 2012+ compatible and
    always run).
*/

SET NOCOUNT ON;
GO

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS TINYINT) < 14
BEGIN
    PRINT '  Skipped: baseline procedures require SQL Server 2017+ (STRING_AGG).';
    RETURN;
END
GO

----------------------------------------------------------------------
-- CAPTURE BASELINE PROCEDURE
----------------------------------------------------------------------
:r baselines\capture_baseline.sql
GO

----------------------------------------------------------------------
-- DETECT ANOMALIES PROCEDURE
----------------------------------------------------------------------
:r baselines\detect_anomalies.sql
GO

PRINT '  → [monitor].[usp_Baseline_Capture] - Weekly baseline capture';
PRINT '  → [monitor].[usp_Baseline_DetectAnomalies] - Real-time anomaly detection';
GO