# SQL Server DBA Scripts

A curated set of T-SQL (and a small Python helper) utilities for SQL Server DBAs to audit, monitor, and maintain SQL Server instances and databases. These scripts are designed to be run in SSMS or via sqlcmd — always review and test in non-production environments first.

## Repository layout

The scripts are organized by purpose to make them easier to find and run:

- [auditing/](auditing)
- [monitoring/](monitoring)
  - [monitoring/Kill_Idle_Sessions_Proc/](monitoring/Kill_Idle_Sessions_Proc)
- [performance/](performance)
- [storage/](storage)
- [security/](security)
- [maintenance/](maintenance)
  - [maintenance/AutoTablePartitioning/](maintenance/AutoTablePartitioning)
    - [maintenance/LinkedServerRecovery/](maintenance/LinkedServerRecovery)
- [utilities/](utilities)

## Categories & Scripts

### Auditing / Object Changes
- [auditing/Audit_DDL_Changes.sql](auditing/Audit_DDL_Changes.sql)
  - Purpose: Finds CREATE and MODIFY timestamps from sys.objects and DROP events from the SQL Server Default Trace.
  - Output: EventTime, EventType (CREATE/MODIFY/DROP), ObjectType, SchemaName, ObjectName, LoginName.

- [auditing/DBA_RecentObjectChanges.sql](auditing/DBA_RecentObjectChanges.sql)
  - Purpose: Alternate report for recent object changes; inspect before using in production.

### Monitoring / Current Activity
- [monitoring/DBA_04_BlockingAndLongQueries.sql](monitoring/DBA_04_BlockingAndLongQueries.sql)
  - Purpose: Shows active sessions, blocking IDs, wait types, duration, current statement, and execution plan context.

- [monitoring/DBA_06_AgentJobStatus.sql](monitoring/DBA_06_AgentJobStatus.sql)
  - Purpose: Lists SQL Agent jobs, last outcome, and scheduled times.

- [monitoring/Kill_Idle_Sessions_Proc/Proc_Kill_Idle_Sessions.sql](monitoring/Kill_Idle_Sessions_Proc/Proc_Kill_Idle_Sessions.sql)
  - Purpose: Stored procedure to identify and terminate idle sessions that have been inactive too long.

### Performance / Indexing / Query Tuning
- [performance/Get_Missing_Index_Recommendations.sql](performance/Get_Missing_Index_Recommendations.sql)
  - Purpose: Uses missing index DMVs to highlight index opportunities.

- [performance/DBA_08_UnusedIndexes.sql](performance/DBA_08_UnusedIndexes.sql)
  - Purpose: Finds nonclustered indexes with write activity but no reads.

- [performance/DBA_12_WaitStatsAnalysis.sql](performance/DBA_12_WaitStatsAnalysis.sql)
  - Purpose: Summarizes waits from sys.dm_os_wait_stats to highlight bottlenecks.

- [performance/DBA_15_MostExpensiveQueries.sql](performance/DBA_15_MostExpensiveQueries.sql)
  - Purpose: Ranks queries by cost (elapsed time, CPU, reads).

- [performance/SqlSrv_DBA_DatabaseOverview.sql](performance/SqlSrv_DBA_DatabaseOverview.sql)
  - Purpose: Provides a quick database health and sizing overview.

- [performance/SqlSrv_DBA_IndexFragmentation.sql](performance/SqlSrv_DBA_IndexFragmentation.sql)
  - Purpose: Shows fragmentation levels and suggested rebuild/reorganize actions.

- [performance/List_Frag_Idx.sql](performance/List_Frag_Idx.sql)
  - Purpose: Lists fragmented indexes and their estimated maintenance impact.

### Storage / I/O / Disk
- [storage/DBA_07_FileIOStats.sql](storage/DBA_07_FileIOStats.sql)
  - Purpose: Captures per-file I/O stats and average read/write stall times.

- [storage/DBA_11_HighVLFCount.sql](storage/DBA_11_HighVLFCount.sql)
  - Purpose: Detects databases with unusually high VLF counts.

- [storage/DBA_14_ServerDiskSpace.sql](storage/DBA_14_ServerDiskSpace.sql)
  - Purpose: Checks free space across SQL Server volumes.

### Security / Permissions / Server Health
- [security/DBA_09_ServerSecurityAudit.sql](security/DBA_09_ServerSecurityAudit.sql)
  - Purpose: Lists server principals and server roles.

- [security/DBA_13_UserPermissionsAudit.sql](security/DBA_13_UserPermissionsAudit.sql)
  - Purpose: Audits database-level permissions and user mappings.

### Maintenance / Utilities
- [maintenance/DBA_10_DropAllObjects.sql](maintenance/DBA_10_DropAllObjects.sql)
  - Purpose: Generates DROP statements for user objects.

- [maintenance/SqlSrv_Drop_AllDb_Objs.sql](maintenance/SqlSrv_Drop_AllDb_Objs.sql)
  - Purpose: Alternate object-drop generator focused on full database cleanup.

