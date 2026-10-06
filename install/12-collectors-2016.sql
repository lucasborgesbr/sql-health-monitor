/*
    SQL Health Monitor - Query Store Collector (2016+)
    ==================================================

    Deploys collectors/collect_query_store.sql. Skipped on SQL Server
    2014 and earlier: the procedure uses sys.query_store_* views that
    only exist in 2016+.

    collectors/collect_live_sessions.sql and
    collectors/collect_index_recommendations.sql are deployed in the
    main install chain -- their features exist in 2012+.
*/

SET NOCOUNT ON;
GO

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS TINYINT) < 13
BEGIN
    PRINT '  Skipped collectors\collect_query_store.sql (requires SQL Server 2016+; uses sys.query_store_*).';
    RETURN;
END
GO

:r collectors\collect_query_store.sql
GO