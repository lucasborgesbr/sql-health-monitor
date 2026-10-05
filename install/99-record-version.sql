/*
    SQL Health Monitor - Version Recording
    Records the version just deployed. Idempotent by version: re-running at
    the same version refreshes LastVerifiedAt instead of adding a row.

    Runs last in the install chain, numbered 99 so that intent is obvious at
    the call site. If an earlier script fails, Install.ps1 stops and this is
    never reached -- which is exactly the signal we want, because
    LastVerifiedAt then still points at the last version that ran to
    completion.

    sqlcmd variables:
      $(Version)  semver being installed, e.g. 1.1.0
      $(Mode)     'Fresh' or 'Upgrade'
      $(Commit)   git short hash, or empty outside a checkout

    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

DECLARE @Version     VARCHAR(20)   = '$(Version)';
DECLARE @Mode        VARCHAR(10)   = '$(Mode)';
DECLARE @Commit      VARCHAR(40)   = NULLIF(LTRIM(RTRIM('$(Commit)')), '');
DECLARE @Previous    VARCHAR(20);

SELECT @Previous = [monitor].[fn_GetInstalledVersion]();

IF NOT EXISTS (SELECT 1 FROM [monitor].[SchemaVersion] WHERE [Version] = @Version)
BEGIN
    INSERT INTO [monitor].[SchemaVersion]
        ([Version], [PreviousVersion], [InstallMode], [InstalledBy], [CommitHash], [LastVerifiedAt])
    VALUES
        (@Version, @Previous, @Mode, SUSER_SNAME(), @Commit, SYSUTCDATETIME());

    PRINT '✓ Recorded version ' + @Version + ' (' + @Mode + ')';
END
ELSE
BEGIN
    UPDATE [monitor].[SchemaVersion]
    SET [LastVerifiedAt] = SYSUTCDATETIME(),
        [CommitHash]     = COALESCE(@Commit, [CommitHash])
    WHERE [Version] = @Version;

    PRINT '✓ Version ' + @Version + ' already recorded; LastVerifiedAt refreshed.';
END
GO
