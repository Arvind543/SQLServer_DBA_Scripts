# SQL Server Automatic Table Partitioning

This package converts eligible existing tables to partitioned tables and maintains them over time. It can run the complete workflow or only one task, such as index maintenance or statistics updates.

## What It Does

- Creates a `RANGE RIGHT` partition function and partition scheme during conversion.
- Supports `DAY`, `WEEK`, `MONTH`, `QUARTER`, `YEAR`, and `INTEGER` ranges.
- Creates future boundaries and removes old partitions according to configuration.
- Optionally switches old data to an empty archive table before removing the partition.
- Rebuilds or reorganizes indexes based on fragmentation thresholds.
- Updates statistics using automatic, sampled, or full-scan options.
- Logs commands, outcomes, row counts, and errors in `dbo.DBA_PartitionMaintenanceHistory`.
- Supports on-premises SQL Server, AWS RDS for SQL Server, Azure SQL Database, and Azure SQL Managed Instance.

The utility manages logical SQL Server partitions. It does not create, resize, or repartition physical disks.

## Consolidated Parameter Quick Reference

Use this table as the first lookup when configuring the procedures. Detailed procedure-specific tables and examples follow later in this guide.

| Parameter | Default | Expected value | Example | Used by |
|---|---|---|---|---|
| `@SchemaName` | Required | Existing schema name | `'dbo'` | Convert, Register |
| `@TableName` | Required | Existing table name | `'SalesHistory'` | Convert, Register |
| `@PartitionColumn` | Required | Date/time or integer column | `'SaleDate'` | Convert, Register |
| `@BatchColumn` | Required for initial load | Monotonic/ordered ID or date column present in source and target | `'SaleDate'` or `'OrderId'` | Initial load |
| `@RangeUnit` | Required / `DAY` for Register | `DAY`, `WEEK`, `MONTH`, `QUARTER`, `YEAR`, `INTEGER` | `'MONTH'` | Convert, Register |
| `@StartValue` | Required | First date/time or integer boundary | `'2024-01-01'` | Convert |
| `@EndValue` | Required | Last date/time or integer boundary | `'2027-12-01'` | Convert |
| `@PartitionInterval` | `1` | Positive interval between boundaries | `1` | Convert, Register |
| `@PartitionFunctionName` | Generated / `NULL` for Register | Unique or existing function name | `'PF_SalesHistory_SaleDate'` | Convert, Register |
| `@PartitionSchemeName` | Generated / `NULL` for Register | Unique or existing scheme name | `'PS_SalesHistory_SaleDate'` | Convert, Register |
| `@FilegroupName` | `PRIMARY` | Existing on-premises filegroup; cloud uses `PRIMARY` | `'PRIMARY'` | Convert, Register |
| `@DeploymentPlatform` | `AUTO` | `AUTO`, `ONPREM`, `AWS_RDS`, `AZURE_SQLDB`, `AZURE_MI` | `'AZURE_SQLDB'` | Convert, Register |
| `@IndexAlignment` | `ALIGNED` | `ALIGNED` or `NONALIGNED` | `'ALIGNED'` | Convert, Register |
| `@TargetTableName` | `NULL` | Empty aligned switch target or `NULL` to delete | `'SalesHistory_Archive'` | Convert, Register |
| `@FuturePartitions` | `4` | At least `1` future boundary | `6` | Convert, Register |
| `@RetentionPartitions` | `52` | Zero or greater partitions to retain | `24` | Convert, Register |
| `@AutoDeleteOldPartitions` | `0` | `0` or `1` | `1` | Convert, Register |
| `@IndexAction` | `AUTO` | `AUTO`, `REBUILD`, `REORGANIZE`, `NONE` | `'AUTO'` | Convert, Register, Index maintenance |
| `@ReorganizeAtPercent` | `10` | Non-negative fragmentation percentage | `10` | Register, Index maintenance |
| `@RebuildAtPercent` | `30` | Greater than reorganize threshold | `30` | Register, Index maintenance |
| `@MinimumPageCount` | `1000` | Minimum index page count | `1000` | Register, Index maintenance |
| `@StatsAction` | `AUTO` | `AUTO`, `FULLSCAN`, `SAMPLE`, `NONE` | `'FULLSCAN'` | Convert, Register, Statistics |
| `@StatsSamplePercent` | `NULL` | `1` to `100` when using `SAMPLE` | `25` | Convert, Register, Statistics |
| `@ConfigId` | `NULL` | `NULL` for all enabled rows or an existing ID | `1` | Maintenance procedures |
| `@FuturePartitionsOverride` | `NULL` | Positive temporary override | `12` | Add boundaries |
| `@BatchSize` | `100000` | Positive number of source rows requested per batch | `50000` | Initial load |
| `@StartValue` | `NULL` | Optional inclusive ID/date lower bound; exclusive when resuming | `'2024-01-01'` | Initial load |
| `@EndValue` | `NULL` | Optional inclusive ID/date upper bound | `'2024-12-31'` | Initial load |
| `@ResumeFromValue` | `0` | `0` for empty target; `1` for exclusive resume | `1` | Initial load |
| `@KeepIdentity` | `1` | `0` or `1` | `1` | Initial load |
| `@MaxBatches` | `0` | `0` for all remaining rows, or a positive limit | `10` | Initial load |
| `@Enabled` | `1` | `0` or `1` | `1` | Register |

