# Migrations

Changes that **cannot** be written idempotently.

The install chain (`install/00` … `install/10`) already reconciles itself:
new columns arrive via `IF COL_LENGTH(...) IS NULL ALTER TABLE`, procedures
and views are updated in place, and configuration is inserted without
overwriting what you changed. You do not need a migration for any of that.

You **do** need one for anything with a one-time effect:

- Renaming a column, table or procedure
- Changing a column's type or nullability
- Backfilling existing rows
- Splitting or merging a table
- Changing a default in `Settings` or `Thresholds` (see the note below)

## Naming

    V<major>_<minor>_<patch>__<short_description>.sql

Example: `V1_2_0__backfill-buffer-cache-hit-ratio.sql`

`Install.ps1 -Mode Upgrade` applies every migration whose version is greater
than `fn_GetInstalledVersion()`, lowest first, and records each file in
`[monitor].[AppliedMigrations]` so it never runs twice.

## Writing one

Guard it so re-running by hand is harmless. `AppliedMigrations` already gives
you that, but a migration someone runs directly against a server should not
double-apply:

```sql
USE [SQLHealthMonitor];
GO

IF NOT EXISTS (SELECT 1 FROM [monitor].[AppliedMigrations]
               WHERE FileName = N'V1_2_0__backfill-buffer-cache-hit-ratio.sql')
BEGIN
    -- the actual change
END
GO
```

## A note on default values

`Settings` and `Thresholds` are merged insert-only, so changing a default in
`05-configure.sql` will **not** reach an existing installation. That is
deliberate — those values belong to the operator.

If a release changes a default and existing installations should pick it up,
write a migration that updates those rows explicitly, and say so in the
CHANGELOG. Otherwise the operator keeps their value and nothing is surprising.