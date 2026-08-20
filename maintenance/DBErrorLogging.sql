/*******************************************************************************
    SQL SERVER WEEKLY PARTITIONED ERROR LOGGING SYSTEM
    
    Description: 
    Comprehensive error logging system with weekly table partitioning,
    automatic partition management, and DDL event tracking.
    
    Author: Database Administrator
    Created: 2025-10-22
    Version: 1.0
    
    Components:
    1. Partition Function (Weekly boundaries for 52 weeks)
    2. Partition Scheme (Maps to PRIMARY filegroup)
    3. Partitioned Error Log Table
    4. Manual Error Logging Stored Procedure
    5. Automatic Partition Management Procedure
    6. DDL Trigger for capturing database events
    7. Helper Views and Queries
    
*******************************************************************************/

USE master;
GO

-- Create dedicated database for error logging (optional but recommended)
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'ErrorLogging')
BEGIN
    CREATE DATABASE ErrorLogging;
    PRINT 'ErrorLogging database created successfully.';
END
GO

USE ErrorLogging;
GO

/*******************************************************************************
    SECTION 1: PARTITION FUNCTION
    
    Purpose: Defines the boundary values for weekly partitions
    Strategy: RIGHT RANGE partitioning - each boundary value represents 
              the START of a new partition
*******************************************************************************/

-- Drop existing objects if they exist (for redeployment)
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'DatabaseErrorLog' AND is_ms_shipped = 0)
    DROP TABLE dbo.DatabaseErrorLog;
GO

IF EXISTS (SELECT * FROM sys.partition_schemes WHERE name = 'PS_Weekly')
    DROP PARTITION SCHEME PS_Weekly;
GO

IF EXISTS (SELECT * FROM sys.partition_functions WHERE name = 'PF_Weekly')
    DROP PARTITION FUNCTION PF_Weekly;
GO

PRINT 'Creating partition function for weekly boundaries...';
GO

-- Generate weekly boundary values for the next 52 weeks
DECLARE @SQL NVARCHAR(MAX);
DECLARE @StartDate DATE = CAST(DATEADD(DAY, -DATEPART(WEEKDAY, GETDATE()) + 1, GETDATE()) AS DATE); -- Start of current week (Monday)
DECLARE @WeekCounter INT = 1;
DECLARE @BoundaryValues NVARCHAR(MAX) = '';

-- Build boundary values string
WHILE @WeekCounter <= 52
BEGIN
    SET @BoundaryValues = @BoundaryValues + 
        '''' + CONVERT(VARCHAR(10), DATEADD(WEEK, @WeekCounter, @StartDate), 120) + '''';
    
    IF @WeekCounter < 52
        SET @BoundaryValues = @BoundaryValues + ', ';
    
    SET @WeekCounter = @WeekCounter + 1;
END

-- Create partition function with RIGHT RANGE
SET @SQL = N'
CREATE PARTITION FUNCTION PF_Weekly (DATETIME)
AS RANGE RIGHT FOR VALUES (' + @BoundaryValues + ')';

EXEC sp_executesql @SQL;
PRINT 'Partition function PF_Weekly created with 52 weekly boundaries.';
GO

/*******************************************************************************
    SECTION 2: PARTITION SCHEME
    
    Purpose: Maps partition function ranges to filegroups
    Note: Using PRIMARY filegroup for all partitions (can be modified for
          multiple filegroups for better I/O distribution)
*******************************************************************************/

PRINT 'Creating partition scheme...';
GO

CREATE PARTITION SCHEME PS_Weekly
AS PARTITION PF_Weekly
ALL TO ([PRIMARY]);

PRINT 'Partition scheme PS_Weekly created and mapped to PRIMARY filegroup.';
GO

/*******************************************************************************
    SECTION 3: PARTITIONED ERROR LOG TABLE
    
    Purpose: Stores detailed error information with weekly partitioning
    Partitioning Key: ErrorDate (DATETIME)
*******************************************************************************/

PRINT 'Creating DatabaseErrorLog table...';
GO

CREATE TABLE dbo.DatabaseErrorLog
(
    ErrorID         BIGINT IDENTITY(1,1) NOT NULL,
    ErrorDate       DATETIME NOT NULL DEFAULT GETDATE(),
    ErrorNumber     INT NULL,
    ErrorSeverity   INT NULL,
    ErrorState      INT NULL,
    ErrorProcedure  NVARCHAR(256) NULL,
    ErrorLine       INT NULL,
    ErrorMessage    NVARCHAR(4000) NULL,
    UserName        NVARCHAR(256) NULL,
    HostName        NVARCHAR(256) NULL,
    DatabaseName    NVARCHAR(256) NULL,
    ApplicationName NVARCHAR(256) NULL,
    
    -- Partition key must be part of primary key for partitioned table
    CONSTRAINT PK_DatabaseErrorLog PRIMARY KEY CLUSTERED 
    (
        ErrorID ASC,
        ErrorDate ASC
    )
) ON PS_Weekly(ErrorDate);

