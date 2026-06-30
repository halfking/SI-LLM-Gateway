#!/bin/bash
# 综合测试脚本：Minimax-m3 路由和节点状态测试
# 针对两个主要问题：
# 1. 所有节点有效，但路由匹配不到可用节点
# 2. 某个节点失败多次，没有及时从候选节点中移除

set -e

# 配置参数
GATEWAY_URL="${GATEWAY_URL:-https://llm.kxpms.cn}"
API_KEY="${API_KEY:-test-api-key-12345}"
DB_URL="${LLM_GATEWAY_DATABASE_URL}"
MODEL="minimax-m3"
ROUNDS="${ROUNDS:-5}"
REQUESTS_PER_ROUND="${REQUESTS_PER_ROUND:-10}"
DELAY_BETWEEN_ROUNDS="${DELAY_BETWEEN_ROUNDS:-5}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 日志文件
LOG_DIR="./test_logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEST_LOG="$LOG_DIR/minimax_test_${TIMESTAMP}.log"
ROUTING_LOG="$LOG_DIR/routing_state_${TIMESTAMP}.log"
FAILURE_LOG="$LOG_DIR/failures_${TIMESTAMP}.log"

echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}🧪 Minimax-m3 综合路由测试${NC}"
echo -e "${CYAN}=========================================${NC}"
echo -e "Gateway: ${BLUE}$GATEWAY_URL${NC}"
echo -e "Model: ${BLUE}$MODEL${NC}"
echo -e "测试轮数: ${BLUE}$ROUNDS${NC}"
echo -e "每轮请求数: ${BLUE}$REQUESTS_PER_ROUND${NC}"
echo -e "日志目录: ${BLUE}$LOG_DIR${NC}"
echo -e ""

# 辅助函数：记录到日志文件
log_to_file() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$TEST_LOG"
}

# 辅助函数：获取路由候选节点
get_routing_candidates() {
    local round=$1
    echo -e "\n${YELLOW}=== 第 $round 轮：检查路由候选节点 ===${NC}" | tee -a "$ROUTING_LOG"
    log_to_file "Round $round: Checking routing candidates"
    
    CANDIDATES=$(curl -s "$GATEWAY_URL/api/routing/resolve?model=$MODEL" \
        -H "Authorization: Bearer $API_KEY" 2>&1)
    
    if [ $? -eq 0 ]; then
        echo "$CANDIDATES" | jq '.' 2>/dev/null | tee -a "$ROUTING_LOG"
        
        # 检查是否有候选节点
        CANDIDATE_COUNT=$(echo "$CANDIDATES" | jq '.candidates | length' 2>/dev/null)
        if [ "$CANDIDATE_COUNT" = "0" ] || [ "$CANDIDATE_COUNT" = "null" ]; then
            echo -e "${RED}⚠️  警告：没有可用的候选节点！${NC}" | tee -a "$ROUTING_LOG"
            log_to_file "WARNING: No candidates available in round $round"
            return 1
        else
            echo -e "${GREEN}✓ 找到 $CANDIDATE_COUNT 个候选节点${NC}" | tee -a "$ROUTING_LOG"
            log_to_file "Found $CANDIDATE_COUNT candidates in round $round"
        fi
    else
        echo -e "${RED}❌ 无法获取路由信息: $CANDIDATES${NC}" | tee -a "$ROUTING_LOG"
        log_to_file "ERROR: Failed to get routing info in round $round"
        return 1
    fi
}

# 辅助函数：检查数据库中的节点状态
check_db_node_status() {
    local round=$1
    
    if [ -z "$DB_URL" ]; then
        echo -e "${YELLOW}⚠️  未配置数据库URL，跳过数据库检查${NC}"
        return
    fi
    
    echo -e "\n${YELLOW}=== 第 $round 轮：数据库节点状态 ===${NC}" | tee -a "$ROUTING_LOG"
    log_to_file "Round $round: Checking DB node status"
    
    psql "$DB_URL" <<SQL | tee -a "$ROUTING_LOG"
-- 检查 minimax-m3 的所有凭据状态
SELECT 
    c.id as cred_id,
    c.label,
    c.status,
    c.lifecycle_status,
    c.availability_state,
    c.circuit_state,
    v.is_routable,
    v.unavailable_reason,
    mo.available as offer_available,
    mo.manual_priority,
    mo.routing_tier
FROM model_offers mo
JOIN credentials c ON c.id = mo.credential_id
JOIN providers p ON p.id = c.provider_id
LEFT JOIN v_routable_credential_models v
    ON v.credential_id = mo.credential_id
    AND v.raw_model_name = mo.raw_model_name
WHERE p.tenant_id = 'default'
  AND (lower(mo.raw_model_name) = lower('$MODEL') 
       OR lower(mo.standardized_name) = lower('$MODEL'))
ORDER BY c.id;
SQL
}

