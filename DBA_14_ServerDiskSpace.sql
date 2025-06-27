-- =================================================================================
-- Script:      14. Server Disk Space Usage
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: Reports the total capacity and free space for all disk volumes
--              where SQL Server database files reside. This is critical for
--              capacity planning and preventing out-of-space errors.
-- =================================================================================

SELECT DISTINCT
    vs.volume_mount_point,
    CAST(vs.total_bytes / 1024.0 / 1024 / 1024 AS DECIMAL(18, 2)) AS TotalSizeGB,
    CAST(vs.available_bytes / 1024.0 / 1024 / 1024 AS DECIMAL(18, 2)) AS FreeSpaceGB,
    CAST(CAST(vs.available_bytes AS FLOAT) / CAST(vs.total_bytes AS FLOAT) * 100.0 AS DECIMAL(18, 2)) AS PercentFree
FROM
    sys.master_files AS mf
CROSS APPLY
    sys.dm_os_volume_stats(mf.database_id, mf.file_id) AS vs
ORDER BY
    vs.volume_mount_point;