- [maintenance/DBA_16_DatabaseConfigCheck.sql](maintenance/DBA_16_DatabaseConfigCheck.sql)
  - Purpose: Checks recovery model, auto-shrink, compatibility level, and other key settings.

- [maintenance/DBA_17_LargestTables.sql](maintenance/DBA_17_LargestTables.sql)
  - Purpose: Lists largest tables by space used.

- [maintenance/DBA_19_BackupHistory.sql](maintenance/DBA_19_BackupHistory.sql)
  - Purpose: Queries msdb backup history to verify the last successful backups.

- [maintenance/DBA_20_GenerateSpHelp.sql](maintenance/DBA_20_GenerateSpHelp.sql)
  - Purpose: Generates documentation for stored procedures.

- [maintenance/DBErrorLogging.sql](maintenance/DBErrorLogging.sql)
  - Purpose: Logging infrastructure for DB error capture; inspect carefully before deployment.
- [maintenance/AutoTablePartitioning/DBA_AutoTablePartitioning.sql](maintenance/AutoTablePartitioning/DBA_AutoTablePartitioning.sql)
  - Purpose: Registers existing partitioned tables and automatically adds future boundaries, removes old partitions, maintains indexes, and records history.
- [maintenance/AutoTablePartitioning/DBA_AutoTablePartitioning_Grants.sql](maintenance/AutoTablePartitioning/DBA_AutoTablePartitioning_Grants.sql)
  - Purpose: Creates the operator role and documents the object permissions required by the partition maintenance procedures.
- [maintenance/LinkedServerRecovery/DBA_LinkedServerRecovery.sql](maintenance/LinkedServerRecovery/DBA_LinkedServerRecovery.sql)
  - Purpose: Captures linked-server definitions, security mappings, and mapped-login database permissions, then generates reviewable recovery statements.

### Utilities / Helpers
- [utilities/Exp_DBUsersFor_Refresh.py](utilities/Exp_DBUsersFor_Refresh.py)
  - Purpose: Exports database user creation statements for refresh or migration workflows.

## How to run (quick)

- Using SSMS:
  1. Open the .sql file in SSMS.
  2. Set the correct database in the context selector.
  3. Edit any variables near the top of the file, if present.
  4. Execute.

- Using sqlcmd:
  ```bash
  sqlcmd -S myserver\instance -d MyDatabase -E -i "performance/Get_Missing_Index_Recommendations.sql"
  ```

- Capture output to file:
  ```bash
  sqlcmd -S myserver -d MyDatabase -E -i "maintenance/DBA_10_DropAllObjects.sql" -o "drop_statements.txt"
  ```

- Python helper:
  ```bash
  python3 utilities/Exp_DBUsersFor_Refresh.py --help
  ```

### Automated Table Partitioning
1. Deploy [maintenance/AutoTablePartitioning/DBA_AutoTablePartitioning.sql](maintenance/AutoTablePartitioning/DBA_AutoTablePartitioning.sql) in the application database.
2. Deploy [maintenance/AutoTablePartitioning/DBA_AutoTablePartitioning_Grants.sql](maintenance/AutoTablePartitioning/DBA_AutoTablePartitioning_Grants.sql), then grant `ALTER` on each managed table and its empty switch target to `PartitionMaintenanceOperator`.
3. Register each already-partitioned table. `RANGE RIGHT` partition functions must have at least one seeded boundary:
   ```sql
   EXEC dbo.usp_DBA_RegisterPartitionedTable
       @SchemaName = 'dbo', @TableName = 'SalesHistory', @PartitionColumn = 'SaleDate',
       @TargetTableName = 'SalesHistory_Archive', @RangeUnit = 'MONTH',
       @FuturePartitions = 6, @RetentionPartitions = 24,
       @AutoDeleteOldPartitions = 1, @IndexAction = 'AUTO';
   ```
4. Create a weekly SQL Agent T-SQL step: `EXEC dbo.usp_DBA_MaintainTablePartitions;`.

The utility adds future boundaries, switches or truncates old partition 1 before merging its boundary, rebuilds/reorganizes indexes according to configured thresholds, and records successful and failed actions in `dbo.DBA_PartitionMaintenanceHistory`. `TargetTableName` must be empty and schema/index aligned; use no target when permanent deletion is intended.

## Permissions & Requirements
- Many scripts require VIEW SERVER STATE and/or access to msdb; some require sysadmin rights.
- Default Trace must be enabled for drop-event auditing in [auditing/Audit_DDL_Changes.sql](auditing/Audit_DDL_Changes.sql).
- Always test in non-production and back up before performing structural changes.

## Safety & Best Practices
- Treat scripts that generate DROP statements as generators, not as auto-executing cleanup commands.
- Review instance-level DMV queries before running in multi-tenant or tightly restricted environments.
- Use a dedicated read-only account when possible and inspect results before acting.

## Author / Contact
- Author: @ArvindToorpu (repository owner: @Arvind543)
- Disclaimer: Use at your own risk; test in dev/staging first.
