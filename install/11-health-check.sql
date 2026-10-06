/*
    On-Demand Health Check
    ======================

    Deploys [monitor].[usp_HealthCheck] -- a single-shot snapshot of 10
    independent health checks. Run it from SSMS or call from a job to
    triage a misbehaving instance. Idempotent: replaces the procedure
    in place.

    See ../diagnostics/usp_HealthCheck.sql for the implementation.
*/

:r diagnostics\usp_HealthCheck.sql
GO

PRINT '+ Procedure [monitor].[usp_HealthCheck] installed.';
GO