- =================================================================================
-- Script:      Unused Index Identification
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: Identifies non-clustered indexes that have high write counts
--              (updates) but low or zero read counts (seeks, scans, lookups).
--              These are candidates for being dropped to improve write performance.
-- =================================================================================

SELECT
    DB_NAME() AS DatabaseName,
    s.name AS SchemaName,
    t.name AS TableName,
    i.name AS IndexName,
    us.user_seeks,
    us.user_scans,
    us.user_lookups,
    us.user_updates AS WriteCount,
    (us.user_seeks + us.user_scans + us.user_lookups) AS TotalReadCount,
    'DROP INDEX [' + i.name + '] ON [' + s.name + '].[' + t.name + '];' AS DropStatement
FROM
    sys.dm_db_index_usage_stats AS us
JOIN
    sys.indexes AS i ON us.object_id = i.object_id AND us.index_id = i.index_id
JOIN
    sys.tables AS t ON us.object_id = t.object_id
JOIN
    sys.schemas AS s ON t.schema_id = s.schema_id
WHERE
    us.database_id = DB_ID()
    AND i.type_desc = 'NONCLUSTERED'
    AND i.is_primary_key = 0
    AND i.is_unique_constraint = 0
    AND us.user_seeks = 0
    AND us.user_scans = 0
    AND us.user_lookups = 0
ORDER BY
    us.user_updates DESC;
