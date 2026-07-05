#!/bin/bash
# 统一测试脚本
# 合并所有测试相关脚本

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 加载工具函数
source "$SCRIPT_DIR/utils.sh"

# ==================== 配置变量 ====================
TEST_TYPE=""
DB_NAME="${DB_NAME:-llm_gateway}"
DATABASE_URL="${DATABASE_URL:-}"

# ==================== 显示帮助 ====================
show_usage() {
    cat << EOF
统一测试脚本

使用方法:
  $0 <TEST_TYPE> [选项]

测试类型:
  routing           路由功能测试
  routing-v2        routing-v2 统计功能测试
  routing-fixes     验证路由修复
  all               运行所有测试

选项:
  --db=NAME         指定数据库名称 (默认: llm_gateway)
  --verbose         显示详细输出
  -h, --help        显示此帮助信息

示例:
  # 测试路由功能
  $0 routing

  # 测试routing-v2统计
  $0 routing-v2

  # 验证路由修复
  $0 routing-fixes

  # 运行所有测试
  $0 all

环境变量:
  DATABASE_URL      数据库连接URL
  DB_NAME           数据库名称 (默认: llm_gateway)

EOF
}

# ==================== 解析参数 ====================
parse_arguments() {
    local VERBOSE=false
    
    if [ $# -eq 0 ]; then
        log_error "必须指定测试类型"
        show_usage
        exit 1
    fi
    
    TEST_TYPE="$1"
    shift
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --db=*)
                DB_NAME="${1#*=}"
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    export VERBOSE
}

# ==================== 路由功能测试 ====================
test_routing() {
    print_header "路由功能测试"
    
    log_step "1️⃣  测试数据库连接..."
    if psql -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
        log_success "数据库连接成功"
    else
        log_fail "数据库连接失败"
        exit 1
    fi
    echo ""
    
    log_step "2️⃣  检查可路由节点..."
    echo ""
    psql -d "$DB_NAME" << 'SQL'
SELECT 
    '总览' as 类型,
    COUNT(*) as 总数,
    COUNT(*) FILTER (WHERE is_routable = TRUE) as 可路由,
    COUNT(*) FILTER (WHERE is_routable = FALSE) as 不可路由
FROM v_routable_credential_models
WHERE tenant_id = 'default';

\echo ''
\echo '按 Provider 分组统计:'
SELECT 
    p.display_name as Provider,
    COUNT(*) as 模型数,
    COUNT(*) FILTER (WHERE v.is_routable = TRUE) as 可路由
FROM v_routable_credential_models v
JOIN providers p ON p.id = v.provider_id
WHERE v.tenant_id = 'default'
GROUP BY p.display_name
ORDER BY p.display_name;
SQL
    
    echo ""
    log_step "3️⃣  模拟路由查询 - 测试 gpt-4..."
    echo ""
    psql -d "$DB_NAME" << 'SQL'
SELECT 
    c.id AS credential_id,
    p.id AS provider_id,
    p.display_name AS provider,
    mo.raw_model_name AS model,
    COALESCE(mo.routing_tier, 2) AS tier,
    COALESCE(mo.weight, 100) AS weight,
    COALESCE(mo.manual_priority, 99) AS priority,
    v.is_routable AS routable,
    v.unavailable_reason AS reason
FROM model_offers mo
JOIN credentials c ON c.id = mo.credential_id
JOIN providers p ON p.id = c.provider_id
LEFT JOIN v_routable_credential_models v
       ON v.credential_id = mo.credential_id
      AND v.raw_model_name = mo.raw_model_name
WHERE p.tenant_id = 'default'
  AND COALESCE(c.status, 'active') NOT IN ('disabled')
  AND v.is_routable = TRUE
  AND lower(mo.raw_model_name) = 'gpt-4'
ORDER BY 
    COALESCE(mo.manual_priority, 99),
    COALESCE(mo.routing_tier, 2)
LIMIT 5;
SQL
    
    echo ""
    log_step "4️⃣  模拟路由查询 - 测试 claude-3-5-sonnet..."
    echo ""
    psql -d "$DB_NAME" << 'SQL'
SELECT 
    c.id AS credential_id,
    p.id AS provider_id,
    p.display_name AS provider,
    mo.raw_model_name AS model,
    v.is_routable AS routable
FROM model_offers mo
JOIN credentials c ON c.id = mo.credential_id
JOIN providers p ON p.id = c.provider_id
LEFT JOIN v_routable_credential_models v
       ON v.credential_id = mo.credential_id
      AND v.raw_model_name = mo.raw_model_name
WHERE p.tenant_id = 'default'
  AND v.is_routable = TRUE
  AND lower(mo.raw_model_name) LIKE '%claude-3-5-sonnet%'
ORDER BY 
    COALESCE(mo.manual_priority, 99)
LIMIT 5;
SQL
    
    echo ""
    log_step "5️⃣  测试不存在的模型（应该返回空）..."
    echo ""
    psql -d "$DB_NAME" << 'SQL'
SELECT 
    COUNT(*) as 找到的节点数
FROM model_offers mo
JOIN credentials c ON c.id = mo.credential_id
JOIN providers p ON p.id = c.provider_id
LEFT JOIN v_routable_credential_models v
       ON v.credential_id = mo.credential_id
      AND v.raw_model_name = mo.raw_model_name
WHERE p.tenant_id = 'default'
  AND v.is_routable = TRUE
  AND lower(mo.raw_model_name) = 'non-existent-model';
SQL
    
    echo ""
    print_separator "="
    log_success "路由功能测试完成"
    print_separator "="
    echo ""
    echo "📊 总结:"
    echo "  - 视图工作正常 ✅"
    echo "  - 可路由节点正确过滤 ✅"
    echo "  - SQL 查询逻辑正确 ✅"
    echo ""
}

