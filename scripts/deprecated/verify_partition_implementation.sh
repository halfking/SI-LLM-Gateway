#!/bin/bash
# ============================================================================
# 分区与归档功能验证脚本
# ============================================================================
# 用途：在测试环境验证所有分区和归档功能是否正常工作
# 使用：./verify_partition_implementation.sh
# ============================================================================

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 数据库连接信息（从环境变量读取）
DB_HOST=${DB_HOST:-localhost}
DB_PORT=${DB_PORT:-5432}
DB_USER=${DB_USER:-postgres}
DB_NAME=${DB_NAME:-llm_gateway}

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# 执行SQL并显示结果
exec_sql() {
    local sql="$1"
    local description="$2"
    
    log_info "执行: $description"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "$sql"
}

# 检查表是否存在
check_table_exists() {
    local table_name="$1"
    local result=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc \
        "SELECT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = '$table_name');")
    
    if [ "$result" = "t" ]; then
        log_success "表存在: $table_name"
        return 0
    else
        log_error "表不存在: $table_name"
        return 1
    fi
}

# 检查函数是否存在
check_function_exists() {
    local func_name="$1"
    local result=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc \
        "SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = '$func_name');")
    
    if [ "$result" = "t" ]; then
        log_success "函数存在: $func_name"
        return 0
    else
        log_error "函数不存在: $func_name"
        return 1
    fi
}

echo "============================================================================"
echo "  分区与归档实施验证脚本"
echo "============================================================================"
echo ""
echo "数据库连接信息:"
echo "  主机: $DB_HOST:$DB_PORT"
echo "  数据库: $DB_NAME"
echo "  用户: $DB_USER"
echo ""
read -p "确认连接信息正确？(y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_error "已取消"
    exit 1
fi

# ============================================================================
# 第1步：检查表结构
# ============================================================================
echo ""
echo "============================================================================"
echo "第1步：检查表结构"
echo "============================================================================"

log_info "检查 routing_decision_log 分区表..."
check_table_exists "routing_decision_log"

log_info "检查 routing_decision_log_archive 归档表..."
check_table_exists "routing_decision_log_archive"

log_info "检查 credential_model_index 主表..."
check_table_exists "credential_model_index"

log_info "检查 credential_model_index_archive 归档表..."
check_table_exists "credential_model_index_archive"

# ============================================================================
# 第2步：检查分区
# ============================================================================
echo ""
echo "============================================================================"
echo "第2步：检查分区状态"
echo "============================================================================"

exec_sql "
SELECT 
    parent.relname as 主表,
    child.relname as 分区名,
    pg_get_expr(child.relpartbound, child.oid) as 分区范围,
    COALESCE(am.amname, 'heap') as 存储类型,
    pg_size_pretty(pg_relation_size(child.oid)) as 大小
FROM pg_inherits
JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON pg_inherits.inhrelid = child.oid
LEFT JOIN pg_am am ON child.relam = am.oid
WHERE parent.relname IN ('routing_decision_log', 'routing_decision_log_archive', 
                          'credential_model_index_archive')
ORDER BY parent.relname, child.relname;
" "查看分区列表"

# ============================================================================
# 第3步：检查归档函数
# ============================================================================
echo ""
echo "============================================================================"
echo "第3步：检查归档函数"
echo "============================================================================"

check_function_exists "archive_routing_decision_log"
check_function_exists "archive_credential_model_index"
check_function_exists "cleanup_old_credential_model_index"
check_function_exists "ensure_next_month_routing_archive_partition"
check_function_exists "ensure_next_month_cmi_archive_partition"
check_function_exists "create_next_month_routing_partitions"

# ============================================================================
# 第4步：插入测试数据
# ============================================================================
echo ""
echo "============================================================================"
echo "第4步：插入测试数据"
echo "============================================================================"

log_info "插入测试数据到 routing_decision_log..."
exec_sql "
INSERT INTO routing_decision_log (
    ts, request_id, model, success, tenant_id
) VALUES 
    (NOW(), gen_random_uuid(), 'gpt-4', true, 'test-tenant'),
    (NOW() - INTERVAL '1 day', gen_random_uuid(), 'gpt-4', true, 'test-tenant'),
    (NOW() - INTERVAL '10 days', gen_random_uuid(), 'claude-3', false, 'test-tenant')
ON CONFLICT DO NOTHING;
" "插入测试数据到 routing_decision_log"

