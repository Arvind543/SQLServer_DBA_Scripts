
## Kill Idle Sessions Procedure

## Key Details

### 1. How It Works
- The procedure queries `sys.sysprocesses` to find sessions (SPID) that are **sleeping** and have not executed a query (`last_batch`) in over a day.
- It uses a **temporary table** to store the idle sessions and a **cursor** to iterate over them.
- Each idle session is terminated using the `KILL` command.

---

### 2. Logging
- Logs details of the sessions being killed, including:
  - `SPID`
  - `LoginName`
  - `LastBatch`

---

### 3. Error Handling
- Catches and logs any errors that occur during the `KILL` operation for problematic sessions.

---

### 4. Custom Conditions
- Modify the `WHERE` clause in the query to filter by specific users or applications if needed.
- Example: Add a filter like:

```sql
  AND loginame = 'YourLoginName'
  ```

---

### 5. Test Before Execution
- Run the query manually to verify which sessions will be killed:
  ```sql
  SELECT spid, status, loginame, last_batch
  FROM sys.sysprocesses
  WHERE status = 'sleeping'
  AND DATEDIFF(DAY, last_batch, GETDATE()) > 1;
  ```

---

### 6. Execution
- Execute the procedure using:
  ```sql
  EXEC Kill_Idle_Sessions;
  ```

---

### 7. Permissions
- Ensure the user executing this procedure has the required `KILL` permissions.
```

