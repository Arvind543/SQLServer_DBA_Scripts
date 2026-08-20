- =================================================================================
-- Script:      1. Database Overview and Health Check
-- Author:      Arvind Toorpu
-- Date:        2024-06-21
-- Description: Provides a comprehensive overview of all databases on the instance,
--              including size, space usage, recovery model, state, and last
--              backup dates. Essential for a daily health check.
-- =================================================================================

SELECT
    d.name AS DatabaseName,
    d.state_desc AS DatabaseState,
    d.recovery_model_desc AS RecoveryModel,
    CAST(mf.TotalSizeMB AS DECIMAL(18, 2)) AS TotalSizeMB,
    CAST(mf.LogSizeMB AS DECIMAL(18, 2)) AS LogSizeMB,
    CAST((mf.TotalSizeMB - mf.SpaceUsedMB) AS DECIMAL(18, 2)) AS FreeSpaceMB,
    bs_full.last_full_backup_date,
    bs_diff.last_diff_backup_date,
    bs_log.last_log_backup_date
FROM
    sys.databases d
LEFT JOIN (
    SELECT
        database_id,
        SUM(size * 8.0 / 1024) AS TotalSizeMB,
        SUM(CASE WHEN type_desc = 'LOG' THEN size * 8.0 / 1024 ELSE 0 END) AS LogSizeMB,
        SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS INT) * 8.0 / 1024) AS SpaceUsedMB
    FROM sys.master_files
    GROUP BY database_id
) AS mf ON d.database_id = mf.database_id
LEFT JOIN (
    SELECT
        database_name,
        MAX(backup_finish_date) AS last_full_backup_date
    FROM msdb.dbo.backupset
    WHERE type = 'D'
    GROUP BY database_name
) AS bs_full ON d.name = bs_full.database_name
LEFT JOIN (
    SELECT
        database_name,
        MAX(backup_finish_date) AS last_diff_backup_date
    FROM msdb.dbo.backupset
    WHERE type = 'I'
    GROUP BY database_name
) AS bs_diff ON d.name = bs_diff.database_name
LEFT JOIN (
    SELECT
        database_name,
        MAX(backup_finish_date) AS last_log_backup_date
    FROM msdb.dbo.backupset
    WHERE type = 'L'
    GROUP BY database_name
) AS bs_log ON d.name = bs_log.database_name
ORDER BY
    d.name;
