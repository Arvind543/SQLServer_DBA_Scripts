-----  Created By: Arvind Toorpu
-----  Create Date: 12/04/2024
-----  Details: Below is a stored procedure for SQL Server that identifies and kills sessions (SPIDs) that have been idle for more than one day.
-----  Procedure to Kill Idle Sessions Older Than One Day 

  
CREATE PROCEDURE kill_idle_sessions
AS
  BEGIN
    SET nocount ON;
    -- Temporary table to hold idle sessions
    CREATE TABLE #idlesessions
                 (
                              spid      INT,
                              status    NVARCHAR(50),
                              loginname NVARCHAR(256),
                              lastbatch DATETIME
                 );
    
    -- Insert idle sessions into the temporary table
    INSERT INTO #idlesessions
                (
                            spid,
                            status,
                            loginname,
                            lastbatch
                )
    SELECT spid,
           status,
           loginame,
           last_batch
    FROM   sys.sysprocesses
    WHERE  status = 'sleeping'                       -- Idle sessions
    AND    Datediff(day, last_batch, Getdate()) > 1; -- Idle for more than 1 day
    -- Loop through the sessions and kill them
    DECLARE @SPID INT,
      @Status     NVARCHAR(50),
      @LoginName  NVARCHAR(256),
      @LastBatch  DATETIME;
    DECLARE idlecursor CURSOR FOR
    SELECT spid,
           status,
           loginname,
           lastbatch
    FROM   #idlesessions;
    
    OPEN idlecursor;
    FETCH next
    FROM  idlecursor
    INTO  @SPID,
          @Status,
          @LoginName,
          @LastBatch;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
      PRINT 'Killing SPID: ' + Cast(@SPID AS NVARCHAR) + ', LoginName: ' + @LoginName + ', LastBatch: ' + Cast(@LastBatch AS NVARCHAR);
      BEGIN try
        -- Kill the session
        EXEC('KILL ' + cast(@SPID AS nvarchar));
      END try
      BEGIN catch
        PRINT 'Error occurred while killing SPID: ' + Cast(@SPID AS NVARCHAR) + ' - ' + Error_message();
      END catch;
      FETCH next
      FROM  idlecursor
      INTO  @SPID,
            @Status,
            @LoginName,
            @LastBatch;
    
    END;
    CLOSE idlecursor;
    DEALLOCATE idlecursor;
    -- Clean up the temporary table
    DROP TABLE #idlesessions;
    
    PRINT 'Idle session cleanup complete.';
  END;
GO
