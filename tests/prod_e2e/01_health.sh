#!/usr/bin/env bash
# 01_health.sh - A 类：健康检查 & 元数据
# A1 /healthz 200 + proxy.healthy=true
# A2 /metrics 返回 Prometheus 文本
# A3 /v1/models 包含 ≥ 10 个家族
# A4 未知 API key → 401 invalid_key
# A5 缺失 Authorization → 401 missing_key

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
suite_start "01_health"

# === A1: /healthz ===
log_info "A1: 测试 /healthz"
RESP=$(call_health)
HEALTH_CODE=$(echo "$RESP" | head -n 1)
HEALTH_BODY=$(echo "$RESP" | tail -n +2)

assert_http_code "A1" "200" "$HEALTH_CODE" "${HEALTH_BODY:0:200}" "/healthz 返回 200"

# 验证 JSON 字段
PROXY_HEALTHY=$(echo "$HEALTH_BODY" | jq -r '.proxy.healthy // false' 2>/dev/null)
assert_eq "A1.b" "true" "$PROXY_HEALTHY" "proxy.healthy=true"

STATUS=$(echo "$HEALTH_BODY" | jq -r '.status // ""' 2>/dev/null)
assert_eq "A1.c" "ok" "$STATUS" "/healthz status=ok"

# === A2: /metrics ===
log_info "A2: 测试 /metrics"
METRICS=$(call_metrics)
if echo "$METRICS" | grep -q "^# HELP " && echo "$METRICS" | grep -q "^# TYPE "; then
    emit_result "A2" "PASS" "/metrics 返回 Prometheus 格式" "$(jq -n --arg m "$METRICS" '{first_100_chars:$m[0:100], line_count: ($m | split("\n") | length)}')"
else
    emit_result "A2" "FAIL" "/metrics 不是 Prometheus 格式" "$(jq -n --arg m "$METRICS" '{first_200_chars:$m[0:200]}')"
fi

# === A3: /v1/models 多家族 ===
log_info "A3: 测试 /v1/models 多家族覆盖"
MODELS=$(call_models)
TOTAL=$(echo "$MODELS" | jq -r '.data | length' 2>/dev/null)
if [[ "$TOTAL" =~ ^[0-9]+$ ]] && [[ "$TOTAL" -gt 100 ]]; then
    emit_result "A3.a" "PASS" "/v1/models 返回 $TOTAL 个模型" "{\"total\":$TOTAL}"
else
    emit_result "A3.a" "FAIL" "/v1/models 模型数异常" "{\"total\":\"$TOTAL\"}"
fi

# 检查关键家族
FAMILIES=("minimax" "zhipu-glm" "deepseek" "openai-gpt" "moonshot" "qwen" "doubao" "mistral" "meta-llama" "nvidia")
MISSING=()
for fam in "${FAMILIES[@]}"; do
    COUNT=$(echo "$MODELS" | jq --arg f "$fam" '[.data[] | select(.family == $f)] | length' 2>/dev/null)
    if [[ "$COUNT" -lt 1 ]]; then
        MISSING+=("$fam")
    fi
done

if [[ ${#MISSING[@]} -eq 0 ]]; then
    emit_result "A3.b" "PASS" "所有 10 个目标家族都存在" "{\"families_checked\":10}"
else
    emit_result "A3.b" "FAIL" "缺失家族: ${MISSING[*]}" "$(jq -n --arg m "${MISSING[*]}" '{missing: ($m | split(" "))}')"
fi

# === A4: 未知 API key ===
log_info "A4: 测试未知 API key"
BAD_BODY='{"model":"minimax-m3","messages":[{"role":"user","content":"hi"}],"max_tokens":5}'
TMP=$(mktemp)
CODE=$(curl -s -o "$TMP" -w "%{http_code}" -m 30 \
    -H "Authorization: Bearer sk-bogus-key-invalid-12345" \
    -H "Content-Type: application/json" \
    -X POST "$API_BASE/v1/chat/completions" \
    -d "$BAD_BODY")
BAD_RESP=$(cat "$TMP")
rm -f "$TMP"

assert_http_code "A4" "401" "$CODE" "${BAD_RESP:0:200}" "未知 API key → 401"
ERR_CODE=$(echo "$BAD_RESP" | jq -r '.error.code // ""' 2>/dev/null)
assert_eq "A4.b" "invalid_key" "$ERR_CODE" "error.code=invalid_key"

# === A5: 缺失 Authorization ===
log_info "A5: 测试缺失 Authorization 头"
TMP=$(mktemp)
CODE=$(curl -s -o "$TMP" -w "%{http_code}" -m 30 \
    -H "Content-Type: application/json" \
    -X POST "$API_BASE/v1/chat/completions" \
    -d "$BAD_BODY")
NOAUTH_RESP=$(cat "$TMP")
rm -f "$TMP"

assert_http_code "A5" "401" "$CODE" "${NOAUTH_RESP:0:200}" "缺失 Authorization → 401"
ERR_CODE=$(echo "$NOAUTH_RESP" | jq -r '.error.code // ""' 2>/dev/null)
assert_eq "A5.b" "missing_key" "$ERR_CODE" "error.code=missing_key"

print_summary
exit "$FAIL_COUNT"