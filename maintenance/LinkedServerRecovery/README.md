# Linked Server Recovery

Deploy [DBA_LinkedServerRecovery.sql](DBA_LinkedServerRecovery.sql) in a DBA utility database. The script creates a snapshot repository and `dbo.usp_DBA_LinkedServerRecovery`.

Capture the current instance configuration and return a generated recovery script:

```sql
EXEC dbo.usp_DBA_LinkedServerRecovery @Action = 'CAPTURE_AND_GENERATE';
```

Capture only, then generate the latest snapshot later:

```sql
EXEC dbo.usp_DBA_LinkedServerRecovery @Action = 'CAPTURE';
EXEC dbo.usp_DBA_LinkedServerRecovery @Action = 'GENERATE';
```

The snapshot includes linked-server provider settings, server options, all linked-server security mappings, and explicit database permissions for mapped local logins. Set `@IncludeDatabasePermissions = 0` to omit the database scan or `@IncludeSystemDatabases = 1` to include system databases.

SQL Server does not expose linked-server passwords. Mappings that use a remote credential are generated with `&lt;REPLACE_WITH_SECRET&gt;`; replace that value securely before execution. The captured configuration represents outbound linked-server definitions from the source instance. An inbound connection is configured on the remote instance, so capture and restore that instance separately as well.

The procedure only generates statements. Review provider names, data sources, credentials, permissions, and target-server differences before running the output. The caller needs permission to read linked-server metadata and database permissions; generation should be performed by an administrator.