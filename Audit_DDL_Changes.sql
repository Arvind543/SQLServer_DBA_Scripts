-- =================================================================================
-- SQL Server Script to Identify Recent Object Changes (CREATE, MODIFY, DROP)
-- =================================================================================
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: This script identifies database objects that have been created,
--              modified, or dropped within a specified recent timeframe.
--              It uses a combination of system catalog views (for CREATE/MODIFY)
--              and the SQL Server Default Trace (for DROP) to provide a
--              comprehensive audit of recent DDL changes.
--
-- How to Use:
-- 1. Set the @HoursToGoBack variable to the desired timeframe (in hours).
--    For example, 24 for the last day, 168 for the last week.
-- 2. Connect to the target SQL Server database in SSMS.
-- 3. Run this script.
-- 4. The result set will show a chronological list of changes.
--
-- Prerequisites:
--  - The SQL Server "Default Trace" must be enabled. It is enabled by default
--    on most modern SQL Server instances. This is required to capture DROP events.
--  - You must have VIEW SERVER STATE permissions to read the default trace.
--
-- =================================================================================

-- ********************************************************************************
-- ** Configuration: Set the timeframe for the report in hours **
-- ********************************************************************************
DECLARE @HoursToGoBack INT = 24; -- Look for changes in the last 24 hours.
-- ********************************************************************************


SET NOCOUNT ON;

DECLARE @TraceFilePath NVARCHAR(260);
DECLARE @CutoffTime DATETIME;

SET @CutoffTime = DATEADD(HOUR, -@HoursToGoBack, GETDATE());

-- Find the path of the default trace file
SELECT @TraceFilePath = path
FROM sys.traces
WHERE is_default = 1;

-- CTE to gather all recent events into a single, unified format
WITH RecentChanges AS (
    -- 1. Get CREATED objects from sys.objects
    SELECT
        o.create_date AS EventTime,
        'CREATE' AS EventType,
        o.type_desc AS ObjectType,
        s.name AS SchemaName,
        o.name AS ObjectName,
        NULL AS LoginName -- Login info is not in sys.objects
    FROM
        sys.objects AS o
    INNER JOIN
        sys.schemas AS s ON o.schema_id = s.schema_id
    WHERE
        o.is_ms_shipped = 0
        AND o.create_date >= @CutoffTime

    UNION ALL

    -- 2. Get MODIFIED objects from sys.objects
    SELECT
        o.modify_date AS EventTime,
        'MODIFY' AS EventType,
        o.type_desc AS ObjectType,
        s.name AS SchemaName,
        o.name AS ObjectName,
        NULL AS LoginName
    FROM
        sys.objects AS o
    INNER JOIN
        sys.schemas AS s ON o.schema_id = s.schema_id
    WHERE
        o.is_ms_shipped = 0
        AND o.modify_date > o.create_date -- Ensure it's a true modification
        AND o.modify_date >= @CutoffTime

    UNION ALL

    -- 3. Get DROPPED objects from the Default Trace
    --    This part will return no rows if the default trace is disabled.
    SELECT
        t.StartTime AS EventTime,
        'DROP' AS EventType,
        t.ObjectTypeName AS ObjectType,
        t.SchemaName AS SchemaName,
        t.ObjectName AS ObjectName,
        t.LoginName
    FROM
        sys.fn_trace_gettable(@TraceFilePath, DEFAULT) AS t
    WHERE
        t.EventClass = 47 -- Event Class 47 corresponds to 'Object:Deleted'
        AND t.DatabaseName = DB_NAME() -- Filter for the current database
        AND t.StartTime >= @CutoffTime
)
-- Final result set
SELECT
    rc.EventTime,
    rc.EventType,
    rc.ObjectType,
    rc.SchemaName,
    rc.ObjectName,
    ISNULL(rc.LoginName, 'N/A (from sys.objects)') AS LoginName
FROM
    RecentChanges rc
ORDER BY
    rc.EventTime DESC;

-- Provide feedback if the trace file could not be found
IF @TraceFilePath IS NULL
BEGIN
    PRINT 'Warning: SQL Server Default Trace file not found or is disabled.';
    PRINT '         DROP events cannot be tracked without it.';
END;

SET NOCOUNT OFF;
