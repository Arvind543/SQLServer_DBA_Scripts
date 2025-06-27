-- =================================================================================
-- Script:      13. Database User Permissions Audit
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: Provides a detailed report of all explicit user and role permissions
--              granted on objects within the current database. Excellent for
--              security auditing and ensuring the principle of least privilege.
-- =================================================================================

SELECT
    dp.permission_name,
    dp.state_desc, -- GRANT, DENY, etc.
    obj.type_desc AS ObjectType,
    sch.name AS SchemaName,
    obj.name AS ObjectName,
    prin.name AS PrincipalName, -- User or Role
    prin.type_desc AS PrincipalType
FROM
    sys.database_permissions AS dp
JOIN
    sys.objects AS obj ON dp.major_id = obj.object_id
JOIN
    sys.schemas AS sch ON obj.schema_id = sch.schema_id
JOIN
    sys.database_principals AS prin ON dp.grantee_principal_id = prin.principal_id
WHERE
    prin.principal_id > 4 -- Exclude system principals
ORDER BY
    PrincipalName,
    SchemaName,
    ObjectName;

