#!/bin/bash
# 统一诊断脚本
# 合并所有诊断相关脚本

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 加载工具函数
source "$SCRIPT_DIR/utils.sh"

# ==================== 配置变量 ====================
DIAG_TYPE=""
DB_NAME="${DB_NAME:-llm_gateway}"
DATABASE_URL="${DATABASE_URL:-}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-postgres}"

# 71服务器配置
SERVER_71_HOST="${SERVER_71_HOST:-root@14.103.174.71}"
SERVER_71_PORT="${SERVER_71_PORT:-25022}"

# ==================== 显示帮助 ====================
show_usage() {
    cat << EOF
统一诊断脚本

使用方法:
  $0 <DIAG_TYPE> [选项]

诊断类型:
  routing           路由问题诊断和自动修复
  credential        凭据检查诊断
  logs-71           71服务器日志诊断
  redis             Redis路由节点状态检查
  repair            完整修复验证
  all               运行所有诊断

选项:
  --db=NAME         指定数据库名称 (默认: llm_gateway)
  --auto-fix        自动修复发现的问题
  -h, --help        显示此帮助信息

示例:
  # 诊断路由问题
  $0 routing

  # 诊断路由问题并自动修复
  $0 routing --auto-fix

  # 诊断凭据问题
  $0 credential

  # 诊断71服务器日志
  $0 logs-71

  # 检查Redis状态
  $0 redis

环境变量:
  DATABASE_URL      数据库连接URL
  DB_NAME           数据库名称
  DB_HOST           数据库主机
  DB_PORT           数据库端口
  DB_USER           数据库用户

EOF
}

# ==================== 解析参数 ====================
parse_arguments() {
    local AUTO_FIX=false
    
    if [ $# -eq 0 ]; then
        log_error "必须指定诊断类型"
        show_usage
        exit 1
    fi
    
    DIAG_TYPE="$1"
    shift
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --db=*)
                DB_NAME="${1#*=}"
                shift
                ;;
            --auto-fix)
                AUTO_FIX=true
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
    
    export AUTO_FIX
}