## Files and Procedures

| File | Purpose |
|---|---|
| [DBA_AutoTablePartitioning.sql](DBA_AutoTablePartitioning.sql) | Creates the configuration/history tables and stored procedures |
| [DBA_AutoTablePartitioning_Grants.sql](DBA_AutoTablePartitioning_Grants.sql) | Creates the operator role and shared permissions |

| Procedure | Use it for |
|---|---|
| `dbo.usp_DBA_ConvertTableToPartitioned` | One-time conversion of an existing eligible table |
| `dbo.usp_DBA_BatchLoadPartitionedTable` | Batch-loading an existing non-partitioned table into an empty partitioned target |
| `dbo.usp_DBA_CreateAndLoadPartitionedTable` | Creating a target from source metadata, partitioning it, copying keys/indexes, and batch-loading data |
| `dbo.usp_DBA_RegisterPartitionedTable` | Configuring a table that is already partitioned |
| `dbo.usp_DBA_AddPartitionBoundaries` | Adding future partitions only |
| `dbo.usp_DBA_RemoveOldPartitions` | Removing old partitions only |
| `dbo.usp_DBA_MaintainTableIndexes` | Index rebuild/reorganize only |
| `dbo.usp_DBA_UpdateTableStatistics` | Statistics updates only |
| `dbo.usp_DBA_MaintainTablePartitions` | Full weekly workflow |

## Before You Start

1. Test the conversion and maintenance process in a non-production database.
2. Take a backup and confirm enough storage and transaction-log capacity for the clustered-index rebuild.
3. Confirm the table has a clustered index. The conversion procedure intentionally does not guess a clustered key for a heap.
4. Confirm the partition column is a supported `date`, `datetime`, `datetime2`, `smalldatetime`, `tinyint`, `smallint`, `int`, or `bigint` column.
5. If using `SWITCH`, create an empty target table with matching columns, indexes, constraints, compression, and partitioning requirements.
6. Make sure the partition column is in every unique index key that must become aligned.

For an initial load, use `dbo.usp_DBA_CreateAndLoadPartitionedTable` when you want the package to create the target automatically. It derives partition function and scheme names from the target table and partition column when names are not supplied. The source table remains unchanged, so the final cutover can be performed during a planned maintenance window.

## 1. Install the Package

Run both scripts in the database that owns the application table:

```sql
-- Run first.
-- DBA_AutoTablePartitioning.sql

-- Run second.
-- DBA_AutoTablePartitioning_Grants.sql
```

Grant `ALTER` on each managed table and empty switch target to `PartitionMaintenanceOperator`. Review the grants script before applying it in a restricted environment.

## 2. Select the Deployment Platform

Pass `@DeploymentPlatform` to the conversion or registration procedure:

| Value | Use it for | Filegroup behavior |
|---|---|---|
| `AUTO` | Default choice when Azure detection is sufficient | Detects Azure SQL Database/Managed Instance; otherwise uses on-premises behavior |
| `ONPREM` | On-premises SQL Server | Uses the existing `@FilegroupName` |
| `AWS_RDS` | Amazon RDS for SQL Server | Uses logical `PRIMARY`; no physical disk/filegroup work |
| `AZURE_SQLDB` | Azure SQL Database | Uses logical `PRIMARY`; no physical disk/filegroup work |
| `AZURE_MI` | Azure SQL Managed Instance | Uses logical `PRIMARY`; no physical disk/filegroup work |

