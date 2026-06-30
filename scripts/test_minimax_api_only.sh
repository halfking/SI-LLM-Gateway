#!/usr/bin/env bash
# Minimax-m3 API层面测试（不需要数据库连接）
# 专注于检测：
# 1. 路由匹配失败问题
# 2. 节点切换问题

set -e

# 配置参数
GATEWAY_URL="${GATEWAY_URL:-https://llm.kxpms.cn}"
API_KEY="${API_KEY:-sk-1vH6C2I9pywyvUXaUXj4vdMZbeYVE5VB0fBYVgqA97JrltE9}"
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
NC='\033[0m'

# 日志文件
LOG_DIR="./test_logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEST_LOG="$LOG_DIR/minimax_api_test_${TIMESTAMP}.log"
DETAIL_LOG="$LOG_DIR/minimax_details_${TIMESTAMP}.log"

echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}🧪 Minimax-m3 API路由测试${NC}"
echo -e "${CYAN}=========================================${NC}"
echo -e "Gateway: ${BLUE}$GATEWAY_URL${NC}"
echo -e "Model: ${BLUE}$MODEL${NC}"
echo -e "测试轮数: ${BLUE}$ROUNDS${NC}"
echo -e "每轮请求数: ${BLUE}$REQUESTS_PER_ROUND${NC}"
echo -e "日志目录: ${BLUE}$LOG_DIR${NC}"
echo ""

# 统计变量（使用普通变量避免bash版本兼容问题）
TOTAL_SUCCESS=0
TOTAL_FAILURE=0
TOTAL_NO_CANDIDATE=0
TOTAL_TIMEOUT=0
TOTAL_OTHER_ERROR=0

# 记录到日志
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$TEST_LOG"
}

