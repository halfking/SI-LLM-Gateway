#!/usr/bin/env bash
# common.sh - 共用辅助函数（颜色、日志、断言、JSON 输出）
# 用法：source common.sh

set -u
set -o pipefail

# === 颜色输出 ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# === 全局配置 ===
API_BASE="${API_BASE:-https://[PROD_DOMAIN]}"
API_KEY="${API_KEY:-sk-e2e-1781897808-B-3322}"
RESULTS_DIR="${RESULTS_DIR:-$(dirname "${BASH_SOURCE[0]}")/results}"

# 每个用例一条 JSON 结果
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
SUITE_NAME="${SUITE_NAME:-default}"

mkdir -p "$RESULTS_DIR"
RESULT_JSONL="$RESULTS_DIR/${SUITE_NAME}.jsonl"
SUMMARY_FILE="$RESULTS_DIR/${SUITE_NAME}.summary"
FAILURES_FILE="$RESULTS_DIR/${SUITE_NAME}.failures.log"

# 清空旧结果
: > "$RESULT_JSONL"
: > "$SUMMARY_FILE"
: > "$FAILURES_FILE"

# === 工具函数 ===

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*" >&2; }
log_pass()  { echo -e "${GREEN}[PASS]${NC}  $*" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*" >&2; }
log_fail()  { echo -e "${RED}[FAIL]${NC}  $*" >&2; }
log_skip()  { echo -e "${CYAN}[SKIP]${NC}  $*" >&2; }

# emit_result <test_id> <status> <message> [<details_json>]
emit_result() {
    local test_id="$1"
    local status="$2"
    local message="$3"
    local details="${4:-{\}}"
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # 合并 details
    local merged
    merged=$(jq -n --arg id "$test_id" --arg st "$status" --arg msg "$message" \
                   --arg ts "$ts" --argjson det "$details" \
                   '{ts:$id, test_id:$id, status:$st, message:$msg, details:$det}' \
                   2>/dev/null || echo "{\"ts\":\"$ts\",\"test_id\":\"$test_id\",\"status\":\"$status\",\"message\":\"$message\",\"details\":$details}")

    echo "$merged" >> "$RESULT_JSONL"

    case "$status" in
        PASS) ((PASS_COUNT++)); log_pass  "$test_id: $message" ;;
        FAIL) ((FAIL_COUNT++)); log_fail  "$test_id: $message"; echo "$test_id: $message" >> "$FAILURES_FILE" ;;
        SKIP) ((SKIP_COUNT++)); log_skip  "$test_id: $message" ;;
        *)    log_warn  "$test_id: unknown status=$status ($message)" ;;
    esac
}

# assert_eq <test_id> <expected> <actual> <description>
assert_eq() {
    local id="$1" expected="$2" actual="$3" desc="$4"
    if [[ "$expected" == "$actual" ]]; then
        emit_result "$id" "PASS" "$desc (got=$actual)" "{\"expected\":\"$expected\",\"actual\":\"$actual\"}"
    else
        emit_result "$id" "FAIL" "$desc (expected=$expected, got=$actual)" "{\"expected\":\"$expected\",\"actual\":\"$actual\"}"
    fi
}

# assert_http_code <test_id> <expected_code> <actual_code> <body_preview> <description>
assert_http_code() {
    local id="$1" expected="$2" actual="$3" body="$4" desc="$5"
    if [[ "$expected" == "$actual" ]]; then
        emit_result "$id" "PASS" "$desc (HTTP $actual)" "$(jq -n --arg e "$expected" --arg a "$actual" --arg b "$body" '{expected:$e,actual:$a,body_preview:$b}')"
    else
        emit_result "$id" "FAIL" "$desc (expected=$expected, got=$actual)" "$(jq -n --arg e "$expected" --arg a "$actual" --arg b "$body" '{expected:$e,actual:$a,body_preview:$b}')"
    fi
}

# call_chat <model> [<max_tokens>] [<stream>] [extra_body_json]
# 输出: HTTP_CODE\\nBODY (用 echo 拼接后用 read 拆开)
call_chat() {
    local model="$1" max_tokens="${2:-30}" stream="${3:-false}"
    local extra="${4:-}"
    local body
    body=$(jq -n --arg m "$model" --argjson mt "$max_tokens" --argjson s "$stream" \
                '{model:$m, messages:[{role:"user", content:"Reply with the single word OK and nothing else."}], max_tokens:$mt, stream:$s, temperature:0}')

    if [[ -n "$extra" ]]; then
        body=$(echo "$body" | jq --argjson e "$extra" '. + $e')
    fi

    local tmp
    tmp=$(mktemp)
    local code
    # Bounded timeout 150s: after the upstream-hang fix, sync_retry path still
    # takes up to ~130s before returning 503; -m 90 was too tight and caused
    # the test harness to report HTTP 000 (curl timeout). 150s comfortably
    # covers both healthy and fixed-but-bounded error paths.
    code=$(curl --http1.1 -s -o "$tmp" -w "%{http_code}" -m 150 \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -X POST "$API_BASE/v1/chat/completions" \
        -d "$body" 2>&1)
    local body_content
    body_content=$(cat "$tmp")
    rm -f "$tmp"

    printf '%s\n%s' "$code" "$body_content"
}