`AUTO` cannot reliably distinguish AWS RDS from on-premises SQL Server, so select `AWS_RDS` explicitly on RDS.

## 3. Convert an Existing Table

The conversion creates the partition function and scheme, rebuilds the clustered index on the scheme, and optionally rebuilds rowstore nonclustered indexes as aligned indexes.

### Monthly Azure Example

This creates monthly boundaries from January 2024 through December 2027:

```sql
EXEC dbo.usp_DBA_ConvertTableToPartitioned
    @SchemaName = 'dbo',
    @TableName = 'SalesHistory',
    @PartitionColumn = 'SaleDate',
    @RangeUnit = 'MONTH',
    @StartValue = '2024-01-01',
    @EndValue = '2027-12-01',
    @PartitionInterval = 1,
    @PartitionFunctionName = 'PF_SalesHistory_SaleDate',
    @PartitionSchemeName = 'PS_SalesHistory_SaleDate',
    @DeploymentPlatform = 'AZURE_SQLDB',
    @IndexAlignment = 'ALIGNED',
    @StatsAction = 'FULLSCAN';
```

### Other Temporal Ranges

Use the same procedure with these values:

| Range | `@StartValue` example | `@EndValue` example | `@PartitionInterval` |
|---|---|---|---:|
| Daily | `'2026-01-01'` | `'2026-12-31'` | `1` |
| Weekly | `'2026-01-05'` | `'2027-01-04'` | `1` |
| Monthly | `'2024-01-01'` | `'2027-12-01'` | `1` |
| Quarterly | `'2024-01-01'` | `'2028-01-01'` | `1` |
| Yearly | `'2020-01-01'` | `'2030-01-01'` | `1` |
| Every 3 months | `'2024-01-01'` | `'2030-01-01'` | `3` |

### Integer Range Example

```sql
EXEC dbo.usp_DBA_ConvertTableToPartitioned
    @SchemaName = 'dbo',
    @TableName = 'OrderEvents',
    @PartitionColumn = 'EventId',
    @RangeUnit = 'INTEGER',
    @StartValue = '0',
    @EndValue = '10000000',
    @PartitionInterval = 100000,
    @DeploymentPlatform = 'AWS_RDS',
    @IndexAlignment = 'NONALIGNED',
    @StatsAction = 'SAMPLE',
    @StatsSamplePercent = 25;
```

### Conversion Parameters

| Parameter | Default | Expected values | Example |
|---|---|---|---|
| `@SchemaName`, `@TableName` | Required | Existing table | `'dbo'`, `'SalesHistory'` |
| `@PartitionColumn` | Required | Supported date/time or integer column | `'SaleDate'` |
| `@RangeUnit` | Required | `DAY`, `WEEK`, `MONTH`, `QUARTER`, `YEAR`, `INTEGER` | `'MONTH'` |
| `@StartValue`, `@EndValue` | Required | Boundary values matching the column type | `'2024-01-01'`, `'2027-12-01'` |
| `@PartitionInterval` | `1` | Positive unit count | `1` |
| `@PartitionFunctionName` | Generated | New unique name | `'PF_SalesHistory_SaleDate'` |
| `@PartitionSchemeName` | Generated | New unique name | `'PS_SalesHistory_SaleDate'` |
| `@FilegroupName` | `PRIMARY` | Existing filegroup; used on-premises | `'PRIMARY'` |
| `@DeploymentPlatform` | `AUTO` | `AUTO`, `ONPREM`, `AWS_RDS`, `AZURE_SQLDB`, `AZURE_MI` | `'ONPREM'` |
| `@IndexAlignment` | `ALIGNED` | `ALIGNED` or `NONALIGNED` | `'NONALIGNED'` |
| `@StatsAction` | `AUTO` | `AUTO`, `FULLSCAN`, `SAMPLE`, `NONE` | `'FULLSCAN'` |
| `@StatsSamplePercent` | `NULL` | `1` to `100` when using `SAMPLE` | `25` |