# 获取路由信息（可选，如果无权限则跳过）
check_routing() {
    local round=$1
    echo -e "\n${YELLOW}=== 第 $round 轮：检查路由候选 ===${NC}"
    log_msg "Round $round: Checking routing candidates"
    
    local response=$(curl -s -w "\n%{http_code}" "$GATEWAY_URL/api/routing/resolve?model=$MODEL" \
        -H "Authorization: Bearer $API_KEY" 2>&1)
    
    local http_code=$(echo "$response" | grep -o '[0-9]\{3\}$' || echo "000")
    local body=$(echo "$response" | grep -v '^[0-9]\{3\}$')
    
    if [ "$http_code" = "200" ]; then
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        
        local candidate_count=$(echo "$body" | jq '.candidates | length' 2>/dev/null)
        if [ "$candidate_count" = "0" ] || [ "$candidate_count" = "null" ]; then
            echo -e "${RED}⚠️  警告：没有可用的候选节点！${NC}"
            log_msg "WARNING: No routing candidates available"
            return 1
        else
            echo -e "${GREEN}✓ 找到 $candidate_count 个候选节点${NC}"
            
            # 尝试提取候选节点信息
            echo "$body" | jq -r '.candidates[] | "  - \(.credential_id // .id): \(.label // "unknown") (priority: \(.priority // "N/A"))"' 2>/dev/null || true
            
            log_msg "Found $candidate_count candidates"
            return 0
        fi
    elif [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
        echo -e "${YELLOW}⚠️  路由API无权限访问，跳过路由检查（将通过实际请求测试路由）${NC}"
        log_msg "INFO: Routing API not accessible (auth required), will test via actual requests"
        return 0
    else
        echo -e "${RED}❌ 无法获取路由信息 (HTTP $http_code)${NC}"
        echo "$body"
        log_msg "ERROR: Failed to get routing info - HTTP $http_code"
        return 1
    fi
}

# 发送单个测试请求
send_request() {
    local round=$1
    local req_num=$2
    
    local response=$(curl -s -w "\nHTTP_CODE:%{http_code}\nTIME_TOTAL:%{time_total}" -X POST "$GATEWAY_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $API_KEY" \
        --max-time 30 \
        -d "{
            \"model\":\"$MODEL\",
            \"messages\":[{\"role\":\"user\",\"content\":\"测试 R${round}-${req_num}: 用一句话解释什么是人工智能？\"}],
            \"max_tokens\":50
        }" 2>&1)
    
    local time_total=$(echo "$response" | grep "^TIME_TOTAL:" | cut -d: -f2)
    local http_code=$(echo "$response" | grep "^HTTP_CODE:" | cut -d: -f2)
    local body=$(echo "$response" | grep -v "^HTTP_CODE:\|^TIME_TOTAL:")
    
    # 记录详细响应
    echo -e "\n[Round $round, Request $req_num] HTTP $http_code, Time: ${time_total}s" >> "$DETAIL_LOG"
    echo "$body" >> "$DETAIL_LOG"
    
    if [ "$http_code" = "200" ]; then
        # 尝试提取模型和使用的凭据信息
        local model_used=$(echo "$body" | jq -r '.model // "unknown"' 2>/dev/null)
        local choice_text=$(echo "$body" | jq -r '.choices[0].message.content // "empty"' 2>/dev/null | head -c 50)
        
        echo -e "${GREEN}✅ [$req_num] 成功 (${time_total}s, model: $model_used)${NC}"
        log_msg "Round $round, Req $req_num: SUCCESS - ${time_total}s"
        return 0
    else
        local error_msg=$(echo "$body" | jq -r '.error.message // .message // "unknown"' 2>/dev/null)
        local error_type=$(echo "$body" | jq -r '.error.type // .error.code // "unknown"' 2>/dev/null)
        
        # 检测错误类型
        if [[ "$error_msg" == *"no candidate"* ]] || [[ "$error_type" == *"no_candidate"* ]]; then
            echo -e "${RED}❌ [$req_num] 无候选节点 (HTTP $http_code)${NC}"
            log_msg "Round $round, Req $req_num: NO_CANDIDATE - $error_msg"
            return 2
        elif [[ "$http_code" == "000" ]] || [[ "$error_msg" == *"timeout"* ]]; then
            echo -e "${RED}❌ [$req_num] 超时 (${time_total}s)${NC}"
            log_msg "Round $round, Req $req_num: TIMEOUT"
            return 3
        else
            echo -e "${RED}❌ [$req_num] 失败 (HTTP $http_code): $error_msg${NC}"
            log_msg "Round $round, Req $req_num: ERROR - $error_type - $error_msg"
            return 1
        fi
    fi
}

# 执行一轮测试
run_round() {
    local round=$1
    local round_success=0
    local round_failure=0
    local round_no_candidate=0
    local round_timeout=0
    
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}🔄 第 $round/$ROUNDS 轮测试${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 检查路由
    check_routing $round
    local routing_check=$?
    
    # 发送请求
    echo -e "\n${BLUE}📤 发送 $REQUESTS_PER_ROUND 个请求...${NC}"
    local start_time=$(date +%s)
    
    for i in $(seq 1 $REQUESTS_PER_ROUND); do
        send_request $round $i
        local result=$?
        
        case $result in
            0) ((round_success++)); ((TOTAL_SUCCESS++));;
            2) ((round_no_candidate++)); ((TOTAL_NO_CANDIDATE++)); ((round_failure++));;
            3) ((round_timeout++)); ((TOTAL_TIMEOUT++)); ((round_failure++));;
            *) ((round_failure++)); ((TOTAL_OTHER_ERROR++));;
        esac
        
        # 小延迟避免过快
        sleep 0.2
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 轮次统计
    echo -e "\n${MAGENTA}📊 第 $round 轮统计：${NC}"
    echo -e "  ✅ 成功: ${GREEN}$round_success${NC} / $REQUESTS_PER_ROUND"
    echo -e "  ❌ 失败: ${RED}$round_failure${NC}"
    
    if [ $round_no_candidate -gt 0 ]; then
        echo -e "  ${RED}🚨 无候选节点: $round_no_candidate${NC}"
    fi
    if [ $round_timeout -gt 0 ]; then
        echo -e "  ⏱️  超时: $round_timeout"
    fi
    
    echo -e "  ⏱️  耗时: ${CYAN}${duration}秒${NC}"
    
    local success_rate=0
    if [ $REQUESTS_PER_ROUND -gt 0 ]; then
        success_rate=$((round_success * 100 / REQUESTS_PER_ROUND))
    fi
    echo -e "  📈 成功率: ${success_rate}%"
    
    # 问题检测
    if [ $routing_check -ne 0 ] && [ $round_no_candidate -gt 0 ]; then
        echo -e "\n${RED}🚨 检测到问题1：路由无候选节点，且请求确实失败！${NC}"
        log_msg "CRITICAL: Problem 1 detected - No routing candidates and requests failing"
    fi
    
    if [ $round_failure -gt $((REQUESTS_PER_ROUND / 2)) ]; then
        echo -e "\n${RED}🚨 警告：超过50%的请求失败，可能是问题2（节点未及时切换）${NC}"
        log_msg "WARNING: >50% failures - possible Problem 2 (node not removed)"
    fi
}

