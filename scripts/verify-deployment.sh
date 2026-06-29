#!/bin/bash
# verify-deployment.sh — 部署后验证脚本
#
# 用法：
#   ./scripts/verify-deployment.sh <server-ip> <api-key>
#
# 示例：
#   ./scripts/verify-deployment.sh 192.168.1.[SERVER_IP] sk-test-xxx

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "用法: $0 <server-ip> <api-key>"
  exit 1
fi

SERVER_IP="$1"
API_KEY="$2"
BASE_URL="http://${SERVER_IP}:8080"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_success() {
  echo -e "${GREEN}✓${NC} $*"
}

log_error() {
  echo -e "${RED}✗${NC} $*"
}

log_info() {
  echo -e "${YELLOW}ℹ${NC} $*"
}

test_count=0
pass_count=0
fail_count=0

run_test() {
  local test_name="$1"
  shift
  test_count=$((test_count + 1))
  
  echo ""
  log_info "测试 $test_count: $test_name"
  
  if "$@"; then
    log_success "$test_name"
    pass_count=$((pass_count + 1))
    return 0
  else
    log_error "$test_name"
    fail_count=$((fail_count + 1))
    return 1
  fi
}

# 测试 1: 健康检查
test_health() {
  curl -f -s "${BASE_URL}/health" > /dev/null
}

# 测试 2: /v1/chat/completions 会话管理
test_chat_session() {
  local response
  response=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/v1/chat/completions" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "gpt-4o-mini",
      "messages": [{"role": "user", "content": "test"}],
      "max_tokens": 10,
      "stream": false
    }')
  
  local http_code=$(echo "$response" | tail -n1)
  local body=$(echo "$response" | head -n-1)
  
  if [ "$http_code" != "200" ]; then
    echo "  HTTP $http_code: $body"
    return 1
  fi
  
  if echo "$body" | jq -e '.choices[0].message.content' > /dev/null 2>&1; then
    return 0
  else
    echo "  响应缺少 content 字段: $body"
    return 1
  fi
}

# 测试 3: /v1/messages 会话管理
test_messages_session() {
  local response
  response=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/v1/messages" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "claude-3-5-sonnet-20241022",
      "max_tokens": 10,
      "messages": [{"role": "user", "content": "test"}]
    }')
  
  local http_code=$(echo "$response" | tail -n1)
  local body=$(echo "$response" | head -n-1)
  
  if [ "$http_code" != "200" ]; then
    echo "  HTTP $http_code: $body"
    return 1
  fi
  
  if echo "$body" | jq -e '.content[0].text' > /dev/null 2>&1; then
    return 0
  else
    echo "  响应缺少 content 字段: $body"
    return 1
  fi
}

# 测试 4: 会话头识别（使用 X-Conversation-Id）
test_alternate_session_header() {
  local response
  response=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/v1/messages" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "X-Conversation-Id: test-conv-$(date +%s)" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "claude-3-5-sonnet-20241022",
      "max_tokens": 10,
      "messages": [{"role": "user", "content": "test"}]
    }')
  
  local http_code=$(echo "$response" | tail -n1)
  
  # 只要不是 403/410（会话错误），就认为头部被识别了
  if [ "$http_code" = "403" ] || [ "$http_code" = "410" ]; then
    echo "  会话头未被识别: HTTP $http_code"
    return 1
  fi
  
  return 0
}

# 测试 5: 断线重连配置查询（可选）
test_reconnect_config() {
  local response
  response=$(curl -s -w "\n%{http_code}" "${BASE_URL}/api/reconnect/config" \
    -H "Authorization: Bearer ${API_KEY}")
  
  local http_code=$(echo "$response" | tail -n1)
  local body=$(echo "$response" | head -n-1)
  
  # 如果端点不存在，跳过测试
  if [ "$http_code" = "404" ]; then
    echo "  管理端点未启用（正常）"
    return 0
  fi
  
  if [ "$http_code" != "200" ]; then
    echo "  HTTP $http_code"
    return 1
  fi
  
  # 检查配置默认值
  if echo "$body" | jq -e '.enabled == false' > /dev/null 2>&1; then
    echo "  配置正确（默认禁用）"
    return 0
  else
    echo "  配置异常: $body"
    return 1
  fi
}

# 执行所有测试
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "部署验证测试"
echo "服务器: $SERVER_IP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

run_test "健康检查" test_health
run_test "/v1/chat/completions 会话管理" test_chat_session
run_test "/v1/messages 会话管理" test_messages_session
run_test "会话头识别（X-Conversation-Id）" test_alternate_session_header
run_test "断线重连配置（可选）" test_reconnect_config || true

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "测试结果: $pass_count/$test_count 通过"
if [ $fail_count -eq 0 ]; then
  log_success "所有测试通过！"
  exit 0
else
  log_error "$fail_count 个测试失败"
  exit 1
fi