`ALIGNED` rebuilds eligible rowstore nonclustered indexes onto the partition scheme. `NONALIGNED` leaves nonclustered indexes in their current data space. Unique indexes must contain the partition column to be aligned.

## 4. Initial Load in Batches

Use `dbo.usp_DBA_BatchLoadPartitionedTable` after the target table has been created and partitioned. The procedure copies rows in ordered batches based on an ID or date column. Each batch is committed and logged separately, so a failed run can be resumed by calling it again with the last completed boundary supplied as `@StartValue`.

### Initial-load sequence

1. Keep the original non-partitioned table unchanged.
2. Create an empty target table with the same columns, data types, identity properties, constraints, and indexes.
3. Give the empty target a clustered index. It may initially be on `PRIMARY`.
4. Convert the empty target with `usp_DBA_ConvertTableToPartitioned`; this creates its partition function and scheme.
5. Run the batch loader with an ID or date `@BatchColumn`.
6. Review `INITIAL_LOAD_BATCH`, `INITIAL_LOAD_COMPLETE`, and `INITIAL_LOAD_ERROR` history rows.
7. Stop writes or use a CDC/change-tracking catch-up process, validate row counts, then perform the final rename/synonym/application cutover separately.

The target must be empty for a new load and must already have a clustered index on a partition scheme. Set `@ResumeFromValue = 1` only when continuing a partially loaded target. In resume mode, `@StartValue` is exclusive, so rows at the last successful boundary are not copied twice. `@BatchColumn` must be present with a compatible type in both tables. Duplicate date values are supported: a batch may contain more than `@BatchSize` rows so all rows sharing the boundary value are copied together. For best restart behavior, use a non-null, increasing ID when one is available.

### Automatic create, metadata copy, and load

This procedure creates the target from source column metadata, creates partition objects using the target table name, recreates primary keys, unique constraints, defaults, checks, and rowstore indexes, then loads the data in batches:

```sql
EXEC dbo.usp_DBA_CreateAndLoadPartitionedTable
    @SourceSchemaName = 'dbo',
    @SourceTableName = 'SalesHistory',
    @TargetSchemaName = 'dbo',
    @TargetTableName = 'SalesHistory_Partitioned',
    @PartitionColumn = 'SaleDate',
    @RangeUnit = 'MONTH',
    @StartValue = '2024-01-01',
    @EndValue = '2027-12-01',
    @PartitionInterval = 1,
    @DeploymentPlatform = 'AZURE_SQLDB',
    @IndexAlignment = 'ALIGNED',
    @BatchColumn = 'SaleDate',
    @BatchSize = 50000,
    @LoadStartValue = '2024-01-01',
    @LoadEndValue = '2027-12-01',
    @KeepIdentity = 1,
    @StatsAction = 'FULLSCAN';
```

If partition object names are omitted, the procedure generates `PF_DBA_<TargetTable>_<PartitionColumn>` and `PS_DBA_<TargetTable>_<PartitionColumn>`. The target must not already exist.

The automatic copy supports ordinary rowstore indexes, primary keys, unique constraints, default constraints, check constraints, identity columns, included columns, and filtered indexes. Foreign keys, computed columns, XML/spatial/columnstore/hash indexes, triggers, permissions, and extended properties require explicit deployment review and are not silently copied.

| Parameter | Default | Expected value | Example |
|---|---|---|---|
| `@SourceSchemaName`, `@SourceTableName` | Required | Existing source table | `'dbo'`, `'SalesHistory'` |
| `@TargetSchemaName`, `@TargetTableName` | Required | New target table name; target must not exist | `'dbo'`, `'SalesHistory_Partitioned'` |
| `@PartitionColumn` | Required | Source date/time or integer column | `'SaleDate'` |
| `@RangeUnit` | Required | `DAY`, `WEEK`, `MONTH`, `QUARTER`, `YEAR`, `INTEGER` | `'MONTH'` |
| `@StartValue`, `@EndValue` | Required | Partition boundary values | `'2024-01-01'`, `'2027-12-01'` |
| `@PartitionFunctionName`, `@PartitionSchemeName` | Generated | Optional unique object names | `'PF_SalesHistory_Partitioned'` |
| `@DeploymentPlatform` | `AUTO` | `AUTO`, `ONPREM`, `AWS_RDS`, `AZURE_SQLDB`, `AZURE_MI` | `'AZURE_SQLDB'` |
| `@IndexAlignment` | `ALIGNED` | `ALIGNED` or `NONALIGNED` | `'ALIGNED'` |
| `@BatchColumn` | `@PartitionColumn` | Ordered ID/date column in source and target | `'SaleDate'` |
| `@BatchSize` | `100000` | Positive row target per batch | `50000` |
| `@LoadStartValue`, `@LoadEndValue` | `NULL` | Optional inclusive load bounds | `'2024-01-01'`, `'2027-12-01'` |
| `@KeepIdentity` | `1` | `0` or `1` | `1` |
| `@MaxBatches` | `0` | `0` for all rows or positive test limit | `5` |

