-- =================================================================================
-- Script:      16. Database Configuration Best Practices Check
-- Author:      Arvind Toorpu
-- Date:        2024-06-27
-- Description: Audits databases for common configuration settings that deviate from
--              best practices, such as AUTO_SHRINK, AUTO_CLOSE, and PAGE_VERIFY
--              options that are not CHECKSUM.
-- =================================================================================

SELECT
    name AS DatabaseName,
    CASE is_auto_close_on
        WHEN 1 THEN 'Yes - BAD'
        ELSE 'No - GOOD'
    END AS IsAutoCloseOn,
    CASE is_auto_shrink_on
        WHEN 1 THEN 'Yes - BAD'
        ELSE 'No - GOOD'
    END AS IsAutoShrinkOn,
    CASE page_verify_option_desc
        WHEN 'CHECKSUM' THEN 'CHECKSUM - GOOD'
        ELSE page_verify_option_desc + ' - BAD'
    END AS PageVerifyOption,
    CASE compatibility_level
        WHEN 150 THEN 'SQL 2019 - OK'
        WHEN 140 THEN 'SQL 2017 - OK'
        WHEN 130 THEN 'SQL 2016 - OK'
        ELSE CAST(compatibility_level AS VARCHAR(10)) + ' - Consider upgrading'
    END AS CompatibilityLevel
FROM
    sys.databases
WHERE
    database_id > 4; -- Exclude system databases
