-- =================================================================================
-- SQL Server Script to Identify Missing Indexes
-- =================================================================================
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: This script queries SQL Server's Dynamic Management Views (DMVs)
--              to find missing indexes that the query optimizer has identified
--              as potentially beneficial for query performance. The results are
--              ordered by the potential improvement score.
--
-- How to Use:
-- 1. Connect to the target SQL Server database in SQL Server Management Studio (SSMS).
-- 2. Run this script.
-- 3. The results will show a list of recommended indexes, including the table,
--    the columns to include, and a generated CREATE INDEX statement.
-- 4. Review the recommendations carefully. The "ImprovementScore" is a key
--    metric calculated by the query optimizer. Higher scores indicate a
--    higher potential impact on performance.
--
-- IMPORTANT:
--  - The data in these DMVs is cleared upon server restart. For best results,
--    run this script on a server that has been running for a while with a
--    typical production workload.
--  - DO NOT blindly create all recommended indexes. Each new index adds
--    overhead to write operations (INSERT, UPDATE, DELETE).
--  - ALWAYS test the impact of a new index in a development or staging
--    environment before applying it to production.
-- =================================================================================

SET NOCOUNT ON;

SELECT
    -- Object Details
    DB_NAME(mid.database_id) AS DatabaseName,
    OBJECT_SCHEMA_NAME(mid.object_id, mid.database_id) AS SchemaName,
    OBJECT_NAME(mid.object_id, mid.database_id) AS TableName,

    -- Index Details
    mid.equality_columns AS EqualityColumns,
    mid.inequality_columns AS InequalityColumns,
    mid.included_columns AS IncludedColumns,

    -- Performance Impact Statistics
    migs.user_seeks AS UserSeeks,
    migs.user_scans AS UserScans,
    migs.avg_total_user_cost AS AvgTotalUserCost,
    migs.avg_user_impact AS AvgUserImpact, -- Percentage improvement

    -- Calculated Improvement Score
    -- This metric combines seeks, scans, and impact to give a single value
    -- for prioritizing which indexes to create first.
    ROUND((migs.user_seeks + migs.user_scans) * migs.avg_total_user_cost * migs.avg_user_impact, 2) AS ImprovementScore,

    -- Generated CREATE INDEX Statement
    'CREATE NONCLUSTERED INDEX [IX_'
        + OBJECT_NAME(mid.object_id, mid.database_id)
        + '_' + REPLACE(REPLACE(REPLACE(ISNULL(mid.equality_columns, ''), ', ', '_'), '[', ''), ']','')
        + CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN '_' ELSE '' END
        + REPLACE(REPLACE(REPLACE(ISNULL(mid.inequality_columns, ''), ', ', '_'), '[', ''), ']','')
    + ']'
    + ' ON ' + QUOTENAME(OBJECT_SCHEMA_NAME(mid.object_id, mid.database_id)) + '.' + QUOTENAME(OBJECT_NAME(mid.object_id, mid.database_id))
    + ' (' + ISNULL(mid.equality_columns, '')
        + CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN ',' ELSE '' END
        + ISNULL(mid.inequality_columns, '')
    + ')'
    + ISNULL(' INCLUDE (' + mid.included_columns + ');', ';') AS CreateIndexStatement

FROM
    sys.dm_db_missing_index_groups AS mig
INNER JOIN
    sys.dm_db_missing_index_group_stats AS migs ON migs.group_handle = mig.index_group_handle
INNER JOIN
    sys.dm_db_missing_index_details AS mid ON mig.index_handle = mid.index_handle
WHERE
    mid.database_id = DB_ID() -- Filter for the current database
ORDER BY
    ImprovementScore DESC;

GO