### Prepare the empty target

Create the target using your normal schema deployment process so identity properties, defaults, constraints, compression, and indexes are preserved. The following is a minimal shape example; replace the columns and clustered key with the real source-table definition:

```sql
CREATE TABLE dbo.SalesHistory_Partitioned
(
    SalesHistoryId bigint NOT NULL,
    SaleDate date NOT NULL,
    CustomerId int NOT NULL,
    Amount decimal(19,4) NOT NULL
);

CREATE UNIQUE CLUSTERED INDEX CX_SalesHistory_Partitioned
    ON dbo.SalesHistory_Partitioned (SalesHistoryId, SaleDate);

-- Partition the empty target before loading it.
EXEC dbo.usp_DBA_ConvertTableToPartitioned
    @SchemaName = 'dbo',
    @TableName = 'SalesHistory_Partitioned',
    @PartitionColumn = 'SaleDate',
    @RangeUnit = 'MONTH',
    @StartValue = '2024-01-01',
    @EndValue = '2027-12-01',
    @PartitionFunctionName = 'PF_SalesHistory_Load',
    @PartitionSchemeName = 'PS_SalesHistory_Load',
    @IndexAlignment = 'ALIGNED';
```

The target conversion must complete successfully before `usp_DBA_BatchLoadPartitionedTable` is called. The source and target need not have the same table name, but their insertable column names and data types must match.

### Date-based batch load

```sql
EXEC dbo.usp_DBA_BatchLoadPartitionedTable
    @SourceSchemaName = 'dbo',
    @SourceTableName = 'SalesHistory',
    @TargetSchemaName = 'dbo',
    @TargetTableName = 'SalesHistory_Partitioned',
    @BatchColumn = 'SaleDate',
    @BatchSize = 50000,
    @StartValue = '2024-01-01',
    @EndValue = '2027-12-01',
    @KeepIdentity = 1;
```

### ID-based batch load

```sql
EXEC dbo.usp_DBA_BatchLoadPartitionedTable
    @SourceSchemaName = 'dbo',
    @SourceTableName = 'OrderEvents',
    @TargetSchemaName = 'dbo',
    @TargetTableName = 'OrderEvents_Partitioned',
    @BatchColumn = 'OrderId',
    @BatchSize = 100000,
    @StartValue = '1',
    @EndValue = '10000000',
    @KeepIdentity = 1;
```

### Controlled test and resume

Run only five batches first, inspect the target, then continue from the last logged boundary:

```sql
-- Test only five batches.
EXEC dbo.usp_DBA_BatchLoadPartitionedTable
    @SourceSchemaName = 'dbo', @SourceTableName = 'SalesHistory',
    @TargetSchemaName = 'dbo', @TargetTableName = 'SalesHistory_Partitioned',
    @BatchColumn = 'SaleDate', @BatchSize = 50000,
    @StartValue = '2024-01-01', @EndValue = '2027-12-01',
    @MaxBatches = 5;

-- Resume after checking the last successful boundary.
SELECT TOP (1) BoundaryValue
FROM dbo.DBA_PartitionMaintenanceHistory
WHERE Action = 'INITIAL_LOAD_BATCH'
  AND TableName = 'SalesHistory_Partitioned'
  AND Succeeded = 1
ORDER BY EventTime DESC;

-- Pass the returned boundary as an exclusive resume value.
EXEC dbo.usp_DBA_BatchLoadPartitionedTable
    @SourceSchemaName = 'dbo', @SourceTableName = 'SalesHistory',
    @TargetSchemaName = 'dbo', @TargetTableName = 'SalesHistory_Partitioned',
    @BatchColumn = 'SaleDate', @BatchSize = 50000,
    @StartValue = '2025-06-01', @EndValue = '2027-12-01',
    @ResumeFromValue = 1;
```

