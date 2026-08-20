-- =================================================================================
-- Script:      7. Database File I/O Statistics
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: Analyzes I/O statistics for each database file, helping to
--              identify disk bottlenecks by showing read/write counts, total
--              bytes, and average stall times.
-- =================================================================================

SELECT
    DB_NAME(vfs.database_id) AS DatabaseName,
    mf.name AS LogicalFileName,
    mf.physical_name AS PhysicalFileName,
    vfs.num_of_reads AS NumberOfReads,
    vfs.num_of_writes AS NumberOfWrites,
    CAST(vfs.num_of_bytes_read / 1024.0 / 1024.0 AS DECIMAL(18, 2)) AS TotalBytesReadMB,
    CAST(vfs.num_of_bytes_written / 1024.0 / 1024.0 AS DECIMAL(18, 2)) AS TotalBytesWrittenMB,
    CASE WHEN vfs.num_of_reads = 0 THEN 0 ELSE
        CAST(vfs.io_stall_read_ms / vfs.num_of_reads AS DECIMAL(18, 2))
    END AS AvgReadStallMS,
    CASE WHEN vfs.num_of_writes = 0 THEN 0 ELSE
        CAST(vfs.io_stall_write_ms / vfs.num_of_writes AS DECIMAL(18, 2))
    END AS AvgWriteStallMS
FROM
    sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
JOIN
    sys.master_files AS mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
ORDER BY
    (vfs.io_stall_read_ms + vfs.io_stall_write_ms) DESC;
-- =================================================================================
-- Script:      7. Database File I/O Statistics
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: Analyzes I/O statistics for each database file, helping to
--              identify disk bottlenecks by showing read/write counts, total
--              bytes, and average stall times.
-- =================================================================================

SELECT
    DB_NAME(vfs.database_id) AS DatabaseName,
    mf.name AS LogicalFileName,
    mf.physical_name AS PhysicalFileName,
    vfs.num_of_reads AS NumberOfReads,
    vfs.num_of_writes AS NumberOfWrites,
    CAST(vfs.num_of_bytes_read / 1024.0 / 1024.0 AS DECIMAL(18, 2)) AS TotalBytesReadMB,
    CAST(vfs.num_of_bytes_written / 1024.0 / 1024.0 AS DECIMAL(18, 2)) AS TotalBytesWrittenMB,
    CASE WHEN vfs.num_of_reads = 0 THEN 0 ELSE
        CAST(vfs.io_stall_read_ms / vfs.num_of_reads AS DECIMAL(18, 2))
    END AS AvgReadStallMS,
    CASE WHEN vfs.num_of_writes = 0 THEN 0 ELSE
        CAST(vfs.io_stall_write_ms / vfs.num_of_writes AS DECIMAL(18, 2))
    END AS AvgWriteStallMS
FROM
    sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
JOIN
    sys.master_files AS mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
ORDER BY
    (vfs.io_stall_read_ms + vfs.io_stall_write_ms) DESC;
