/*
    SQL Health Monitor - Sample Instance Registration
    Example INSERT statements showing how to register your SQL Server instances.
    
    Customize these for your environment before running.
    
    Schema: [monitor]
    Compatibility: SQL Server 2016+
*/

USE [SQLHealthMonitor];
GO

-- ============================================================
-- SAMPLE: REGISTER YOUR INSTANCES
-- Copy and modify these examples for your environment.
-- ============================================================

-- Example: Development instance (standalone)
IF NOT EXISTS (SELECT 1 FROM [monitor].[RegisteredServers] WHERE InstanceName = 'SQL-DEV-01')
    INSERT INTO [monitor].[RegisteredServers] 
        (InstanceName, DisplayName, Environment, AgRole, ServerRole, IsActive, MonitorDatabase, Notes)
    VALUES 
        ('SQL-DEV-01', 'Development Server', 'DEV', 'STANDALONE', 'MIXED', 1, 'SQLHealthMonitor', 
         'Development instance. Used for testing and validation.');

-- Example: Staging instance (standalone)
IF NOT EXISTS (SELECT 1 FROM [monitor].[RegisteredServers] WHERE InstanceName = 'SQL-STG-01')
    INSERT INTO [monitor].[RegisteredServers] 
        (InstanceName, DisplayName, Environment, AgRole, ServerRole, IsActive, MonitorDatabase, Notes)
    VALUES 
        ('SQL-STG-01', 'Staging Server', 'STG', 'STANDALONE', 'MIXED', 1, 'SQLHealthMonitor', 
         'Staging instance. Pre-production validation environment.');

-- Example: Production primary (AG)
IF NOT EXISTS (SELECT 1 FROM [monitor].[RegisteredServers] WHERE InstanceName = 'SQL-PRD-01')
    INSERT INTO [monitor].[RegisteredServers] 
        (InstanceName, DisplayName, Environment, AgRole, ServerRole, IsActive, IsPrimary, MonitorDatabase, Notes)
    VALUES 
        ('SQL-PRD-01', 'Production Primary', 'PRD', 'PRIMARY', 'OLTP', 1, 1, 'SQLHealthMonitor', 
         'Primary production OLTP instance. AG primary replica.');

-- Example: Production secondary (AG - reporting workload)
IF NOT EXISTS (SELECT 1 FROM [monitor].[RegisteredServers] WHERE InstanceName = 'SQL-PRD-02')
    INSERT INTO [monitor].[RegisteredServers] 
        (InstanceName, DisplayName, Environment, AgRole, ServerRole, IsActive, MonitorDatabase, Notes)
    VALUES 
        ('SQL-PRD-02', 'Production Secondary', 'PRD', 'SECONDARY', 'REPORTING', 1, 'SQLHealthMonitor', 
         'AG secondary replica. Read-only reporting workload.');

-- Example: ETL/Application server
IF NOT EXISTS (SELECT 1 FROM [monitor].[RegisteredServers] WHERE InstanceName = 'SQL-ETL-01')
    INSERT INTO [monitor].[RegisteredServers] 
        (InstanceName, DisplayName, Environment, AgRole, ServerRole, IsActive, MonitorDatabase, Notes)
    VALUES 
        ('SQL-ETL-01', 'ETL Server', 'PRD', 'STANDALONE', 'ETL', 1, 'SQLHealthMonitor', 
         'Application/ETL instance. Handles data processing and integrations.');

GO

PRINT '✓ Sample instances registered. Modify for your environment.';
PRINT '  Available Environments: DEV, STG, PRD, DR';
PRINT '  Available AgRoles: STANDALONE, PRIMARY, SECONDARY, FORWARDER';
PRINT '  Available ServerRoles: OLTP, REPORTING, ETL, MIXED, ARCHIVE';
GO
