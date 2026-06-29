#!/bin/bash
# 数据库配置更新脚本 - 在 184 机器上执行
# 用法：在 184 机器上运行此脚本

set -euo pipefail

echo "======================================"
echo "更新 minimax-prod-1 fp_slot_limit"
echo "======================================"
echo ""

# 数据库配置
DB_NAME="llm_gateway"
DB_USER="postgres"

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_info "准备更新数据库配置..."
echo ""
echo "目标: credentials 表 (id=6, minimax-prod-1)"
echo "修改: fp_slot_limit 从 25 → 5"
echo ""
read -p "确认执行？(yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    log_warn "操作已取消"
    exit 0
fi

# 执行更新
log_info "执行 SQL 更新..."
psql -U "$DB_USER" -d "$DB_NAME" << 'EOF'
BEGIN;

-- 1. 查看修改前的配置
\echo '=== 修改前 ==='
SELECT 
    id,
    label,
    concurrency_limit,
    fp_slot_limit,
    updated_at
FROM credentials
WHERE id = 6;

-- 2. 执行更新
UPDATE credentials 
SET fp_slot_limit = 5, 
    updated_at = NOW() 
WHERE id = 6;

-- 3. 确认修改后的配置
\echo ''
\echo '=== 修改后 ==='
SELECT 
    id,
    label,
    concurrency_limit,
    fp_slot_limit,
    updated_at
FROM credentials
WHERE id = 6;

-- 4. 提交事务
COMMIT;

\echo ''
\echo '✓ 配置更新成功'
EOF

if [ $? -eq 0 ]; then
    log_info "✓ 数据库配置更新成功"
    echo ""
    log_info "fp_slot_limit 已从 25 更新为 5"
    echo ""
    log_warn "接下来请部署 71 机器的二进制文件"
else
    log_warn "✗ 数据库配置更新失败"
    exit 1
fi
