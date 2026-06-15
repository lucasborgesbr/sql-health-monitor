/*
    SQL Health Monitor - Collect All Instances
    Wrapper procedure that iterates registered servers and collects health snapshots.
    
    Uses linked servers or sp_executesql with AT clause for remote execution.
    Stores results in InstanceHealthSnapshot for cross-instance comparison.
    
    Schema: [monitor]
    Compatibility: SQL Server 2016+
    Author: Lucas Allan Borges
    
    Parameters:
        @Environment    NVARCHAR(20) - Filter by environment (NULL = all active)
        @InstanceName   NVARCHAR(256)- Specific instance (NULL = all matching)
        @TimeoutSeconds INT          - Per-instance timeout (default: 60)
        @DebugMode      BIT          - Print execution plan without running (default: 0)
    
    Example Usage:
        -- Collect from all active instances
        EXEC [monitor].[usp_CollectAllInstances];
        
        -- Collect only production
        EXEC [monitor].[usp_CollectAllInstances] @Environment = 'PRD';
        
        -- Collect specific instance
        EXEC [monitor].[usp_CollectAllInstances] @InstanceName = 'DBPRD';
        
        -- Debug mode
        EXEC [monitor].[usp_CollectAllInstances] @DebugMode = 1;
*/

USE [SQLHealthMonitor];
GO

/*
    SQL Health Monitor - Collect All Instances
    Wrapper procedure that iterates registered servers and collects health snapshots.
    
    Uses linked servers or sp_executesql with AT clause for remote execution.
    Stores results in InstanceHealthSnapshot for cross-instance comparison.
    
    Schema: [monitor]
    Compatibility: SQL Server 2016+
    Author: Lucas Allan Borges
    
    Parameters:
        @Environment    NVARCHAR(20) - Filter by environment (NULL = all active)
        @InstanceName   NVARCHAR(256)- Specific instance (NULL = all matching)
        @TimeoutSeconds INT          - Per-instance timeout (default: 60)
        @DebugMode      BIT          - Print execution plan without running (default: 0)
    
    Example Usage:
        -- Collect from all active instances
        EXEC [monitor].[usp_CollectAllInstances];
        
        -- Collect only production
        EXEC [monitor].[usp_CollectAllInstances] @Environment = 'PRD';
        
        -- Collect specific instance
        EXEC [monitor].[usp_CollectAllInstances] @InstanceName = 'DBPRD';
        
        -- Debug mode
        EXEC [monitor].[usp_CollectAllInstances] @DebugMode = 1;
*/

USE [SQLHealthMonitor];
GO

