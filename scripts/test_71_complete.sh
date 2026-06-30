#!/usr/bin/env bash
# 在71服务器上执行的完整测试套件
# 包括：API测试 + 数据库诊断

set -e

# 配置
GATEWAY_URL="${GATEWAY_URL:-https://llm.kxpms.cn}"
API_KEY1="sk-1R7IBh2THq1Id2BDWOWHstpFu2oG09Qd1kgYn9hasxFcKZw7"
API_KEY2="sk-1vH6C2I9pywyvUXaUXj4vdMZbeYVE5VB0fBYVgqA97JrltE9"
API_KEY="${API_KEY:-$API_KEY1}"
MODEL="minimax-m3"
TEST_ROUNDS=3
REQUESTS_PER_ROUND=5

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# 日志
LOG_DIR="./test_logs_71"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MAIN_LOG="$LOG_DIR/test_${TIMESTAMP}.log"

echo -e "${CYAN}=========================================${NC}" | tee -a "$MAIN_LOG"
echo -e "${CYAN}🧪 71服务器完整测试套件${NC}" | tee -a "$MAIN_LOG"
echo -e "${CYAN}=========================================${NC}" | tee -a "$MAIN_LOG"
echo -e "Gateway: ${BLUE}$GATEWAY_URL${NC}" | tee -a "$MAIN_LOG"
echo -e "Model: ${BLUE}$MODEL${NC}" | tee -a "$MAIN_LOG"
echo -e "测试轮数: ${BLUE}$TEST_ROUNDS${NC}" | tee -a "$MAIN_LOG"
echo -e "时间戳: ${BLUE}$TIMESTAMP${NC}" | tee -a "$MAIN_LOG"
echo "" | tee -a "$MAIN_LOG"

# 检测数据库连接
echo -e "${YELLOW}📊 检查数据库连接...${NC}" | tee -a "$MAIN_LOG"
if [ -z "$LLM_GATEWAY_DATABASE_URL" ]; then
    echo -e "${YELLOW}⚠️  LLM_GATEWAY_DATABASE_URL 未设置，尝试从环境中查找...${NC}" | tee -a "$MAIN_LOG"
    
    # 尝试从常见位置查找
    if [ -f "/etc/systemd/system/llm-gateway.service" ]; then
        echo "从 systemd 服务文件查找..." | tee -a "$MAIN_LOG"
        DB_FROM_SERVICE=$(grep -oP 'LLM_GATEWAY_DATABASE_URL=\K[^\s]+' /etc/systemd/system/llm-gateway.service 2>/dev/null || echo "")
        if [ -n "$DB_FROM_SERVICE" ]; then
            export LLM_GATEWAY_DATABASE_URL="$DB_FROM_SERVICE"
            echo -e "${GREEN}✓ 找到数据库配置${NC}" | tee -a "$MAIN_LOG"
        fi
    fi
    
    if [ -z "$LLM_GATEWAY_DATABASE_URL" ]; then
        echo -e "${YELLOW}⚠️  无法自动检测数据库，将只进行 API 测试${NC}" | tee -a "$MAIN_LOG"
        HAS_DB=false
    else
        HAS_DB=true
    fi
else
    HAS_DB=true
    echo -e "${GREEN}✓ 数据库连接已配置${NC}" | tee -a "$MAIN_LOG"
fi

# 统计变量
TOTAL_SUCCESS=0
TOTAL_FAILURE=0
TOTAL_EMPTY_RESPONSE=0
TOTAL_NO_CANDIDATE=0
TOTAL_TIMEOUT=0
TOTAL_OTHER_ERROR=0