PRINT 'DatabaseErrorLog table created with weekly partitioning.';
GO

-- Create non-clustered indexes for common queries
CREATE NONCLUSTERED INDEX IX_DatabaseErrorLog_ErrorDate 
    ON dbo.DatabaseErrorLog(ErrorDate DESC) 
    INCLUDE (ErrorNumber, ErrorMessage, DatabaseName)
    ON PS_Weekly(ErrorDate);

CREATE NONCLUSTERED INDEX IX_DatabaseErrorLog_ErrorNumber 
    ON dbo.DatabaseErrorLog(ErrorNumber, ErrorDate DESC)
    ON PS_Weekly(ErrorDate);

CREATE NONCLUSTERED INDEX IX_DatabaseErrorLog_DatabaseName 
    ON dbo.DatabaseErrorLog(DatabaseName, ErrorDate DESC)
    ON PS_Weekly(ErrorDate);

PRINT 'Non-clustered indexes created on DatabaseErrorLog table.';
GO

/*******************************************************************************
    SECTION 4: STORED PROCEDURE FOR MANUAL ERROR LOGGING
    
    Purpose: Allows manual logging of errors from TRY-CATCH blocks
    Usage: EXEC dbo.usp_LogError
*******************************************************************************/

PRINT 'Creating stored procedure usp_LogError...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_LogError
    @ErrorNumber    INT = NULL,
    @ErrorSeverity  INT = NULL,
    @ErrorState     INT = NULL,
    @ErrorProcedure NVARCHAR(256) = NULL,
    @ErrorLine      INT = NULL,
    @ErrorMessage   NVARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        -- If parameters are not provided, get them from ERROR functions
        DECLARE @ErrNumber INT = ISNULL(@ErrorNumber, ERROR_NUMBER());
        DECLARE @ErrSeverity INT = ISNULL(@ErrorSeverity, ERROR_SEVERITY());
        DECLARE @ErrState INT = ISNULL(@ErrorState, ERROR_STATE());
        DECLARE @ErrProcedure NVARCHAR(256) = ISNULL(@ErrorProcedure, ERROR_PROCEDURE());
        DECLARE @ErrLine INT = ISNULL(@ErrorLine, ERROR_LINE());
        DECLARE @ErrMessage NVARCHAR(4000) = ISNULL(@ErrorMessage, ERROR_MESSAGE());
        
        -- Insert error details into log table
        INSERT INTO dbo.DatabaseErrorLog
        (
            ErrorDate,
            ErrorNumber,
            ErrorSeverity,
            ErrorState,
            ErrorProcedure,
            ErrorLine,
            ErrorMessage,
            UserName,
            HostName,
            DatabaseName,
            ApplicationName
        )
        VALUES
        (
            GETDATE(),
            @ErrNumber,
            @ErrSeverity,
            @ErrState,
            @ErrProcedure,
            @ErrLine,
            @ErrMessage,
            SUSER_SNAME(),
            HOST_NAME(),
            DB_NAME(),
            APP_NAME()
        );
        
        -- Return the ErrorID of the logged error
        RETURN SCOPE_IDENTITY();
        
    END TRY
    BEGIN CATCH
        -- If logging fails, raise error but don't cascade failure
        DECLARE @ErrorMsg NVARCHAR(4000) = 
            'Error in usp_LogError: ' + ERROR_MESSAGE();
        RAISERROR(@ErrorMsg, 10, 1) WITH LOG;
        RETURN -1;
    END CATCH
END
GO

PRINT 'Stored procedure usp_LogError created successfully.';
GO

/*******************************************************************************
    SECTION 5: STORED PROCEDURE FOR AUTOMATIC PARTITION MANAGEMENT
    
    Purpose: Adds new weekly partitions automatically
    Recommendation: Schedule this procedure to run weekly via SQL Agent Job
*******************************************************************************/

