-- =================================================================================
-- Script:      2. Index Fragmentation Analysis
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: Identifies fragmented indexes within the current database that may
--              negatively impact performance. Provides recommendations to REBUILD
--              (for >30% fragmentation) or REORGANIZE (for 10-30%).
-- =================================================================================

SELECT
    DB_NAME() AS DatabaseName,
    s.name AS SchemaName,
    t.name AS TableName,
    i.name AS IndexName,
    ps.index_type_desc AS IndexType,
    ps.avg_fragmentation_in_percent,
    ps.page_count,
    CASE
        WHEN ps.avg_fragmentation_in_percent > 30 THEN 'REBUILD'
        WHEN ps.avg_fragmentation_in_percent > 10 THEN 'REORGANIZE'
        ELSE 'OK'
    END AS Recommendation,
    'ALTER INDEX [' + i.name + '] ON [' + s.name + '].[' + t.name + '] ' +
    CASE
        WHEN ps.avg_fragmentation_in_percent > 30 THEN 'REBUILD'
        ELSE 'REORGANIZE'
    END + ';' AS MaintenanceScript
FROM
    sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'SAMPLED') AS ps
JOIN
    sys.indexes AS i ON ps.object_id = i.object_id AND ps.index_id = i.index_id
JOIN
    sys.tables AS t ON ps.object_id = t.object_id
JOIN
    sys.schemas AS s ON t.schema_id = s.schema_id
WHERE
    ps.avg_fragmentation_in_percent > 10 -- Only show indexes with >10% fragmentation
    AND ps.page_count > 100 -- Ignore very small indexes
    AND i.name IS NOT NULL
ORDER BY
    ps.avg_fragmentation_in_percent DESC;
