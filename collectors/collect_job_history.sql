/*
    SQL Health Monitor - Job History Collector
    Collects SQL Agent job status and failures.
    
    Schedule: Every 15 minutes
    Compatibility: SQL Server 2016+
*/

IF OBJECT_ID('[monitor].[usp_Collect_JobHistory]', 'P') IS NOT NULL
    EXEC('ALTER PROCEDURE [monitor].[usp_Collect_JobHistory]  AS SET NOCOUNT ON; BEGIN DECLARE @Dummy INT = 0; END;');
GO

IF OBJECT_ID('[monitor].[usp_Collect_JobHistory]', 'P') IS NULL
    
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
        J
        o
        b
        H
        i
        s
        t
        o
        r
        y
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

ALTER PROCEDURE [monitor].[usp_Collect_JobHistory]
    
    INSERT INTO [monitor].[JobHistory]
        (JobName, LastRunDate, LastRunStatus, LastRunDuration, NextRunDate, IsEnabled)
    SELECT
        j.name AS JobName,
        CASE WHEN jh.run_date > 0 THEN
            CONVERT(DATETIME2,
                STUFF(STUFF(CAST(jh.run_date AS VARCHAR(8)), 5, 0, '-'), 8, 0, '-') + ' ' +
                STUFF(STUFF(RIGHT('000000' + CAST(jh.run_time AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':')
            )
        END AS LastRunDate,
        CASE jh.run_status
            WHEN 0 THEN 'Failed'
            WHEN 1 THEN 'Succeeded'
            WHEN 2 THEN 'Retry'
            WHEN 3 THEN 'Canceled'
            WHEN 4 THEN 'Running'
            ELSE 'Unknown'
        END AS LastRunStatus,
        (jh.run_duration / 10000) * 3600 + 
        ((jh.run_duration % 10000) / 100) * 60 + 
        (jh.run_duration % 100) AS LastRunDuration,
        CASE WHEN js.next_run_date > 0 THEN
            CONVERT(DATETIME2,
                STUFF(STUFF(CAST(js.next_run_date AS VARCHAR(8)), 5, 0, '-'), 8, 0, '-') + ' ' +
                STUFF(STUFF(RIGHT('000000' + CAST(js.next_run_time AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':')
            )
        END AS NextRunDate,
        j.enabled AS IsEnabled
    FROM msdb.dbo.sysjobs j
    OUTER APPLY (
        SELECT TOP 1 run_date, run_time, run_status, run_duration
        FROM msdb.dbo.sysjobhistory h
        WHERE h.job_id = j.job_id AND h.step_id = 0
        ORDER BY h.instance_id DESC
    ) jh
    LEFT JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
    WHERE j.enabled = 1;
END;
GO
