/* Run in the database containing DBA_AutoTablePartitioning.sql objects. */
IF DATABASE_PRINCIPAL_ID(N'PartitionMaintenanceOperator') IS NULL
    CREATE ROLE PartitionMaintenanceOperator AUTHORIZATION dbo;
GO
GRANT SELECT, INSERT, UPDATE ON dbo.DBA_PartitionMaintenanceConfig TO PartitionMaintenanceOperator;
GRANT SELECT, INSERT ON dbo.DBA_PartitionMaintenanceHistory TO PartitionMaintenanceOperator;
GRANT EXECUTE ON dbo.usp_DBA_RegisterPartitionedTable TO PartitionMaintenanceOperator;
GRANT EXECUTE ON dbo.usp_DBA_ConvertTableToPartitioned TO PartitionMaintenanceOperator;
GRANT EXECUTE ON dbo.usp_DBA_AddPartitionBoundaries TO PartitionMaintenanceOperator;
GRANT EXECUTE ON dbo.usp_DBA_RemoveOldPartitions TO PartitionMaintenanceOperator;
GRANT EXECUTE ON dbo.usp_DBA_UpdateTableStatistics TO PartitionMaintenanceOperator;
GRANT EXECUTE ON dbo.usp_DBA_MaintainTableIndexes TO PartitionMaintenanceOperator;
GRANT EXECUTE ON dbo.usp_DBA_MaintainTablePartitions TO PartitionMaintenanceOperator;
GRANT VIEW DATABASE STATE TO PartitionMaintenanceOperator;
GRANT ALTER ANY DATASPACE TO PartitionMaintenanceOperator;
GO
/* Grant per configured object after review:
GRANT ALTER ON OBJECT::dbo.YourTable TO PartitionMaintenanceOperator;
GRANT ALTER ON OBJECT::dbo.YourEmptySwitchTarget TO PartitionMaintenanceOperator;
GRANT ALTER ON PARTITION FUNCTION::YourPartitionFunction TO PartitionMaintenanceOperator;
GRANT ALTER ON PARTITION SCHEME::YourPartitionScheme TO PartitionMaintenanceOperator;
GRANT VIEW DATABASE STATE TO PartitionMaintenanceOperator;
*/