# 辅助函数：检查最近的失败记录
check_recent_failures() {
    local round=$1
    
    if [ -z "$DB_URL" ]; then
        return
    fi
    
    echo -e "\n${YELLOW}=== 第 $round 轮：检查最近失败记录 ===${NC}" | tee -a "$FAILURE_LOG"
    log_to_file "Round $round: Checking recent failures"
    
    psql "$DB_URL" <<SQL | tee -a "$FAILURE_LOG"
-- 最近5分钟内每个凭据的请求统计
SELECT 
    c.id as credential_id,
    c.label,
    COUNT(*) as total_requests,
    COUNT(CASE WHEN rl.success THEN 1 END) as success_count,
    COUNT(CASE WHEN NOT rl.success THEN 1 END) as failure_count,
    ROUND(COUNT(CASE WHEN rl.success THEN 1 END)::numeric / NULLIF(COUNT(*), 0)::numeric * 100, 1) as success_rate,
    array_agg(DISTINCT rl.error_kind) FILTER (WHERE rl.error_kind IS NOT NULL) as error_types,
    MAX(rl.ts) as last_request_time
FROM request_logs rl
JOIN credentials c ON c.id = rl.credential_id
WHERE lower(rl.client_model) = lower('$MODEL')
  AND rl.ts > NOW() - INTERVAL '5 minutes'
GROUP BY c.id, c.label
ORDER BY failure_count DESC, c.id;

-- 检查是否有"no_candidate"错误
SELECT COUNT(*) as no_candidate_errors
FROM request_logs
WHERE lower(client_model) = lower('$MODEL')
  AND error_kind = 'no_candidate'
  AND ts > NOW() - INTERVAL '5 minutes';
SQL
}

# 辅助函数：发送测试请求
send_test_requests() {
    local round=$1
    local success_count=0
    local failure_count=0
    local no_candidate_count=0
    
    echo -e "\n${CYAN}=== 第 $round 轮：发送 $REQUESTS_PER_ROUND 个测试请求 ===${NC}"
    log_to_file "Round $round: Sending $REQUESTS_PER_ROUND requests"
    
    local start_time=$(date +%s)
    
    for i in $(seq 1 $REQUESTS_PER_ROUND); do
        RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$GATEWAY_URL/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $API_KEY" \
            -d "{
                \"model\":\"$MODEL\",
                \"messages\":[{\"role\":\"user\",\"content\":\"测试请求 Round$round-Req$i: 请用一句话回答什么是AI？\"}],
                \"max_tokens\":50
            }" 2>&1)
        
        HTTP_CODE=$(echo "$RESPONSE" | tail -1)
        BODY=$(echo "$RESPONSE" | head -n -1)
        
        if [ "$HTTP_CODE" = "200" ]; then
            echo -e "${GREEN}✅ 请求 $i: 成功${NC}"
            ((success_count++))
            log_to_file "Round $round, Request $i: SUCCESS"
        else
            ERROR_MSG=$(echo "$BODY" | jq -r '.error.message // .error.type // "unknown"' 2>/dev/null)
            ERROR_TYPE=$(echo "$BODY" | jq -r '.error.type // "unknown"' 2>/dev/null)
            
            if [[ "$ERROR_MSG" == *"no candidate"* ]] || [[ "$ERROR_TYPE" == *"no_candidate"* ]]; then
                echo -e "${RED}❌ 请求 $i: HTTP $HTTP_CODE - 无候选节点！${NC}"
                ((no_candidate_count++))
                log_to_file "Round $round, Request $i: NO_CANDIDATE - $ERROR_MSG"
            else
                echo -e "${RED}❌ 请求 $i: HTTP $HTTP_CODE - $ERROR_MSG${NC}"
                log_to_file "Round $round, Request $i: FAILED - $ERROR_MSG"
            fi
            ((failure_count++))
            
            # 记录失败详情
            echo -e "\n[Round $round, Request $i] HTTP $HTTP_CODE" >> "$FAILURE_LOG"
            echo "$BODY" | jq '.' 2>/dev/null >> "$FAILURE_LOG" || echo "$BODY" >> "$FAILURE_LOG"
        fi
        
        # 每个请求之间短暂延迟
        sleep 0.1
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo -e "\n${MAGENTA}📊 第 $round 轮统计：${NC}"
    echo -e "  成功: ${GREEN}$success_count${NC}"
    echo -e "  失败: ${RED}$failure_count${NC}"
    echo -e "  无候选节点错误: ${RED}$no_candidate_count${NC}"
    echo -e "  耗时: ${CYAN}${duration}秒${NC}"
    
    log_to_file "Round $round Summary: Success=$success_count, Failure=$failure_count, NoCandidates=$no_candidate_count, Duration=${duration}s"
    
    # 如果有"无候选节点"错误，这是严重问题
    if [ $no_candidate_count -gt 0 ]; then
        echo -e "${RED}🚨 检测到问题1：路由匹配不到可用节点！${NC}"
        log_to_file "ISSUE DETECTED: No candidate routing failures in round $round"
    fi
}

