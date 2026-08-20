-- =================================================================================
-- Script:      19. Database Backup History
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: Retrieves the backup history for a specific database over the
--              last 30 days. Useful for verifying backup completion and RPO.
-- =================================================================================

-- Set the target database name here
DECLARE @DatabaseName SYSNAME = DB_NAME();

SELECT TOP 100
    bs.database_name,
    CASE bs.type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
    END AS BackupType,
    bs.backup_start_date,
    bs.backup_finish_date,
    CAST(bs.backup_size / 1024 / 1024 AS DECIMAL(18, 2)) AS BackupSizeMB,
    bmf.physical_device_name
FROM
    msdb.dbo.backupset bs
JOIN
    msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
WHERE
    bs.database_name = @DatabaseName
    AND bs.backup_start_date > DATEADD(DAY, -30, GETDATE()) -- Last 30 days
ORDER BY
    bs.backup_start_date DESC;

