/*
    SQL Health Monitor - Register DataBank Environment
    INSERT statements for DataBank SQL Server instances.
    
    Instances: DBDEV, DBSTG, DBPRD, DBAPP, DFW3PRDBCSSQL01, DFW3PRDBCSSQL03, DFW3PRDBCSSQL04, DFW3PRDBCSSQL05
    
    Schema: [monitor]
    Compatibility: SQL Server 2016+
    Author: Lucas Allan Borges
*/

USE [DBA_Monitor];
GO

-- ============================================================
-- REGISTER DATABANK INSTANCES
-- ============================================================

-- Development
IF NOT EXISTS (SELECT 1 FROM [monitor].[RegisteredServers] WHERE InstanceName = 'DBDEV')
    INSERT INTO [monitor].[RegisteredServers] 
        (InstanceName, DisplayName, Environment, AgRole, ServerRole, IsActive, MonitorDatabase, Notes)
    VALUES 
        ('DBDEV', 'DataBank Dev', 'DEV', 'STANDALONE', 'MIXED', 1, 'DBA_Monitor', 
         'Development instance. Used for testing and validation.');

-- Staging
IF NOT EXISTS (SELECT 1 FROM [monitor].[RegisteredServers] WHERE InstanceName = 'DBSTG')
    INSERT INTO [monitor].[RegisteredServers] 
        (InstanceName, DisplayName, Environment, AgRole, ServerRole, IsActive, MonitorDatabase, Notes)
    VALUES 
        ('DBSTG', 'DataBank Staging', 'STG', 'STANDALONE', 'MIXED', 1, 'DBA_Monitor', 
         'Staging instance. Pre-production validation environment.');

-- Production - Main
IF NOT EXISTS (SELECT 1 FROM [monitor].[RegisteredServers] WHERE InstanceName = 'DBPRD')
    INSERT INTO [monitor].[RegisteredServers] 
        (InstanceName, DisplayName, Environment, AgRole, ServerRole, IsActive, IsPrimary, MonitorDatabase, Notes)
    VALUES 
        ('DBPRD', 'DataBank Production', 'PRD', 'PRIMARY', 'OLTP', 1, 1, 'DBA_Monitor', 
         'Primary production OLTP instance. AG primary replica.');

-- Application Server
IF NOT EXISTS (SELECT 1 FROM [monitor].[RegisteredServers] WHERE InstanceName = 'DBAPP')
    INSERT INTO [monitor].[RegisteredServers] 
        (InstanceName, DisplayName, Environment, AgRole, ServerRole, IsActive, MonitorDatabase, Notes)
    VALUES 
        ('DBAPP', 'DataBank App Server', 'PRD', 'STANDALONE', 'ETL', 1, 'DBA_Monitor', 
         'Application/ETL instance. Handles data processing and integrations.');

-- DFW3 Production Cluster Node 01
IF NOT EXISTS (SELECT 1 FROM [monitor].[RegisteredServers] WHERE InstanceName = 'DFW3PRDBCSSQL01')
    INSERT INTO [monitor].[RegisteredServers] 
        (InstanceName, DisplayName, Environment, AgRole, ServerRole, IsActive, MonitorDatabase, Notes)
    VALUES 
        ('DFW3PRDBCSSQL01', 'DFW3 PRD Node 01', 'PRD', 'SECONDARY', 'OLTP', 1, 'DBA_Monitor', 
         'DFW3 datacenter production AG secondary replica.');

-- DFW3 Production Cluster Node 03
IF NOT EXISTS (SELECT 1 FROM [monitor].[RegisteredServers] WHERE InstanceName = 'DFW3PRDBCSSQL03')
    INSERT INTO [monitor].[RegisteredServers] 
        (InstanceName, DisplayName, Environment, AgRole, ServerRole, IsActive, MonitorDatabase, Notes)
    VALUES 
        ('DFW3PRDBCSSQL03', 'DFW3 PRD Node 03', 'PRD', 'SECONDARY', 'REPORTING', 1, 'DBA_Monitor', 
         'DFW3 datacenter production AG secondary. Read-only reporting workload.');

-- DFW3 Production Cluster Node 04
IF NOT EXISTS (SELECT 1 FROM [monitor].[RegisteredServers] WHERE InstanceName = 'DFW3PRDBCSSQL04')
    INSERT INTO [monitor].[RegisteredServers] 
        (InstanceName, DisplayName, Environment, AgRole, ServerRole, IsActive, MonitorDatabase, Notes)
    VALUES 
        ('DFW3PRDBCSSQL04', 'DFW3 PRD Node 04', 'PRD', 'SECONDARY', 'OLTP', 1, 'DBA_Monitor', 
         'DFW3 datacenter production AG secondary replica.');

-- DFW3 Production Cluster Node 05
IF NOT EXISTS (SELECT 1 FROM [monitor].[RegisteredServers] WHERE InstanceName = 'DFW3PRDBCSSQL05')
    INSERT INTO [monitor].[RegisteredServers] 
        (InstanceName, DisplayName, Environment, AgRole, ServerRole, IsActive, MonitorDatabase, Notes)
    VALUES 
        ('DFW3PRDBCSSQL05', 'DFW3 PRD Node 05', 'PRD', 'SECONDARY', 'OLTP', 1, 'DBA_Monitor', 
         'DFW3 datacenter production AG secondary replica.');

GO

PRINT '✓ DataBank environment registered (8 instances):';
PRINT '  → DBDEV (Dev)';
PRINT '  → DBSTG (Staging)';
PRINT '  → DBPRD (Production Primary)';
PRINT '  → DBAPP (Application/ETL)';
PRINT '  → DFW3PRDBCSSQL01 (PRD Secondary)';
PRINT '  → DFW3PRDBCSSQL03 (PRD Reporting)';
PRINT '  → DFW3PRDBCSSQL04 (PRD Secondary)';
PRINT '  → DFW3PRDBCSSQL05 (PRD Secondary)';
GO
