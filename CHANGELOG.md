# SQL Health Monitor - Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-10-06

### Added
- `VERSION` file: the single semver source the installer reads
- `[monitor].[SchemaVersion]` — one row per version applied, with the commit
  hash and the `LastVerifiedAt` a failed deployment leaves behind
- `[monitor].[AppliedMigrations]` and `[monitor].[fn_GetInstalledVersion]()`
- `install/99-record-version.sql`, run last in the chain
- `install/migrations/` for changes that cannot be written idempotently
- `Install.ps1 -Mode Status | Upgrade | Fresh`, plus `-Force`, `-ResetSchedules`,
  `-SkipJobs`, `-AssumeVersion` and `-BackupPath`
- `tests/Test-Install.ps1` — 30 scenarios against a live instance
- `tools/gen-column-guards.py` and `tools/rewrite-jobs.py`

### Changed
- Install scripts reconcile table columns on existing installations, so a new
  column finally reaches an upgrade instead of being silently skipped
- `05-configure.sql` inserts defaults without overwriting existing values
- `04-create-jobs.sql` creates a job only when absent; an existing job gets its
  step refreshed and its schedule left alone
- `Uninstall.ps1` takes `-Database` and reports the server, database and
  installed version before asking for confirmation
- `validate_installation.sql` reports the recorded version and applied migrations

### Fixed
- Re-running the installer no longer wipes `Settings`, `Thresholds` or job
  schedules
- `Install.ps1` stops at the first failing script and names it, instead of
  counting errors and reporting completion over a partial install
- `Install.ps1` and `Uninstall.ps1` honour `SQLCMDUSER` / `SQLCMDPASSWORD`
  instead of forcing `-E`, and pass `-C`, which sqlcmd 18 requires
- `04-create-jobs.sql` idempotency guard tested `OBJECT_ID(..., 'IP')` instead
  of `'P'`, so the collector could be installed once and never reinstalled
- Phase 1-3 (schema, three collectors, on-demand health check) added to the
  install chain; it had never been installed
- `LiveSessionsHistory` declared a column named `c` while the collector inserts
  `RowCount`; `QueryHash` missing from an INSERT column list; memory grants read
  from a DMV column that no longer exists on SQL Server 2016+
- A report that fails now raises instead of sending a blank email

### Notes
- Values in `Settings` and `Thresholds` are yours: an upgrade inserts new
  defaults but never overwrites what you set. Changing a default in the repo
  does not reach existing installations — that needs a migration.
- Install from a tag, not from `main`. `git clone --branch v1.1.0` gives you
  exactly that release.

## [1.1.1] - 2026-10-06

### Added
- `diagnostics/usp_HealthCheck.sql` rewritten to 10 verified checks and
  deployed by `install/11-health-check.sql` (replaces the 574-line stub that
  had never run). The procedure accepts `@CheckId`, `@OutputType` (`TABLE` |
  `TEXT` | `COUNT_ONLY`) and `@DatabaseName` so it can be triggered on demand
  or wired into a job.
- `README-PTBR.md` documents the on-demand health check.

### Fixed
- `CheckId` filter used to compare against the IDENTITY column, so a single
  check never returned its findings on re-runs. The new layout stores the
  source check number in a non-IDENTITY column and uses it for filtering.

## [1.1.2] - 2026-10-06

### Added
- `install/00-compat-checks.sql` runs first and aborts the install on SQL
  Server 2008 or earlier.
- `install/11-health-check-2016.sql`, `install/12-collectors-2016.sql` and
  `install/13-baselines-2017.sql` guard the three scripts that use
  features added after SQL Server 2012:
    - `sys.dm_db_stats_properties` (2016+)
    - `sys.query_store_*` views (2016+)
    - `STRING_AGG` and `PERCENTILE_CONT` (2017+)
  The guards return early with a notice rather than letting the parser
  fail mid-deploy.
- `README-PTBR.md` documents the per-version skip matrix.

