#!/bin/bash
# 附件归档功能验证测试脚本
# 在 71 服务器上执行，验证部署是否成功
# 使用方法: bash verify_attachments.sh <api-key> [admin-jwt-token]

set -euo pipefail

# 配置
API_KEY="${1:-}"
ADMIN_JWT="${2:-}"
BASE_URL="http://localhost:8080"
DB_NAME="llm_gateway"

# 1x1 红色 PNG (70 bytes)
IMG_B64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================
# 辅助函数
# ============================================================
test_pass() {
    echo -e "${GREEN}✓ PASS${NC} $1"
    ((TESTS_PASSED++))
}

test_fail() {
    echo -e "${RED}✗ FAIL${NC} $1"
    echo -e "${YELLOW}  原因: $2${NC}"
    ((TESTS_FAILED++))
}

test_skip() {
    echo -e "${YELLOW}⊘ SKIP${NC} $1"
}

section() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# ============================================================
# 前置检查
# ============================================================
section "前置检查"

if [[ -z "$API_KEY" ]]; then
    echo -e "${RED}错误: 缺少 API Key${NC}"
    echo "用法: $0 <api-key> [admin-jwt-token]"
    exit 1
fi

echo "API Key: ${API_KEY:0:20}..."
if [[ -n "$ADMIN_JWT" ]]; then
    echo "Admin JWT: ${ADMIN_JWT:0:30}..."
else
    echo "Admin JWT: 未提供（跳过 API 下载测试）"
fi
echo ""

# ============================================================
# 测试 1: 服务健康检查
# ============================================================
section "测试 1: 服务健康检查"

if curl -f -s "$BASE_URL/healthz" > /dev/null 2>&1; then
    test_pass "服务健康检查"
else
    test_fail "服务健康检查" "无法访问 /healthz"
fi

# ============================================================
# 测试 2: OpenAI 格式图片请求
# ============================================================
section "测试 2: OpenAI 格式图片请求 (/v1/chat/completions)"

OPENAI_RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [{
      "role": "user",
      "content": [
        {"type": "text", "text": "what color is this pixel?"},
        {"type": "image_url", "image_url": {"url": "data:image/png;base64,'"$IMG_B64"'"}}
      ]
    }],
    "max_tokens": 50
  }')

HTTP_CODE=$(echo "$OPENAI_RESP" | tail -1)
BODY=$(echo "$OPENAI_RESP" | sed '$d')

if [[ "$HTTP_CODE" == "200" ]]; then
    test_pass "OpenAI 格式请求成功 (HTTP 200)"
    OPENAI_REQUEST_ID=$(echo "$BODY" | jq -r '.id // empty')
    if [[ -n "$OPENAI_REQUEST_ID" ]]; then
        echo "  Request ID: $OPENAI_REQUEST_ID"
    fi
else
    test_fail "OpenAI 格式请求失败" "HTTP $HTTP_CODE"
    echo "$BODY" | head -10
fi

# ============================================================
# 测试 3: Anthropic 格式图片请求
# ============================================================
section "测试 3: Anthropic 格式图片请求 (/v1/messages)"

ANTHROPIC_RESP=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/messages" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 50,
    "messages": [{
      "role": "user",
      "content": [
        {"type": "text", "text": "what is this image?"},
        {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": "'"$IMG_B64"'"}}
      ]
    }]
  }')

HTTP_CODE=$(echo "$ANTHROPIC_RESP" | tail -1)
BODY=$(echo "$ANTHROPIC_RESP" | sed '$d')

if [[ "$HTTP_CODE" == "200" ]]; then
    test_pass "Anthropic 格式请求成功 (HTTP 200)"
    ANTHROPIC_REQUEST_ID=$(echo "$BODY" | jq -r '.id // empty')
    if [[ -n "$ANTHROPIC_REQUEST_ID" ]]; then
        echo "  Request ID: $ANTHROPIC_REQUEST_ID"
    fi