log_info "插入测试数据到 credential_model_index..."
exec_sql "
INSERT INTO credential_model_index (
    bucket, credential_id, raw_model, success_rate, p95_latency_ms
) VALUES 
    (date_trunc('hour', NOW() - NOW()::time), 1, 'gpt-4', 0.95, 500),
    (date_trunc('hour', NOW() - NOW()::time - INTERVAL '1 day'), 1, 'gpt-4', 0.92, 520),
    (date_trunc('hour', NOW() - NOW()::time - INTERVAL '10 days'), 1, 'claude-3', 0.98, 300)
ON CONFLICT (bucket, credential_id, raw_model) DO UPDATE SET
    success_rate = EXCLUDED.success_rate,
    p95_latency_ms = EXCLUDED.p95_latency_ms;
" "插入测试数据到 credential_model_index"

# ============================================================================
# 第5步：测试查询功能
# ============================================================================
echo ""
echo "============================================================================"
echo "第5步：测试查询功能"
echo "============================================================================"

exec_sql "
SELECT 
    'routing_decision_log' as 表名,
    COUNT(*) as 行数,
    MIN(ts) as 最早时间,
    MAX(ts) as 最新时间
FROM routing_decision_log
WHERE tenant_id = 'test-tenant';
" "查询 routing_decision_log"

exec_sql "
SELECT 
    'credential_model_index' as 表名,
    COUNT(*) as 行数,
    MIN(bucket) as 最早bucket,
    MAX(bucket) as 最新bucket
FROM credential_model_index;
" "查询 credential_model_index"

# ============================================================================
# 第6步：测试归档函数（可选）
# ============================================================================
echo ""
echo "============================================================================"
echo "第6步：测试归档函数（可选）"
echo "============================================================================"

read -p "是否测试归档函数？这会移动数据到归档表。(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "测试 cleanup_old_credential_model_index()..."
    exec_sql "SELECT cleanup_old_credential_model_index() as 已删除行数;" "清理旧数据"
    
    log_info "检查是否有上月数据可归档..."
    last_month=$(date -d "last month" +%Y-%m-01)
    
    log_info "尝试归档上月数据: $last_month"
    exec_sql "SELECT * FROM archive_routing_decision_log('$last_month');" "归档 routing_decision_log"
    exec_sql "SELECT * FROM archive_credential_model_index('$last_month');" "归档 credential_model_index"
else
    log_warning "跳过归档函数测试"
fi

# ============================================================================
# 第7步：检查RLS策略
# ============================================================================
echo ""
echo "============================================================================"
echo "第7步：检查RLS策略"
echo "============================================================================"

exec_sql "
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual
FROM pg_policies
WHERE tablename LIKE '%_archive%'
ORDER BY tablename, policyname;
" "查看RLS策略"

# ============================================================================
# 第8步：存储空间统计
# ============================================================================
echo ""
echo "============================================================================"
echo "第8步：存储空间统计"
echo "============================================================================"

exec_sql "
SELECT 
    schemaname || '.' || tablename as 表名,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as 总大小,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as 表大小,
    pg_size_pretty(pg_indexes_size(schemaname||'.'||tablename)) as 索引大小
FROM pg_tables
WHERE tablename IN ('routing_decision_log', 'routing_decision_log_archive',
                     'credential_model_index', 'credential_model_index_archive',
                     'request_logs', 'request_logs_archive')
ORDER BY tablename;
" "存储空间统计"

# ============================================================================
# 第9步：清理测试数据（可选）
# ============================================================================
echo ""
echo "============================================================================"
echo "第9步：清理测试数据（可选）"
echo "============================================================================"

read -p "是否清理测试数据？(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "清理测试数据..."
    exec_sql "DELETE FROM routing_decision_log WHERE tenant_id = 'test-tenant';" "清理 routing_decision_log"
    exec_sql "DELETE FROM credential_model_index WHERE credential_id = 1;" "清理 credential_model_index"
    log_success "测试数据已清理"
else
    log_warning "保留测试数据"
fi

# ============================================================================
# 总结
# ============================================================================
echo ""
echo "============================================================================"
echo "验证完成！"
echo "============================================================================"
echo ""
log_success "所有检查已完成"
echo ""
echo "下一步建议："
echo "  1. 检查应用日志确认 TelemetryArchiver 已启动"
echo "  2. 观察首次月度归档执行（下月1日凌晨2:00）"
echo "  3. 设置监控告警"
echo "  4. 准备生产部署计划"
echo ""