# ==================== 路由问题诊断 ====================
diagnose_routing() {
    print_header "路由问题诊断和修复"
    
    # 检查 psql 是否可用
    require_command "psql" "请安装 PostgreSQL 客户端" || exit 1
    
    # 测试数据库连接
    log_step "📊 步骤 1/5: 测试数据库连接..."
    if ! PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
        log_error "无法连接到数据库。请检查连接信息或启动数据库。"
        echo "   数据库: $DB_NAME@$DB_HOST:$DB_PORT"
        echo ""
        echo "💡 如果数据库未启动，可以尝试："
        echo "   brew services start postgresql"
        echo "   或"
        echo "   pg_ctl -D /usr/local/var/postgres start"
        exit 1
    fi
    log_success "数据库连接成功"
    echo ""
    
    # 检查视图是否存在
    log_step "🔍 步骤 2/5: 检查 v_routable_credential_models 视图..."
    VIEW_EXISTS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'v_routable_credential_models';" | tr -d ' ')
    
    if [ "$VIEW_EXISTS" = "0" ]; then
        log_fail "视图不存在！这就是问题所在。"
        
        if [ -f "$PROJECT_ROOT/fix_routing_issue.sql" ]; then
            echo ""
            log_step "📝 正在创建视图..."
            PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$PROJECT_ROOT/fix_routing_issue.sql"
            log_success "视图创建完成"
        else
            log_error "fix_routing_issue.sql 文件不存在"
            exit 1
        fi
    else
        log_success "视图存在"
        
        # 检查可路由节点数量
        echo ""
        log_step "📊 步骤 3/5: 检查可路由节点数量..."
        PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'EOF'
\x on
SELECT 
    COUNT(*) as total_records,
    COUNT(*) FILTER (WHERE is_routable = TRUE) as routable_count,
    COUNT(*) FILTER (WHERE is_routable = FALSE) as not_routable_count,
    COUNT(*) FILTER (WHERE is_routable IS NULL) as null_routable,
    COUNT(DISTINCT credential_id) as unique_credentials,
    COUNT(DISTINCT raw_model_name) as unique_models
FROM v_routable_credential_models
WHERE tenant_id = 'default';
\x off
EOF
        
        ROUTABLE_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM v_routable_credential_models WHERE tenant_id = 'default' AND is_routable = TRUE;" | tr -d ' ')
        
        if [ "$ROUTABLE_COUNT" = "0" ]; then
            echo ""
            log_warn "没有可路由的节点！"
            echo ""
            log_step "📊 步骤 4/5: 分析不可路由原因..."
            PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'EOF'
SELECT 
    COALESCE(unavailable_reason, 'NULL') as reason,
    COUNT(*) as count
FROM v_routable_credential_models
WHERE tenant_id = 'default' AND is_routable = FALSE
GROUP BY unavailable_reason
ORDER BY count DESC
LIMIT 10;
EOF
            
            if [ "$AUTO_FIX" = true ]; then
                echo ""
                log_step "🔧 步骤 5/5: 执行自动修复..."
                PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'EOF'
-- 1. 启用所有 providers
UPDATE providers
SET 
    enabled = TRUE,
    manual_disabled = FALSE
WHERE tenant_id = 'default';

-- 2. 恢复所有 credentials
UPDATE credentials
SET 
    availability_state = 'ready',
    availability_recover_at = NULL,
    quota_state = 'ok',
    quota_recover_at = NULL,
    lifecycle_status = 'active',
    status = 'active',
    circuit_state = 'closed',
    consecutive_failures = 0,
    cooling_until = NULL,
    state_reason_code = NULL,
    state_reason_detail = NULL,
    state_updated_at = now()
WHERE tenant_id = 'default'
AND lifecycle_status != 'archived';

-- 3. 恢复所有 model_offers
UPDATE model_offers mo
SET 
    available = TRUE,
    unavailable_reason = NULL,
    unavailable_at = NULL,
    unavailable_recover_at = NULL
FROM credentials c
WHERE mo.credential_id = c.id
AND c.tenant_id = 'default'
AND COALESCE(mo.unavailable_reason, '') NOT LIKE 'manual%'
AND COALESCE(mo.admin_protected, FALSE) = FALSE;

-- 显示修复结果
SELECT 'Providers updated:' as action, COUNT(*) as count FROM providers WHERE tenant_id = 'default' AND enabled = TRUE
UNION ALL
SELECT 'Credentials updated:', COUNT(*) FROM credentials WHERE tenant_id = 'default' AND availability_state = 'ready'
UNION ALL
SELECT 'Model offers updated:', COUNT(*) FROM model_offers mo JOIN credentials c ON mo.credential_id = c.id WHERE c.tenant_id = 'default' AND mo.available = TRUE;
EOF
                
                echo ""
                log_success "修复完成！正在验证..."
                echo ""
                PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'EOF'
SELECT 
    COUNT(*) FILTER (WHERE is_routable = TRUE) as routable_nodes,
    COUNT(DISTINCT credential_id) as routable_credentials,
    COUNT(DISTINCT raw_model_name) as routable_models
FROM v_routable_credential_models
WHERE tenant_id = 'default';
EOF
                
                echo ""
                log_success "🎉 修复完成！请重启应用以使缓存失效。"
            else
                echo ""
                log_warn "需要自动修复吗？使用 --auto-fix 参数"
            fi
        else
            log_success "找到 $ROUTABLE_COUNT 个可路由节点，路由配置正常"
        fi
    fi
    
    echo ""
    print_separator "="
    log_info "诊断完成"
    print_separator "="
}

# ==================== 凭据检查诊断 ====================
diagnose_credential() {
    print_header "凭据检查ID不匹配问题诊断"
    
    if [ -z "$DATABASE_URL" ]; then
        log_error "DATABASE_URL 环境变量未设置"
        echo "请设置 DATABASE_URL: postgresql://user:password@host:port/dbname"
        exit 1
    fi
    
    log_step "1. 检查 Provider 314 和 35..."
    psql "$DATABASE_URL" -c "
SELECT id, code, display_name, catalog_code, enabled
FROM providers 
WHERE id IN (314, 35)
ORDER BY id;
"
    
    echo ""
    log_step "2. 检查 Credential 2 和 12..."
    psql "$DATABASE_URL" -c "
SELECT id, provider_id, label, status, lifecycle_status
FROM credentials 
WHERE id IN (2, 12)
ORDER BY id;
"
    
    echo ""
    log_step "3. 检查最近的 health_check 任务ID不匹配..."
    psql "$DATABASE_URL" -c "
SELECT 
    id, 
    task_type, 
    provider_id, 
    credential_id, 
    (request_json->>'provider_id')::bigint AS req_pid,
    (request_json->>'credential_id')::bigint AS req_cid,
    status,
    started_at
FROM background_tasks 
WHERE task_type = 'health_check'
  AND ( (request_json->>'provider_id')::bigint IS DISTINCT FROM provider_id
     OR (request_json->>'credential_id')::bigint IS DISTINCT FROM credential_id )
ORDER BY id DESC 
LIMIT 20;
"
    
    echo ""
    log_step "4. 检查所有最近的 health_check 任务..."
    psql "$DATABASE_URL" -c "
SELECT 
    id, 
    provider_id, 
    credential_id, 
    (request_json->>'provider_id')::bigint AS req_pid,
    (request_json->>'credential_id')::bigint AS req_cid,
    status,
    started_at
FROM background_tasks 
WHERE task_type = 'health_check'
ORDER BY id DESC 
LIMIT 10;
"
    
    echo ""
    print_separator "="
    log_info "诊断完成！"
    print_separator "="
    echo ""
    echo "下一步："
    echo "1. 如果 credential 2 属于 provider 35 (不是 314)，前端使用了错误的URL"
    echo "2. 如果 credential 2 属于 provider 314，存在后端路由bug"
    echo "3. 如果出现ID不匹配行，存在INSERT bug"
}