# call_chat_with_body <body_json>
call_chat_with_body() {
    local body="$1"
    local tmp
    tmp=$(mktemp)
    local code
    code=$(curl --http1.1 -s -o "$tmp" -w "%{http_code}" -m 150 \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -X POST "$API_BASE/v1/chat/completions" \
        -d "$body" 2>&1)
    local body_content
    body_content=$(cat "$tmp")
    rm -f "$tmp"
    printf '%s\n%s' "$code" "$body_content"
}

# call_messages <body_json>
call_messages() {
    local body="$1"
    local tmp
    tmp=$(mktemp)
    local code
    code=$(curl --http1.1 -s -o "$tmp" -w "%{http_code}" -m 150 \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -H "anthropic-version: 2023-06-01" \
        -X POST "$API_BASE/v1/messages" \
        -d "$body" 2>&1)
    local body_content
    body_content=$(cat "$tmp")
    rm -f "$tmp"
    printf '%s\n%s' "$code" "$body_content"
}

# call_responses <body_json>
call_responses() {
    local body="$1"
    local tmp
    tmp=$(mktemp)
    local code
    code=$(curl --http1.1 -s -o "$tmp" -w "%{http_code}" -m 150 \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -X POST "$API_BASE/v1/responses" \
        -d "$body" 2>&1)
    local body_content
    body_content=$(cat "$tmp")
    rm -f "$tmp"
    printf '%s\n%s' "$code" "$body_content"
}

# call_health
call_health() {
    local tmp
    tmp=$(mktemp)
    local code
    code=$(curl --http1.1 -s -o "$tmp" -w "%{http_code}" -m 10 "$API_BASE/healthz" 2>&1)
    local body_content
    body_content=$(cat "$tmp")
    rm -f "$tmp"
    printf '%s\n%s' "$code" "$body_content"
}

# call_models
call_models() {
    curl --http1.1 -s -m 30 "$API_BASE/v1/models" \
        -H "Authorization: Bearer $API_KEY"
}

# call_metrics
call_metrics() {
    curl --http1.1 -s -m 30 "$API_BASE/metrics" 2>&1 | head -200
}

# call_chat_stream <body_json> <output_file> <max_seconds>
# 捕获 SSE 流到文件，返回总耗时
call_chat_stream() {
    local body="$1" outfile="$2" max_seconds="${3:-60}"
    local start end
    start=$(date +%s.%N)
    curl --http1.1 -s --no-buffer -N -m "$max_seconds" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -X POST "$API_BASE/v1/chat/completions" \
        -d "$body" > "$outfile" 2>&1 &
    local pid=$!

    ( sleep "$max_seconds" && kill -9 "$pid" 2>/dev/null ) &
    local watcher=$!

    wait "$pid" 2>/dev/null
    local code=$?
    kill -9 "$watcher" 2>/dev/null

    end=$(date +%s.%N)
    echo "$end $start" | awk '{printf "%.3f\n", $1-$2}'
}

# === 摘要打印 ===
print_summary() {
    local total=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
    cat <<EOF

========================================
测试套件: $SUITE_NAME
========================================
总计:    $total
通过:    $PASS_COUNT
失败:    $FAIL_COUNT
跳过:    $SKIP_COUNT
========================================
EOF
    echo "结果文件:"
    echo "  - $RESULT_JSONL"
    echo "  - $FAILURES_FILE"
}

# suite_start <name>
suite_start() {
    SUITE_NAME="$1"
    RESULTS_DIR="${RESULTS_DIR:-$(dirname "${BASH_SOURCE[0]}")/results}"
    mkdir -p "$RESULTS_DIR"
    RESULT_JSONL="$RESULTS_DIR/${SUITE_NAME}.jsonl"
    SUMMARY_FILE="$RESULTS_DIR/${SUITE_NAME}.summary"
    FAILURES_FILE="$RESULTS_DIR/${SUITE_NAME}.failures.log"
    : > "$RESULT_JSONL"
    : > "$SUMMARY_FILE"
    : > "$FAILURES_FILE"
    PASS_COUNT=0
    FAIL_COUNT=0
    SKIP_COUNT=0
    log_info "套件启动: $SUITE_NAME (API_BASE=$API_BASE)"
}