### Changed
- The minimum supported SQL Server is now 2012 (was 2016 by accident of
  `usp_HealthCheck` and the query-store collector). All 2012+ features
  in the install chain were verified; 2016+ and 2017+ features are
  guarded by the new files.
- `diagnostics/usp_HealthCheck.sql` uses `CREATE PROCEDURE`; idempotency
  is owned by `install/11-health-check-2016.sql`.

## [1.1.3] - 2026-10-06

### Changed
- `Install.ps1` and `Test-Install.ps1` fall back to Windows authentication
  (`-E` to sqlcmd) when neither `-SqlAuth` nor the `SQLCMDUSER` env var
  is set. The previous "No SQL credentials available" exit is gone --
  the operator with only domain credentials now reaches the same point
  that an SQL-auth user would, and gets a sqlcmd login error if the
  Windows account does not have access to the target instance. Pass
  `-SqlAuth -Login sa -Password ...` to force SQL auth even when
  `SQLCMDUSER` happens to be set.

## [1.0.0] - 2026-06-02

### Added
- Complete SQL Server monitoring solution with 16 health collectors
- Real-time alerting system with configurable thresholds
- Multi-language support (English and Portuguese-BR)
- Comprehensive reporting system with HTML templates
- PowerShell deployment automation
- Multi-instance support with drift detection
- Statistical baseline engine for anomaly detection
- Automated maintenance and data retention
- Visual status indicators (🟢🟡🔴)

### Changed
- Standardized database naming to `SQLHealthMonitor`
- Unified procedure naming convention (`usp_Collect_[Feature]`)
- Enhanced collector error handling and logging
- Improved report templates with responsive design
- Optimized data collection performance
- Enhanced alert cooldown mechanism

### Fixed
- **Critical**: Fixed 6 stub files with minimal implementation
- **Critical**: Fixed procedure name mismatches between references and definitions
- **Critical**: Removed unnecessary migration scripts (`SQLHealthMonitor` → `SQLHealthMonitor`)
- **High**: Fixed inconsistent database references across all scripts
- **High**: Fixed PowerShell installation validation script
- **Medium**: Cleaned up duplicate documentation files
- **Medium**: Fixed view definitions and missing schema tables

### Security
- Implemented proper error handling in all collectors
- Added input validation for configuration parameters
- Secure credential handling for email notifications
- Proper permission management for database objects

### Documentation
- Complete installation guide with step-by-step instructions
- Configuration guide with all available parameters
- Customization guide for different environments
- Troubleshooting guide with common issues
- API documentation for all procedures and views

### Performance
- Optimized collection queries with proper indexing
- Implemented batch processing for large datasets
- Added query timeout handling
- Optimized memory usage for long-running operations
- Added performance monitoring for the monitor itself

### Testing
- Comprehensive installation validation script
- Procedure existence and functionality validation
- Data integrity checks for all collectors
- Alert system validation
- Report generation testing

## [0.9.0] - 2026-05-31

### Added
- Initial beta release with core monitoring features
- Basic alert system
- PowerShell deployment scripts
- HTML report templates

### Known Issues (Resolved in 1.0.0)
- Stub files with incomplete implementations
- Procedure name inconsistencies
- Migration scripts not needed for release
- Database reference mismatches

---

## Installation Instructions

### For New Installations
1. Review the [Installation Guide](docs/INSTALLATION-GUIDE.md)
2. Configure [Settings](docs/CONFIGURATION.md)
3. Deploy using PowerShell scripts
4. Validate installation with `validate_installation.sql`

### For Upgrades from 0.9.0
1. Backup existing database
2. Run schema update scripts
3. Update configuration if needed
4. Validate with `validate_installation.sql`

## Support

For support and questions:
- Review [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- Check [Configuration Guide](docs/CONFIGURATION.md)
- Contact development team for enterprise support

## Contributing

This is a production-ready release. For contributions, please follow:
1. Fork the repository
2. Create a feature branch
3. Test thoroughly
4. Submit pull request with detailed changes

---

*This changelog follows the principles of transparency and user communication, providing clear information about what has changed, why it changed, and what impact it has on users.*