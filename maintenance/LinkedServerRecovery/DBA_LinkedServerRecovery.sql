/*
    DBA Linked Server Recovery

    Run this script in a DBA utility database (not an application database) on
    the instance whose linked servers should be recoverable. It creates a
    snapshot repository and procedures that capture linked-server definitions,
    security mappings, and permissions for explicitly mapped local logins.

    Capture:
        EXEC dbo.usp_DBA_LinkedServerRecovery @Action = 'CAPTURE_AND_GENERATE';

    Generate a previous snapshot:
        EXEC dbo.usp_DBA_LinkedServerRecovery @Action = 'GENERATE',
            @SnapshotId = '00000000-0000-0000-0000-000000000000';

    Passwords are never exposed by SQL Server metadata. Generated scripts use
    a clearly marked password placeholder for mappings that require one.
    Review generated output before running it on a rebuilt instance.
*/
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dbo.DBA_LinkedServerRecoverySnapshot', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DBA_LinkedServerRecoverySnapshot
    (
        SnapshotId uniqueidentifier NOT NULL CONSTRAINT PK_DBA_LinkedServerRecoverySnapshot PRIMARY KEY,
        CapturedAtUtc datetime2(0) NOT NULL CONSTRAINT DF_DBA_LSRSnapshot_CapturedAt DEFAULT (SYSUTCDATETIME()),
        SourceServer sysname NOT NULL,
        IncludeDatabasePermissions bit NOT NULL,
        IncludeSystemDatabases bit NOT NULL
    );
END;
GO

