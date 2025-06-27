-- =================================================================================
-- Script:      20. Generate sp_help for All Tables
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: A utility script that generates and executes sp_help for every
--              user-defined table in the database. The output is a complete
--              documentation dump of all table structures.
-- =================================================================================

-- Note: This script EXECUTES sp_help for each table. The results will appear
-- one after another in the results pane.

SET NOCOUNT ON;

DECLARE @TableName NVARCHAR(256);
DECLARE @SchemaName NVARCHAR(256);
DECLARE @Command NVARCHAR(512);

DECLARE cur_tables CURSOR FOR
    SELECT s.name, t.name
    FROM sys.tables AS t
    JOIN sys.schemas AS s ON t.schema_id = s.schema_id
    WHERE t.is_ms_shipped = 0
    ORDER BY s.name, t.name;

OPEN cur_tables;
FETCH NEXT FROM cur_tables INTO @SchemaName, @TableName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Command = 'EXEC sp_help ''' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ''';';
    PRINT '-- Executing: ' + @Command;
    EXEC sp_executesql @Command;

    FETCH NEXT FROM cur_tables INTO @SchemaName, @TableName;
END

CLOSE cur_tables;
DEALLOCATE cur_tables;

SET NOCOUNT OFF;
