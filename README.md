# SQL Server DBA Scripts

A curated set of T-SQL (and a small Python helper) utilities for SQL Server DBAs to audit, monitor, and maintain SQL Server instances and databases. These scripts are designed to be run in SSMS or via sqlcmd — always review and test in non-production environments first.

## Categories & Scripts

### Auditing / Object Changes
- Audit_DDL_Changes.sql
  - Purpose: Finds CREATE and MODIFY timestamps from sys.objects and DROP events from the SQL Server Default Trace.
  - Example:
    ```sql
    -- Edit the hours window near the top of the file:
    DECLARE @HoursToGoBack INT = 168; -- last 7 days
    -- Run the script in the database you want to audit
    ```
  - Output: EventTime, EventType (CREATE/MODIFY/DROP), ObjectType, SchemaName, ObjectName, LoginName

- DBA_RecentObjectChanges.sql
  - Purpose: Alternate report for recent object changes; inspect for differences in logic before use.

### Monitoring / Current Activity
- DBA_04_BlockingAndLongQueries.sql
  - Purpose: Shows active sessions, blocking IDs, waits, duration, current statement and plan.
  - Example (sqlcmd):
    ```bash
    sqlcmd -S myserver -d master -E -i "DBA_04_BlockingAndLongQueries.sql"
    ```

- DBA_06_AgentJobStatus.sql
  - Purpose: Lists SQL Agent jobs, last outcome and scheduled times.
  - Note: Queries `msdb` — run where msdb is accessible.

### Performance / Indexing / Query Tuning
- Get_Missing_Index_Recommendations.sql
  - Purpose: Missing index DMVs to identify index opportunities. Review suggestions and test.
- DBA_08_UnusedIndexes.sql
  - Purpose: Finds nonclustered indexes with write activity but zero reads.
  - Output: Includes a `DROP INDEX [...]` suggestion — DO NOT run without review.

- DBA_15_MostExpensiveQueries.sql
  - Purpose: Rank queries by cost (elapsed time / CPU / reads). Use to target tuning.

- SqlSrv_DBA_IndexFragmentation.sql
  - Purpose: Show fragmentation levels and suggested rebuild/reorganize actions.

### Storage / I/O / Disk
- DBA_07_FileIOStats.sql
  - Purpose: Per-file I/O stats via sys.dm_io_virtual_file_stats; shows ave read/write stall times.
- DBA_11_HighVLFCount.sql
  - Purpose: Detect databases with large numbers of VLFs (log fragmentation).
- DBA_14_ServerDiskSpace.sql
  - Purpose: Checks server volume/disk free space.

### Waits / Resource Analysis
- DBA_12_WaitStatsAnalysis.sql
  - Purpose: Summarizes waits (sys.dm_os_wait_stats) to highlight resource bottlenecks.

### Security / Permissions / Server Health
- DBA_09_ServerSecurityAudit.sql
  - Purpose: Lists server principals (logins) and their server roles.
- DBA_13_UserPermissionsAudit.sql
  - Purpose: Audits database-level permissions and user mappings.

### Maintenance / Utilities
- DBA_10_DropAllObjects.sql and SqlSrv_Drop_AllDb_Objs.sql
  - Purpose: Generate DROP statements for user objects (foreign keys, views, procs, functions, tables, types).
  - WARNING: These scripts print DROP statements; they do NOT execute them automatically. Copy the printed statements to a new window, review, then execute only when safe.

- DBA_16_DatabaseConfigCheck.sql
  - Purpose: Check key DB configuration settings (recovery model, auto-shrink, compatibility level, etc.)

- DBA_17_LargestTables.sql
  - Purpose: List tables ordered by space used (useful for cleanup / archiving decisions).

- DBA_19_BackupHistory.sql
  - Purpose: Query msdb backup history to verify last backups per database.

- DBA_20_GenerateSpHelp.sql
  - Purpose: Generate documentation/help for stored procedures (inspect the file for exact behavior).

- DBErrorLogging.sql
  - Purpose: Logging infrastructure for DB error capture — large script; inspect before deploying.

- Exp_DBUsersFor_Refresh.py
  - Purpose: Python helper to export DB user creation statements for refresh/migration workflows.
  - Example:
    ```bash
    python3 Exp_DBUsersFor_Refresh.py --help
    ```
    (Inspect header/comments for exact CLI arguments.)

## How to run (quick)
- Using SSMS:
  1. Open the .sql file in SSMS.
  2. Set the correct database in the context selector.
  3. Edit any variables near the top of the file (where present).
  4. Execute.

- Using sqlcmd (Windows auth example):
  ```bash
  sqlcmd -S myserver\instance -d MyDatabase -E -i "Get_Missing_Index_Recommendations.sql"
  ```

- Capture output to file:
  ```bash
  sqlcmd -S myserver -d MyDatabase -E -i "DBA_10_DropAllObjects.sql" -o "drop_statements.txt"
  ```

## Permissions & Requirements
- Many scripts require VIEW SERVER STATE and/or access to msdb. Some require sysadmin.
- Default Trace must be enabled for DROP event auditing (Audit_DDL_Changes.sql).
- Always test in non-production and back up before performing structural changes.

## Safety & Best Practices
- Scripts that produce DROP statements should be treated as generators — do not execute automatically.
- Review queries that reference instance-level DMVs before running in multi-tenant / restricted environments.
- Use a dedicated read-only account where appropriate or run interactively in SSMS so you can inspect results before acting.

## Suggested next steps (if you want me to apply changes)
- I can create a README commit with this content and a commit message like:
  `docs: expand README with script categories, descriptions and run examples`
- Or I can open a PR with the README update so you can review before merging.

## Author / Contact
- Author: @ArvindToorpu (repository owner: @Arvind543)
- Disclaimer: Use at your own risk — test in dev/staging first.
