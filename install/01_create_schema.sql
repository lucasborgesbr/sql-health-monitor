-- 01_create_schema.sql - Create database schema and base objects
-- SQL Health Monitor v1.0

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'monitor')
    EXEC('CREATE SCHEMA [monitor]')

PRINT 'Schema [monitor] ready'
GO