| Parameter | Default | Expected value | Example |
|---|---|---|---|
| `@SourceSchemaName`, `@SourceTableName` | Required | Existing non-partitioned source table | `'dbo'`, `'SalesHistory'` |
| `@TargetSchemaName`, `@TargetTableName` | Required | Empty partitioned target table | `'dbo'`, `'SalesHistory_Partitioned'` |
| `@BatchColumn` | Required | Non-null ordered ID/date column in both tables | `'OrderId'` or `'SaleDate'` |
| `@BatchSize` | `100000` | Positive batch row target | `50000` |
| `@StartValue` | `NULL` | Inclusive lower ID/date bound | `'2024-01-01'` |
| `@EndValue` | `NULL` | Inclusive upper ID/date bound | `'2027-12-01'` |
| `@ResumeFromValue` | `0` | `0` for empty target; `1` for exclusive resume | `1` |
| `@KeepIdentity` | `1` | `0` or `1` | `1` |
| `@MaxBatches` | `0` | `0` for all rows, or positive test limit | `5` |

## 5. Register an Already Partitioned Table

Use registration when the table already has a partition function, partition scheme, and aligned clustered index:

```sql
EXEC dbo.usp_DBA_RegisterPartitionedTable
    @SchemaName = 'dbo',
    @TableName = 'SalesHistory',
    @PartitionColumn = 'SaleDate',
    @TargetTableName = 'SalesHistory_Archive',
    @RangeUnit = 'MONTH',
    @PartitionInterval = 1,
    @DeploymentPlatform = 'ONPREM',
    @FilegroupName = 'PRIMARY',
    @FuturePartitions = 6,
    @RetentionPartitions = 24,
    @AutoDeleteOldPartitions = 1,
    @IndexAction = 'AUTO',
    @StatsAction = 'AUTO';
```

`@TargetTableName = NULL` permanently deletes old data after truncating the old partition. A target table must be empty and schema/index aligned for `ALTER TABLE ... SWITCH` to succeed.

| Parameter | Default | Expected values | Example |
|---|---|---|---|
| `@RangeUnit` | `DAY` | `DAY`, `WEEK`, `MONTH`, `QUARTER`, `YEAR`, `INTEGER` | `'MONTH'` |
| `@PartitionInterval` | `1` | Positive interval | `1` |
| `@DeploymentPlatform` | `AUTO` | `AUTO`, `ONPREM`, `AWS_RDS`, `AZURE_SQLDB`, `AZURE_MI` | `'AZURE_SQLDB'` |
| `@FuturePartitions` | `4` | At least `1` | `6` |
| `@RetentionPartitions` | `52` | Zero or greater | `24` |
| `@AutoDeleteOldPartitions` | `0` | `0` or `1` | `1` |
| `@IndexAction` | `AUTO` | `AUTO`, `REBUILD`, `REORGANIZE`, `NONE` | `'AUTO'` |
| `@StatsAction` | `AUTO` | `AUTO`, `FULLSCAN`, `SAMPLE`, `NONE` | `'SAMPLE'` |
| `@StatsSamplePercent` | `NULL` | `1` to `100` with `SAMPLE` | `20` |
| `@Enabled` | `1` | `0` or `1` | `1` |

## 6. Run the Full Maintenance Workflow

Create a weekly job step with:

```sql
EXEC dbo.usp_DBA_MaintainTablePartitions;
```

This performs, in order:

1. Adds missing future boundaries.
2. Switches or truncates old partitions when retention is exceeded.
3. Rebuilds or reorganizes indexes according to fragmentation settings.
4. Updates statistics according to the configured statistics action.
5. Logs each operation and error.

For one table only:

```sql
EXEC dbo.usp_DBA_MaintainTablePartitions @ConfigId = 1;
```

## 7. Run Only One Maintenance Task

These procedures do not create, split, merge, switch, or delete partitions unless explicitly stated:

