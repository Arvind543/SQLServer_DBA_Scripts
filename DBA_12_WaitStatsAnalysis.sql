-- =================================================================================
-- Script:      12. Wait Stats Analysis
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: Analyzes cumulative wait statistics since the last SQL Server restart.
--              It filters out common, benign waits to help focus on real
--              performance bottlenecks like I/O, CPU, or locking issues.
-- =================================================================================

WITH Waits AS
(
    SELECT
        wait_type,
        wait_time_ms / 1000.0 AS WaitS,
        (wait_time_ms - signal_wait_time_ms) / 1000.0 AS ResourceS,
        signal_wait_time_ms / 1000.0 AS SignalS,
        waiting_tasks_count AS WaitCount,
        100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS Pct
    FROM
        sys.dm_os_wait_stats
    WHERE
        -- Filter out common, benign wait types that are typically not actionable
        wait_type NOT IN (
            'BROKER_EVENTHANDLER', 'BROKER_RECEIVE_WAITFOR', 'BROKER_TASK_STOP',
            'BROKER_TO_FLUSH', 'BROKER_TRANSMITTER', 'CHECKPOINT_QUEUE', 'CHKPT',
            'CLR_AUTO_EVENT', 'CLR_MANUAL_EVENT', 'CLR_SEMAPHORE', 'DBMIRROR_DBM_EVENT',
            'DBMIRROR_EVENTS_QUEUE', 'DBMIRROR_WORKER_QUEUE', 'DBMIRRORING_CMD',
            'DIRTY_PAGE_POLL', 'DISPATCHER_QUEUE_SEMAPHORE', 'EXECSYNC', 'FSAGENT',
            'FT_IFTS_SCHEDULER_IDLE_WAIT', 'FT_IFTSHC_MUTEX', 'HADR_CLUSAPI_CALL',
            'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'HADR_LOGCAPTURE_WAIT',
            'HADR_NOTIFY_SYNC', 'HADR_TIMER_TASK', 'HADR_WORK_QUEUE', 'KSOURCE_WAKEUP',
            'LAZYWRITER_SLEEP', 'LOGMGR_QUEUE', 'MEMORY_ALLOCATION_EXT',
            'ONDEMAND_TASK_QUEUE', 'PARALLEL_REDO_DRAIN_WORKER',
            'PARALLEL_REDO_LOG_CACHE', 'PARALLEL_REDO_TRAN_LIST',
            'PARALLEL_REDO_WORKER_SYNC', 'PARALLEL_REDO_WORKER_WAIT_WORK',
            'PREEMPTIVE_OS_WRITEFILEGATHER', 'PWAIT_ALL_COMPONENTS_INITIALIZED',
            'PWAIT_DIRECTLOGCONSUMER_GETNEXT', 'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
            'QDS_ASYNC_QUEUE', 'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
            'QDS_SHUTDOWN_QUEUE', 'REDO_THREAD_PENDING_WORK', 'REQUEST_FOR_DEADLOCK_SEARCH',
            'RESOURCE_QUEUE', 'SERVER_IDLE_CHECK', 'SLEEP_BPOOL_FLUSH', 'SLEEP_DBSTARTUP',
            'SLEEP_DCOMSTARTUP', 'SLEEP_MASTERDBREADY', 'SLEEP_MASTERMDREADY',
            'SLEEP_MASTERUPGRADED', 'SLEEP_MSDBSTARTUP', 'SLEEP_SYSTEMTASK', 'SLEEP_TASK',
            'SLEEP_TEMPDBSTARTUP', 'SNI_HTTP_ACCEPT_WAIT', 'SP_SERVER_DIAGNOSTICS_SLEEP',
            'SQLTRACE_BUFFER_FLUSH', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
            'SQLTRACE_WAIT_ENTRIES', 'WAIT_FOR_RESULTS', 'WAITFOR', 'WAITFOR_TASKSHUTDOWN',
            'WAIT_XTP_RECOVERY', 'WAIT_XTP_HOST_WAIT', 'WAIT_XTP_CKPT_CLOSE',
            'XE_DISPATCHER_JOIN', 'XE_DISPATCHER_WAIT', 'XE_TIMER_EVENT'
        )
)
SELECT
    W.wait_type,
    CAST(W.WaitS AS DECIMAL(14, 2)) AS WaitS,
    CAST(W.ResourceS AS DECIMAL(14, 2)) AS ResourceS,
    CAST(W.SignalS AS DECIMAL(14, 2)) AS SignalS,
    W.WaitCount,
    CAST(W.Pct AS DECIMAL(14, 2)) AS Pct
FROM
    Waits AS W
ORDER BY
    W.WaitS DESC;