# 主测试循环
main() {
    echo -e "${CYAN}开始测试...${NC}\n"
    log_to_file "=== Test Started ==="
    
    # 在测试前检查初始状态
    echo -e "${BLUE}📋 检查初始状态...${NC}"
    get_routing_candidates 0
    check_db_node_status 0
    
    # 执行多轮测试
    for round in $(seq 1 $ROUNDS); do
        echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}🔄 开始第 $round/$ROUNDS 轮测试${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        # 1. 检查路由候选
        get_routing_candidates $round
        
        # 2. 发送测试请求
        send_test_requests $round
        
        # 3. 检查失败记录
        check_recent_failures $round
        
        # 4. 检查节点状态（看是否有节点被正确标记为不可用）
        check_db_node_status $round
        
        # 轮次之间延迟
        if [ $round -lt $ROUNDS ]; then
            echo -e "\n${YELLOW}⏳ 等待 $DELAY_BETWEEN_ROUNDS 秒后开始下一轮...${NC}"
            sleep $DELAY_BETWEEN_ROUNDS
        fi
    done
    
    # 测试完成后的总结
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📊 测试总结${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ -n "$DB_URL" ]; then
        echo -e "\n${YELLOW}=== 整体测试期间的统计 ===${NC}"
        psql "$DB_URL" <<SQL
-- 测试期间的整体统计
SELECT 
    COUNT(*) as total_requests,
    COUNT(CASE WHEN success THEN 1 END) as success_count,
    COUNT(CASE WHEN NOT success THEN 1 END) as failure_count,
    ROUND(COUNT(CASE WHEN success THEN 1 END)::numeric / NULLIF(COUNT(*), 0)::numeric * 100, 1) as success_rate,
    COUNT(CASE WHEN error_kind = 'no_candidate' THEN 1 END) as no_candidate_errors,
    COUNT(DISTINCT credential_id) as credentials_used
FROM request_logs
WHERE lower(client_model) = lower('$MODEL')
  AND ts > NOW() - INTERVAL '10 minutes';

-- 各凭据的表现
SELECT 
    c.id,
    c.label,
    COUNT(*) as requests,
    COUNT(CASE WHEN rl.success THEN 1 END) as success,
    COUNT(CASE WHEN NOT rl.success THEN 1 END) as failures,
    ROUND(COUNT(CASE WHEN rl.success THEN 1 END)::numeric / NULLIF(COUNT(*), 0)::numeric * 100, 1) as success_rate
FROM request_logs rl
JOIN credentials c ON c.id = rl.credential_id
WHERE lower(rl.client_model) = lower('$MODEL')
  AND rl.ts > NOW() - INTERVAL '10 minutes'
GROUP BY c.id, c.label
ORDER BY requests DESC;
SQL
    fi
    
    echo -e "\n${GREEN}✅ 测试完成！${NC}"
    echo -e "${BLUE}📁 日志文件：${NC}"
    echo -e "  - 测试日志: $TEST_LOG"
    echo -e "  - 路由状态: $ROUTING_LOG"
    echo -e "  - 失败详情: $FAILURE_LOG"
    
    log_to_file "=== Test Completed ==="
}

# 执行主函数
main