IF OBJECT_ID(N'dbo.DBA_LinkedServerRecoveryServer', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DBA_LinkedServerRecoveryServer
    (
        SnapshotId uniqueidentifier NOT NULL,
        ServerName sysname NOT NULL,
        ServerId int NOT NULL,
        Product nvarchar(128) NULL,
        Provider nvarchar(128) NULL,
        DataSource nvarchar(4000) NULL,
        Location nvarchar(4000) NULL,
        ProviderString nvarchar(4000) NULL,
        Catalog sysname NULL,
        ConnectTimeout int NULL,
        QueryTimeout int NULL,
        IsDataAccessEnabled bit NOT NULL,
        IsRpcOutEnabled bit NOT NULL,
        IsRemoteLoginEnabled bit NOT NULL,
        IsCollationCompatible bit NOT NULL,
        UsesRemoteCollation bit NOT NULL,
        LazySchemaValidation bit NOT NULL,
        IsRemoteProcTransactionPromotionEnabled bit NOT NULL,
        CONSTRAINT PK_DBA_LinkedServerRecoveryServer PRIMARY KEY (SnapshotId, ServerName),
        CONSTRAINT FK_DBA_LinkedServerRecoveryServer_Snapshot FOREIGN KEY (SnapshotId)
            REFERENCES dbo.DBA_LinkedServerRecoverySnapshot (SnapshotId)
    );
END;
GO

IF OBJECT_ID(N'dbo.DBA_LinkedServerRecoveryLogin', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DBA_LinkedServerRecoveryLogin
    (
        SnapshotId uniqueidentifier NOT NULL,
        ServerName sysname NOT NULL,
        LocalPrincipalId int NULL,
        LocalPrincipalName sysname NULL,
        LocalPrincipalType nvarchar(60) NULL,
        UsesSelfCredential bit NOT NULL,
        RemoteName sysname NULL,
        CONSTRAINT FK_DBA_LinkedServerRecoveryLogin_Snapshot FOREIGN KEY (SnapshotId)
            REFERENCES dbo.DBA_LinkedServerRecoverySnapshot (SnapshotId)
    );
    CREATE INDEX IX_DBA_LinkedServerRecoveryLogin_Server
        ON dbo.DBA_LinkedServerRecoveryLogin (SnapshotId, ServerName);
END;
GO

IF OBJECT_ID(N'dbo.DBA_LinkedServerRecoveryPermission', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DBA_LinkedServerRecoveryPermission
    (
        SnapshotId uniqueidentifier NOT NULL,
        DatabaseName sysname NOT NULL,
        PrincipalName sysname NOT NULL,
        PrincipalType nvarchar(60) NOT NULL,
        PermissionState char(1) NOT NULL,
        PermissionName sysname NOT NULL,
        PermissionClass int NOT NULL,
        SchemaName sysname NULL,
        ObjectName sysname NULL,
        CONSTRAINT FK_DBA_LinkedServerRecoveryPermission_Snapshot FOREIGN KEY (SnapshotId)
            REFERENCES dbo.DBA_LinkedServerRecoverySnapshot (SnapshotId)
    );
    CREATE INDEX IX_DBA_LinkedServerRecoveryPermission_Snapshot
        ON dbo.DBA_LinkedServerRecoveryPermission (SnapshotId, DatabaseName, PrincipalName);
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_DBA_LinkedServerRecovery
    @Action varchar(20) = 'CAPTURE',
    @SnapshotId uniqueidentifier = NULL,
    @LinkedServerName sysname = NULL,
    @IncludeDatabasePermissions bit = 1,
    @IncludeSystemDatabases bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Action NOT IN ('CAPTURE', 'GENERATE', 'CAPTURE_AND_GENERATE')
        THROW 51000, 'Action must be CAPTURE, GENERATE, or CAPTURE_AND_GENERATE.', 1;

    IF @Action IN ('CAPTURE', 'CAPTURE_AND_GENERATE')
    BEGIN
        SET @SnapshotId = NEWID();

        INSERT dbo.DBA_LinkedServerRecoverySnapshot
            (SnapshotId, SourceServer, IncludeDatabasePermissions, IncludeSystemDatabases)
        VALUES
            (@SnapshotId, CONVERT(sysname, SERVERPROPERTY('ServerName')),
             @IncludeDatabasePermissions, @IncludeSystemDatabases);

        INSERT dbo.DBA_LinkedServerRecoveryServer
        (
            SnapshotId, ServerName, ServerId, Product, Provider, DataSource, Location,
            ProviderString, Catalog, ConnectTimeout, QueryTimeout, IsDataAccessEnabled,
            IsRpcOutEnabled, IsRemoteLoginEnabled, IsCollationCompatible, UsesRemoteCollation,
            LazySchemaValidation, IsRemoteProcTransactionPromotionEnabled
        )
        SELECT @SnapshotId, s.name, s.server_id, s.product, s.provider, s.data_source,
            s.location, s.provider_string, s.catalog, s.connect_timeout, s.query_timeout,
            s.is_data_access_enabled, s.is_rpc_out_enabled, s.is_remote_login_enabled,
            s.is_collation_compatible, s.uses_remote_collation, s.lazy_schema_validation,
            s.is_remote_proc_transaction_promotion_enabled
        FROM sys.servers AS s
        WHERE s.server_id <> 0
          AND s.is_linked = 1
          AND (@LinkedServerName IS NULL OR s.name = @LinkedServerName);

        INSERT dbo.DBA_LinkedServerRecoveryLogin
            (SnapshotId, ServerName, LocalPrincipalId, LocalPrincipalName,
             LocalPrincipalType, UsesSelfCredential, RemoteName)
        SELECT @SnapshotId, s.name, ll.local_principal_id, sp.name, sp.type_desc,
            ll.uses_self_credential, ll.remote_name
        FROM sys.linked_logins AS ll
        INNER JOIN sys.servers AS s ON s.server_id = ll.server_id
        LEFT JOIN sys.server_principals AS sp ON sp.principal_id = ll.local_principal_id
        WHERE s.server_id <> 0
          AND s.is_linked = 1
          AND (@LinkedServerName IS NULL OR s.name = @LinkedServerName);

        IF @IncludeDatabasePermissions = 1
        BEGIN
            DECLARE @RepositoryDatabase sysname = DB_NAME();
            DECLARE @DatabaseName sysname;
            DECLARE @Sql nvarchar(max);
            DECLARE DatabaseCursor CURSOR LOCAL FAST_FORWARD FOR
                SELECT name
                FROM sys.databases
                WHERE state_desc = 'ONLINE'
                  AND HAS_DBACCESS(name) = 1
                  AND (@IncludeSystemDatabases = 1 OR database_id > 4);

            OPEN DatabaseCursor;
            FETCH NEXT FROM DatabaseCursor INTO @DatabaseName;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                SET @Sql = N'USE ' + QUOTENAME(@DatabaseName) + N';
                    INSERT INTO ' + QUOTENAME(@RepositoryDatabase) + N'.dbo.DBA_LinkedServerRecoveryPermission
                        (SnapshotId, DatabaseName, PrincipalName, PrincipalType, PermissionState,
                         PermissionName, PermissionClass, SchemaName, ObjectName)
                    SELECT @SnapshotId, DB_NAME(), dpn.name, dpn.type_desc, p.state,
                        p.permission_name, p.class, sch.name, obj.name
                    FROM sys.database_permissions AS p
                    INNER JOIN sys.database_principals AS dpn
                        ON dpn.principal_id = p.grantee_principal_id
                    LEFT JOIN sys.objects AS obj
                        ON obj.object_id = p.major_id AND p.class = 1
                    LEFT JOIN sys.schemas AS sch
                        ON sch.schema_id = CASE WHEN p.class = 3 THEN p.major_id ELSE obj.schema_id END
                    WHERE p.minor_id = 0
                      AND dpn.name IN
                      (
                          SELECT LocalPrincipalName
                          FROM ' + QUOTENAME(@RepositoryDatabase) + N'.dbo.DBA_LinkedServerRecoveryLogin
                          WHERE SnapshotId = @SnapshotId AND LocalPrincipalName IS NOT NULL
                      );';
                BEGIN TRY
                    EXEC sys.sp_executesql @Sql, N'@SnapshotId uniqueidentifier', @SnapshotId;
                END TRY
                BEGIN CATCH
                    PRINT N'Skipped permissions in ' + QUOTENAME(@DatabaseName) + N': ' + ERROR_MESSAGE();
                END CATCH;
                FETCH NEXT FROM DatabaseCursor INTO @DatabaseName;
            END;
            CLOSE DatabaseCursor;
            DEALLOCATE DatabaseCursor;
        END;
    END;

    IF @Action IN ('GENERATE', 'CAPTURE_AND_GENERATE')
    BEGIN
        IF @SnapshotId IS NULL
            SELECT TOP (1) @SnapshotId = SnapshotId
            FROM dbo.DBA_LinkedServerRecoverySnapshot
            ORDER BY CapturedAtUtc DESC;
        IF NOT EXISTS (SELECT 1 FROM dbo.DBA_LinkedServerRecoverySnapshot WHERE SnapshotId = @SnapshotId)
            THROW 51001, 'The requested snapshot does not exist.', 1;

        CREATE TABLE #RecoveryScript (LineNumber int IDENTITY(1,1), ScriptLine nvarchar(max) NOT NULL);
        INSERT #RecoveryScript (ScriptLine) VALUES
            (N'/* Review this generated script. Run it on the target instance as an administrator. */'),
            (N'/* Linked server credentials are intentionally omitted by SQL Server metadata. */'),
            (N'');

        INSERT #RecoveryScript (ScriptLine)
        SELECT N'IF NOT EXISTS (SELECT 1 FROM master.sys.servers WHERE name = N''' + REPLACE(ServerName, '''', '''''') + N''')'
            + N' EXEC master.dbo.sp_addlinkedserver @server=N''' + REPLACE(ServerName, '''', '''''')
            + N''', @srvproduct=' + CASE WHEN Product IS NULL THEN N'NULL' ELSE N'N''' + REPLACE(Product, '''', '''''') + N'''' END
            + N', @provider=' + CASE WHEN Provider IS NULL THEN N'NULL' ELSE N'N''' + REPLACE(Provider, '''', '''''') + N'''' END
            + N', @datasrc=' + CASE WHEN DataSource IS NULL THEN N'NULL' ELSE N'N''' + REPLACE(DataSource, '''', '''''') + N'''' END
            + N', @location=' + CASE WHEN Location IS NULL THEN N'NULL' ELSE N'N''' + REPLACE(Location, '''', '''''') + N'''' END
            + N', @provstr=' + CASE WHEN ProviderString IS NULL THEN N'NULL' ELSE N'N''' + REPLACE(ProviderString, '''', '''''') + N'''' END
            + N', @catalog=' + CASE WHEN Catalog IS NULL THEN N'NULL' ELSE N'N''' + REPLACE(Catalog, '''', '''''') + N'''' END + N';'
        FROM dbo.DBA_LinkedServerRecoveryServer
        WHERE SnapshotId = @SnapshotId;

        INSERT #RecoveryScript (ScriptLine)
        SELECT N'EXEC master.dbo.sp_serveroption @server=N''' + REPLACE(ServerName, '''', '''''')
            + N''', @optname=N''' + OptionName + N''', @optvalue=N''' + OptionValue + N''';'
        FROM dbo.DBA_LinkedServerRecoveryServer AS s
        CROSS APPLY
        (
            VALUES (N'data access', CASE WHEN IsDataAccessEnabled = 1 THEN N'true' ELSE N'false' END),
                   (N'rpc', CASE WHEN IsRemoteLoginEnabled = 1 THEN N'true' ELSE N'false' END),
                   (N'rpc out', CASE WHEN IsRpcOutEnabled = 1 THEN N'true' ELSE N'false' END),
                   (N'collation compatible', CASE WHEN IsCollationCompatible = 1 THEN N'true' ELSE N'false' END),
                   (N'use remote collation', CASE WHEN UsesRemoteCollation = 1 THEN N'true' ELSE N'false' END),
                   (N'lazy schema validation', CASE WHEN LazySchemaValidation = 1 THEN N'true' ELSE N'false' END),
                   (N'remote proc transaction promotion', CASE WHEN IsRemoteProcTransactionPromotionEnabled = 1 THEN N'true' ELSE N'false' END),
                   (N'connect timeout', CONVERT(nvarchar(12), ConnectTimeout)),
                   (N'query timeout', CONVERT(nvarchar(12), QueryTimeout))
        ) Options(OptionName, OptionValue)
        WHERE SnapshotId = @SnapshotId;

        INSERT #RecoveryScript (ScriptLine)
        SELECT CASE WHEN LocalPrincipalId IS NULL THEN N'EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N''' + REPLACE(ServerName, '''', '''''')
                + N''', @useself=N''' + CASE WHEN UsesSelfCredential = 1 THEN N'True' ELSE N'False' END + N''', @locallogin=NULL, @rmtuser='
            ELSE N'EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N''' + REPLACE(ServerName, '''', '''''')
                + N''', @useself=N''' + CASE WHEN UsesSelfCredential = 1 THEN N'True' ELSE N'False' END + N''', @locallogin=N''' + REPLACE(LocalPrincipalName, '''', '''''') + N''', @rmtuser=' END
            + CASE WHEN RemoteName IS NULL THEN N'NULL' ELSE N'N''' + REPLACE(RemoteName, '''', '''''') + N'''' END
            + CASE WHEN UsesSelfCredential = 1 THEN N';'
                ELSE N', @rmtpassword=N''<REPLACE_WITH_SECRET>''; -- Password is not recoverable from metadata.' END
        FROM dbo.DBA_LinkedServerRecoveryLogin
        WHERE SnapshotId = @SnapshotId;

        INSERT #RecoveryScript (ScriptLine) VALUES (N'');
        INSERT #RecoveryScript (ScriptLine)
        SELECT N'USE ' + QUOTENAME(DatabaseName) + N'; ' +
            CASE PermissionState WHEN 'D' THEN N'DENY ' WHEN 'R' THEN N'REVOKE ' ELSE N'GRANT ' END + PermissionName +
            CASE PermissionClass WHEN 0 THEN CASE WHEN PermissionState = 'R' THEN N' FROM ' ELSE N' TO ' END + QUOTENAME(PrincipalName)
                WHEN 3 THEN N' ON SCHEMA::' + QUOTENAME(SchemaName) + CASE WHEN PermissionState = 'R' THEN N' FROM ' ELSE N' TO ' END + QUOTENAME(PrincipalName)
                ELSE N' ON OBJECT::' + QUOTENAME(SchemaName) + N'.' + QUOTENAME(ObjectName) + CASE WHEN PermissionState = 'R' THEN N' FROM ' ELSE N' TO ' END + QUOTENAME(PrincipalName) END
            + CASE WHEN PermissionState = 'W' THEN N' WITH GRANT OPTION;' ELSE N';' END
        FROM dbo.DBA_LinkedServerRecoveryPermission
        WHERE SnapshotId = @SnapshotId;

        SELECT @SnapshotId AS SnapshotId, LineNumber, ScriptLine
        FROM #RecoveryScript
        ORDER BY LineNumber;
    END
    ELSE
        SELECT @SnapshotId AS SnapshotId, COUNT(*) AS LinkedServersCaptured
        FROM dbo.DBA_LinkedServerRecoveryServer
        WHERE SnapshotId = @SnapshotId;
END;
GO