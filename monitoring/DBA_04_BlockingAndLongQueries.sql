-- =================================================================================
-- Script:      Active Blocking and Long-Running Queries
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: Identifies currently executing requests, their duration, wait
--              types, and any blocking sessions. Essential for diagnosing
--              real-time performance bottlenecks and locking issues.
-- =================================================================================

SELECT
    s.session_id,
    r.status,
    r.blocking_session_id AS BlockingSessionID,
    s.login_name AS LoginName,
    s.host_name AS HostName,
    DB_NAME(r.database_id) AS DatabaseName,
    r.command,
    CAST(DATEDIFF(second, r.start_time, GETDATE()) AS VARCHAR(10)) + 's' AS DurationSeconds,
    r.wait_type,
    r.wait_time AS WaitTimeMS,
    (
        SELECT SUBSTRING(st.text, (r.statement_start_offset/2) + 1,
        ((CASE r.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE r.statement_end_offset
         END - r.statement_start_offset)/2) + 1)
        FROM sys.dm_exec_sql_text(r.sql_handle) AS st
    ) AS CurrentStatementText,
    qp.query_plan AS QueryPlan
FROM
    sys.dm_exec_sessions AS s
JOIN
    sys.dm_exec_requests AS r ON s.session_id = r.session_id
OUTER APPLY
    sys.dm_exec_query_plan(r.plan_handle) AS qp
WHERE
    s.is_user_process = 1
    AND s.session_id <> @@SPID -- Exclude the current session
ORDER BY
    r.total_elapsed_time DESC;
