/*
    SQL Health Monitor - Compatibility Floor
    =====================================

    Runs as the first script in the install chain. Aborts if the SQL Server
    build is below the project's stated minimum (2012). For supported builds,
    it documents which scripts are skipped on which versions so that
    Install.ps1's "stop at first error" rule does not become "stop at the
    first thing that looks like an error but is really a feature guard".

    Compatibility matrix:

        SQL 2012-2014   full install (skip nothing installed by the
                        guards in 07, 11 and 12)
        SQL 2016+       full install

    Per-script skips live where they belong (so a future maintainer who
    edits baselines/capture_baseline.sql will not look here for the guard
    that wraps it):
      install/07-baselines.sql         skips procedures on <2017
      install/11-health-check.sql      skips whole file on <2016
      install/12-collectors-2016.sql   skips whole file on <2016
*/

SET NOCOUNT ON;
GO

DECLARE @Major    TINYINT = CAST(SERVERPROPERTY('ProductMajorVersion') AS TINYINT);
DECLARE @Level    VARCHAR(20) =
        CASE @Major
            WHEN 11 THEN 'SQL Server 2012'
            WHEN 12 THEN 'SQL Server 2014'
            WHEN 13 THEN 'SQL Server 2016'
            WHEN 14 THEN 'SQL Server 2017'
            WHEN 15 THEN 'SQL Server 2019'
            WHEN 16 THEN 'SQL Server 2022'
            ELSE 'SQL Server ' + ISNULL(CAST(@Major AS VARCHAR(3)), 'unknown')
        END;

IF @Major < 11
BEGIN
    RAISERROR('SQL Health Monitor requires SQL Server 2012 or later. Detected %s.', 16, 1, @Level);
    RETURN 1;
END

PRINT '+ SQL Health Monitor compatibility check passed (' + @Level + ').';
GO