PRINT 'Creating stored procedure usp_ManageErrorLogPartitions...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_ManageErrorLogPartitions
    @WeeksToAdd INT = 4  -- Add partitions for next 4 weeks by default
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        DECLARE @SQL NVARCHAR(MAX);
        DECLARE @CurrentMaxBoundary DATETIME;
        DECLARE @NewBoundary DATETIME;
        DECLARE @Counter INT = 1;
        DECLARE @PartitionsAdded INT = 0;
        
        -- Get the current maximum boundary value
        SELECT @CurrentMaxBoundary = MAX(CAST(value AS DATETIME))
        FROM sys.partition_range_values prv
        INNER JOIN sys.partition_functions pf 
            ON prv.function_id = pf.function_id
        WHERE pf.name = 'PF_Weekly';
        
        PRINT 'Current maximum partition boundary: ' + 
              CONVERT(VARCHAR(23), @CurrentMaxBoundary, 121);
        
        -- Add new partitions
        WHILE @Counter <= @WeeksToAdd
        BEGIN
            SET @NewBoundary = DATEADD(WEEK, @Counter, @CurrentMaxBoundary);
            
            -- Split the partition to add new boundary
            SET @SQL = N'ALTER PARTITION SCHEME PS_Weekly NEXT USED [PRIMARY];' + CHAR(13) + CHAR(10);
            SET @SQL = @SQL + N'ALTER PARTITION FUNCTION PF_Weekly() SPLIT RANGE (''' + 
                       CONVERT(VARCHAR(23), @NewBoundary, 121) + ''');';
            
            EXEC sp_executesql @SQL;
            
            PRINT 'Added partition boundary: ' + CONVERT(VARCHAR(23), @NewBoundary, 121);
            SET @PartitionsAdded = @PartitionsAdded + 1;
            SET @Counter = @Counter + 1;
        END
        
        PRINT CAST(@PartitionsAdded AS VARCHAR(10)) + ' new partition(s) added successfully.';
        
        -- Log the partition management activity
        INSERT INTO dbo.DatabaseErrorLog
        (
            ErrorDate,
            ErrorNumber,
            ErrorSeverity,
            ErrorMessage,
            UserName,
            DatabaseName,
            ApplicationName
        )
        VALUES
        (
            GETDATE(),
            0,  -- Custom code for maintenance activity
            0,
            'Partition Management: Added ' + CAST(@PartitionsAdded AS VARCHAR(10)) + 
            ' new weekly partitions. New max boundary: ' + 
            CONVERT(VARCHAR(23), @NewBoundary, 121),
            SUSER_SNAME(),
            DB_NAME(),
            'PartitionManagement'
        );
        
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        
        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
        
        -- Log the error
        EXEC dbo.usp_LogError;
    END CATCH
END
GO

PRINT 'Stored procedure usp_ManageErrorLogPartitions created successfully.';
GO

/*******************************************************************************
    SECTION 6: DDL TRIGGER FOR DATABASE-LEVEL EVENTS
    
    Purpose: Automatically captures DDL events and significant database changes
    Scope: Database-level trigger
*******************************************************************************/

PRINT 'Creating DDL trigger for database events...';
GO

CREATE OR ALTER TRIGGER trg_DDL_DatabaseEvents
ON DATABASE
FOR DDL_DATABASE_LEVEL_EVENTS, DDL_TABLE_VIEW_EVENTS, DDL_PROCEDURE_EVENTS
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        DECLARE @EventData XML = EVENTDATA();
        DECLARE @EventType NVARCHAR(100);
        DECLARE @ObjectName NVARCHAR(256);
        DECLARE @TSQLCommand NVARCHAR(MAX);
        
        -- Extract event information
        SELECT 
            @EventType = @EventData.value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)'),
            @ObjectName = @EventData.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(256)'),
            @TSQLCommand = @EventData.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'NVARCHAR(MAX)');
        
        -- Log the DDL event
        INSERT INTO dbo.DatabaseErrorLog
        (
            ErrorDate,
            ErrorNumber,
            ErrorSeverity,
            ErrorState,
            ErrorProcedure,
            ErrorMessage,
            UserName,
            HostName,
            DatabaseName,
            ApplicationName
        )
        VALUES
        (
            GETDATE(),
            50001,  -- Custom code for DDL events
            10,
            1,
            @ObjectName,
            'DDL Event: ' + @EventType + CHAR(13) + CHAR(10) + 
            'Command: ' + LEFT(@TSQLCommand, 3900),
            SUSER_SNAME(),
            HOST_NAME(),
            DB_NAME(),
            APP_NAME()
        );
        
    END TRY
    BEGIN CATCH
        -- Silently fail to avoid blocking DDL operations
        -- Error is logged to SQL Server error log
        DECLARE @ErrorMsg NVARCHAR(4000) = 
            'Error in DDL trigger: ' + ERROR_MESSAGE();
        EXEC sys.sp_log_event @event_data = @ErrorMsg;
    END CATCH
END
GO

PRINT 'DDL trigger trg_DDL_DatabaseEvents created successfully.';
GO

/*******************************************************************************
    SECTION 7: HELPER VIEW FOR PARTITION INFORMATION
    
    Purpose: Provides easy access to partition statistics
*******************************************************************************/

PRINT 'Creating helper view for partition information...';
GO

CREATE OR ALTER VIEW dbo.vw_PartitionInfo
AS
SELECT 
    pf.name AS PartitionFunction,
    ps.name AS PartitionScheme,
    p.partition_number AS PartitionNumber,
    fg.name AS FileGroupName,
    prv.value AS BoundaryValue,
    CASE pf.boundary_value_on_right
        WHEN 1 THEN 'RIGHT'
        ELSE 'LEFT'
    END AS BoundaryType,
    p.rows AS RowCount,
    au.total_pages * 8 / 1024.0 AS TotalSpaceMB,
    au.used_pages * 8 / 1024.0 AS UsedSpaceMB,
    (au.total_pages - au.used_pages) * 8 / 1024.0 AS FreeSpaceMB
FROM sys.partition_functions pf
INNER JOIN sys.partition_schemes ps 
    ON ps.function_id = pf.function_id
INNER JOIN sys.indexes i 
    ON i.data_space_id = ps.data_space_id
INNER JOIN sys.tables t 
    ON t.object_id = i.object_id
INNER JOIN sys.partitions p 
    ON p.object_id = i.object_id AND p.index_id = i.index_id
INNER JOIN sys.allocation_units au 
    ON au.container_id = p.partition_id
LEFT JOIN sys.partition_range_values prv 
    ON prv.function_id = pf.function_id 
    AND prv.boundary_id = p.partition_number
INNER JOIN sys.destination_data_spaces dds 
    ON dds.partition_scheme_id = ps.data_space_id 
    AND dds.destination_id = p.partition_number
INNER JOIN sys.filegroups fg 
    ON fg.data_space_id = dds.data_space_id
WHERE t.name = 'DatabaseErrorLog'
    AND i.index_id IN (0, 1);
GO

PRINT 'View vw_PartitionInfo created successfully.';
GO

/*******************************************************************************
    SECTION 8: EXAMPLE USAGE WITH TRY-CATCH BLOCK
    
    Demonstrates how to use the error logging system in production code
*******************************************************************************/

PRINT 'Creating example stored procedure with error handling...';
GO

CREATE OR ALTER PROCEDURE dbo.usp_ExampleWithErrorHandling
    @DivideByZero BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        DECLARE @Result INT;
        
        PRINT 'Starting example procedure...';
        
        -- Simulate an error if requested
        IF @DivideByZero = 1
        BEGIN
            SET @Result = 100 / 0;  -- This will cause divide by zero error
        END
        ELSE
        BEGIN
            SET @Result = 100 / 2;
            PRINT 'Calculation successful. Result: ' + CAST(@Result AS VARCHAR(10));
        END
        
    END TRY
    BEGIN CATCH
        -- Log the error using our custom procedure
        EXEC dbo.usp_LogError;
        
        -- Re-throw the error to calling application
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        
        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END
GO

PRINT 'Example stored procedure created successfully.';
GO

/*******************************************************************************
    SECTION 9: QUERY TO VIEW PARTITION INFORMATION
    
    Provides detailed information about partitions and their data distribution
*******************************************************************************/

PRINT '
================================================================================
    DEPLOYMENT COMPLETE
================================================================================

The following objects have been created:

1. Partition Function: PF_Weekly (52 weekly boundaries)
2. Partition Scheme: PS_Weekly
3. Table: dbo.DatabaseErrorLog (partitioned by ErrorDate)
4. Stored Procedure: dbo.usp_LogError
5. Stored Procedure: dbo.usp_ManageErrorLogPartitions
6. Stored Procedure: dbo.usp_ExampleWithErrorHandling
7. DDL Trigger: trg_DDL_DatabaseEvents
8. View: dbo.vw_PartitionInfo

================================================================================
    RECOMMENDED NEXT STEPS
================================================================================

1. Create SQL Agent Job to run usp_ManageErrorLogPartitions weekly
2. Test error logging with: EXEC dbo.usp_ExampleWithErrorHandling @DivideByZero = 1
3. Review partition information with: SELECT * FROM dbo.vw_PartitionInfo
4. Set up alerts for high-severity errors
5. Implement partition archival/cleanup strategy for old data

================================================================================
    EXAMPLE QUERIES
================================================================================
';
GO

-- Query 1: View all partition information
PRINT 'Query 1: View partition information:';
GO

SELECT * FROM dbo.vw_PartitionInfo
ORDER BY PartitionNumber;
GO

-- Query 2: View recent errors
PRINT '
Query 2: View recent errors (last 24 hours):';
GO

SELECT TOP 100
    ErrorID,
    ErrorDate,
    ErrorNumber,
    ErrorSeverity,
    ErrorMessage,
    ErrorProcedure,
    DatabaseName,
    UserName
FROM dbo.DatabaseErrorLog
WHERE ErrorDate >= DATEADD(HOUR, -24, GETDATE())
ORDER BY ErrorDate DESC;
GO

-- Query 3: Error summary by database
PRINT '
Query 3: Error summary by database:';
GO

SELECT 
    DatabaseName,
    COUNT(*) AS ErrorCount,
    MIN(ErrorDate) AS FirstError,
    MAX(ErrorDate) AS LastError,
    COUNT(DISTINCT ErrorNumber) AS UniqueErrors
FROM dbo.DatabaseErrorLog
WHERE ErrorDate >= DATEADD(DAY, -7, GETDATE())
GROUP BY DatabaseName
ORDER BY ErrorCount DESC;
GO

-- Query 4: Partition statistics
PRINT '
Query 4: Partition statistics:';
GO

SELECT 
    PartitionNumber,
    CONVERT(VARCHAR(10), BoundaryValue, 120) AS WeekStartDate,
    RowCount,
    CAST(UsedSpaceMB AS DECIMAL(10,2)) AS UsedSpaceMB,
    CASE 
        WHEN RowCount > 0 
        THEN CAST((UsedSpaceMB * 1024.0) / RowCount AS DECIMAL(10,4))
        ELSE 0 
    END AS AvgKBPerRow
FROM dbo.vw_PartitionInfo
ORDER BY PartitionNumber;
GO

-- Query 5: Test error logging
PRINT '
Query 5: Test error logging (run this to generate a test error):';
PRINT 'EXEC dbo.usp_ExampleWithErrorHandling @DivideByZero = 1;';
GO

/*******************************************************************************
    MAINTENANCE SCRIPT: Add New Partitions
    
    Run this periodically (e.g., weekly via SQL Agent Job)
*******************************************************************************/
PRINT '
================================================================================
    MAINTENANCE COMMANDS
================================================================================

-- Add 4 weeks of new partitions:
EXEC dbo.usp_ManageErrorLogPartitions @WeeksToAdd = 4;

-- View partition distribution:
SELECT * FROM dbo.vw_PartitionInfo ORDER BY PartitionNumber;

-- Archive old partitions (example - modify as needed):
-- Step 1: Switch old partition to staging table
-- Step 2: Compress or archive staging table data
-- Step 3: Merge empty partition boundary

/*
Example: Merge oldest partition (after archiving data)
DECLARE @OldestBoundary DATETIME;
SELECT TOP 1 @OldestBoundary = CAST(value AS DATETIME)
FROM sys.partition_range_values prv
INNER JOIN sys.partition_functions pf ON prv.function_id = pf.function_id
WHERE pf.name = ''PF_Weekly''
ORDER BY prv.boundary_id;

ALTER PARTITION FUNCTION PF_Weekly() MERGE RANGE (@OldestBoundary);
*/

================================================================================
    MONITORING QUERIES
================================================================================

-- Check for errors in the last hour:
SELECT ErrorNumber, COUNT(*) AS ErrorCount
FROM dbo.DatabaseErrorLog
WHERE ErrorDate >= DATEADD(HOUR, -1, GETDATE())
    AND ErrorNumber > 0
GROUP BY ErrorNumber
ORDER BY ErrorCount DESC;

-- Check partition health:
SELECT 
    PartitionNumber,
    BoundaryValue,
    RowCount,
    UsedSpaceMB
FROM dbo.vw_PartitionInfo
WHERE RowCount > 1000000  -- Alert if partition exceeds 1M rows
ORDER BY PartitionNumber;

================================================================================
';
GO

PRINT 'All scripts completed successfully!';
PRINT 'Database: ErrorLogging';
PRINT 'Use the example queries above to test the system.';
GO