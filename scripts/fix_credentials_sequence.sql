-- ============================================================================
-- 修复 credentials 表序列不同步问题
-- 问题：ERROR: duplicate key value violates unique constraint "credentials_pkey"
-- 原因：序列值小于或等于表中已存在的最大 ID
-- ============================================================================

-- 1. 诊断：检查当前状态
SELECT 
    'Current sequence value' AS info,
    nextval('credentials_id_seq') AS next_val;

SELECT 
    'Max ID in table' AS info,
    COALESCE(MAX(id), 0) AS max_id 
FROM credentials;

-- 2. 修复：将序列重置为表中最大 ID + 1
SELECT setval('credentials_id_seq', COALESCE((SELECT MAX(id) FROM credentials), 1), true);

-- 3. 验证：显示修复后的状态
SELECT 
    'After fix - sequence value' AS info,
    currval('credentials_id_seq') AS current_val,
    nextval('credentials_id_seq') AS next_val;

SELECT 
    'After fix - max ID in table' AS info,
    COALESCE(MAX(id), 0) AS max_id 
FROM credentials;
