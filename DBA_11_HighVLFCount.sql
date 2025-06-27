-- =================================================================================
-- Script:      11. High Virtual Log File (VLF) Count Detection
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: Checks for databases with a high number of Virtual Log Files (VLFs),
--              which can degrade performance during startup, backups, and restores.
--              Generally, a count over 100-200 for smaller logs or 1000 for
--              larger logs is worth investigating.
-- =================================================================================
SET NOCOUNT ON;

-- Create a temporary table to store the results of DBCC LOGINFO
CREATE TABLE #VLFInfo (
    RecoveryUnitId INT,
    FileId INT,
    FileSize BIGINT,
    StartOffset BIGINT,
    FSeqNo INT,
    Status TINYINT,
    Parity TINYINT,
    CreateLSN NUMERIC(25,0)
);

-- Create a table to hold the final VLF counts for each database
CREATE TABLE #VLFCounts (
    DatabaseName SYSNAME,
    VLFCount INT
);

-- Use a cursor to iterate through all online databases
DECLARE @db_name SYSNAME;
DECLARE @sql_command NVARCHAR(MAX);

DECLARE db_cursor CURSOR FOR
SELECT name
FROM sys.databases
WHERE state = 0; -- Only online databases

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql_command = N'USE ' + QUOTENAME(@db_name) + N'; INSERT INTO #VLFInfo EXEC sp_executesql N''DBCC LOGINFO'';';

    -- Clear the temp table for the next database
    TRUNCATE TABLE #VLFInfo;

    -- Execute the command
    BEGIN TRY
        EXEC sp_executesql @sql_command;
        INSERT INTO #VLFCounts (DatabaseName, VLFCount)
        SELECT @db_name, COUNT(*) FROM #VLFInfo;
    END TRY
    BEGIN CATCH
        PRINT N'Could not check VLF count for database ' + QUOTENAME(@db_name) + N'. Error: ' + ERROR_MESSAGE();
    END CATCH

    FETCH NEXT FROM db_cursor INTO @db_name;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

-- Display the results, ordered by the highest VLF count
SELECT
    DatabaseName,
    VLFCount,
    CASE
        WHEN VLFCount > 1000 THEN 'High - Investigate ASAP'
        WHEN VLFCount > 200 THEN 'Warning - Monitor'
        ELSE 'OK'
    END AS Recommendation
FROM #VLFCounts
ORDER BY VLFCount DESC;

-- Clean up temporary tables
DROP TABLE #VLFInfo;
DROP TABLE #VLFCounts;