| Task | Command |
|---|---|
| Index maintenance only | `EXEC dbo.usp_DBA_MaintainTableIndexes;` |
| One table's indexes | `EXEC dbo.usp_DBA_MaintainTableIndexes @ConfigId = 1;` |
| Statistics only | `EXEC dbo.usp_DBA_UpdateTableStatistics;` |
| One table's statistics | `EXEC dbo.usp_DBA_UpdateTableStatistics @ConfigId = 1;` |
| Add future boundaries only | `EXEC dbo.usp_DBA_AddPartitionBoundaries;` |
| Remove old partitions only | `EXEC dbo.usp_DBA_RemoveOldPartitions;` |

### Maintenance Procedure Parameters

| Procedure | Parameter | Default | Expected value | Example |
|---|---|---|---|---|
| `usp_DBA_MaintainTablePartitions` | `@ConfigId` | `NULL` | `NULL` for all enabled configurations, or an existing `ConfigId` | `@ConfigId = 1` |
| `usp_DBA_MaintainTableIndexes` | `@ConfigId` | `NULL` | `NULL` for all enabled configurations, or an existing `ConfigId` | `@ConfigId = 1` |
| `usp_DBA_UpdateTableStatistics` | `@ConfigId` | `NULL` | `NULL` for all enabled configurations, or an existing `ConfigId` | `@ConfigId = 1` |
| `usp_DBA_AddPartitionBoundaries` | `@ConfigId` | `NULL` | `NULL` for all enabled configurations, or an existing `ConfigId` | `@ConfigId = 1` |
| `usp_DBA_AddPartitionBoundaries` | `@FuturePartitionsOverride` | `NULL` | Positive integer; temporarily overrides configured future count | `@FuturePartitionsOverride = 12` |
| `usp_DBA_RemoveOldPartitions` | `@ConfigId` | `NULL` | `NULL` for all enabled delete configurations, or an existing `ConfigId` | `@ConfigId = 1` |

### Configuration Table Reference

These values are stored in `dbo.DBA_PartitionMaintenanceConfig` and are used by the scheduled procedures:

| Column | Default | Expected value | Example |
|---|---|---|---|
| `SchemaName`, `TableName` | Required | Existing table identity | `'dbo'`, `'SalesHistory'` |
| `PartitionColumn` | Required | Date/time or integer column used by the partition function | `'SaleDate'` |
| `TargetTableName` | `NULL` | Empty aligned switch target, or `NULL` to delete data | `'SalesHistory_Archive'` |
| `RangeUnit` | `DAY` | `DAY`, `WEEK`, `MONTH`, `QUARTER`, `YEAR`, `INTEGER` | `'MONTH'` |
| `PartitionInterval` | `1` | Positive interval between boundaries | `1` |
| `PartitionFunctionName` | `NULL` | Existing partition function name | `'PF_SalesHistory_SaleDate'` |
| `PartitionSchemeName` | `NULL` | Existing partition scheme name | `'PS_SalesHistory_SaleDate'` |
| `FilegroupName` | `PRIMARY` | Existing on-premises filegroup; cloud modes use `PRIMARY` | `'PRIMARY'` |
| `DeploymentPlatform` | `AUTO` | `AUTO`, `ONPREM`, `AWS_RDS`, `AZURE_SQLDB`, `AZURE_MI` | `'AWS_RDS'` |
| `FuturePartitions` | `4` | At least `1` future boundary | `6` |
| `RetentionPartitions` | `52` | Zero or greater partitions to retain | `24` |
| `AutoDeleteOldPartitions` | `0` | `0` or `1` | `1` |
| `IndexAction` | `AUTO` | `AUTO`, `REBUILD`, `REORGANIZE`, `NONE` | `'AUTO'` |
| `IndexAlignment` | `ALIGNED` | `ALIGNED` or `NONALIGNED` | `'ALIGNED'` |
| `ReorganizeAtPercent` | `10` | Non-negative fragmentation percentage | `10` |
| `RebuildAtPercent` | `30` | Greater than `ReorganizeAtPercent` | `30` |
| `MinimumPageCount` | `1000` | Minimum index page count for maintenance | `1000` |
| `StatsAction` | `AUTO` | `AUTO`, `FULLSCAN`, `SAMPLE`, `NONE` | `'FULLSCAN'` |
| `StatsSamplePercent` | `NULL` | `1` to `100` when using `SAMPLE` | `25` |
| `Enabled` | `1` | `0` or `1` | `1` |

