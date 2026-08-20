/*
Author: Arvind Toorpu
Date Created: December 4, 2024
Description: 
This script identifies and returns all fragmented indexes on all databases within the SQL Server instance where it is executed. 
It can be run across multiple instances using the Central Management Server (CMS) capability for consolidated management.
The script includes details about the database, schema, table, index name, fragmentation percentage, and page count.

Usage:
Run the script in a SQL Server Management Studio (SSMS) query window. 
Ensure you have appropriate permissions to execute dynamic SQL and access database details.

Note: 
Indexes with a page count greater than 1000 and fragmentation percentage higher than 5% are included in the result.
*/

/* Create a temporary table to store fragmented index details */
CREATE TABLE #temp_if (
    [DBName] NVARCHAR(128) NULL,
    [SchemaName] NVARCHAR(128) NULL,
    [ObjectName] NVARCHAR(128) NULL,
    [IndexName] NVARCHAR(128) NULL,
    [Fragmentation] NUMERIC(38, 35) NULL,
    [Page_Count] BIGINT NULL
);

/* Gather fragmented index details from all databases */
EXEC master.sys.sp_msforeachdb 
    'USE [?];
    INSERT INTO #temp_if
    SELECT 
        ''?'' AS [DBName],
        dbschemas.[name] AS [SchemaName], 
        dbtables.[name] AS [ObjectName], 
        dbindexes.[name] AS [IndexName],
        indexstats.avg_fragmentation_in_percent AS [Fragmentation],
        indexstats.page_count AS [Page_Count]
    FROM sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL, NULL, NULL) AS indexstats
    INNER JOIN sys.tables dbtables ON dbtables.[object_id] = indexstats.[object_id]
    INNER JOIN sys.schemas dbschemas ON dbtables.[schema_id] = dbschemas.[schema_id]
    INNER JOIN sys.indexes dbindexes ON dbindexes.[object_id] = indexstats.[object_id]
        AND indexstats.index_id = dbindexes.index_id
    WHERE indexstats.database_id = DB_ID() 
        AND indexstats.page_count > 1000
        AND indexstats.avg_fragmentation_in_percent > 5
        AND dbindexes.[name] IS NOT NULL;';

/* Retrieve and display the results, ordered by page count */
SELECT * 
FROM #temp_if
ORDER BY Page_Count DESC;

/* Drop the temporary table */
DROP TABLE #temp_if;
