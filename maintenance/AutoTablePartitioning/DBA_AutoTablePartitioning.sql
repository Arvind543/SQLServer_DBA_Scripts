/*
    DBA Auto Table Partitioning

    Run in the database that owns the managed tables.
    SQL Agent entry point: EXEC dbo.usp_DBA_MaintainTablePartitions;

    The source table must already have a RANGE RIGHT partition function and an
    aligned clustered index. TargetTableName is optional: when supplied it is
    an empty, schema-identical SWITCH destination; otherwise the oldest
    partition is truncated before MERGE RANGE.

    DeploymentPlatform values: AUTO, ONPREM, AWS_RDS, AZURE_SQLDB, AZURE_MI.
    Cloud modes use PRIMARY for logical partition placement and do not create
    or manage physical disks, volumes, or filegroups.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.DBA_PartitionMaintenanceConfig', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DBA_PartitionMaintenanceConfig
    (
        ConfigId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_DBA_PartitionMaintenanceConfig PRIMARY KEY,
        SchemaName sysname NOT NULL,
        TableName sysname NOT NULL,
        TargetTableName sysname NULL,
        PartitionColumn sysname NOT NULL,
        RangeUnit varchar(10) NOT NULL CONSTRAINT DF_DBA_PartitionConfig_RangeUnit DEFAULT ('DAY'),
        PartitionInterval int NOT NULL CONSTRAINT DF_DBA_PartitionConfig_Interval DEFAULT (1),
        PartitionFunctionName sysname NULL,
        PartitionSchemeName sysname NULL,
        FilegroupName sysname NOT NULL CONSTRAINT DF_DBA_PartitionConfig_Filegroup DEFAULT ('PRIMARY'),
        DeploymentPlatform varchar(20) NOT NULL CONSTRAINT DF_DBA_PartitionConfig_Platform DEFAULT ('AUTO'),
        FuturePartitions int NOT NULL CONSTRAINT DF_DBA_PartitionConfig_Future DEFAULT (4),
        RetentionPartitions int NOT NULL CONSTRAINT DF_DBA_PartitionConfig_Retention DEFAULT (52),
        AutoDeleteOldPartitions bit NOT NULL CONSTRAINT DF_DBA_PartitionConfig_Delete DEFAULT (0),
        IndexAction varchar(12) NOT NULL CONSTRAINT DF_DBA_PartitionConfig_IndexAction DEFAULT ('AUTO'),
        IndexAlignment varchar(12) NOT NULL CONSTRAINT DF_DBA_PartitionConfig_IndexAlignment DEFAULT ('ALIGNED'),
        StatsAction varchar(12) NOT NULL CONSTRAINT DF_DBA_PartitionConfig_StatsAction DEFAULT ('AUTO'),
        StatsSamplePercent int NULL,
        ReorganizeAtPercent decimal(5,2) NOT NULL CONSTRAINT DF_DBA_PartitionConfig_Reorg DEFAULT (10),
        RebuildAtPercent decimal(5,2) NOT NULL CONSTRAINT DF_DBA_PartitionConfig_Rebuild DEFAULT (30),
        MinimumPageCount int NOT NULL CONSTRAINT DF_DBA_PartitionConfig_MinPages DEFAULT (1000),
        Enabled bit NOT NULL CONSTRAINT DF_DBA_PartitionConfig_Enabled DEFAULT (1),
        CreatedAt datetime2(0) NOT NULL CONSTRAINT DF_DBA_PartitionConfig_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedAt datetime2(0) NOT NULL CONSTRAINT DF_DBA_PartitionConfig_Modified DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_DBA_PartitionMaintenanceConfig UNIQUE (SchemaName, TableName),
        CONSTRAINT CK_DBA_PartitionConfig_RangeUnit CHECK (RangeUnit IN ('DAY','WEEK','MONTH','QUARTER','YEAR','INTEGER')),
        CONSTRAINT CK_DBA_PartitionConfig_Counts CHECK (FuturePartitions >= 1 AND RetentionPartitions >= 0),
        CONSTRAINT CK_DBA_PartitionConfig_IndexAction CHECK (IndexAction IN ('AUTO','REBUILD','REORGANIZE','NONE')),
        CONSTRAINT CK_DBA_PartitionConfig_IndexAlignment CHECK (IndexAlignment IN ('ALIGNED','NONALIGNED')),
        CONSTRAINT CK_DBA_PartitionConfig_StatsAction CHECK (StatsAction IN ('AUTO','FULLSCAN','SAMPLE','NONE')),
        CONSTRAINT CK_DBA_PartitionConfig_Platform CHECK (DeploymentPlatform IN ('AUTO','ONPREM','AWS_RDS','AZURE_SQLDB','AZURE_MI')),
        CONSTRAINT CK_DBA_PartitionConfig_Thresholds CHECK (ReorganizeAtPercent >= 0 AND RebuildAtPercent > ReorganizeAtPercent)
    );
END;
GO

IF COL_LENGTH(N'dbo.DBA_PartitionMaintenanceConfig', N'PartitionInterval') IS NULL
    ALTER TABLE dbo.DBA_PartitionMaintenanceConfig ADD PartitionInterval int NOT NULL CONSTRAINT DF_DBA_PartitionConfig_Interval_Upgrade DEFAULT (1);
IF COL_LENGTH(N'dbo.DBA_PartitionMaintenanceConfig', N'PartitionFunctionName') IS NULL
    ALTER TABLE dbo.DBA_PartitionMaintenanceConfig ADD PartitionFunctionName sysname NULL;
IF COL_LENGTH(N'dbo.DBA_PartitionMaintenanceConfig', N'PartitionSchemeName') IS NULL
    ALTER TABLE dbo.DBA_PartitionMaintenanceConfig ADD PartitionSchemeName sysname NULL;
IF COL_LENGTH(N'dbo.DBA_PartitionMaintenanceConfig', N'FilegroupName') IS NULL
    ALTER TABLE dbo.DBA_PartitionMaintenanceConfig ADD FilegroupName sysname NOT NULL CONSTRAINT DF_DBA_PartitionConfig_Filegroup_Upgrade DEFAULT ('PRIMARY');
IF COL_LENGTH(N'dbo.DBA_PartitionMaintenanceConfig', N'IndexAlignment') IS NULL
    ALTER TABLE dbo.DBA_PartitionMaintenanceConfig ADD IndexAlignment varchar(12) NOT NULL CONSTRAINT DF_DBA_PartitionConfig_IndexAlignment_Upgrade DEFAULT ('ALIGNED');
IF COL_LENGTH(N'dbo.DBA_PartitionMaintenanceConfig', N'StatsAction') IS NULL
    ALTER TABLE dbo.DBA_PartitionMaintenanceConfig ADD StatsAction varchar(12) NOT NULL CONSTRAINT DF_DBA_PartitionConfig_StatsAction_Upgrade DEFAULT ('AUTO');
IF COL_LENGTH(N'dbo.DBA_PartitionMaintenanceConfig', N'StatsSamplePercent') IS NULL
    ALTER TABLE dbo.DBA_PartitionMaintenanceConfig ADD StatsSamplePercent int NULL;
IF COL_LENGTH(N'dbo.DBA_PartitionMaintenanceConfig', N'DeploymentPlatform') IS NULL
    ALTER TABLE dbo.DBA_PartitionMaintenanceConfig ADD DeploymentPlatform varchar(20) NOT NULL CONSTRAINT DF_DBA_PartitionConfig_Platform_Upgrade DEFAULT ('AUTO');
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_DBA_PartitionConfig_RangeUnit')
    ALTER TABLE dbo.DBA_PartitionMaintenanceConfig DROP CONSTRAINT CK_DBA_PartitionConfig_RangeUnit;
ALTER TABLE dbo.DBA_PartitionMaintenanceConfig ADD CONSTRAINT CK_DBA_PartitionConfig_RangeUnit
    CHECK (RangeUnit IN ('DAY','WEEK','MONTH','QUARTER','YEAR','INTEGER'));
GO

IF OBJECT_ID(N'dbo.DBA_PartitionMaintenanceHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DBA_PartitionMaintenanceHistory
    (
        HistoryId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_DBA_PartitionMaintenanceHistory PRIMARY KEY,
        ConfigId int NULL, RunId uniqueidentifier NOT NULL,
        EventTime datetime2(0) NOT NULL CONSTRAINT DF_DBA_PartitionHistory_EventTime DEFAULT (SYSUTCDATETIME()),
        Action varchar(30) NOT NULL, SchemaName sysname NULL, TableName sysname NULL,
        PartitionNumber int NULL, BoundaryValue nvarchar(128) NULL, CommandText nvarchar(max) NULL,
        RowsAffected bigint NULL, Succeeded bit NOT NULL, ErrorNumber int NULL, ErrorMessage nvarchar(4000) NULL
    );
    CREATE INDEX IX_DBA_PartitionHistory_RunTime ON dbo.DBA_PartitionMaintenanceHistory (RunId, EventTime);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_DBA_RegisterPartitionedTable
    @SchemaName sysname, @TableName sysname, @PartitionColumn sysname,
    @TargetTableName sysname = NULL, @RangeUnit varchar(10) = 'DAY',
    @PartitionInterval int = 1, @PartitionFunctionName sysname = NULL,
    @PartitionSchemeName sysname = NULL, @FilegroupName sysname = 'PRIMARY',
    @DeploymentPlatform varchar(20) = 'AUTO',
    @FuturePartitions int = 4, @RetentionPartitions int = 52,
    @AutoDeleteOldPartitions bit = 0, @IndexAction varchar(12) = 'AUTO',
    @IndexAlignment varchar(12) = 'ALIGNED', @StatsAction varchar(12) = 'AUTO',
    @StatsSamplePercent int = NULL,
    @ReorganizeAtPercent decimal(5,2) = 10, @RebuildAtPercent decimal(5,2) = 30,
    @MinimumPageCount int = 1000, @Enabled bit = 1
AS
BEGIN
    SET NOCOUNT ON;
    IF OBJECT_ID(QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName), N'U') IS NULL
        THROW 51000, 'The source table does not exist.', 1;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName)) AND name = @PartitionColumn)
        THROW 51001, 'The configured partition column does not exist on the source table.', 1;
    IF @TargetTableName IS NOT NULL AND OBJECT_ID(QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TargetTableName), N'U') IS NULL
        THROW 51003, 'The configured switch target table does not exist.', 1;
    IF @PartitionInterval < 1 OR @RangeUnit NOT IN ('DAY','WEEK','MONTH','QUARTER','YEAR','INTEGER')
        THROW 51005, 'PartitionInterval must be positive and RangeUnit must be a supported value.', 1;
    IF @DeploymentPlatform NOT IN ('AUTO','ONPREM','AWS_RDS','AZURE_SQLDB','AZURE_MI')
        THROW 51007, 'DeploymentPlatform must be AUTO, ONPREM, AWS_RDS, AZURE_SQLDB, or AZURE_MI.', 1;
    IF @DeploymentPlatform IN ('AWS_RDS','AZURE_SQLDB','AZURE_MI') SET @FilegroupName='PRIMARY';
    MERGE dbo.DBA_PartitionMaintenanceConfig AS target
    USING (SELECT @SchemaName AS SchemaName, @TableName AS TableName) AS source
       ON target.SchemaName = source.SchemaName AND target.TableName = source.TableName
    WHEN MATCHED THEN UPDATE SET TargetTableName=@TargetTableName, PartitionColumn=@PartitionColumn,
        PartitionInterval=@PartitionInterval, PartitionFunctionName=@PartitionFunctionName,
        PartitionSchemeName=@PartitionSchemeName, FilegroupName=@FilegroupName, DeploymentPlatform=@DeploymentPlatform,
        RangeUnit=@RangeUnit, FuturePartitions=@FuturePartitions, RetentionPartitions=@RetentionPartitions,
        AutoDeleteOldPartitions=@AutoDeleteOldPartitions, IndexAction=@IndexAction, IndexAlignment=@IndexAlignment,
        StatsAction=@StatsAction, StatsSamplePercent=@StatsSamplePercent,
        ReorganizeAtPercent=@ReorganizeAtPercent, RebuildAtPercent=@RebuildAtPercent,
        MinimumPageCount=@MinimumPageCount, Enabled=@Enabled, ModifiedAt=SYSUTCDATETIME()
    WHEN NOT MATCHED THEN INSERT (SchemaName,TableName,TargetTableName,PartitionColumn,PartitionInterval,PartitionFunctionName,
        PartitionSchemeName,FilegroupName,DeploymentPlatform,RangeUnit,FuturePartitions,RetentionPartitions,AutoDeleteOldPartitions,IndexAction,
        IndexAlignment,StatsAction,StatsSamplePercent,ReorganizeAtPercent,RebuildAtPercent,MinimumPageCount,Enabled)
        VALUES (@SchemaName,@TableName,@TargetTableName,@PartitionColumn,@PartitionInterval,@PartitionFunctionName,
        @PartitionSchemeName,@FilegroupName,@DeploymentPlatform,@RangeUnit,@FuturePartitions,@RetentionPartitions,@AutoDeleteOldPartitions,@IndexAction,
        @IndexAlignment,@StatsAction,@StatsSamplePercent,@ReorganizeAtPercent,@RebuildAtPercent,@MinimumPageCount,@Enabled);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_DBA_ConvertTableToPartitioned
    @SchemaName sysname,
    @TableName sysname,
    @PartitionColumn sysname,
    @RangeUnit varchar(10),
    @StartValue nvarchar(128),
    @EndValue nvarchar(128),
    @PartitionInterval int = 1,
    @PartitionFunctionName sysname = NULL,
    @PartitionSchemeName sysname = NULL,
    @FilegroupName sysname = 'PRIMARY',
    @DeploymentPlatform varchar(20) = 'AUTO',
    @IndexAlignment varchar(12) = 'ALIGNED',
    @TargetTableName sysname = NULL,
    @FuturePartitions int = 4,
    @RetentionPartitions int = 52,
    @AutoDeleteOldPartitions bit = 0,
    @IndexAction varchar(12) = 'AUTO',
    @StatsAction varchar(12) = 'AUTO',
    @StatsSamplePercent int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @objectId int = OBJECT_ID(QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName), N'U');
    DECLARE @columnId int, @systemTypeId int, @precision int, @scale int, @typeSql nvarchar(60), @typeName sysname;
    DECLARE @pf sysname = ISNULL(@PartitionFunctionName, LEFT(N'PF_DBA_' + @TableName + N'_' + @PartitionColumn, 128));
    DECLARE @ps sysname = ISNULL(@PartitionSchemeName, LEFT(N'PS_DBA_' + @TableName + N'_' + @PartitionColumn, 128));
    DECLARE @sql nvarchar(max), @boundaries nvarchar(max), @keyColumns nvarchar(max), @includeColumns nvarchar(max), @filter nvarchar(max);
    DECLARE @startDate datetime2(7), @endDate datetime2(7), @currentDate datetime2(7), @startInt bigint, @endInt bigint, @currentInt bigint;
    DECLARE @clusteredName sysname, @clusteredUnique bit, @runId uniqueidentifier = NEWID(), @platform varchar(20);

    IF @objectId IS NULL THROW 51010, 'The source table does not exist.', 1;
    IF @RangeUnit NOT IN ('DAY','WEEK','MONTH','QUARTER','YEAR','INTEGER') OR @PartitionInterval < 1
        THROW 51011, 'RangeUnit or PartitionInterval is invalid.', 1;
    IF @DeploymentPlatform NOT IN ('AUTO','ONPREM','AWS_RDS','AZURE_SQLDB','AZURE_MI')
        THROW 51027, 'DeploymentPlatform must be AUTO, ONPREM, AWS_RDS, AZURE_SQLDB, or AZURE_MI.', 1;
    SET @platform=CASE WHEN @DeploymentPlatform<>'AUTO' THEN @DeploymentPlatform
        WHEN CONVERT(int,SERVERPROPERTY('EngineEdition'))=5 THEN 'AZURE_SQLDB'
        WHEN CONVERT(int,SERVERPROPERTY('EngineEdition'))=8 THEN 'AZURE_MI'
        ELSE 'ONPREM' END;
    IF @platform IN ('AWS_RDS','AZURE_SQLDB','AZURE_MI') SET @FilegroupName='PRIMARY';
    IF @IndexAlignment NOT IN ('ALIGNED','NONALIGNED') THROW 51012, 'IndexAlignment must be ALIGNED or NONALIGNED.', 1;
    IF @StatsSamplePercent IS NOT NULL AND (@StatsSamplePercent < 1 OR @StatsSamplePercent > 100)
        THROW 51026, 'StatsSamplePercent must be between 1 and 100.', 1;
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=@objectId AND index_id=1 AND data_space_id IN (SELECT data_space_id FROM sys.partition_schemes))
        THROW 51013, 'The table is already partitioned.', 1;
    IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name=@pf) OR EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name=@ps)
        THROW 51014, 'The requested partition function or scheme name already exists.', 1;
    IF NOT EXISTS (SELECT 1 FROM sys.filegroups WHERE name=@FilegroupName)
        THROW 51015, 'The requested filegroup does not exist.', 1;

    SELECT @columnId=c.column_id, @systemTypeId=c.system_type_id, @precision=c.precision, @scale=c.scale,
        @typeName=TYPE_NAME(c.system_type_id)
    FROM sys.columns c WHERE c.object_id=@objectId AND c.name=@PartitionColumn;
    IF @columnId IS NULL THROW 51016, 'The partition column does not exist.', 1;
    SET @typeSql=CASE WHEN @systemTypeId=40 THEN N'date' WHEN @systemTypeId=41 THEN N'time'
        WHEN @systemTypeId=42 THEN N'datetime2('+CONVERT(nvarchar(3),@scale)+N')' WHEN @systemTypeId=58 THEN N'smalldatetime'
        WHEN @systemTypeId=61 THEN N'datetime' WHEN @systemTypeId=48 THEN N'tinyint' WHEN @systemTypeId=52 THEN N'smallint'
        WHEN @systemTypeId=56 THEN N'int' WHEN @systemTypeId=127 THEN N'bigint' ELSE NULL END;
    IF @typeSql IS NULL OR (@systemTypeId=41)
        THROW 51017, 'Supported partition columns are date/datetime types or integer types.', 1;
    IF (@RangeUnit='INTEGER' AND @systemTypeId NOT IN (48,52,56,127))
        OR (@RangeUnit<>'INTEGER' AND @systemTypeId IN (48,52,56,127))
        THROW 51025, 'INTEGER ranges require an integer column; temporal ranges require a date/datetime column.', 1;

    SELECT @clusteredName=i.name, @clusteredUnique=i.is_unique
    FROM sys.indexes i WHERE i.object_id=@objectId AND i.index_id=1;
    IF @clusteredName IS NULL THROW 51018, 'The source table must have a clustered index for this conversion procedure.', 1;
    IF @clusteredUnique=1 AND NOT EXISTS
    (
        SELECT 1 FROM sys.index_columns ic WHERE ic.object_id=@objectId AND ic.index_id=1 AND ic.column_id=@columnId AND ic.key_ordinal>0
    )
        THROW 51019, 'A unique clustered index must contain the partition column to become aligned.', 1;
    IF @IndexAlignment='ALIGNED' AND EXISTS
    (
        SELECT 1 FROM sys.indexes i WHERE i.object_id=@objectId AND i.index_id>1 AND i.is_unique=1
          AND NOT EXISTS (SELECT 1 FROM sys.index_columns ic WHERE ic.object_id=i.object_id AND ic.index_id=i.index_id AND ic.column_id=@columnId AND ic.key_ordinal>0)
    )
        THROW 51020, 'A unique nonclustered index does not contain the partition column and cannot be aligned.', 1;

    CREATE TABLE #Boundaries (BoundaryOrder int IDENTITY(1,1), BoundaryValue nvarchar(128) NOT NULL);
    IF @RangeUnit='INTEGER'
    BEGIN
        SET @startInt=TRY_CONVERT(bigint,@StartValue); SET @endInt=TRY_CONVERT(bigint,@EndValue);
        IF @startInt IS NULL OR @endInt IS NULL OR @startInt>=@endInt THROW 51021, 'Integer range values are invalid.', 1;
        SET @currentInt=@startInt;
        WHILE @currentInt<=@endInt
        BEGIN
            INSERT #Boundaries(BoundaryValue) VALUES(CONVERT(nvarchar(128),@currentInt));
            SET @currentInt=@currentInt+@PartitionInterval;
            IF @currentInt<0 AND @endInt>0 THROW 51022, 'Integer range overflow occurred.', 1;
        END;
    END
    ELSE
    BEGIN
        SET @startDate=TRY_CONVERT(datetime2(7),@StartValue); SET @endDate=TRY_CONVERT(datetime2(7),@EndValue);
        IF @startDate IS NULL OR @endDate IS NULL OR @startDate>=@endDate THROW 51023, 'Temporal range values are invalid.', 1;
        SET @currentDate=@startDate;
        WHILE @currentDate<=@endDate
        BEGIN
            INSERT #Boundaries(BoundaryValue) VALUES(CONVERT(nvarchar(128),@currentDate,126));
            SET @currentDate=CASE @RangeUnit WHEN 'DAY' THEN DATEADD(DAY,@PartitionInterval,@currentDate)
                WHEN 'WEEK' THEN DATEADD(WEEK,@PartitionInterval,@currentDate) WHEN 'MONTH' THEN DATEADD(MONTH,@PartitionInterval,@currentDate)
                WHEN 'QUARTER' THEN DATEADD(QUARTER,@PartitionInterval,@currentDate) ELSE DATEADD(YEAR,@PartitionInterval,@currentDate) END;
        END;
    END;
    SELECT @boundaries=STUFF((SELECT N','''+REPLACE(BoundaryValue,'''','''''')+N'''' FROM #Boundaries ORDER BY BoundaryOrder FOR XML PATH(''),TYPE).value('.','nvarchar(max)'),1,1,N'');
    SELECT @keyColumns=STUFF((SELECT N','+QUOTENAME(c.name)+(CASE WHEN ic.is_descending_key=1 THEN N' DESC' ELSE N' ASC' END)
        FROM sys.index_columns ic JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
        WHERE ic.object_id=@objectId AND ic.index_id=1 AND ic.key_ordinal>0 ORDER BY ic.key_ordinal FOR XML PATH(''),TYPE).value('.','nvarchar(max)'),1,1,N'');
    IF @keyColumns IS NULL THROW 51024, 'The clustered index has no key columns.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;
        SET @sql=N'CREATE PARTITION FUNCTION '+QUOTENAME(@pf)+N'('+@typeSql+N') AS RANGE RIGHT FOR VALUES ('+@boundaries+N');'+
            N' CREATE PARTITION SCHEME '+QUOTENAME(@ps)+N' AS PARTITION '+QUOTENAME(@pf)+N' ALL TO ('+QUOTENAME(@FilegroupName)+N');';
        EXEC sys.sp_executesql @sql;
        SET @sql=N'CREATE '+CASE WHEN @clusteredUnique=1 THEN N'UNIQUE ' ELSE N'' END+N'CLUSTERED INDEX '+QUOTENAME(@clusteredName)+N' ON '+QUOTENAME(@SchemaName)+N'.'+QUOTENAME(@TableName)+N'('+STUFF(@keyColumns,1,1,N'')+N') WITH (DROP_EXISTING=ON) ON '+QUOTENAME(@ps)+N'('+QUOTENAME(@PartitionColumn)+N');';
        EXEC sys.sp_executesql @sql;

        IF @IndexAlignment='ALIGNED'
        BEGIN
            DECLARE indexes CURSOR LOCAL FAST_FORWARD FOR SELECT i.name,i.is_unique,
                STUFF((SELECT N','+QUOTENAME(c.name)+(CASE WHEN ic2.is_descending_key=1 THEN N' DESC' ELSE N' ASC' END) FROM sys.index_columns ic2 JOIN sys.columns c ON c.object_id=ic2.object_id AND c.column_id=ic2.column_id WHERE ic2.object_id=i.object_id AND ic2.index_id=i.index_id AND ic2.key_ordinal>0 ORDER BY ic2.key_ordinal FOR XML PATH(''),TYPE).value('.','nvarchar(max)'),1,1,N''),
                STUFF((SELECT N','+QUOTENAME(c.name) FROM sys.index_columns ic2 JOIN sys.columns c ON c.object_id=ic2.object_id AND c.column_id=ic2.column_id WHERE ic2.object_id=i.object_id AND ic2.index_id=i.index_id AND ic2.is_included_column=1 ORDER BY ic2.index_column_id FOR XML PATH(''),TYPE).value('.','nvarchar(max)'),1,1,N''), i.filter_definition
                FROM sys.indexes i WHERE i.object_id=@objectId AND i.index_id>1 AND i.type=2 AND i.is_disabled=0;
            DECLARE @indexName sysname,@indexUnique bit;
            OPEN indexes; FETCH NEXT FROM indexes INTO @indexName,@indexUnique,@keyColumns,@includeColumns,@filter;
            WHILE @@FETCH_STATUS=0
            BEGIN
                SET @sql=N'CREATE '+CASE WHEN @indexUnique=1 THEN N'UNIQUE ' ELSE N'' END+N'NONCLUSTERED INDEX '+QUOTENAME(@indexName)+N' ON '+QUOTENAME(@SchemaName)+N'.'+QUOTENAME(@TableName)+N'('+@keyColumns+N')'+CASE WHEN @includeColumns IS NOT NULL THEN N' INCLUDE ('+@includeColumns+N')' ELSE N'' END+N' WITH (DROP_EXISTING=ON) ON '+QUOTENAME(@ps)+N'('+QUOTENAME(@PartitionColumn)+N')'+CASE WHEN @filter IS NOT NULL THEN N' WHERE '+@filter ELSE N'' END+N';';
                EXEC sys.sp_executesql @sql;
                FETCH NEXT FROM indexes INTO @indexName,@indexUnique,@keyColumns,@includeColumns,@filter;
            END;
            CLOSE indexes; DEALLOCATE indexes;
        END;
        EXEC dbo.usp_DBA_RegisterPartitionedTable @SchemaName=@SchemaName,@TableName=@TableName,@PartitionColumn=@PartitionColumn,
            @TargetTableName=@TargetTableName,@RangeUnit=@RangeUnit,@PartitionInterval=@PartitionInterval,
            @PartitionFunctionName=@pf,@PartitionSchemeName=@ps,@FilegroupName=@FilegroupName,@DeploymentPlatform=@platform,@FuturePartitions=@FuturePartitions,
            @RetentionPartitions=@RetentionPartitions,@AutoDeleteOldPartitions=@AutoDeleteOldPartitions,@IndexAction=@IndexAction,
            @IndexAlignment=@IndexAlignment,@StatsAction=@StatsAction,@StatsSamplePercent=@StatsSamplePercent;
        INSERT dbo.DBA_PartitionMaintenanceHistory(RunId,Action,SchemaName,TableName,CommandText,Succeeded)
            VALUES(@runId,'CONVERT_TABLE',@SchemaName,@TableName,@sql,1);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        INSERT dbo.DBA_PartitionMaintenanceHistory(RunId,Action,SchemaName,TableName,CommandText,Succeeded,ErrorNumber,ErrorMessage)
            VALUES(@runId,'CONVERT_ERROR',@SchemaName,@TableName,@sql,0,ERROR_NUMBER(),ERROR_MESSAGE());
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_DBA_AddPartitionBoundaries
    @ConfigId int = NULL, @FuturePartitionsOverride int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @FuturePartitionsOverride IS NOT NULL AND @FuturePartitionsOverride < 1
        THROW 51006, 'FuturePartitionsOverride must be at least 1.', 1;
    DECLARE @RunId uniqueidentifier=NEWID(), @id int, @schema sysname, @table sysname, @pf sysname, @ps sysname, @filegroup sysname, @platform varchar(20),
        @unit varchar(10), @interval int, @future int, @sql nvarchar(max), @maxBoundary datetime2(7), @desired datetime2(7),
        @newBoundary datetime2(7), @maxInt bigint, @desiredInt bigint, @newInt bigint, @added int;
    DECLARE configs CURSOR LOCAL FAST_FORWARD FOR SELECT ConfigId,SchemaName,TableName,RangeUnit,
        PartitionInterval,ISNULL(@FuturePartitionsOverride,FuturePartitions),FilegroupName,DeploymentPlatform FROM dbo.DBA_PartitionMaintenanceConfig
        WHERE Enabled=1 AND (@ConfigId IS NULL OR ConfigId=@ConfigId);
    OPEN configs; FETCH NEXT FROM configs INTO @id,@schema,@table,@unit,@interval,@future,@filegroup,@platform;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @added=0;
        BEGIN TRY
            SET @platform=CASE WHEN @platform<>'AUTO' THEN @platform
                WHEN CONVERT(int,SERVERPROPERTY('EngineEdition'))=5 THEN 'AZURE_SQLDB'
                WHEN CONVERT(int,SERVERPROPERTY('EngineEdition'))=8 THEN 'AZURE_MI'
                ELSE 'ONPREM' END;
            IF @platform IN ('AWS_RDS','AZURE_SQLDB','AZURE_MI') SET @filegroup='PRIMARY';
            SELECT @pf=pf.name,@ps=ps.name FROM sys.tables t JOIN sys.indexes i ON i.object_id=t.object_id AND i.index_id=1
                JOIN sys.partition_schemes ps ON ps.data_space_id=i.data_space_id JOIN sys.partition_functions pf ON pf.function_id=ps.function_id
                WHERE t.object_id=OBJECT_ID(QUOTENAME(@schema)+N'.'+QUOTENAME(@table));
            IF @pf IS NULL THROW 51002,'The table clustered index is not on a partition scheme.',1;
            IF @unit='INTEGER'
            BEGIN
                SELECT @maxInt=MAX(CONVERT(bigint,prv.value)) FROM sys.partition_range_values prv JOIN sys.partition_functions pf ON pf.function_id=prv.function_id WHERE pf.name=@pf;
                IF @maxInt IS NULL THROW 51004,'The partition function has no boundary. Seed at least one boundary before scheduling maintenance.',1;
                SET @desiredInt=@maxInt+(@interval*@future);
                WHILE @maxInt<@desiredInt
                BEGIN
                    SET @newInt=@maxInt+@interval;
                    SET @sql=N'ALTER PARTITION SCHEME '+QUOTENAME(@ps)+N' NEXT USED '+QUOTENAME(@filegroup)+N'; ALTER PARTITION FUNCTION '+QUOTENAME(@pf)+N'() SPLIT RANGE ('+CONVERT(varchar(40),@newInt)+N');';
                    EXEC sys.sp_executesql @sql;
                    INSERT dbo.DBA_PartitionMaintenanceHistory(ConfigId,RunId,Action,SchemaName,TableName,BoundaryValue,CommandText,Succeeded)
                        VALUES(@id,@RunId,'ADD_BOUNDARY',@schema,@table,CONVERT(nvarchar(128),@newInt),@sql,1);
                    SET @maxInt=@newInt; SET @added+=1;
                END;
            END;
            ELSE
            BEGIN
                SELECT @maxBoundary=MAX(CONVERT(datetime2(7),prv.value)) FROM sys.partition_range_values prv JOIN sys.partition_functions pf ON pf.function_id=prv.function_id WHERE pf.name=@pf;
                IF @maxBoundary IS NULL THROW 51004,'The partition function has no boundary. Seed at least one boundary before scheduling maintenance.',1;
                SET @desired=CASE @unit WHEN 'DAY' THEN DATEADD(DAY,@interval*@future,CONVERT(date,GETDATE()))
                    WHEN 'WEEK' THEN DATEADD(WEEK,@interval*@future,DATEADD(DAY,1-DATEPART(WEEKDAY,CONVERT(date,GETDATE())),CONVERT(date,GETDATE())))
                    WHEN 'MONTH' THEN DATEADD(MONTH,@interval*@future,DATEFROMPARTS(YEAR(GETDATE()),MONTH(GETDATE()),1))
                    WHEN 'QUARTER' THEN DATEADD(QUARTER,@interval*@future,DATEFROMPARTS(YEAR(GETDATE()),((DATEPART(QUARTER,GETDATE())-1)*3)+1,1))
                    ELSE DATEADD(YEAR,@interval*@future,DATEFROMPARTS(YEAR(GETDATE()),1,1)) END;
                WHILE @maxBoundary < @desired
                BEGIN
                    SET @newBoundary=CASE @unit WHEN 'DAY' THEN DATEADD(DAY,@interval,@maxBoundary) WHEN 'WEEK' THEN DATEADD(WEEK,@interval,@maxBoundary)
                        WHEN 'MONTH' THEN DATEADD(MONTH,@interval,@maxBoundary) WHEN 'QUARTER' THEN DATEADD(QUARTER,@interval,@maxBoundary)
                        ELSE DATEADD(YEAR,@interval,@maxBoundary) END;
                    SET @sql=N'ALTER PARTITION SCHEME '+QUOTENAME(@ps)+N' NEXT USED '+QUOTENAME(@filegroup)+N'; ALTER PARTITION FUNCTION '+QUOTENAME(@pf)+N'() SPLIT RANGE ('''+CONVERT(varchar(33),@newBoundary,126)+N''');';
                    EXEC sys.sp_executesql @sql;
                    INSERT dbo.DBA_PartitionMaintenanceHistory(ConfigId,RunId,Action,SchemaName,TableName,BoundaryValue,CommandText,Succeeded)
                        VALUES(@id,@RunId,'ADD_BOUNDARY',@schema,@table,CONVERT(nvarchar(128),@newBoundary,126),@sql,1);
                    SET @maxBoundary=@newBoundary; SET @added+=1;
                END;
            END;
            INSERT dbo.DBA_PartitionMaintenanceHistory(ConfigId,RunId,Action,SchemaName,TableName,RowsAffected,Succeeded)
                VALUES(@id,@RunId,'ADD_SUMMARY',@schema,@table,@added,1);
        END TRY
        BEGIN CATCH
            INSERT dbo.DBA_PartitionMaintenanceHistory(ConfigId,RunId,Action,SchemaName,TableName,Succeeded,ErrorNumber,ErrorMessage)
                VALUES(@id,@RunId,'ADD_ERROR',@schema,@table,0,ERROR_NUMBER(),ERROR_MESSAGE()); THROW;
        END CATCH;
        FETCH NEXT FROM configs INTO @id,@schema,@table,@unit,@interval,@future,@filegroup,@platform;
    END;
    CLOSE configs; DEALLOCATE configs;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_DBA_RemoveOldPartitions
    @ConfigId int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @RunId uniqueidentifier=NEWID(),@id int,@schema sysname,@table sysname,@target sysname,@pf sysname,@retention int,@future int,
        @sql nvarchar(max),@boundary nvarchar(128),@count int;
    DECLARE configs CURSOR LOCAL FAST_FORWARD FOR SELECT ConfigId,SchemaName,TableName,TargetTableName,RetentionPartitions,FuturePartitions
        FROM dbo.DBA_PartitionMaintenanceConfig WHERE Enabled=1 AND AutoDeleteOldPartitions=1 AND (@ConfigId IS NULL OR ConfigId=@ConfigId);
    OPEN configs; FETCH NEXT FROM configs INTO @id,@schema,@table,@target,@retention,@future;
    WHILE @@FETCH_STATUS=0
    BEGIN
        BEGIN TRY
            SELECT @pf=pf.name FROM sys.tables t JOIN sys.indexes i ON i.object_id=t.object_id AND i.index_id=1
                JOIN sys.partition_schemes ps ON ps.data_space_id=i.data_space_id JOIN sys.partition_functions pf ON pf.function_id=ps.function_id
                WHERE t.object_id=OBJECT_ID(QUOTENAME(@schema)+N'.'+QUOTENAME(@table));
            SELECT @count=COUNT(*) FROM sys.partition_range_values prv JOIN sys.partition_functions pf ON pf.function_id=prv.function_id WHERE pf.name=@pf;
            WHILE @count>@retention+@future+1
            BEGIN
                SELECT @boundary=CONVERT(nvarchar(128),prv.value,126) FROM sys.partition_range_values prv JOIN sys.partition_functions pf ON pf.function_id=prv.function_id WHERE pf.name=@pf AND prv.boundary_id=1;
                IF @target IS NOT NULL SET @sql=N'ALTER TABLE '+QUOTENAME(@schema)+N'.'+QUOTENAME(@table)+N' SWITCH PARTITION 1 TO '+QUOTENAME(@schema)+N'.'+QUOTENAME(@target)+N';';
                ELSE SET @sql=N'TRUNCATE TABLE '+QUOTENAME(@schema)+N'.'+QUOTENAME(@table)+N' WITH (PARTITIONS (1));';
                EXEC sys.sp_executesql @sql;
                SET @sql=N'ALTER PARTITION FUNCTION '+QUOTENAME(@pf)+N'() MERGE RANGE ('''+@boundary+N''');'; EXEC sys.sp_executesql @sql;
                INSERT dbo.DBA_PartitionMaintenanceHistory(ConfigId,RunId,Action,SchemaName,TableName,PartitionNumber,BoundaryValue,CommandText,Succeeded)
                    VALUES(@id,@RunId,'REMOVE_PARTITION',@schema,@table,1,@boundary,@sql,1);
                SELECT @count=COUNT(*) FROM sys.partition_range_values prv JOIN sys.partition_functions pf ON pf.function_id=prv.function_id WHERE pf.name=@pf;
            END;
        END TRY
        BEGIN CATCH
            INSERT dbo.DBA_PartitionMaintenanceHistory(ConfigId,RunId,Action,SchemaName,TableName,Succeeded,ErrorNumber,ErrorMessage)
                VALUES(@id,@RunId,'REMOVE_ERROR',@schema,@table,0,ERROR_NUMBER(),ERROR_MESSAGE()); THROW;
        END CATCH;
        FETCH NEXT FROM configs INTO @id,@schema,@table,@target,@retention,@future;
    END;
    CLOSE configs; DEALLOCATE configs;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_DBA_UpdateTableStatistics
    @ConfigId int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @RunId uniqueidentifier=NEWID(), @id int, @schema sysname, @table sysname,
        @action varchar(12), @sample int, @sql nvarchar(max);
    DECLARE configs CURSOR LOCAL FAST_FORWARD FOR
        SELECT ConfigId,SchemaName,TableName,StatsAction,StatsSamplePercent
        FROM dbo.DBA_PartitionMaintenanceConfig
        WHERE Enabled=1 AND StatsAction<>'NONE' AND (@ConfigId IS NULL OR ConfigId=@ConfigId);
    OPEN configs; FETCH NEXT FROM configs INTO @id,@schema,@table,@action,@sample;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @sql=N'UPDATE STATISTICS '+QUOTENAME(@schema)+N'.'+QUOTENAME(@table)+
            CASE WHEN @action='FULLSCAN' THEN N' WITH FULLSCAN;'
                 WHEN @action='SAMPLE' AND @sample IS NOT NULL THEN N' WITH SAMPLE '+CONVERT(nvarchar(10),@sample)+N' PERCENT;'
                 ELSE N';' END;
        BEGIN TRY
            EXEC sys.sp_executesql @sql;
            INSERT dbo.DBA_PartitionMaintenanceHistory(ConfigId,RunId,Action,SchemaName,TableName,CommandText,Succeeded)
                VALUES(@id,@RunId,'STATISTICS_UPDATE',@schema,@table,@sql,1);
        END TRY
        BEGIN CATCH
            INSERT dbo.DBA_PartitionMaintenanceHistory(ConfigId,RunId,Action,SchemaName,TableName,CommandText,Succeeded,ErrorNumber,ErrorMessage)
                VALUES(@id,@RunId,'STATISTICS_ERROR',@schema,@table,@sql,0,ERROR_NUMBER(),ERROR_MESSAGE()); THROW;
        END CATCH;
        FETCH NEXT FROM configs INTO @id,@schema,@table,@action,@sample;
    END;
    CLOSE configs; DEALLOCATE configs;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_DBA_MaintainTableIndexes
    @ConfigId int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @RunId uniqueidentifier=NEWID(), @id int, @schema sysname, @table sysname,
        @action varchar(12), @minPages int, @reorg decimal(5,2), @rebuild decimal(5,2),
        @sql nvarchar(max), @fragmentation decimal(9,2);
    DECLARE configs CURSOR LOCAL FAST_FORWARD FOR
        SELECT ConfigId,SchemaName,TableName,IndexAction,MinimumPageCount,ReorganizeAtPercent,RebuildAtPercent
        FROM dbo.DBA_PartitionMaintenanceConfig
        WHERE Enabled=1 AND IndexAction<>'NONE' AND (@ConfigId IS NULL OR ConfigId=@ConfigId);
    OPEN configs; FETCH NEXT FROM configs INTO @id,@schema,@table,@action,@minPages,@reorg,@rebuild;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @sql=NULL; SET @fragmentation=NULL;
        SELECT @fragmentation=MAX(ps.avg_fragmentation_in_percent)
        FROM sys.dm_db_index_physical_stats(DB_ID(),OBJECT_ID(QUOTENAME(@schema)+N'.'+QUOTENAME(@table)),NULL,NULL,'LIMITED') ps
        JOIN sys.indexes i ON i.object_id=ps.object_id AND i.index_id=ps.index_id
        WHERE ps.page_count>=@minPages AND i.index_id>0;
        IF @fragmentation IS NOT NULL AND (@action='REBUILD' OR (@action='AUTO' AND @fragmentation>=@rebuild))
            SET @sql=N'ALTER INDEX ALL ON '+QUOTENAME(@schema)+N'.'+QUOTENAME(@table)+N' REBUILD;';
        ELSE IF @fragmentation IS NOT NULL AND (@action='REORGANIZE' OR (@action='AUTO' AND @fragmentation>=@reorg))
            SET @sql=N'ALTER INDEX ALL ON '+QUOTENAME(@schema)+N'.'+QUOTENAME(@table)+N' REORGANIZE;';
        IF @sql IS NOT NULL
        BEGIN
            BEGIN TRY
                EXEC sys.sp_executesql @sql;
                INSERT dbo.DBA_PartitionMaintenanceHistory(ConfigId,RunId,Action,SchemaName,TableName,CommandText,RowsAffected,Succeeded)
                    VALUES(@id,@RunId,'INDEX_MAINTENANCE_ONLY',@schema,@table,@sql,CONVERT(bigint,@fragmentation),1);
            END TRY
            BEGIN CATCH
                INSERT dbo.DBA_PartitionMaintenanceHistory(ConfigId,RunId,Action,SchemaName,TableName,CommandText,Succeeded,ErrorNumber,ErrorMessage)
                    VALUES(@id,@RunId,'INDEX_MAINTENANCE_ERROR',@schema,@table,@sql,0,ERROR_NUMBER(),ERROR_MESSAGE()); THROW;
            END CATCH;
        END;
        FETCH NEXT FROM configs INTO @id,@schema,@table,@action,@minPages,@reorg,@rebuild;
    END;
    CLOSE configs; DEALLOCATE configs;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_DBA_MaintainTablePartitions
    @ConfigId int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.usp_DBA_AddPartitionBoundaries @ConfigId=@ConfigId;
    EXEC dbo.usp_DBA_RemoveOldPartitions @ConfigId=@ConfigId;
    DECLARE @RunId uniqueidentifier=NEWID(),@id int,@schema sysname,@table sysname,@action varchar(12),@minPages int,
        @reorg decimal(5,2),@rebuild decimal(5,2),@sql nvarchar(max),@fragmentation decimal(9,2);
    DECLARE configs CURSOR LOCAL FAST_FORWARD FOR SELECT ConfigId,SchemaName,TableName,IndexAction,MinimumPageCount,ReorganizeAtPercent,RebuildAtPercent
        FROM dbo.DBA_PartitionMaintenanceConfig WHERE Enabled=1 AND IndexAction<>'NONE' AND (@ConfigId IS NULL OR ConfigId=@ConfigId);
    OPEN configs; FETCH NEXT FROM configs INTO @id,@schema,@table,@action,@minPages,@reorg,@rebuild;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @sql=NULL;
        SET @fragmentation=NULL;
        SELECT @fragmentation=MAX(ps.avg_fragmentation_in_percent) FROM sys.dm_db_index_physical_stats(DB_ID(),OBJECT_ID(QUOTENAME(@schema)+N'.'+QUOTENAME(@table)),NULL,NULL,'LIMITED') ps
            JOIN sys.indexes i ON i.object_id=ps.object_id AND i.index_id=ps.index_id WHERE ps.page_count>=@minPages AND i.index_id>0;
        IF @fragmentation IS NOT NULL AND (@action='REBUILD' OR (@action='AUTO' AND @fragmentation>=@rebuild)) SET @sql=N'ALTER INDEX ALL ON '+QUOTENAME(@schema)+N'.'+QUOTENAME(@table)+N' REBUILD;';
        ELSE IF @fragmentation IS NOT NULL AND (@action='REORGANIZE' OR (@action='AUTO' AND @fragmentation>=@reorg)) SET @sql=N'ALTER INDEX ALL ON '+QUOTENAME(@schema)+N'.'+QUOTENAME(@table)+N' REORGANIZE;';
        IF @sql IS NOT NULL
        BEGIN
            BEGIN TRY
                EXEC sys.sp_executesql @sql;
                INSERT dbo.DBA_PartitionMaintenanceHistory(ConfigId,RunId,Action,SchemaName,TableName,CommandText,RowsAffected,Succeeded)
                    VALUES(@id,@RunId,'INDEX_MAINTENANCE',@schema,@table,@sql,CONVERT(bigint,@fragmentation),1);
            END TRY
            BEGIN CATCH
                INSERT dbo.DBA_PartitionMaintenanceHistory(ConfigId,RunId,Action,SchemaName,TableName,CommandText,Succeeded,ErrorNumber,ErrorMessage)
                    VALUES(@id,@RunId,'INDEX_ERROR',@schema,@table,@sql,0,ERROR_NUMBER(),ERROR_MESSAGE()); THROW;
            END CATCH;
        END;
        FETCH NEXT FROM configs INTO @id,@schema,@table,@action,@minPages,@reorg,@rebuild;
    END;
    CLOSE configs; DEALLOCATE configs;
    EXEC dbo.usp_DBA_UpdateTableStatistics @ConfigId=@ConfigId;
END;
GO