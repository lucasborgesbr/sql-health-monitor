/*
    On-Demand Health Check (SQL Server 2016+)
    =========================================

    Deploys [monitor].[usp_HealthCheck] -- a single-shot snapshot of 10
    independent health checks. Run it from SSMS or call from a job to
    triage a misbehaving instance. Idempotent: replaces the procedure
    in place.

    Skipped on SQL Server 2014 and earlier: the procedure uses
    sys.dm_db_stats_properties (a DMF added in 2016).

    See ../diagnostics/usp_HealthCheck.sql for the implementation.
*/

SET NOCOUNT ON;
GO

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS TINYINT) < 13
BEGIN
    PRINT '  Skipped diagnostics\usp_HealthCheck.sql (requires SQL Server 2016+; uses sys.dm_db_stats_properties).';
    RETURN;
END
GO

-- Idempotent deploy: drop any existing copy before re-creating. The
-- procedure body itself uses CREATE (not CREATE OR ALTER) so SQL Server
-- 2014 would fail to parse it.
IF OBJECT_ID(N'monitor.usp_HealthCheck', 'P') IS NOT NULL
    DROP PROCEDURE [monitor].[usp_HealthCheck];
GO

:r diagnostics\usp_HealthCheck.sql
GO

PRINT '+ Procedure [monitor].[usp_HealthCheck] installed.';
GO