IF OBJECT_ID('[monitor].[usp_CollectAllInstances]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_CollectAllInstances] @Environment    NVARCHAR(20) = NULL, @InstanceName   NVARCHAR(256) = NULL, @TimeoutSeconds INT = NULL, @DebugMode      BIT = NULL AS SET NOCOUNT ON; BEGIN DECLARE @D INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_CollectAllInstances]', 'P') IS NULL
    EXEC('
    CREATE PROCEDURE [monitor].[usp_CollectAllInstances]
        
        @Environment    NVARCHAR(20) = NULL,
        @InstanceName   NVARCHAR(256) = NULL,
        @TimeoutSeconds INT = 60,
        @DebugMode      BIT = 0
    AS
    BEGIN
        SET NOCOUNT ON;
        PRINT ''Placeholder'';
    END;
    ');
GO

ALTER PROCEDURE [monitor].[usp_CollectAllInstances]
    @Environment    NVARCHAR(20) = NULL,
    @InstanceName   NVARCHAR(256) = NULL,
    @TimeoutSeconds INT = 60,
    @DebugMode      BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @CurrentInstance NVARCHAR(256);
    DECLARE @CurrentDB NVARCHAR(128);
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SuccessCount INT = 0, @FailCount INT = 0;

    -- ============================================================
    -- GET TARGET INSTANCES
    -- ============================================================
    DECLARE @Targets TABLE (
        InstanceName    NVARCHAR(256),
        MonitorDatabase NVARCHAR(128),
        Environment     NVARCHAR(20)
    );

    INSERT INTO @Targets (InstanceName, MonitorDatabase, Environment)
    SELECT InstanceName, MonitorDatabase, Environment
    FROM [monitor].[RegisteredServers]
    WHERE IsActive = 1
        AND (@Environment IS NULL OR Environment = @Environment)
        AND (@InstanceName IS NULL OR InstanceName = @InstanceName);

    IF NOT EXISTS (SELECT 1 FROM @Targets)
    BEGIN
        PRINT '⚠ No active instances found matching criteria.';
        RETURN;
    END;

    -- Debug mode: show plan
    IF @DebugMode = 1
    BEGIN
        SELECT InstanceName, MonitorDatabase, Environment,
            'Will collect health snapshot via linked server or AT clause' AS Action
        FROM @Targets
        ORDER BY Environment, InstanceName;
        RETURN;
    END;

    -- ============================================================
    -- ITERATE AND COLLECT
    -- ============================================================
    DECLARE instance_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT InstanceName, MonitorDatabase FROM @Targets;

    OPEN instance_cursor;
    FETCH NEXT FROM instance_cursor INTO @CurrentInstance, @CurrentDB;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            -- Build remote health query
            -- This query runs on the remote instance and returns a single-row health summary
            SET @SQL = N'
                SELECT 
                    @p_Instance AS InstanceName,
                    -- Health Score
                    100 
                        - CASE WHEN cpu.CpuMax >= 95 THEN 25 WHEN cpu.CpuMax >= 80 THEN 10 ELSE 0 END
                        - CASE WHEN mem.PleMin <= 100 THEN 25 WHEN mem.PleMin <= 300 THEN 10 ELSE 0 END
                        - CASE WHEN dsk.DiskMax >= 95 THEN 20 WHEN dsk.DiskMax >= 85 THEN 8 ELSE 0 END
                        - CASE WHEN ag.AgLag >= 120 THEN 20 WHEN ag.AgLag >= 30 THEN 8 ELSE 0 END
                    AS HealthScore,
                    cpu.CpuAvg, cpu.CpuMax,
                    mem.PleAvg,
                    dsk.DiskMax AS DiskMaxUsedPct,
                    ISNULL(ag.AgLag, 0) AS AgMaxLagSec,
                    ISNULL(blk.BlockCount, 0) AS BlockingCount,
                    ISNULL(alt.AlertCount, 0) AS AlertCount,
                    CASE 
                        WHEN cpu.CpuMax >= 95 OR mem.PleMin <= 100 OR dsk.DiskMax >= 95 OR ag.AgLag >= 120 THEN ''critical''
                        WHEN cpu.CpuMax >= 80 OR mem.PleMin <= 300 OR dsk.DiskMax >= 85 OR ag.AgLag >= 30 THEN ''warning''
                        ELSE ''healthy''
                    END AS OverallStatus
                FROM (
                    SELECT AVG(SqlCpuPct) AS CpuAvg, MAX(SqlCpuPct) AS CpuMax
                    FROM [' + @CurrentDB + N'].[monitor].[CpuHistory]
                    WHERE CollectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
                ) cpu
                CROSS JOIN (
                    SELECT AVG(PageLifeExpectancy) AS PleAvg, MIN(PageLifeExpectancy) AS PleMin
                    FROM [' + @CurrentDB + N'].[monitor].[MemoryHistory]
                    WHERE CollectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
                ) mem
                CROSS JOIN (
                    SELECT ISNULL(MAX(UsedPct), 0) AS DiskMax
                    FROM [' + @CurrentDB + N'].[monitor].[DiskHistory]
                    WHERE CollectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
                ) dsk
                CROSS JOIN (
                    SELECT MAX(ISNULL(SecondsBehindPrimary, 0)) AS AgLag
                    FROM [' + @CurrentDB + N'].[monitor].[AgHealthHistory]
                    WHERE CollectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
                ) ag
                CROSS JOIN (
                    SELECT COUNT(*) AS BlockCount
                    FROM [' + @CurrentDB + N'].[monitor].[BlockingHistory]
                    WHERE DetectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
                ) blk
                CROSS JOIN (
                    SELECT COUNT(*) AS AlertCount
                    FROM [' + @CurrentDB + N'].[monitor].[AlertHistory]
                    WHERE FiredAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
                ) alt;';

            -- Execute on remote instance via linked server
            -- If the instance is local (current server), run directly
            IF @CurrentInstance = @@SERVERNAME OR @CurrentInstance = CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(256))
            BEGIN
                -- Local execution
                INSERT INTO [monitor].[InstanceHealthSnapshot]
                    (InstanceName, HealthScore, CpuAvg, CpuMax, PleAvg, DiskMaxUsedPct, AgMaxLagSec, BlockingCount, AlertCount, OverallStatus)
                EXEC sp_executesql @SQL, N'@p_Instance NVARCHAR(256)', @p_Instance = @CurrentInstance;
            END
            ELSE
            BEGIN
                -- Remote execution via linked server
                DECLARE @RemoteSQL NVARCHAR(MAX) = N'
                    INSERT INTO [monitor].[InstanceHealthSnapshot]
                        (InstanceName, HealthScore, CpuAvg, CpuMax, PleAvg, DiskMaxUsedPct, AgMaxLagSec, BlockingCount, AlertCount, OverallStatus)
                    EXEC (''' + REPLACE(@SQL, '''', '''''') + N''') AT [' + @CurrentInstance + N'];';

                -- Try linked server first
                IF EXISTS (SELECT 1 FROM sys.servers WHERE name = @CurrentInstance)
                BEGIN
                    EXEC sp_executesql @RemoteSQL, N'@p_Instance NVARCHAR(256)', @p_Instance = @CurrentInstance;
                END
                ELSE
                BEGIN
                    -- Fallback: try OPENQUERY if linked server exists with different name
                    RAISERROR('Linked server [%s] not found. Register it or use PowerShell multi-instance collection.', 16, 1, @CurrentInstance);
                END;
            END;

            -- Update registration status
            UPDATE [monitor].[RegisteredServers]
            SET LastCollectedAt = SYSUTCDATETIME(), LastCollectionStatus = 'Success'
            WHERE InstanceName = @CurrentInstance;

            SET @SuccessCount += 1;

        END TRY
        BEGIN CATCH
            -- Log failure but continue with other instances
            UPDATE [monitor].[RegisteredServers]
            SET LastCollectedAt = SYSUTCDATETIME(), LastCollectionStatus = 'Failed'
            WHERE InstanceName = @CurrentInstance;

            INSERT INTO [monitor].[ErrorLogHistory] (LogDate, ProcessInfo, ErrorMessage, Severity)
            VALUES (SYSUTCDATETIME(), 'MultiInstance', 
                'Failed to collect from [' + @CurrentInstance + ']: ' + ERROR_MESSAGE(), 'Warning');

            SET @FailCount += 1;
        END CATCH;

        FETCH NEXT FROM instance_cursor INTO @CurrentInstance, @CurrentDB;
    END;

    CLOSE instance_cursor;
    DEALLOCATE instance_cursor;

    -- Summary
    DECLARE @Duration INT = DATEDIFF(SECOND, @StartTime, SYSUTCDATETIME());
    PRINT '✓ Multi-instance collection complete in ' + CAST(@Duration AS NVARCHAR) + 's: '
        + CAST(@SuccessCount AS NVARCHAR) + ' succeeded, ' + CAST(@FailCount AS NVARCHAR) + ' failed.';