else
    test_fail "Anthropic 格式请求失败" "HTTP $HTTP_CODE"
    echo "$BODY" | head -10
fi

# 等待归档完成
sleep 2

# ============================================================
# 测试 4: 数据库 - request_logs 有计数
# ============================================================
section "测试 4: 数据库 - request_logs 附件计数"

if command -v psql > /dev/null 2>&1; then
    ATTACHMENT_ROWS=$(sudo -u postgres psql -d $DB_NAME -t -c "
        SELECT COUNT(*) 
        FROM request_logs 
        WHERE has_attachments = true 
          AND created_at > NOW() - INTERVAL '5 minutes';
    " 2>/dev/null | tr -d ' ')

    if [[ "$ATTACHMENT_ROWS" -gt 0 ]]; then
        test_pass "request_logs 有附件记录 ($ATTACHMENT_ROWS 条)"
        
        # 显示最新记录
        echo ""
        echo "最新 3 条带附件的请求："
        sudo -u postgres psql -d $DB_NAME -c "
            SELECT request_id, has_attachments, attachment_count, ts
            FROM request_logs
            WHERE has_attachments = true
            ORDER BY ts DESC
            LIMIT 3;
        " 2>/dev/null
    else
        test_fail "request_logs 无附件记录" "过去 5 分钟内没有 has_attachments=true 的记录"
    fi
else
    test_skip "request_logs 检查（psql 不可用）"
fi

# ============================================================
# 测试 5: 数据库 - attachments 表有记录
# ============================================================
section "测试 5: 数据库 - attachments 表记录"

if command -v psql > /dev/null 2>&1; then
    ATTACHMENT_FILES=$(sudo -u postgres psql -d $DB_NAME -t -c "
        SELECT COUNT(*) 
        FROM attachments 
        WHERE created_at > NOW() - INTERVAL '5 minutes';
    " 2>/dev/null | tr -d ' ')

    if [[ "$ATTACHMENT_FILES" -gt 0 ]]; then
        test_pass "attachments 表有记录 ($ATTACHMENT_FILES 条)"
        
        # 显示最新记录
        echo ""
        echo "最新 3 条附件："
        sudo -u postgres psql -d $DB_NAME -c "
            SELECT id, request_id, media_type, file_size, 
                   LEFT(content_hash, 12) AS hash_prefix, created_at
            FROM attachments
            ORDER BY created_at DESC
            LIMIT 3;
        " 2>/dev/null
        
        # 保存一个 attachment_id 用于后续测试
        SAMPLE_ATT_ID=$(sudo -u postgres psql -d $DB_NAME -t -c "
            SELECT id FROM attachments ORDER BY created_at DESC LIMIT 1;
        " 2>/dev/null | tr -d ' ')
        echo ""
        echo "示例 Attachment ID: $SAMPLE_ATT_ID"
    else
        test_fail "attachments 表无记录" "过去 5 分钟内没有新增附件"
    fi
else
    test_skip "attachments 检查（psql 不可用）"
fi

# ============================================================
# 测试 6: 文件系统 - 附件文件存在
# ============================================================
section "测试 6: 文件系统 - 附件文件存在"

STORAGE_DIR="/opt/llm-gateway-go/data/attachments"
if [[ -d "$STORAGE_DIR" ]]; then
    FILE_COUNT=$(find "$STORAGE_DIR" -type f -name "*.png" -mmin -5 | wc -l)
    
    if [[ $FILE_COUNT -gt 0 ]]; then
        test_pass "附件文件已写入磁盘 ($FILE_COUNT 个文件)"
        echo ""
        echo "最新文件："
        find "$STORAGE_DIR" -type f -mmin -5 -exec ls -lh {} \; | head -5
    else
        test_fail "附件文件未找到" "过去 5 分钟内没有新增 PNG 文件"
    fi
    
    # 磁盘空间
    echo ""
    echo "存储目录磁盘使用："
    du -sh "$STORAGE_DIR"
    df -h "$STORAGE_DIR" | tail -1
else
    test_fail "附件存储目录不存在" "$STORAGE_DIR"
fi

# ============================================================
# 测试 7: Admin API - 附件下载
# ============================================================
section "测试 7: Admin API - 附件下载"

if [[ -z "$ADMIN_JWT" ]]; then
    test_skip "附件下载测试（未提供 Admin JWT）"
elif [[ -z "${SAMPLE_ATT_ID:-}" ]]; then
    test_skip "附件下载测试（没有可用的 attachment_id）"
else
    DOWNLOAD_RESP=$(curl -s -w "\n%{http_code}" \
      -H "Authorization: Bearer $ADMIN_JWT" \
      "$BASE_URL/api/admin/attachments/$SAMPLE_ATT_ID")
    
    HTTP_CODE=$(echo "$DOWNLOAD_RESP" | tail -1)
    
    if [[ "$HTTP_CODE" == "200" ]]; then
        test_pass "附件下载成功 (HTTP 200)"
        
        # 保存到临时文件验证
        TEMP_FILE="/tmp/downloaded_attachment_$$.png"
        curl -s -H "Authorization: Bearer $ADMIN_JWT" \
          "$BASE_URL/api/admin/attachments/$SAMPLE_ATT_ID" \
          -o "$TEMP_FILE"
        
        if file "$TEMP_FILE" | grep -q "PNG image data"; then
            test_pass "下载的文件是有效的 PNG"
            ls -lh "$TEMP_FILE"
        else
            test_fail "下载的文件不是 PNG" "$(file $TEMP_FILE)"
        fi
        
        rm -f "$TEMP_FILE"
    else
        test_fail "附件下载失败" "HTTP $HTTP_CODE"
    fi
fi

# ============================================================
# 测试 8: Admin API - 按 request_id 列表
# ============================================================
section "测试 8: Admin API - 按 request_id 列表附件"

if [[ -z "$ADMIN_JWT" ]]; then
    test_skip "request_id 列表测试（未提供 Admin JWT）"
elif [[ -z "${OPENAI_REQUEST_ID:-}" ]]; then
    test_skip "request_id 列表测试（没有可用的 request_id）"
else
    # 从 request_logs 获取一个有附件的 request_id
    if command -v psql > /dev/null 2>&1; then
        TEST_REQ_ID=$(sudo -u postgres psql -d $DB_NAME -t -c "
            SELECT request_id 
            FROM request_logs 
            WHERE has_attachments = true 
            ORDER BY ts DESC 
            LIMIT 1;
        " 2>/dev/null | tr -d ' ')
    fi
    
    if [[ -n "${TEST_REQ_ID:-}" ]]; then
        LIST_RESP=$(curl -s -w "\n%{http_code}" \
          -H "Authorization: Bearer $ADMIN_JWT" \
          "$BASE_URL/api/admin/attachments?request_id=$TEST_REQ_ID")
        
        HTTP_CODE=$(echo "$LIST_RESP" | tail -1)
        BODY=$(echo "$LIST_RESP" | sed '$d')
        
        if [[ "$HTTP_CODE" == "200" ]]; then
            COUNT=$(echo "$BODY" | jq 'length')
            test_pass "按 request_id 列表成功 (返回 $COUNT 个附件)"
            echo "$BODY" | jq -r '.[] | "\(.id) - \(.media_type) - \(.file_size) bytes"' | head -5
        else
            test_fail "按 request_id 列表失败" "HTTP $HTTP_CODE"
        fi
    else
        test_skip "request_id 列表测试（无法获取 request_id）"
    fi
fi

# ============================================================
# 测试 9: 日志检查 - 归档成功日志
# ============================================================
section "测试 9: 日志检查 - 归档成功日志"

ARCHIVE_LOGS=$(journalctl -u llm-gateway --since '5 minutes ago' | grep "attachments archived" | wc -l)

if [[ $ARCHIVE_LOGS -gt 0 ]]; then
    test_pass "发现归档成功日志 ($ARCHIVE_LOGS 条)"
    echo ""
    echo "最新归档日志："
    journalctl -u llm-gateway --since '5 minutes ago' | grep "attachments archived" | tail -3
else
    test_fail "未发现归档成功日志" "检查是否启用 ATTACHMENT_ENABLED=true"
fi

# ============================================================
# 测试 10: 日志检查 - 无错误
# ============================================================
section "测试 10: 日志检查 - 归档错误日志"

ERROR_LOGS=$(journalctl -u llm-gateway --since '5 minutes ago' | grep -i "attachment.*failed\|attachment.*error" | wc -l)

if [[ $ERROR_LOGS -eq 0 ]]; then
    test_pass "无归档错误日志"
else
    test_fail "发现归档错误日志 ($ERROR_LOGS 条)" "见下方日志"
    echo ""
    journalctl -u llm-gateway --since '5 minutes ago' | grep -i "attachment.*failed\|attachment.*error"
fi

# ============================================================
# 测试 11: 去重验证
# ============================================================
section "测试 11: 去重验证（同一图片多次上传）"

if command -v psql > /dev/null 2>&1; then
    # 发送两次相同图片
    echo "发送第 1 次..."
    curl -s -X POST "$BASE_URL/v1/chat/completions" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "model": "gpt-4o",
        "messages": [{"role": "user", "content": [
          {"type": "text", "text": "test"},
          {"type": "image_url", "image_url": {"url": "data:image/png;base64,'"$IMG_B64"'"}}
        ]}],
        "max_tokens": 10
      }' > /dev/null
    
    sleep 1
    
    echo "发送第 2 次..."
    curl -s -X POST "$BASE_URL/v1/chat/completions" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -d '{
        "model": "gpt-4o",
        "messages": [{"role": "user", "content": [
          {"type": "text", "text": "test"},
          {"type": "image_url", "image_url": {"url": "data:image/png;base64,'"$IMG_B64"'"}}
        ]}],
        "max_tokens": 10
      }' > /dev/null
    
    sleep 2
    
    # 检查是否只有一个物理文件
    UNIQUE_HASHES=$(sudo -u postgres psql -d $DB_NAME -t -c "
        SELECT COUNT(DISTINCT content_hash)
        FROM attachments
        WHERE created_at > NOW() - INTERVAL '1 minute';
    " 2>/dev/null | tr -d ' ')
    
    TOTAL_RECORDS=$(sudo -u postgres psql -d $DB_NAME -t -c "
        SELECT COUNT(*)
        FROM attachments
        WHERE created_at > NOW() - INTERVAL '1 minute';
    " 2>/dev/null | tr -d ' ')
    
    if [[ $TOTAL_RECORDS -ge 2 ]] && [[ $UNIQUE_HASHES -eq 1 ]]; then
        test_pass "去重生效（$TOTAL_RECORDS 条记录，1 个唯一 hash）"
    else
        test_fail "去重可能未生效" "records=$TOTAL_RECORDS, unique_hashes=$UNIQUE_HASHES"
    fi
else
    test_skip "去重验证（psql 不可用）"
fi

# ============================================================
# 总结
# ============================================================
section "测试总结"

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))
echo ""
echo "总测试数: $TOTAL_TESTS"
echo -e "${GREEN}通过: $TESTS_PASSED${NC}"
echo -e "${RED}失败: $TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ 所有测试通过！${NC}"
    echo -e "${GREEN}========================================${NC}"
    exit 0
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ 部分测试失败${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "建议："
    echo "  1. 检查日志: journalctl -u llm-gateway -n 100"
    echo "  2. 检查环境变量: systemctl cat llm-gateway | grep ATTACHMENT"
    echo "  3. 检查磁盘空间: df -h /opt/llm-gateway-go/data/attachments"
    exit 1
fi
