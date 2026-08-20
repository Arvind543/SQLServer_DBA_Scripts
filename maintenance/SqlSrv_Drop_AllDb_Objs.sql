-- =================================================================================
-- SQL Server Script to Generate DROP Statements for All Database Objects
-- =================================================================================
-- Author:      Arvind Toorpu
-- Date:        2024-06-26
-- Description: This script dynamically generates the T-SQL commands needed to
--              drop all user-defined objects in the current database. It respects
--              object dependencies by dropping them in a specific order.
--
-- How to Use:
-- 1. Connect to the target SQL Server database in SQL Server Management Studio (SSMS).
-- 2. Run this entire script.
-- 3. The script will output a series of DROP statements in the "Messages" tab.
-- 4. Copy the generated DROP statements from the "Messages" tab into a new query window.
-- 5. Review the generated script carefully to ensure you are dropping the correct objects.
-- 6. Execute the new script to drop all the objects.
--
-- IMPORTANT:
--  - This script is designed for user databases. Do NOT run it on system databases
--    (master, model, msdb, tempdb).
--  - It drops ALL user objects, including tables, views, procedures, functions, etc.
--  - ALWAYS take a backup of your database before running the generated script.
-- =================================================================================

SET NOCOUNT ON;

-- Use a temporary table to store the generated DROP commands
DECLARE @DropCommands TABLE (
    ID INT IDENTITY(1,1),
    Command NVARCHAR(MAX)
);

-- 1. Drop Foreign Key Constraints
PRINT '-- (1) Dropping Foreign Key Constraints...';
INSERT INTO @DropCommands (Command)
SELECT
    'ALTER TABLE ' + QUOTENAME(s.name) + '.' + QUOTENAME(t.name) +
    ' DROP CONSTRAINT ' + QUOTENAME(fk.name) + ';'
FROM
    sys.foreign_keys AS fk
INNER JOIN
    sys.tables AS t ON fk.parent_object_id = t.object_id
INNER JOIN
    sys.schemas AS s ON t.schema_id = s.schema_id
WHERE
    fk.is_ms_shipped = 0;

-- 2. Drop Triggers
PRINT '-- (2) Dropping Triggers...';
INSERT INTO @DropCommands (Command)
SELECT
    'DROP TRIGGER ' + QUOTENAME(s.name) + '.' + QUOTENAME(tr.name) + ';'
FROM
    sys.triggers AS tr
INNER JOIN
    sys.objects AS o ON tr.parent_id = o.object_id
INNER JOIN
    sys.schemas AS s ON o.schema_id = s.schema_id
WHERE
    tr.is_ms_shipped = 0;


-- 3. Drop Views
PRINT '-- (3) Dropping Views...';
INSERT INTO @DropCommands (Command)
SELECT
    'DROP VIEW ' + QUOTENAME(SCHEMA_NAME(schema_id)) + '.' + QUOTENAME(name) + ';'
FROM
    sys.views
WHERE
    is_ms_shipped = 0;

-- 4. Drop Stored Procedures
PRINT '-- (4) Dropping Stored Procedures...';
INSERT INTO @DropCommands (Command)
SELECT
    'DROP PROCEDURE ' + QUOTENAME(SCHEMA_NAME(schema_id)) + '.' + QUOTENAME(name) + ';'
FROM
    sys.procedures
WHERE
    is_ms_shipped = 0;

-- 5. Drop User-Defined Functions (Scalar, Inline Table-Valued, Multi-statement Table-Valued)
PRINT '-- (5) Dropping User-Defined Functions...';
INSERT INTO @DropCommands (Command)
SELECT
    'DROP FUNCTION ' + QUOTENAME(SCHEMA_NAME(schema_id)) + '.' + QUOTENAME(name) + ';'
FROM
    sys.objects
WHERE
    type IN ('FN', 'IF', 'TF', 'FS', 'FT')
    AND is_ms_shipped = 0;


-- 6. Drop Default and Check Constraints
PRINT '-- (6) Dropping Default and Check Constraints...';
INSERT INTO @DropCommands (Command)
SELECT
    'ALTER TABLE ' + QUOTENAME(s.name) + '.' + QUOTENAME(t.name) +
    ' DROP CONSTRAINT ' + QUOTENAME(dc.name) + ';'
FROM
    sys.default_constraints AS dc
INNER JOIN
    sys.tables AS t ON dc.parent_object_id = t.object_id
INNER JOIN
    sys.schemas AS s ON t.schema_id = s.schema_id
WHERE
    dc.is_ms_shipped = 0;

INSERT INTO @DropCommands (Command)
SELECT
    'ALTER TABLE ' + QUOTENAME(s.name) + '.' + QUOTENAME(t.name) +
    ' DROP CONSTRAINT ' + QUOTENAME(cc.name) + ';'
FROM
    sys.check_constraints AS cc
INNER JOIN
    sys.tables AS t ON cc.parent_object_id = t.object_id
INNER JOIN
    sys.schemas AS s ON t.schema_id = s.schema_id
WHERE
    cc.is_ms_shipped = 0;

-- 7. Drop User-Defined Table Types
PRINT '-- (7) Dropping User-Defined Table Types...';
INSERT INTO @DropCommands (Command)
SELECT
    'DROP TYPE ' + QUOTENAME(SCHEMA_NAME(schema_id)) + '.' + QUOTENAME(name) + ';'
FROM
    sys.table_types
WHERE
    is_user_defined = 1;


-- 8. Drop Tables
PRINT '-- (8) Dropping Tables...';
INSERT INTO @DropCommands (Command)
SELECT
    'DROP TABLE ' + QUOTENAME(SCHEMA_NAME(schema_id)) + '.' + QUOTENAME(name) + ';'
FROM
    sys.tables
WHERE
    is_ms_shipped = 0;

-- 9. Drop User-Defined Data Types (Aliases)
PRINT '-- (9) Dropping User-Defined Data Types...';
INSERT INTO @DropCommands (Command)
SELECT
    'DROP TYPE ' + QUOTENAME(SCHEMA_NAME(schema_id)) + '.' + QUOTENAME(name) + ';'
FROM
    sys.types
WHERE
    is_user_defined = 1 AND is_table_type = 0;

-- 10. Drop Schemas (if they are empty)
PRINT '-- (10) Dropping User-Defined Schemas...';
INSERT INTO @DropCommands (Command)
SELECT
    'DROP SCHEMA ' + QUOTENAME(name) + ';'
FROM
    sys.schemas
WHERE
    schema_id > 4 -- Exclude system schemas (dbo, guest, sys, INFORMATION_SCHEMA)
    AND principal_id > 4; -- Additional check for user schemas


-- Print all generated commands
PRINT '--------------------------------------------------------------------------------';
PRINT '-- Generated DROP Script - Please review carefully before executing!        --';
PRINT '--------------------------------------------------------------------------------';

DECLARE @CommandToPrint NVARCHAR(MAX);
DECLARE cur CURSOR FOR
SELECT Command FROM @DropCommands ORDER BY ID;

OPEN cur;
FETCH NEXT FROM cur INTO @CommandToPrint;
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT @CommandToPrint;
    FETCH NEXT FROM cur INTO @CommandToPrint;
END
CLOSE cur;
DEALLOCATE cur;

PRINT '--------------------------------------------------------------------------------';
PRINT '-- End of Generated Script                                                  --';
PRINT '--------------------------------------------------------------------------------';

SET NOCOUNT OFF;