# ==================== 71服务器日志诊断 ====================
diagnose_logs_71() {
    print_header "71服务器日志诊断"
    
    log_info "连接到: ${SERVER_71_HOST}:${SERVER_71_PORT}"
    echo ""
    
    test_ssh_connection "$SERVER_71_HOST" "$SERVER_71_PORT" || exit 1
    
    log_step "执行远程诊断脚本..."
    echo ""
    
    ssh -p "$SERVER_71_PORT" "$SERVER_71_HOST" bash << 'REMOTE_SCRIPT'
echo "=========== 1. 找 PG 容器和凭据 ==========="
docker ps --format 'table {{.Names}}\t{{.Image}}' | grep -iE 'postgres|pg' || true
echo "--- /opt/llm-gateway-go 下的 .env ---"
ls -la /opt/llm-gateway-go/.env* 2>/dev/null || echo "no env file"

echo ""
echo "=========== 2. request_logs 最新数据 ==========="
GW_CTN=$(docker ps --filter "name=gateway" --format "{{.Names}}" | head -1)
PG_CTN=$(docker ps --format '{{.Names}}' | grep -iE 'postgres|^pg_' | head -1)

if [ -n "$PG_CTN" ]; then
    docker exec "$PG_CTN" psql -U postgres -d llm_gateway -c "
      SELECT now() AS db_now,
             MAX(ts) AS latest_request_ts,
             MAX(ts) > now() - interval '5 minutes' AS has_5min_data,
             COUNT(*) FILTER (WHERE ts > now() - interval '1 hour') AS last_1h,
             COUNT(*) FILTER (WHERE ts > now() - interval '5 minutes') AS last_5m
      FROM request_logs;
    " 2>&1 | head -20
fi

echo ""
echo "=========== 3. gateway 日志中的 telemetry 错误 ==========="
if [ -n "$GW_CTN" ]; then
    echo "--- telemetry 错误 ---"
    docker logs --since 10m "$GW_CTN" 2>&1 | grep -iE "telemetry.*failed|dropping|postgres disabled" | tail -20
fi

echo ""
echo "=========== 4. 当前时间对照 ==========="
echo "Host: $(date -u +%FT%TZ)"
if [ -n "$GW_CTN" ]; then
    echo "Gateway: $(docker exec $GW_CTN date -u +%FT%TZ 2>&1)"
fi
REMOTE_SCRIPT
    
    echo ""
    print_separator "="
    log_info "71服务器日志诊断完成"
    print_separator "="
}

