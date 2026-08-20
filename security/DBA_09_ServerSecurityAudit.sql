-- =================================================================================
-- Script:      9. Server Security Audit (Logins and Roles)
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: Performs a basic server security audit by listing all logins
--              (both SQL and Windows) and their associated server-level roles
--              (e.g., sysadmin, securityadmin).
-- =================================================================================

SELECT
    sp.name AS LoginName,
    sp.type_desc AS LoginType,
    sp.is_disabled,
    CONVERT(VARCHAR(19), sp.create_date, 120) AS CreateDate,
    CONVERT(VARCHAR(19), sp.modify_date, 120) AS ModifyDate,
    STUFF((
        SELECT ', ' + rp.name
        FROM sys.server_role_members srm
        JOIN sys.server_principals rp ON srm.role_principal_id = rp.principal_id
        WHERE srm.member_principal_id = sp.principal_id
        FOR XML PATH('')
    ), 1, 2, '') AS ServerRoles
FROM
    sys.server_principals AS sp
WHERE
    sp.type IN ('S', 'U', 'G') -- SQL Logins, Windows Users, Windows Groups
    AND sp.principal_id > 1 -- Exclude sa
    AND sp.name NOT LIKE '##%' -- Exclude system-generated principals
ORDER BY
    sp.name;
