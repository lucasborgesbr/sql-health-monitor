/*
    SQL Health Monitor - Error Log Collector
    Collects recent error log entries (errors and warnings only).
    
    Schedule: Every 15 minutes
    Compatibility: SQL Server 2016+
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
    
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LastCollected DATETIME2 = 
        ISNULL((SELECT MAX(LogDate) FROM [monitor].[ErrorLogHistory]), DATEADD(HOUR, -1, SYSUTCDATETIME()));

    -- Temp table for xp_readerrorlog output
    CREATE TABLE #ErrorLog (
        LogDate DATETIME,
        ProcessInfo NVARCHAR(50),
        [Text] NVARCHAR(MAX)
    );

    -- Read current error log
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
END;
GO
