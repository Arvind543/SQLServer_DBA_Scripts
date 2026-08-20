-- =================================================================================
-- Script:      15. Most Expensive Queries
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: Finds the most resource-intensive queries from the plan cache
--              based on total CPU time, logical reads, and execution count.
--              This is a primary tool for performance tuning efforts.
-- =================================================================================

-- Change this to order by a different metric if needed
DECLARE @OrderBy VARCHAR(10) = 'CPU'; -- Options: 'CPU', 'Reads', 'Writes', 'Duration'

SELECT TOP 50
    qs.execution_count,
    qs.total_worker_time / 1000 AS TotalCpuTime_ms,
    qs.total_elapsed_time / 1000 AS TotalDuration_ms,
    qs.total_logical_reads,
    qs.total_logical_writes,
    SUBSTRING(st.text, (qs.statement_start_offset/2) + 1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset
         END - qs.statement_start_offset)/2) + 1) AS QueryText,
    DB_NAME(st.dbid) AS DatabaseName,
    qp.query_plan
FROM
    sys.dm_exec_query_stats AS qs
CROSS APPLY
    sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY
    sys.dm_exec_query_plan(qs.plan_handle) AS qp
ORDER BY
    CASE
        WHEN @OrderBy = 'CPU' THEN qs.total_worker_time
        WHEN @OrderBy = 'Reads' THEN qs.total_logical_reads
        WHEN @OrderBy = 'Writes' THEN qs.total_logical_writes
        WHEN @OrderBy = 'Duration' THEN qs.total_elapsed_time
        ELSE qs.total_worker_time
    END DESC;
