-----  Below is a stored procedure for SQL Server that identifies and kills sessions (SPIDs) that have been idle for more than one day.
----- Procedure to Kill Idle Sessions Older Than One Day



CREATE PROCEDURE Kill_Idle_Sessions

AS

BEGIN

    SET NOCOUNT ON;



    -- Temporary table to hold idle sessions

    CREATE TABLE #IdleSessions (

        SPID INT,

        Status NVARCHAR(50),

        LoginName NVARCHAR(256),

        LastBatch DATETIME

    );



    -- Insert idle sessions into the temporary table

    INSERT INTO #IdleSessions (SPID, Status, LoginName, LastBatch)

    SELECT spid, status, loginame, last_batch

    FROM sys.sysprocesses

    WHERE status = 'sleeping' -- Idle sessions

      AND DATEDIFF(DAY, last_batch, GETDATE()) > 1; -- Idle for more than 1 day



    -- Loop through the sessions and kill them

    DECLARE @SPID INT, @Status NVARCHAR(50), @LoginName NVARCHAR(256), @LastBatch DATETIME;



    DECLARE IdleCursor CURSOR FOR

        SELECT SPID, Status, LoginName, LastBatch

        FROM #IdleSessions;



    OPEN IdleCursor;



    FETCH NEXT FROM IdleCursor INTO @SPID, @Status, @LoginName, @LastBatch;



    WHILE @@FETCH_STATUS = 0

    BEGIN

        PRINT 'Killing SPID: ' + CAST(@SPID AS NVARCHAR) +

              ', LoginName: ' + @LoginName +

              ', LastBatch: ' + CAST(@LastBatch AS NVARCHAR);



        BEGIN TRY

            -- Kill the session

            EXEC('KILL ' + CAST(@SPID AS NVARCHAR));

        END TRY

        BEGIN CATCH

            PRINT 'Error occurred while killing SPID: ' + CAST(@SPID AS NVARCHAR) + ' - ' + ERROR_MESSAGE();

        END CATCH;



        FETCH NEXT FROM IdleCursor INTO @SPID, @Status, @LoginName, @LastBatch;

    END;



    CLOSE IdleCursor;

    DEALLOCATE IdleCursor;



    -- Clean up the temporary table

    DROP TABLE #IdleSessions;



    PRINT 'Idle session cleanup complete.';

END;

GO