# 主函数
main() {
    log_msg "=== Test Started ==="
    echo -e "${BLUE}🚀 开始测试...${NC}\n"
    
    # 初始状态检查
    echo -e "${BLUE}📋 检查初始路由状态...${NC}"
    check_routing 0
    
    # 执行多轮测试
    for round in $(seq 1 $ROUNDS); do
        run_round $round
        
        # 轮次之间延迟
        if [ $round -lt $ROUNDS ]; then
            echo -e "\n${YELLOW}⏳ 等待 $DELAY_BETWEEN_ROUNDS 秒...${NC}"
            sleep $DELAY_BETWEEN_ROUNDS
        fi
    done
    
    # 最终统计
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📊 测试总结${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local total_requests=$((ROUNDS * REQUESTS_PER_ROUND))
    local total_success=$TOTAL_SUCCESS
    local total_failure=$((TOTAL_NO_CANDIDATE + TOTAL_TIMEOUT + TOTAL_OTHER_ERROR))
    
    echo -e "\n总请求数: $total_requests"
    echo -e "✅ 成功: ${GREEN}$total_success${NC}"
    echo -e "❌ 失败: ${RED}$total_failure${NC}"
    echo -e "   - 无候选节点: $TOTAL_NO_CANDIDATE"
    echo -e "   - 超时: $TOTAL_TIMEOUT"
    echo -e "   - 其他错误: $TOTAL_OTHER_ERROR"
    
    if [ $total_requests -gt 0 ]; then
        local overall_success_rate=$((total_success * 100 / total_requests))
        echo -e "\n📈 总体成功率: ${overall_success_rate}%"
        
        if [ $overall_success_rate -lt 80 ]; then
            echo -e "${RED}⚠️  成功率低于80%，建议检查节点状态${NC}"
        fi
    fi
    
    echo -e "\n${BLUE}📁 日志文件：${NC}"
    echo -e "  - 测试日志: $TEST_LOG"
    echo -e "  - 详细响应: $DETAIL_LOG"
    
    echo -e "\n${GREEN}✅ 测试完成${NC}"
    log_msg "=== Test Completed ==="
    
    # 检查是否需要在71服务器上查看详细日志
    echo -e "\n${YELLOW}💡 后续步骤：${NC}"
    echo -e "1. 在71服务器上查看 request_logs:"
    echo -e "   ${CYAN}tail -f /path/to/request_logs${NC}"
    echo -e "2. 查看服务端日志:"
    echo -e "   ${CYAN}journalctl -u llm-gateway -f${NC} (或相应的日志命令)"
    echo -e "3. 运行数据库诊断（在71服务器上）:"
    echo -e "   ${CYAN}./scripts/diagnose_routing_issue.sh minimax-m3${NC}"
}

# 执行
main
