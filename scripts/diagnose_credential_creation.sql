-- ============================================================================
-- 诊断凭据创建问题的完整检查脚本
-- ============================================================================

\echo '========================================='
\echo '1. 检查序列状态'
\echo '========================================='
SELECT 
    'credentials_id_seq' as sequence_name,
    last_value as current_value,
    (SELECT COALESCE(MAX(id), 0) FROM credentials) as max_table_id,
    CASE 
        WHEN last_value >= (SELECT COALESCE(MAX(id), 0) FROM credentials) 
        THEN '✓ 正常'
        ELSE '✗ 不同步 - 需要修复'
    END as status
FROM credentials_id_seq;

\echo ''
\echo '========================================='
\echo '2. 检查 provider_id = 24 是否存在'
\echo '========================================='
SELECT 
    id, 
    name, 
    provider_type,
    base_url,
    CASE 
        WHEN base_url IS NULL OR base_url = '' 
        THEN '✗ base_url 为空'
        ELSE '✓ base_url: ' || base_url
    END as base_url_status
FROM providers 
WHERE id = 24;

\echo ''
\echo '========================================='
\echo '3. 检查 provider 24 的现有凭据'
\echo '========================================='
SELECT 
    id,
    label,
    status,
    health_status,
    created_at
FROM credentials 
WHERE provider_id = 24
ORDER BY id DESC
LIMIT 10;

\echo ''
\echo '========================================='
\echo '4. 检查是否有重复的 label'
\echo '========================================='
SELECT 
    provider_id,
    tenant_id,
    label,
    COUNT(*) as count
FROM credentials
WHERE provider_id = 24
GROUP BY provider_id, tenant_id, label
HAVING COUNT(*) > 1;

\echo ''
\echo '========================================='
\echo '5. 测试插入（DRY RUN - 会回滚）'
\echo '========================================='
BEGIN;
DO $$
DECLARE
    new_id bigint;
    test_encrypted bytea := '\\x74657374'::bytea;  -- 'test' 的十六进制
BEGIN
    BEGIN
        INSERT INTO credentials (
            provider_id, 
            label, 
            secret_ciphertext, 
            status, 
            concurrency_limit, 
            fp_slot_limit, 
            balance_usd
        )
        VALUES (24, 'test_diagnostic_' || extract(epoch from now())::bigint, test_encrypted, 'active', 10, NULL, 1000.0)
        RETURNING id INTO new_id;
        
        RAISE NOTICE '✓ 测试插入成功! 新 ID: %', new_id;
        RAISE NOTICE '  下一个真实插入应该使用 ID: %', new_id + 1;
    EXCEPTION 
        WHEN unique_violation THEN
            RAISE NOTICE '✗ 唯一性约束冲突:';
            RAISE NOTICE '  错误: %', SQLERRM;
            RAISE NOTICE '  可能原因:';
            RAISE NOTICE '    1. 序列不同步 (credentials_pkey)';
            RAISE NOTICE '    2. label 重复 (credentials_unique_provider_label)';
        WHEN OTHERS THEN
            RAISE NOTICE '✗ 其他错误: %', SQLERRM;
    END;
END $$;
ROLLBACK;

\echo ''
\echo '========================================='
\echo '6. 检查约束定义'
\echo '========================================='
SELECT 
    conname as constraint_name,
    contype as constraint_type,
    pg_get_constraintdef(oid) as definition
FROM pg_constraint
WHERE conrelid = 'credentials'::regclass
  AND conname IN ('credentials_pkey', 'credentials_unique_provider_label', 'credentials_fp_slot_vs_concurrency')
ORDER BY conname;

\echo ''
\echo '========================================='
\echo '7. 检查最近的插入失败（如果有 logs）'
\echo '========================================='
-- 这需要根据你的日志表结构调整
-- SELECT * FROM request_logs WHERE path LIKE '%/credentials' AND status_code = 500 ORDER BY created_at DESC LIMIT 5;

\echo ''
\echo '========================================='
\echo '建议修复步骤:'
\echo '========================================='
\echo '如果序列不同步，执行:'
\echo '  SELECT setval(''credentials_id_seq'', COALESCE((SELECT MAX(id) FROM credentials), 1), true);'
\echo ''
\echo '如果 base_url 错误，执行:'
\echo '  UPDATE providers SET base_url = ''正确的URL'' WHERE id = 24;'
\echo ''
\echo '如果 label 重复，使用不同的 label 或删除旧凭据'
\echo '========================================='
