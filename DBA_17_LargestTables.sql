-- =================================================================================
-- Script:      17. Top 20 Largest Tables by Row Count and Size
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: Lists the top 20 largest tables in the current database, sorted
--              by the total space they occupy. Essential for capacity management
--              and identifying tables that may need archiving or partitioning.
-- =================================================================================

SELECT TOP 20
    s.name AS SchemaName,
    t.name AS TableName,
    p.rows AS RowCount,
    CAST((SUM(a.total_pages) * 8.0 / 1024) AS DECIMAL(18, 2)) AS TotalSpaceMB,
    CAST((SUM(a.used_pages) * 8.0 / 1024) AS DECIMAL(18, 2)) AS UsedSpaceMB,
    CAST((SUM(a.data_pages) * 8.0 / 1024) AS DECIMAL(18, 2)) AS DataSpaceMB
FROM
    sys.tables t
INNER JOIN
    sys.schemas s ON s.schema_id = t.schema_id
INNER JOIN
    sys.indexes i ON t.object_id = i.object_id
INNER JOIN
    sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
INNER JOIN
    sys.allocation_units a ON p.partition_id = a.container_id
WHERE
    t.is_ms_shipped = 0
    AND i.object_id > 255
GROUP BY
    t.name, s.name, p.rows
ORDER BY
    TotalSpaceMB DESC;