# ==================== Redis 诊断 ====================
diagnose_redis() {
    print_header "Redis 路由节点状态检查"
    
    require_command "redis-cli" "请安装 redis-cli" || exit 1
    
    log_step "1️⃣  检查 Redis 连接..."
    test_redis_connection || exit 1
    echo ""
    
    log_step "2️⃣  查找 minimax-m3 的 route_node 键..."
    KEYS=$(redis-cli KEYS "route_node:*:minimax-m3" 2>/dev/null)
    if [ -z "$KEYS" ]; then
        log_success "没有找到 minimax-m3 的 route_node 记录"
        echo "   这意味着该节点从未被标记为不可用"
    else
        log_warn "找到以下 route_node 记录:"
        echo "$KEYS"
        echo ""
        for key in $KEYS; do
            echo "键: $key"
            redis-cli GET "$key" | python3 -m json.tool 2>/dev/null || redis-cli GET "$key"
            echo ""
        done
    fi
    echo ""
    
    log_step "3️⃣  查找所有 minimax 相关的 route_node 键..."
    ALL_MINIMAX=$(redis-cli KEYS "route_node:*:minimax*" 2>/dev/null)
    if [ -z "$ALL_MINIMAX" ]; then
        log_success "没有找到任何 minimax 相关的 route_node 记录"
    else
        echo "找到以下记录:"
        for key in $ALL_MINIMAX; do
            echo "  - $key"
        done
    fi
    echo ""
    
    log_step "4️⃣  查找 credential 10 的所有 route_node 记录..."
    CRED_10=$(redis-cli KEYS "route_node:10:*" 2>/dev/null)
    if [ -z "$CRED_10" ]; then
        log_success "Credential 10 没有任何 route_node 记录"
    else
        echo "找到以下记录:"
        for key in $CRED_10; do
            echo "  键: $key"
            VALUE=$(redis-cli GET "$key")
            echo "  值: $VALUE" | head -c 200
            echo ""
        done
    fi
    echo ""
    
    print_separator "="
    log_info "📊 诊断结论"
    print_separator "="
    echo ""
    echo "如果没有找到 route_node 键："
    echo "  → 节点从未被标记为不可用"
    echo "  → RouteNodeStore.IsUsable() 会返回 true（默认可用）"
    echo ""
    echo "如果找到了该键且包含 Disabled=true："
    echo "  → 需要清除该键或等待冷却时间过期"
    echo "  → 清除命令: redis-cli DEL <key>"
    echo ""
}

# ==================== 完整修复验证 ====================
diagnose_repair() {
    print_header "完整修复验证"
    
    log_step "1️⃣  检查 PostgreSQL 服务..."
    if brew services list | grep -q "postgresql.*started"; then
        log_success "PostgreSQL 服务运行中"
    else
        log_fail "PostgreSQL 服务未运行"
        echo "   运行: brew services start postgresql@15"
        exit 1
    fi
    echo ""
    
    log_step "2️⃣  检查数据库连接..."
    if psql -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
        log_success "数据库连接成功"
    else
        log_fail "无法连接到数据库"
        exit 1
    fi
    echo ""
    
    log_step "3️⃣  检查视图存在..."
    VIEW_EXISTS=$(psql -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM information_schema.views WHERE table_name = 'v_routable_credential_models';" 2>/dev/null | tr -d ' ')
    if [ "$VIEW_EXISTS" = "1" ]; then
        log_success "视图 v_routable_credential_models 存在"
    else
        log_fail "视图不存在"
        exit 1
    fi
    echo ""
    
    log_step "4️⃣  检查可路由节点..."
    ROUTABLE=$(psql -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM v_routable_credential_models WHERE tenant_id = 'default' AND is_routable = TRUE;" 2>/dev/null | tr -d ' ')
    if [ "$ROUTABLE" -gt 0 ]; then
        log_success "找到 $ROUTABLE 个可路由节点"
    else
        log_warn "没有可路由节点（需要添加生产数据）"
    fi
    echo ""
    
    log_step "5️⃣  系统统计..."
    psql -d "$DB_NAME" -c "
SELECT 
    'Providers' as 类型, COUNT(*)::text as 数量 FROM providers
UNION ALL
SELECT 'Credentials', COUNT(*)::text FROM credentials
UNION ALL
SELECT 'Model Offers', COUNT(*)::text FROM model_offers
UNION ALL
SELECT 'Routable Nodes', COUNT(*)::text FROM v_routable_credential_models WHERE tenant_id = 'default' AND is_routable = TRUE;
" 2>/dev/null
    
    echo ""
    print_separator "="
    log_info "📊 验证结果汇总"
    print_separator "="
    if [ "$ROUTABLE" -gt 0 ]; then
        log_success "系统状态: 正常"
        log_success "可路由节点: $ROUTABLE 个"
        log_success "修复状态: 完成"
    else
        log_warn "系统状态: 部分完成"
        log_warn "可路由节点: 0 个（需要添加数据）"
        log_success "修复状态: 基础结构完成"
    fi
}

# ==================== 主函数 ====================
main() {
    parse_arguments "$@"
    
    case "$DIAG_TYPE" in
        routing)
            diagnose_routing
            ;;
        credential)
            diagnose_credential
            ;;
        logs-71)
            diagnose_logs_71
            ;;
        redis)
            diagnose_redis
            ;;
        repair)
            diagnose_repair
            ;;
        all)
            diagnose_routing
            echo ""
            diagnose_credential
            echo ""
            diagnose_redis
            echo ""
            diagnose_repair
            ;;
        *)
            log_error "未知诊断类型: $DIAG_TYPE"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