# API测试函数
test_api() {
    local round=$1
    local req_num=$2
    local api_key=$3
    
    echo -e "${BLUE}[R${round}-${req_num}]${NC} 发送请求..." | tee -a "$MAIN_LOG"
    
    local start_time=$(date +%s)
    local response=$(curl -s -w "\nHTTP_CODE:%{http_code}\nTIME_TOTAL:%{time_total}" \
        -X POST "$GATEWAY_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $api_key" \
        --max-time 35 \
        -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"测试R${round}-${req_num}: 简单回答，什么是AI？\"}],\"max_tokens\":30}" 2>&1)
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 从curl获取实际时间（秒），转换为毫秒显示
    local time_total=$(echo "$response" | grep "^TIME_TOTAL:" | cut -d: -f2)
    local duration_display="${duration}s"
    if [ -n "$time_total" ]; then
        # time_total 是秒，例如 1.234
        duration_display="${time_total}s"
    fi
    
    local http_code=$(echo "$response" | grep "^HTTP_CODE:" | cut -d: -f2)
    local body=$(echo "$response" | grep -v "^HTTP_CODE:\|^TIME_TOTAL:")
    
    # 保存详细响应
    echo "=== Round $round, Request $req_num ===" >> "$LOG_DIR/responses_${TIMESTAMP}.log"
    echo "HTTP Code: $http_code" >> "$LOG_DIR/responses_${TIMESTAMP}.log"
    echo "Duration: ${duration_display}" >> "$LOG_DIR/responses_${TIMESTAMP}.log"
    echo "Body: $body" >> "$LOG_DIR/responses_${TIMESTAMP}.log"
    echo "" >> "$LOG_DIR/responses_${TIMESTAMP}.log"
    
    if [ "$http_code" = "200" ]; then
        local model_used=$(echo "$body" | jq -r '.model // "unknown"' 2>/dev/null)
        local content=$(echo "$body" | jq -r '.choices[0].message.content // ""' 2>/dev/null)
        local tokens=$(echo "$body" | jq -r '.usage.total_tokens // 0' 2>/dev/null)
        
        if [ -z "$content" ] || [ "$content" = "null" ] || [ "$content" = "" ]; then
            echo -e "${RED}❌ [R${round}-${req_num}] Empty Response! (${duration_display}, model: $model_used)${NC}" | tee -a "$MAIN_LOG"
            ((TOTAL_EMPTY_RESPONSE++))
            ((TOTAL_FAILURE++))
            return 2
        else
            echo -e "${GREEN}✅ [R${round}-${req_num}] 成功 (${duration_display}, tokens: $tokens)${NC}" | tee -a "$MAIN_LOG"
            ((TOTAL_SUCCESS++))
            return 0
        fi
    else
        local error_msg=$(echo "$body" | jq -r '.error.message // .message // "unknown"' 2>/dev/null)
        local error_type=$(echo "$body" | jq -r '.error.type // "unknown"' 2>/dev/null)
        
        if [[ "$error_msg" == *"no candidate"* ]] || [[ "$error_type" == *"no_candidate"* ]]; then
            echo -e "${RED}❌ [R${round}-${req_num}] 无候选节点 (${duration_display})${NC}" | tee -a "$MAIN_LOG"
            ((TOTAL_NO_CANDIDATE++))
            ((TOTAL_FAILURE++))
            return 3
        elif [[ "$http_code" == "000" ]] || [ ${duration%.*} -gt 34 ]; then
            echo -e "${RED}❌ [R${round}-${req_num}] 超时 (${duration_display})${NC}" | tee -a "$MAIN_LOG"
            ((TOTAL_TIMEOUT++))
            ((TOTAL_FAILURE++))
            return 4
        else
            echo -e "${RED}❌ [R${round}-${req_num}] 失败 HTTP $http_code: $error_msg (${duration_display})${NC}" | tee -a "$MAIN_LOG"
            ((TOTAL_OTHER_ERROR++))
            ((TOTAL_FAILURE++))
            return 1
        fi
    fi
}

# 执行测试轮次
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$MAIN_LOG"
echo -e "${CYAN}🔄 开始 API 测试${NC}" | tee -a "$MAIN_LOG"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$MAIN_LOG"

for round in $(seq 1 $TEST_ROUNDS); do
    echo -e "\n${MAGENTA}=== 第 $round/$TEST_ROUNDS 轮 ===${NC}" | tee -a "$MAIN_LOG"
    
    for req in $(seq 1 $REQUESTS_PER_ROUND); do
        # 交替使用两个 API key
        if [ $((req % 2)) -eq 0 ]; then
            test_api $round $req "$API_KEY2"
        else
            test_api $round $req "$API_KEY1"
        fi
        sleep 0.3
    done
    
    echo "" | tee -a "$MAIN_LOG"
    sleep 2
done

# API测试总结
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$MAIN_LOG"
echo -e "${CYAN}📊 API 测试总结${NC}" | tee -a "$MAIN_LOG"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$MAIN_LOG"

TOTAL_REQUESTS=$((TEST_ROUNDS * REQUESTS_PER_ROUND))
echo -e "\n总请求数: $TOTAL_REQUESTS" | tee -a "$MAIN_LOG"
echo -e "✅ 成功: ${GREEN}$TOTAL_SUCCESS${NC}" | tee -a "$MAIN_LOG"
echo -e "❌ 失败: ${RED}$TOTAL_FAILURE${NC}" | tee -a "$MAIN_LOG"
echo -e "   ${RED}⚠️  Empty Response: $TOTAL_EMPTY_RESPONSE${NC}" | tee -a "$MAIN_LOG"
echo -e "   - 无候选节点: $TOTAL_NO_CANDIDATE" | tee -a "$MAIN_LOG"
echo -e "   - 超时: $TOTAL_TIMEOUT" | tee -a "$MAIN_LOG"
echo -e "   - 其他错误: $TOTAL_OTHER_ERROR" | tee -a "$MAIN_LOG"

if [ $TOTAL_REQUESTS -gt 0 ]; then
    SUCCESS_RATE=$((TOTAL_SUCCESS * 100 / TOTAL_REQUESTS))
    EMPTY_RATE=$((TOTAL_EMPTY_RESPONSE * 100 / TOTAL_REQUESTS))
    echo -e "\n成功率: ${SUCCESS_RATE}%" | tee -a "$MAIN_LOG"
    echo -e "Empty Response 比例: ${EMPTY_RATE}%" | tee -a "$MAIN_LOG"