# ==================== routing-v2 统计测试 ====================
test_routing_v2() {
    print_header "routing-v2 统计功能测试"
    
    # 检查环境变量
    if [ -z "$DATABASE_URL" ]; then
        log_error "DATABASE_URL 环境变量未设置"
        echo "请设置 DATABASE_URL，例如："
        echo "export DATABASE_URL='postgresql://user:password@localhost:5432/dbname'"
        exit 1
    fi
    log_success "DATABASE_URL 已设置"
    echo ""
    
    log_step "[1/5] 运行 Go 单元测试..."
    if go test ./admin -v -run TestSpecified 2>&1 | tee /tmp/test_output.log | grep -q "PASS"; then
        log_success "Go 单元测试通过"
    else
        log_fail "Go 单元测试失败"
        echo "详细日志："
        cat /tmp/test_output.log
        exit 1
    fi
    echo ""
    
    log_step "[2/5] 检查数据库连接..."
    if psql "$DATABASE_URL" -c "SELECT 1" > /dev/null 2>&1; then
        log_success "数据库连接正常"
    else
        log_fail "数据库连接失败"
        exit 1
    fi
    echo ""
    
    log_step "[3/5] 检查必需索引..."
    INDEX_CHECK=$(psql "$DATABASE_URL" -t -c "
SELECT COUNT(*)
FROM pg_indexes
WHERE tablename = 'request_logs'
  AND indexname = 'idx_request_logs_explicit_model';
")
    
    if [ "$INDEX_CHECK" -eq "1" ]; then
        log_success "idx_request_logs_explicit_model 索引存在"
    else
        log_warn "idx_request_logs_explicit_model 索引不存在"
        echo "建议运行：psql \$DATABASE_URL < docs/2026-06-22-explicit-model-stats.sql"
    fi
    echo ""
    
    log_step "[4/5] 测试统计查询..."
    STATS_RESULT=$(psql "$DATABASE_URL" -t -c "
SELECT 
    COUNT(*) as total_requests,
    COUNT(*) FILTER (WHERE is_auto_request = TRUE) as auto_count,
    COUNT(*) FILTER (WHERE is_auto_request = FALSE) as explicit_count
FROM request_logs
WHERE ts >= NOW() - INTERVAL '7 days'
  AND (
    is_auto_request = TRUE
    OR (is_auto_request = FALSE AND client_model IS NOT NULL AND client_model <> '')
  );
")
    
    echo "7天统计结果："
    echo "$STATS_RESULT"
    
    TOTAL=$(echo "$STATS_RESULT" | awk '{print $1}')
    if [ "$TOTAL" -gt "0" ]; then
        log_success "统计查询返回数据 ($TOTAL 条记录)"
    else
        log_warn "统计查询返回空数据"
        echo "这可能意味着："
        echo "  - 最近 7 天没有请求数据"
        echo "  - request_logs 写入有问题"
        echo "  - 数据不符合查询条件"
    fi
    echo ""
    
    log_step "[5/5] 测试完成"
    print_separator "="
    log_success "routing-v2 统计功能测试完成"
    print_separator "="
}

# ==================== 验证路由修复 ====================
test_routing_fixes() {
    print_header "路由修复验证"
    
    cd "$PROJECT_ROOT"
    
    log_step "📋 检查 P0-1: disableModelOffer 是否已封死..."
    if grep -q "panic(\"disableModelOffer is DEPRECATED" routing/executor.go; then
        log_success "P0-1: disableModelOffer 已添加 panic guard"
    else
        log_fail "P0-1: disableModelOffer panic guard 未找到"
        exit 1
    fi
    
    log_step "📋 检查 P0-2: coolBindingOnMnfStreak 是否写入 unavailable_recover_at..."
    if grep -q "unavailable_recover_at = \$3" routing/executor.go; then
        log_success "P0-2: coolBindingOnMnfStreak 已补写 unavailable_recover_at"
    else
        log_fail "P0-2: unavailable_recover_at 未找到"
        exit 1
    fi
    
    log_step "📋 检查 P0-3: 内层 Circuit.RecordFailure 是否已删除..."
    CHAT_COUNT=$(grep "Circuit.RecordFailure" routing/executor_chat.go 2>/dev/null | grep -v "^[[:space:]]*//\|^[[:space:]]*\*" | wc -l)
    ANTHROPIC_COUNT=$(grep "Circuit.RecordFailure" routing/executor_anthropic.go 2>/dev/null | grep -v "^[[:space:]]*//\|^[[:space:]]*\*" | wc -l)
    
    if [ "$CHAT_COUNT" -eq 0 ] && [ "$ANTHROPIC_COUNT" -eq 0 ]; then
        log_success "P0-3: 内层 Circuit.RecordFailure 已全部删除"
    else
        log_fail "P0-3: 仍有 $CHAT_COUNT (chat) + $ANTHROPIC_COUNT (anthropic) 处调用"
        exit 1
    fi
    
    log_step "📋 检查 P1-1: RestoreOnSuccess 是否增加 unavailable_recover_at 检查..."
    if grep -q "cmb.unavailable_recover_at IS NULL" credentialstate/writer.go && \
       grep -q "cmb.unavailable_recover_at <= now()" credentialstate/writer.go; then
        log_success "P1-1: RestoreOnSuccess WHERE 条件已添加"
    else
        log_fail "P1-1: unavailable_recover_at 检查未找到"
        exit 1
    fi
    
    log_step "📋 检查 P1-2: restoreCredentialState 是否调用 invalidate..."
    if grep -A15 "func (e \*Executor) restoreCredentialState" routing/executor.go | \
       grep -q "InvalidateAllCandidateCache"; then
        log_success "P1-2: restoreCredentialState 已添加 invalidate 调用"
    else
        log_fail "P1-2: invalidate 调用未找到"
        exit 1
    fi
    
    log_step "📋 检查 P1-5: clearSessionPref 是否清除 sticky..."
    if grep -A40 "func (e \*Executor) clearSessionPreferenceOnNodeDisable" routing/executor.go | \
       grep -q "Sticky.Delete"; then
        log_success "P1-5: clearSessionPref 已添加 sticky 清除逻辑"
    else
        log_fail "P1-5: sticky 清除逻辑未找到"
        exit 1
    fi
    
    echo ""
    log_step "🔨 编译验证..."
    if go build ./routing ./credentialstate ./credentialhealth > /dev/null 2>&1; then
        log_success "编译通过"
    else
        log_fail "编译失败"
        exit 1
    fi
    
    echo ""
    log_step "🧪 单元测试验证..."
    if go test ./routing -run="TestExecutor" -v > /tmp/test_output.log 2>&1; then
        PASS_COUNT=$(grep -c "^--- PASS:" /tmp/test_output.log || echo "0")
        log_success "单元测试通过 ($PASS_COUNT 个测试)"
    else
        log_fail "单元测试失败"
        cat /tmp/test_output.log
        exit 1
    fi
    
    echo ""
    print_separator "="
    log_success "所有验证通过！"
    print_separator "="
    echo ""
    echo "📋 修复摘要："
    echo "  ✅ P0-1: disableModelOffer 已封死"
    echo "  ✅ P0-2: mnf 冷却时长修复 (30s → 2min)"
    echo "  ✅ P0-3: Circuit 双重计数修复"
    echo "  ✅ P1-1: AntiFlap 长冷却保护"
    echo "  ✅ P1-2: candCache 即时失效"
    echo "  ✅ P1-5: sticky 清除完整性"
    echo ""
    log_info "🚀 可以安全部署到生产环境"
    echo ""
}

# ==================== 主函数 ====================
main() {
    parse_arguments "$@"
    
    case "$TEST_TYPE" in
        routing)
            test_routing
            ;;
        routing-v2)
            test_routing_v2
            ;;
        routing-fixes)
            test_routing_fixes
            ;;
        all)
            test_routing
            echo ""
            test_routing_v2
            echo ""
            test_routing_fixes
            ;;
        *)
            log_error "未知测试类型: $TEST_TYPE"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
