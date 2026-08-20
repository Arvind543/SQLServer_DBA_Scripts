-- =================================================================================
-- Script:      5. Recent Database Object Changes
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: Audits DDL changes by identifying objects created, modified, or
--              dropped recently. Uses sys.objects for CREATE/MODIFY and the
--              SQL Server Default Trace for DROP events.
-- =================================================================================

-- Configure how many hours back to check for changes
DECLARE @HoursBack INT = 24;

DECLARE @TracePath NVARCHAR(260);
DECLARE @Cutoff DATETIME = DATEADD(HOUR, -@HoursBack, GETDATE());

SELECT @TracePath = path FROM sys.traces WHERE is_default = 1;

WITH Changes AS (
    -- Created Objects
    SELECT create_date AS EventTime, 'CREATE' AS EventType, type_desc AS ObjectType, SCHEMA_NAME(schema_id) AS SchemaName, name AS ObjectName, NULL AS LoginName
    FROM sys.objects
    WHERE is_ms_shipped = 0 AND create_date >= @Cutoff
    UNION ALL
    -- Modified Objects
    SELECT modify_date, 'MODIFY', type_desc, SCHEMA_NAME(schema_id), name, NULL
    FROM sys.objects
    WHERE is_ms_shipped = 0 AND modify_date > create_date AND modify_date >= @Cutoff
    UNION ALL
    -- Dropped Objects (from Default Trace)
    SELECT StartTime, 'DROP', ObjectTypeName, SchemaName, ObjectName, LoginName
    FROM sys.fn_trace_gettable(@TracePath, DEFAULT)
    WHERE EventClass = 47 AND DatabaseName = DB_NAME() AND StartTime >= @Cutoff
)
SELECT * FROM Changes ORDER BY EventTime DESC;

IF @TracePath IS NULL
BEGIN
    PRINT 'Warning: Default Trace is disabled. DROP events cannot be tracked.';
END
