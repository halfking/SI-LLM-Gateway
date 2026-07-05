#!/bin/bash

# ============================================================================
# 修复 credentials 表序列不同步问题
# 使用方法：./scripts/fix_credentials_sequence.sh
# ============================================================================

set -e

echo "=== 修复 credentials 表序列不同步问题 ==="
echo ""

# 数据库连接信息（根据实际情况修改）
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-llm_gateway}"
DB_USER="${DB_USER:-postgres}"

echo "正在连接数据库: $DB_NAME@$DB_HOST:$DB_PORT"
echo ""

# 方法1：如果你有 psql 可以直接访问数据库
if command -v psql &> /dev/null; then
    echo "检测到 psql，执行修复..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" <<'SQL'
-- 1. 查看当前状态
DO $$
DECLARE
    max_id bigint;
    seq_val bigint;
BEGIN
    -- 获取表中最大 ID
    SELECT COALESCE(MAX(id), 0) INTO max_id FROM credentials;
    
    -- 获取序列的当前值（不递增）
    SELECT last_value INTO seq_val FROM credentials_id_seq;
    
    RAISE NOTICE '当前表中最大 ID: %', max_id;
    RAISE NOTICE '当前序列值: %', seq_val;
    
    -- 如果序列值小于最大ID，说明需要修复
    IF seq_val < max_id THEN
        RAISE NOTICE '检测到序列不同步！正在修复...';
        PERFORM setval('credentials_id_seq', max_id, true);
        RAISE NOTICE '已将序列重置为: %', max_id;
    ELSE
        RAISE NOTICE '序列状态正常，无需修复';
    END IF;
    
    -- 显示修复后的状态
    SELECT last_value INTO seq_val FROM credentials_id_seq;
    RAISE NOTICE '修复后序列值: %', seq_val;
    RAISE NOTICE '下一个将使用的 ID: %', seq_val + 1;
END $$;
SQL
    
    echo ""
    echo "✓ 修复完成！"
    echo ""
    echo "验证修复结果："
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT last_value as current_seq_value, (SELECT MAX(id) FROM credentials) as max_table_id FROM credentials_id_seq;"
    
else
    echo "未检测到 psql 命令"
    echo ""
    echo "请在 71 服务器上手动执行以下 SQL："
    echo ""
    cat <<'SQL'
-- 快速修复（单行命令）
SELECT setval('credentials_id_seq', COALESCE((SELECT MAX(id) FROM credentials), 1), true);

-- 或者使用完整的诊断和修复脚本
DO $$
DECLARE
    max_id bigint;
    seq_val bigint;
BEGIN
    SELECT COALESCE(MAX(id), 0) INTO max_id FROM credentials;
    SELECT last_value INTO seq_val FROM credentials_id_seq;
    
    RAISE NOTICE '表中最大 ID: %, 序列值: %', max_id, seq_val;
    
    IF seq_val < max_id THEN
        PERFORM setval('credentials_id_seq', max_id, true);
        RAISE NOTICE '已修复：序列重置为 %', max_id;
    END IF;
END $$;
SQL
fi

echo ""
echo "说明："
echo "  - 此脚本将 credentials_id_seq 重置为表中最大 ID 值"
echo "  - 下次插入时将使用 max(id) + 1 作为新 ID"
echo "  - 这是安全操作，不会影响现有数据"
