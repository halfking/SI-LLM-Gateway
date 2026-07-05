#!/bin/bash

# ============================================================================
# 完整的凭据创建问题诊断和修复脚本
# 使用方法：./scripts/diagnose_and_fix_credentials.sh
# ============================================================================

set -e

echo "=== 凭据创建问题诊断和修复工具 ==="
echo ""

# 数据库连接信息
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-llm_gateway}"
DB_USER="${DB_USER:-postgres}"

echo "数据库: $DB_NAME@$DB_HOST:$DB_PORT"
echo ""

if ! command -v psql &> /dev/null; then
    echo "错误: 未找到 psql 命令"
    echo "请确保 PostgreSQL 客户端已安装"
    exit 1
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "步骤 1: 检查序列状态"
echo "========================================="

RESULT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A -c "
    SELECT 
        CASE 
            WHEN last_value >= (SELECT COALESCE(MAX(id), 0) FROM credentials) 
            THEN 'OK'
            ELSE 'MISMATCH'
        END
    FROM credentials_id_seq;
")

if [ "$RESULT" = "MISMATCH" ]; then
    echo -e "${RED}✗ 序列不同步${NC}"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT 
            last_value as 序列当前值,
            (SELECT MAX(id) FROM credentials) as 表最大ID
        FROM credentials_id_seq;
    "
    
    echo ""
    echo "正在修复序列..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT setval('credentials_id_seq', COALESCE((SELECT MAX(id) FROM credentials), 1), true);
    "
    echo -e "${GREEN}✓ 序列已修复${NC}"
else
    echo -e "${GREEN}✓ 序列状态正常${NC}"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT 
            last_value as 当前序列值,
            (SELECT MAX(id) FROM credentials) as 表最大ID
        FROM credentials_id_seq;
    "
fi

echo ""
echo "========================================="
echo "步骤 2: 检查 Provider 24"
echo "========================================="

PROVIDER_EXISTS=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A -c "
    SELECT COUNT(*) FROM providers WHERE id = 24;
")

if [ "$PROVIDER_EXISTS" = "0" ]; then
    echo -e "${RED}✗ Provider 24 不存在${NC}"
    echo "请先创建 provider 或使用正确的 provider_id"
    exit 1
else
    echo -e "${GREEN}✓ Provider 24 存在${NC}"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT 
            id,
            name as 名称,
            provider_type as 类型,
            COALESCE(base_url, '(未设置)') as base_url,
            CASE 
                WHEN base_url IS NULL OR base_url = '' THEN '需要设置'
                ELSE '已设置'
            END as 状态
        FROM providers 
        WHERE id = 24;
    "
fi

echo ""
echo "========================================="
echo "步骤 3: 检查现有凭据"
echo "========================================="

CRED_COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A -c "
    SELECT COUNT(*) FROM credentials WHERE provider_id = 24;
")

echo "Provider 24 现有凭据数量: $CRED_COUNT"

if [ "$CRED_COUNT" != "0" ]; then
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT 
            id,
            label as 标签,
            status as 状态,
            health_status as 健康状态,
            created_at as 创建时间
        FROM credentials 
        WHERE provider_id = 24
        ORDER BY id DESC
        LIMIT 5;
    "
fi

echo ""
echo "========================================="
echo "步骤 4: 测试插入操作"
echo "========================================="

echo "执行干运行测试（会自动回滚）..."

TEST_RESULT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A -c "
BEGIN;
DO \$\$
DECLARE
    new_id bigint;
    test_label text := 'test_' || extract(epoch from now())::bigint;
BEGIN
    BEGIN
        INSERT INTO credentials (
            provider_id, 
            label, 
            secret_ciphertext, 
            status, 
            concurrency_limit, 
            balance_usd,
            fp_slot_limit
        )
        VALUES (24, test_label, '\\\\x74657374'::bytea, 'active', 10, 1000.0, 5)
        RETURNING id INTO new_id;
        
        RAISE NOTICE 'SUCCESS:%', new_id;
    EXCEPTION 
        WHEN unique_violation THEN
            RAISE NOTICE 'ERROR:unique_violation:%', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'ERROR:other:%', SQLERRM;
    END;
END \$\$;
ROLLBACK;
SELECT 'DONE';
" 2>&1)

if echo "$TEST_RESULT" | grep -q "SUCCESS:"; then
    NEW_ID=$(echo "$TEST_RESULT" | grep "SUCCESS:" | cut -d':' -f2 | tr -d ' ')
    echo -e "${GREEN}✓ 测试插入成功！${NC}"
    echo "  测试使用的 ID: $NEW_ID"
    echo "  下一个真实插入将使用类似的 ID"
elif echo "$TEST_RESULT" | grep -q "unique_violation"; then
    echo -e "${RED}✗ 唯一性约束冲突${NC}"
    ERROR_MSG=$(echo "$TEST_RESULT" | grep "ERROR:" | cut -d':' -f3-)
    echo "  错误详情: $ERROR_MSG"
    
    if echo "$ERROR_MSG" | grep -q "credentials_pkey"; then
        echo -e "${YELLOW}  原因: 主键冲突 - 序列可能仍然不同步${NC}"
    elif echo "$ERROR_MSG" | grep -q "credentials_unique_provider_label"; then
        echo -e "${YELLOW}  原因: label 重复 - 请使用不同的标签${NC}"
    fi
else
    echo -e "${RED}✗ 测试失败${NC}"
    ERROR_MSG=$(echo "$TEST_RESULT" | grep "ERROR:" | cut -d':' -f3-)
    echo "  错误详情: $ERROR_MSG"
fi

echo ""
echo "========================================="
echo "诊断完成"
echo "========================================="
echo ""
echo "下一步操作建议："
echo ""
echo "1. 如果序列已修复且测试成功："
echo "   → 现在可以通过 API 添加凭据"
echo ""
echo "2. 如果 base_url 错误："
echo "   → 修正 provider 的 base_url:"
echo "   UPDATE providers SET base_url = '正确的URL' WHERE id = 24;"
echo ""
echo "3. 如果需要手动添加凭据（用于测试）："
echo "   → 使用 POST /api/providers/24/credentials"
echo "   → 或执行: psql ... -c \"INSERT INTO credentials ...\""
echo ""
echo "4. 修复探活问题："
echo "   → 确保 base_url 正确"
echo "   → 手动触发健康检查: POST /api/providers/24/credentials/{id}/check-health"
echo ""