END;
GO

PRINT '✓ Procedure [monitor].[usp_CollectAllInstances] created.';
GO

    @Environment    NVARCHAR(20) = NULL,
    @InstanceName   NVARCHAR(256) = NULL,
    @TimeoutSeconds INT = 60,
    @DebugMode      BIT = 0
    SET XACT_ABORT ON;

    DECLARE @StartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @CurrentInstance NVARCHAR(256);
    DECLARE @CurrentDB NVARCHAR(128);
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SuccessCount INT = 0, @FailCount INT = 0;

    -- ============================================================
    -- GET TARGET INSTANCES
    -- ============================================================
    DECLARE @Targets TABLE (
        InstanceName    NVARCHAR(256),
        MonitorDatabase NVARCHAR(128),
        Environment     NVARCHAR(20)
    );

    INSERT INTO @Targets (InstanceName, MonitorDatabase, Environment)
    SELECT InstanceName, MonitorDatabase, Environment
    FROM [monitor].[RegisteredServers]
    WHERE IsActive = 1
        AND (@Environment IS NULL OR Environment = @Environment)
        AND (@InstanceName IS NULL OR InstanceName = @InstanceName);

    IF NOT EXISTS (SELECT 1 FROM @Targets)
    BEGIN
        PRINT '⚠ No active instances found matching criteria.';
        RETURN;
    END;

    -- Debug mode: show plan
    IF @DebugMode = 1
    BEGIN
        SELECT InstanceName, MonitorDatabase, Environment,
            'Will collect health snapshot via linked server or AT clause' AS Action
        FROM @Targets
        ORDER BY Environment, InstanceName;
        RETURN;
    END;

    -- ============================================================
    -- ITERATE AND COLLECT
    -- ============================================================
    DECLARE instance_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT InstanceName, MonitorDatabase FROM @Targets;

    OPEN instance_cursor;
    FETCH NEXT FROM instance_cursor INTO @CurrentInstance, @CurrentDB;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            -- Build remote health query
            -- This query runs on the remote instance and returns a single-row health summary
            SET @SQL = N'
                SELECT 
                    @p_Instance AS InstanceName,
                    -- Health Score
                    100 
                        - CASE WHEN cpu.CpuMax >= 95 THEN 25 WHEN cpu.CpuMax >= 80 THEN 10 ELSE 0 END
                        - CASE WHEN mem.PleMin <= 100 THEN 25 WHEN mem.PleMin <= 300 THEN 10 ELSE 0 END
                        - CASE WHEN dsk.DiskMax >= 95 THEN 20 WHEN dsk.DiskMax >= 85 THEN 8 ELSE 0 END
                        - CASE WHEN ag.AgLag >= 120 THEN 20 WHEN ag.AgLag >= 30 THEN 8 ELSE 0 END
                    AS HealthScore,
                    cpu.CpuAvg, cpu.CpuMax,
                    mem.PleAvg,
                    dsk.DiskMax AS DiskMaxUsedPct,
                    ISNULL(ag.AgLag, 0) AS AgMaxLagSec,
                    ISNULL(blk.BlockCount, 0) AS BlockingCount,
                    ISNULL(alt.AlertCount, 0) AS AlertCount,
                    CASE 
                        WHEN cpu.CpuMax >= 95 OR mem.PleMin <= 100 OR dsk.DiskMax >= 95 OR ag.AgLag >= 120 THEN ''critical''
                        WHEN cpu.CpuMax >= 80 OR mem.PleMin <= 300 OR dsk.DiskMax >= 85 OR ag.AgLag >= 30 THEN ''warning''
                        ELSE ''healthy''
                    END AS OverallStatus
                FROM (
                    SELECT AVG(SqlCpuPct) AS CpuAvg, MAX(SqlCpuPct) AS CpuMax
                    FROM [' + @CurrentDB + N'].[monitor].[CpuHistory]
                    WHERE CollectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
                ) cpu
                CROSS JOIN (
                    SELECT AVG(PageLifeExpectancy) AS PleAvg, MIN(PageLifeExpectancy) AS PleMin
                    FROM [' + @CurrentDB + N'].[monitor].[MemoryHistory]
                    WHERE CollectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
                ) mem
                CROSS JOIN (
                    SELECT ISNULL(MAX(UsedPct), 0) AS DiskMax
                    FROM [' + @CurrentDB + N'].[monitor].[DiskHistory]
                    WHERE CollectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
                ) dsk
                CROSS JOIN (
                    SELECT MAX(ISNULL(SecondsBehindPrimary, 0)) AS AgLag
                    FROM [' + @CurrentDB + N'].[monitor].[AgHealthHistory]
                    WHERE CollectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
                ) ag
                CROSS JOIN (
                    SELECT COUNT(*) AS BlockCount
                    FROM [' + @CurrentDB + N'].[monitor].[BlockingHistory]
                    WHERE DetectedAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
                ) blk
                CROSS JOIN (
                    SELECT COUNT(*) AS AlertCount
                    FROM [' + @CurrentDB + N'].[monitor].[AlertHistory]
                    WHERE FiredAt >= DATEADD(HOUR, -1, SYSUTCDATETIME())
                ) alt;';

            -- Execute on remote instance via linked server
            -- If the instance is local (current server), run directly
            IF @CurrentInstance = @@SERVERNAME OR @CurrentInstance = CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(256))
            BEGIN
                -- Local execution
                INSERT INTO [monitor].[InstanceHealthSnapshot]
                    (InstanceName, HealthScore, CpuAvg, CpuMax, PleAvg, DiskMaxUsedPct, AgMaxLagSec, BlockingCount, AlertCount, OverallStatus)
                EXEC sp_executesql @SQL, N'@p_Instance NVARCHAR(256)', @p_Instance = @CurrentInstance;
            END
            ELSE
            BEGIN
                -- Remote execution via linked server
                DECLARE @RemoteSQL NVARCHAR(MAX) = N'
                    INSERT INTO [monitor].[InstanceHealthSnapshot]
                        (InstanceName, HealthScore, CpuAvg, CpuMax, PleAvg, DiskMaxUsedPct, AgMaxLagSec, BlockingCount, AlertCount, OverallStatus)
                    EXEC (''' + REPLACE(@SQL, '''', '''''') + N''') AT [' + @CurrentInstance + N'];';

                -- Try linked server first
                IF EXISTS (SELECT 1 FROM sys.servers WHERE name = @CurrentInstance)
                BEGIN
                    EXEC sp_executesql @RemoteSQL, N'@p_Instance NVARCHAR(256)', @p_Instance = @CurrentInstance;
                END
                ELSE
                BEGIN
                    -- Fallback: try OPENQUERY if linked server exists with different name
                    RAISERROR('Linked server [%s] not found. Register it or use PowerShell multi-instance collection.', 16, 1, @CurrentInstance);
                END;
            END;

            -- Update registration status
            UPDATE [monitor].[RegisteredServers]
            SET LastCollectedAt = SYSUTCDATETIME(), LastCollectionStatus = 'Success'
            WHERE InstanceName = @CurrentInstance;

            SET @SuccessCount += 1;

        END TRY
        BEGIN CATCH
            -- Log failure but continue with other instances
            UPDATE [monitor].[RegisteredServers]
            SET LastCollectedAt = SYSUTCDATETIME(), LastCollectionStatus = 'Failed'
            WHERE InstanceName = @CurrentInstance;

            INSERT INTO [monitor].[ErrorLogHistory] (LogDate, ProcessInfo, ErrorMessage, Severity)
            VALUES (SYSUTCDATETIME(), 'MultiInstance', 
                'Failed to collect from [' + @CurrentInstance + ']: ' + ERROR_MESSAGE(), 'Warning');

            SET @FailCount += 1;
        END CATCH;

        FETCH NEXT FROM instance_cursor INTO @CurrentInstance, @CurrentDB;
    END;

    CLOSE instance_cursor;
    DEALLOCATE instance_cursor;

    -- Summary
    DECLARE @Duration INT = DATEDIFF(SECOND, @StartTime, SYSUTCDATETIME());
    PRINT '✓ Multi-instance collection complete in ' + CAST(@Duration AS NVARCHAR) + 's: '
        + CAST(@SuccessCount AS NVARCHAR) + ' succeeded, ' + CAST(@FailCount AS NVARCHAR) + ' failed.';
END;
GO

PRINT '✓ Procedure [monitor].[usp_CollectAllInstances] created.';
GO