fi

# 数据库诊断
if [ "$HAS_DB" = true ]; then
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$MAIN_LOG"
    echo -e "${CYAN}🔍 数据库诊断${NC}" | tee -a "$MAIN_LOG"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$MAIN_LOG"
    
    echo -e "\n${YELLOW}1. 最近10分钟的请求统计${NC}" | tee -a "$MAIN_LOG"
    psql "$LLM_GATEWAY_DATABASE_URL" <<SQL | tee -a "$MAIN_LOG"
SELECT 
    COUNT(*) as total,
    COUNT(*) FILTER (WHERE success) as success,
    COUNT(*) FILTER (WHERE error_kind = 'empty_response') as empty_response,
    COUNT(*) FILTER (WHERE error_kind = 'no_candidate') as no_candidate,
    ROUND(AVG(duration_ms), 0) as avg_duration_ms
FROM request_logs
WHERE lower(client_model) = lower('$MODEL')
  AND ts > NOW() - INTERVAL '10 minutes';
SQL

    echo -e "\n${YELLOW}2. 各凭据的表现${NC}" | tee -a "$MAIN_LOG"
    psql "$LLM_GATEWAY_DATABASE_URL" <<SQL | tee -a "$MAIN_LOG"
SELECT 
    c.id,
    c.label,
    COUNT(*) as requests,
    COUNT(*) FILTER (WHERE rl.success) as success,
    COUNT(*) FILTER (WHERE rl.error_kind = 'empty_response') as empty_resp,
    ROUND(AVG(rl.duration_ms), 0) as avg_ms
FROM request_logs rl
JOIN credentials c ON c.id = rl.credential_id
WHERE lower(rl.client_model) = lower('$MODEL')
  AND rl.ts > NOW() - INTERVAL '10 minutes'
GROUP BY c.id, c.label
ORDER BY requests DESC;
SQL

    echo -e "\n${YELLOW}3. Empty Response 响应时间分析${NC}" | tee -a "$MAIN_LOG"
    psql "$LLM_GATEWAY_DATABASE_URL" <<SQL | tee -a "$MAIN_LOG"
SELECT 
    COUNT(*) as count,
    ROUND(AVG(duration_ms), 0) as avg_ms,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_ms), 0) as median_ms,
    MIN(duration_ms) as min_ms,
    MAX(duration_ms) as max_ms
FROM request_logs
WHERE error_kind = 'empty_response'
  AND lower(client_model) = lower('$MODEL')
  AND ts > NOW() - INTERVAL '10 minutes';
SQL

    echo -e "\n${YELLOW}4. 路由候选节点状态${NC}" | tee -a "$MAIN_LOG"
    psql "$LLM_GATEWAY_DATABASE_URL" <<SQL | tee -a "$MAIN_LOG"
SELECT 
    c.id,
    c.label,
    c.status,
    c.availability_state,
    c.circuit_state,
    v.is_routable,
    v.unavailable_reason
FROM credentials c
JOIN providers p ON p.id = c.provider_id
JOIN model_offers mo ON mo.credential_id = c.id
LEFT JOIN v_routable_credential_models v 
    ON v.credential_id = c.id AND v.raw_model_name = mo.raw_model_name
WHERE p.tenant_id = 'default'
  AND (lower(mo.raw_model_name) = lower('$MODEL') 
       OR lower(mo.standardized_name) = lower('$MODEL'))
ORDER BY c.id;
SQL
fi

echo -e "\n${GREEN}✅ 测试完成${NC}" | tee -a "$MAIN_LOG"
echo -e "${BLUE}📁 日志保存在: $LOG_DIR${NC}" | tee -a "$MAIN_LOG"

# 问题提示
if [ $TOTAL_EMPTY_RESPONSE -gt 0 ]; then
    echo -e "\n${RED}🚨 检测到 Empty Response 问题！${NC}" | tee -a "$MAIN_LOG"
    echo -e "${YELLOW}建议：${NC}" | tee -a "$MAIN_LOG"
    echo -e "1. 查看响应详情: cat $LOG_DIR/responses_${TIMESTAMP}.log" | tee -a "$MAIN_LOG"
    echo -e "2. 运行深度诊断: ./scripts/diagnose_nvidia_nim_empty_response.sh" | tee -a "$MAIN_LOG"
    echo -e "3. 检查服务端日志获取更多信息" | tee -a "$MAIN_LOG"
fi

if [ $TOTAL_NO_CANDIDATE -gt 0 ]; then
    echo -e "\n${RED}🚨 检测到路由无候选节点问题！${NC}" | tee -a "$MAIN_LOG"
    echo -e "${YELLOW}建议：${NC}" | tee -a "$MAIN_LOG"
    echo -e "1. 检查上面的路由候选节点状态" | tee -a "$MAIN_LOG"
    echo -e "2. 运行: ./scripts/diagnose_routing_issue.sh minimax-m3" | tee -a "$MAIN_LOG"
fi
