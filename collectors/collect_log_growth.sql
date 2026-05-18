/*
    SQL Health Monitor - File Growth Collector
    Tracks database file sizes and growth over time.
    
    Schedule: Every 30 minutes
    Compatibility: SQL Server 2016+
*/

CREATE OR ALTER PROCEDURE [monitor].[usp_Collect_FileGrowth]
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [monitor].[FileGrowthHistory]
        (DatabaseName, FileName, FileType, SizeMB, UsedMB, GrowthMB)
    SELECT
        DB_NAME(mf.database_id) AS DatabaseName,
        mf.name AS FileName,
        mf.type_desc AS FileType,
        mf.size * 8 / 1024 AS SizeMB,
        FILEPROPERTY(mf.name, 'SpaceUsed') * 8 / 1024 AS UsedMB,
        -- Delta from last collection
        (mf.size * 8 / 1024) - ISNULL(prev.SizeMB, mf.size * 8 / 1024) AS GrowthMB
    FROM sys.master_files mf
    OUTER APPLY (
        SELECT TOP 1 SizeMB
        FROM [monitor].[FileGrowthHistory] fgh
        WHERE fgh.DatabaseName = DB_NAME(mf.database_id)
            AND fgh.FileName = mf.name
        ORDER BY fgh.CollectedAt DESC
    ) prev
    WHERE mf.database_id > 4  -- Skip system databases
        AND DB_NAME(mf.database_id) IS NOT NULL;
END;
GO
