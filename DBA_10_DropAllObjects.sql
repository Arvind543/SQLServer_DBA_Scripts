-- =================================================================================
-- Script:      10. Generate Script to Drop All Objects
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: Safely generates T-SQL commands to drop all user-defined objects
--              in the current database, respecting dependencies.
--              *** IT DOES NOT EXECUTE ANYTHING, ONLY PRINTS THE SCRIPT. ***
-- =================================================================================

SET NOCOUNT ON;
DECLARE @sql NVARCHAR(MAX) = N'';

-- Foreign Keys
SELECT @sql += N'ALTER TABLE ' + QUOTENAME(s.name) + '.' + QUOTENAME(t.name) + ' DROP CONSTRAINT ' + QUOTENAME(fk.name) + ';' + CHAR(13)
FROM sys.foreign_keys fk JOIN sys.tables t ON fk.parent_object_id = t.object_id JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE fk.is_ms_shipped = 0;
-- Views, Procs, Functions
SELECT @sql += N'DROP ' + CASE type WHEN 'P' THEN 'PROCEDURE' WHEN 'V' THEN 'VIEW' ELSE 'FUNCTION' END + ' ' + QUOTENAME(SCHEMA_NAME(schema_id)) + '.' + QUOTENAME(name) + ';' + CHAR(13)
FROM sys.objects WHERE type IN ('P', 'V', 'FN', 'IF', 'TF', 'FS', 'FT') AND is_ms_shipped = 0;
-- Tables
SELECT @sql += N'DROP TABLE ' + QUOTENAME(SCHEMA_NAME(schema_id)) + '.' + QUOTENAME(name) + ';' + CHAR(13)
FROM sys.tables WHERE is_ms_shipped = 0;
-- User Defined Types
SELECT @sql += N'DROP TYPE ' + QUOTENAME(SCHEMA_NAME(schema_id)) + '.' + QUOTENAME(name) + ';' + CHAR(13)
FROM sys.types WHERE is_user_defined = 1;

PRINT @sql;
-- Copy the output from the messages tab and execute it in a new window.
-- =================================================================================
-- Script:      10. Generate Script to Drop All Objects
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: Safely generates T-SQL commands to drop all user-defined objects
--              in the current database, respecting dependencies.
--              *** IT DOES NOT EXECUTE ANYTHING, ONLY PRINTS THE SCRIPT. ***
-- =================================================================================

SET NOCOUNT ON;
DECLARE @sql NVARCHAR(MAX) = N'';

-- Foreign Keys
SELECT @sql += N'ALTER TABLE ' + QUOTENAME(s.name) + '.' + QUOTENAME(t.name) + ' DROP CONSTRAINT ' + QUOTENAME(fk.name) + ';' + CHAR(13)
FROM sys.foreign_keys fk JOIN sys.tables t ON fk.parent_object_id = t.object_id JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE fk.is_ms_shipped = 0;
-- Views, Procs, Functions
SELECT @sql += N'DROP ' + CASE type WHEN 'P' THEN 'PROCEDURE' WHEN 'V' THEN 'VIEW' ELSE 'FUNCTION' END + ' ' + QUOTENAME(SCHEMA_NAME(schema_id)) + '.' + QUOTENAME(name) + ';' + CHAR(13)
FROM sys.objects WHERE type IN ('P', 'V', 'FN', 'IF', 'TF', 'FS', 'FT') AND is_ms_shipped = 0;
-- Tables
SELECT @sql += N'DROP TABLE ' + QUOTENAME(SCHEMA_NAME(schema_id)) + '.' + QUOTENAME(name) + ';' + CHAR(13)
FROM sys.tables WHERE is_ms_shipped = 0;
-- User Defined Types
SELECT @sql += N'DROP TYPE ' + QUOTENAME(SCHEMA_NAME(schema_id)) + '.' + QUOTENAME(name) + ';' + CHAR(13)
FROM sys.types WHERE is_user_defined = 1;

PRINT @sql;
-- Copy the output from the messages tab and execute it in a new window.
