/*
    SQL Health Monitor - Error Log Collector (Linux Adaptation)
    Collects recent error log entries using cross-platform methods.
    
    Schedule: Every 15 minutes
    Compatibility: SQL Server 2016+ on Linux
    Features: Cross-platform error log collection
*/

IF OBJECT_ID('[monitor].[usp_Collect_ErrorLog]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_ErrorLog]  AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_ErrorLog]', 'P') IS NULL
    
        E
        X
        E
        C
        (
        '
        

         
         
         
         
        C
        R
        E
        A
        T
        E
         
        P
        R
        O
        C
        E
        D
        U
        R
        E
         
        [
        m
        o
        n
        i
        t
        o
        r
        ]
        .
        [
        u
        s
        p
        _
        C
        o
        l
        l
        e
        c
        t
        _
        E
        r
        r
        o
        r
        L
        o
        g
        ]
        

         
         
         
         
         
         
         
         
        

         
         
         
         
        A
        S
        

         
         
         
         
        B
        E
        G
        I
        N
        

         
         
         
         
         
         
         
         
        S
        E
        T
         
        N
        O
        C
        O
        U
        N
        T
         
        O
        N
        ;
        

         
         
         
         
         
         
         
         
        P
        R
        I
        N
        T
         
        '
        '
        P
        l
        a
        c
        e
        h
        o
        l
        d
        e
        r
        '
        '
        ;
        

         
         
         
         
        E
        N
        D
        ;
        

         
         
         
         
        '
        )
        ;
        
GO

ALTER PROCEDURE [monitor].[usp_Collect_ErrorLog]
    
    DECLARE @LastCollected DATETIME2 = 
        ISNULL((SELECT MAX(LogDate) FROM [monitor].[ErrorLogHistory]), DATEADD(HOUR, -1, SYSUTCDATETIME()));

    -- Method 1: Try xp_readerrorlog first (available on Linux SQL Server 2017+)
    DECLARE @HasXpReadErrorLog BIT = 0;
    
    BEGIN TRY
        -- Test if xp_readerrorlog is available
        CREATE TABLE #TestXp (test_col NVARCHAR(MAX));
        INSERT INTO #TestXp EXEC xp_readerrorlog 0, 1, NULL, NULL, NULL, NULL, 'DESC';
        SET @HasXpReadErrorLog = 1;
        DROP TABLE #TestXp;
    END TRY
    BEGIN CATCH
        SET @HasXpReadErrorLog = 0;
    END CATCH;

    IF @HasXpReadErrorLog = 1
    BEGIN
        -- Use xp_readerrorlog if available (Linux SQL Server 2017+)
        CREATE TABLE #ErrorLog (
            LogDate DATETIME,
            ProcessInfo NVARCHAR(50),
            [Text] NVARCHAR(MAX)
        );

        INSERT INTO #ErrorLog
        EXEC xp_readerrorlog 0, 1, NULL, NULL, @LastCollected, NULL, 'DESC';

        -- Insert only errors/warnings (filter noise)
        INSERT INTO [monitor].[ErrorLogHistory]
            (LogDate, ProcessInfo, ErrorMessage, Severity)
        SELECT
            LogDate,
            ProcessInfo,
            [Text] AS ErrorMessage,
            CASE
                WHEN [Text] LIKE '%Error:%18%' OR [Text] LIKE '%Severity: 2[0-5]%' THEN 'Critical'
                WHEN [Text] LIKE '%Error%' OR [Text] LIKE '%Severity: 1[6-9]%' THEN 'Error'
                WHEN [Text] LIKE '%Warning%' OR [Text] LIKE '%warn%' THEN 'Warning'
                ELSE 'Info'
            END AS Severity
        FROM #ErrorLog
        WHERE LogDate > @LastCollected
            AND (
                [Text] LIKE '%Error%'
                OR [Text] LIKE '%Severity%'
                OR [Text] LIKE '%Warning%'
                OR [Text] LIKE '%fail%'
                OR [Text] LIKE '%corrupt%'
                OR [Text] LIKE '%I/O%'
                OR [Text] LIKE '%deadlock%'
                OR [Text] LIKE '%kill%'
                OR [Text] LIKE '%insufficient%'
            )
            -- Exclude noise
            AND [Text] NOT LIKE '%CHECKDB%found 0 errors%'
            AND [Text] NOT LIKE '%Login succeeded%'
            AND [Text] NOT LIKE '%backup%successfully%';

        DROP TABLE #ErrorLog;
        PRINT '✓ Error log collected using xp_readerrorlog (Linux compatible)';
    END
    ELSE
    BEGIN
        -- Method 2: Use sys.dm_os_ring_buffer for system messages (Linux fallback)
        INSERT INTO [monitor].[ErrorLogHistory]
            (LogDate, ProcessInfo, ErrorMessage, Severity)
        SELECT
            DATEADD(SECOND, -((Ticks / 10000) % 86400), 
                    CAST('1970-01-01' AS DATETIME) + (Ticks / 86400000000.0)) AS LogDate,
            'System' AS ProcessInfo,
            record.value('(./Record/@Source)[1]', 'nvarchar(100)') + ': ' + 
            record.value('(./Record/@Text)[1]', 'nvarchar(max)') AS ErrorMessage,
            CASE 
                WHEN record.value('(./Record/@Text)[1]', 'nvarchar(max)') LIKE '%Error%' THEN 'Error'
                WHEN record.value('(./Record/@Text)[1]', 'nvarchar(max)') LIKE '%Warning%' THEN 'Warning'
                ELSE 'Info'
            END AS Severity
        FROM (
            SELECT 
                Ticks,
                CONVERT(XML, record) AS record
            FROM sys.dm_os_ring_buffer
            WHERE ring_buffer_type = 'RING_BUFFER_ERRORLOG'
              AND TIMESTAMP > (SELECT TOP 1 TIMESTAMP FROM sys.dm_os_ring_buffer 
                              WHERE ring_buffer_type = 'RING_BUFFER_ERRORLOG' 
                              ORDER BY TIMESTAMP DESC)
        ) AS rb
        WHERE record.exist('Record[@Text]') = 1
        ORDER BY Ticks DESC;
        
        PRINT '✓ Error log collected using ring buffer (Linux fallback)';
    END;

    -- Method 3: Capture current system messages and errors
    INSERT INTO [monitor].[ErrorLogHistory]
        (LogDate, ProcessInfo, ErrorMessage, Severity)
    SELECT
        SYSDATETIME() AS LogDate,
        'SQL Health Monitor' AS ProcessInfo,
        'System health check completed' AS ErrorMessage,
        'Info' AS Severity
    WHERE NOT EXISTS (SELECT 1 FROM [monitor].[ErrorLogHistory] 
                     WHERE LogDate >= DATEADD(MINUTE, -1, SYSDATETIME()));
END;
GO