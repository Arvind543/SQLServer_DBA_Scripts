-- =================================================================================
-- Script:      SQL Agent Job Status
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: Checks the status of all SQL Server Agent jobs, showing their
--              last run outcome, duration, and next scheduled run time.
--              Crucial for monitoring automated maintenance and tasks.
-- =================================================================================

SELECT
    j.name AS JobName,
    j.enabled AS IsEnabled,
    CASE h.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 4 THEN 'In Progress'
        ELSE 'Unknown'
    END AS LastRunStatus,
    msdb.dbo.agent_datetime(h.run_date, h.run_time) AS LastRunTime,
    STUFF(STUFF(RIGHT('000000' + CAST(h.run_duration AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':') AS LastRunDuration,
    s.next_run_date,
    s.next_run_time
FROM
    msdb.dbo.sysjobs j
LEFT JOIN
    msdb.dbo.sysjobhistory h ON j.job_id = h.job_id AND h.instance_id = (
        SELECT MAX(instance_id) FROM msdb.dbo.sysjobhistory WHERE job_id = j.job_id
    )
LEFT JOIN
    msdb.dbo.sysjobschedules AS js ON j.job_id = js.job_id
LEFT JOIN
    msdb.dbo.sysschedules AS s ON js.schedule_id = s.schedule_id
ORDER BY
    j.name;