### Rebuild/Reorganize Example

```sql
-- Reorganize from 10% fragmentation and rebuild at 30%.
UPDATE dbo.DBA_PartitionMaintenanceConfig
SET IndexAction = 'AUTO',
    ReorganizeAtPercent = 10,
    RebuildAtPercent = 30,
    MinimumPageCount = 1000
WHERE ConfigId = 1;

EXEC dbo.usp_DBA_MaintainTableIndexes @ConfigId = 1;
```

### Statistics-Only Examples

```sql
-- Default statistics update.
UPDATE dbo.DBA_PartitionMaintenanceConfig
SET StatsAction = 'AUTO'
WHERE ConfigId = 1;
EXEC dbo.usp_DBA_UpdateTableStatistics @ConfigId = 1;

-- Full scan, without index or partition maintenance.
UPDATE dbo.DBA_PartitionMaintenanceConfig
SET StatsAction = 'FULLSCAN'
WHERE ConfigId = 1;
EXEC dbo.usp_DBA_UpdateTableStatistics @ConfigId = 1;

-- 25 percent sample.
UPDATE dbo.DBA_PartitionMaintenanceConfig
SET StatsAction = 'SAMPLE', StatsSamplePercent = 25
WHERE ConfigId = 1;
EXEC dbo.usp_DBA_UpdateTableStatistics @ConfigId = 1;
```

### Partition-Only Example

Use two separate job steps when you want partition growth and retention without index or statistics maintenance:

```sql
EXEC dbo.usp_DBA_AddPartitionBoundaries;
EXEC dbo.usp_DBA_RemoveOldPartitions;
```

## Scheduling by Platform

| Platform | Scheduling option |
|---|---|
| On-premises | SQL Server Agent |
| AWS RDS for SQL Server | Supported RDS SQL Server Agent features or an external scheduler |
| Azure SQL Database | Elastic Jobs, Azure Automation, Azure Functions, or another external scheduler |
| Azure SQL Managed Instance | SQL Server Agent where enabled, or an external scheduler |

The procedures are database-scoped. The scheduler only needs to connect to the target database and execute the selected procedure.

## Verify Configuration and History

```sql
-- Find configuration IDs and current settings.
SELECT *
FROM dbo.DBA_PartitionMaintenanceConfig
ORDER BY SchemaName, TableName;

-- Review recent successes and failures.
SELECT TOP (100)
    EventTime, Action, SchemaName, TableName, BoundaryValue,
    Succeeded, ErrorNumber, ErrorMessage, CommandText
FROM dbo.DBA_PartitionMaintenanceHistory
ORDER BY EventTime DESC;

-- Inspect partition boundaries for one table.
SELECT
    ps.name AS PartitionSchemeName,
    pf.name AS PartitionFunctionName,
    prv.boundary_id,
    CONVERT(nvarchar(128), prv.value) AS BoundaryValue
FROM sys.indexes AS i
JOIN sys.partition_schemes AS ps ON ps.data_space_id = i.data_space_id
JOIN sys.partition_functions AS pf ON pf.function_id = ps.function_id
LEFT JOIN sys.partition_range_values AS prv ON prv.function_id = pf.function_id
WHERE i.object_id = OBJECT_ID(N'dbo.SalesHistory')
  AND i.index_id = 1
ORDER BY prv.boundary_id;
```

## Common Issues

| Symptom | Action |
|---|---|
| `The source table must have a clustered index` | Create and review an appropriate clustered index before conversion. |
| Unique index cannot be aligned | Add the partition column to the unique index key, or use `NONALIGNED` where appropriate. |
| Switch operation fails | Confirm the target is empty and has matching schema, indexes, constraints, compression, and partitioning metadata. |
| Future boundaries are not added | Confirm the table is on a partition scheme, the function has at least one boundary, and the configuration is enabled. |
| Cloud filegroup error | Select `AWS_RDS`, `AZURE_SQLDB`, or `AZURE_MI`; cloud modes use `PRIMARY` and do not require custom filegroups. |
| No index action occurs | Check `IndexAction`, `MinimumPageCount`, and the configured fragmentation thresholds. |

Test structural changes, switching, retention deletion, index operations, and statistics duration in staging before production scheduling.
