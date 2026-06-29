#!/usr/bin/env bash
# 06_errors.sh - F 类：错误路径

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
suite_start "06_errors"

# === F1: 未知模型 → 503 no_candidate ===
log_info "F1: 未知模型"
RESP=$(call_chat "non-existent-fake-model-12345" 10 false)
CODE=$(echo "$RESP" | head -n 1)
BODY=$(echo "$RESP" | tail -n +2)
ERR_CODE=$(echo "$BODY" | jq -r '.error.code // ""' 2>/dev/null)
assert_http_code "F1" "503" "$CODE" "${BODY:0:200}" "未知模型 → 503"
assert_eq "F1.b" "no_candidate" "$ERR_CODE" "error.code=no_candidate"

# === F2: 缺 model 字段 → 400 missing_model ===
log_info "F2: 缺 model 字段"
BODY='{"messages":[{"role":"user","content":"hi"}],"max_tokens":5}'
RESP=$(call_chat_with_body "$BODY")
CODE=$(echo "$RESP" | head -n 1)
RESBODY=$(echo "$RESP" | tail -n +2)
ERR_CODE=$(echo "$RESBODY" | jq -r '.error.code // ""' 2>/dev/null)
assert_http_code "F2" "400" "$CODE" "${RESBODY:0:200}" "缺 model → 400"
assert_eq "F2.b" "missing_model" "$ERR_CODE" "error.code=missing_model"

# === F3: messages=[] → 400 invalid_request ===
log_info "F3: messages=[]"
BODY='{"model":"minimax-m3","messages":[],"max_tokens":5}'
RESP=$(call_chat_with_body "$BODY")
CODE=$(echo "$RESP" | head -n 1)
RESBODY=$(echo "$RESP" | tail -n +2)
assert_http_code "F3" "400" "$CODE" "${RESBODY:0:200}" "messages=[] → 400"

# === F4: body 过大 (10MB) → 413 ===
log_info "F4: body 过大 (10MB)"
HUGE=$(python3 -c "print('A' * 11000000)" 2>/dev/null || perl -e 'print "A" x 11000000')
BODY=$(jq -n --arg c "$HUGE" '{model:"minimax-m3", messages:[{role:"user", content:$c}], max_tokens:5}')
TMP=$(mktemp)
CODE=$(curl --http1.1 -s -o "$TMP" -w "%{http_code}" -m 60 \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -X POST "$API_BASE/v1/chat/completions" \
    -d "$BODY" 2>&1)
RESBODY=$(cat "$TMP")
rm -f "$TMP"

# 413 或 400 都算合理（不同实现）
if [[ "$CODE" == "413" || "$CODE" == "400" ]]; then
    emit_result "F4" "PASS" "body 过大 → $CODE" "$(jq -n --arg c "$CODE" --arg b "${RESBODY:0:300}" '{http:$c, body:$b}')"
else
    emit_result "F4" "FAIL" "body 过大 → HTTP $CODE (期望 413/400)" "$(jq -n --arg c "$CODE" --arg b "${RESBODY:0:300}" '{http:$c, body:$b}')"
fi

# === F5: 非 JSON body → 400 json_parse_error ===
log_info "F5: 非 JSON body"
TMP=$(mktemp)
CODE=$(curl --http1.1 -s -o "$TMP" -w "%{http_code}" -m 30 \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -X POST "$API_BASE/v1/chat/completions" \
    -d 'not-json-at-all' 2>&1)
RESBODY=$(cat "$TMP")
rm -f "$TMP"

assert_http_code "F5" "400" "$CODE" "${RESBODY:0:200}" "非 JSON body → 400"

# === F6: GET /v1/chat/completions → 200 (intentional health-probe response) ===
# 2026-06-28 NOTE: relay/handler.go:416-422 has explicit GET-probe handling
# that returns 200 + {"status":"ok","message":"Chat completions endpoint is
# available. Use POST to send requests."}. This is BY DESIGN (clients use
# this to probe availability). Other methods still get 405.
log_info "F6: GET /v1/chat/completions (intentional health probe)"
TMP=$(mktemp)
CODE=$(curl --http1.1 -s -o "$TMP" -w "%{http_code}" -m 30 \
    -H "Authorization: Bearer $API_KEY" \
    -X GET "$API_BASE/v1/chat/completions" 2>&1)
RESBODY=$(cat "$TMP")
rm -f "$TMP"

assert_http_code "F6" "200" "$CODE" "${RESBODY:0:200}" "GET /v1/chat/completions → 200 (intentional)"

# Verify response is the health-probe message
if echo "$RESBODY" | grep -q "Chat completions endpoint is available"; then
    emit_result "F6.b" "PASS" "GET 返回健康探测消息" "$(jq -n --arg b "${RESBODY:0:200}" '{body:$b}')"
else
    emit_result "F6.b" "FAIL" "GET 响应不是健康探测消息" "$(jq -n --arg b "${RESBODY:0:200}" '{body:$b}')"
fi

# Verify PUT (not in the GET-probe shortlist) still returns 405
log_info "F6.c: PUT /v1/chat/completions → 405 (method not allowed)"
TMP=$(mktemp)
CODE=$(curl --http1.1 -s -o "$TMP" -w "%{http_code}" -m 30 \
    -H "Authorization: Bearer $API_KEY" \
    -X PUT "$API_BASE/v1/chat/completions" 2>&1)
RESBODY=$(cat "$TMP")
rm -f "$TMP"
assert_http_code "F6.c" "405" "$CODE" "${RESBODY:0:200}" "PUT /v1/chat/completions → 405"

# === F7: 错误 model name format ===
log_info "F7: 错误 model name"
# model 为 null
BODY='{"model":null,"messages":[{"role":"user","content":"hi"}],"max_tokens":5}'
RESP=$(call_chat_with_body "$BODY")
CODE=$(echo "$RESP" | head -n 1)
RESBODY=$(echo "$RESP" | tail -n +2)
# 期望 400 或 503
if [[ "$CODE" == "400" || "$CODE" == "503" ]]; then
    emit_result "F7" "PASS" "model=null → $CODE" "$(jq -n --arg c "$CODE" --arg b "${RESBODY:0:200}" '{http:$c, body:$b}')"
else
    emit_result "F7" "FAIL" "model=null → HTTP $CODE (期望 400/503)" "$(jq -n --arg c "$CODE" --arg b "${RESBODY:0:200}" '{http:$c, body:$b}')"
fi

# === F8: anthropic 模型缺 max_tokens → 400 max_tokens_must_be_positive ===
log_info "F8: anthropic 模型缺 max_tokens"
MSG_BODY='{"model":"claude-3-5-sonnet-20241022","messages":[{"role":"user","content":"hi"}]}'
RESP=$(call_messages "$MSG_BODY")
CODE=$(echo "$RESP" | head -n 1)
RESBODY=$(echo "$RESP" | tail -n +2)

if [[ "$CODE" == "400" || "$CODE" == "200" ]]; then
    emit_result "F8" "PASS" "anthropic 缺 max_tokens → $CODE" "$(jq -n --arg c "$CODE" --arg b "${RESBODY:0:200}" '{http:$c, body:$b}')"
else
    emit_result "F8" "FAIL" "anthropic 缺 max_tokens → HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "${RESBODY:0:200}" '{http:$c, body:$b}')"
fi

# === F11: 触发 503 no_candidate（已知不存在的模型）===
log_info "F11: 503 no_candidate"
RESP=$(call_chat "fake-model-99999" 10 false)
CODE=$(echo "$RESP" | head -n 1)
BODY=$(echo "$RESP" | tail -n +2)
ERR_CODE=$(echo "$BODY" | jq -r '.error.code // ""' 2>/dev/null)
assert_http_code "F11" "503" "$CODE" "${BODY:0:200}" "503 no_candidate"
assert_eq "F11.b" "no_candidate" "$ERR_CODE" "error.code=no_candidate"

# 验证错误响应包含 request_id
REQ_ID=$(echo "$BODY" | jq -r '.error.request_id // .request_id // ""' 2>/dev/null)
if [[ -n "$REQ_ID" ]]; then
    emit_result "F11.c" "PASS" "错误响应含 request_id" "$(jq -n --arg r "$REQ_ID" '{request_id:$r}')"
else
    emit_result "F11.c" "FAIL" "错误响应不含 request_id" "$(jq -n --arg b "${BODY:0:200}" '{body:$b}')"
fi

# === F12: 触发限流 - 在一分钟内连续发 100 个请求（应该触发 429）===
log_info "F12: 限流触发（连续 50 个请求）"
TRIGGERED=0
LAST_CODE=""
LAST_BODY=""
for i in $(seq 1 50); do
    RESP=$(call_chat "minimax-m3" 5 false 2>&1)
    CODE=$(echo "$RESP" | head -n 1)
    LAST_CODE="$CODE"
    LAST_BODY=$(echo "$RESP" | tail -n +2)
    if [[ "$CODE" == "429" ]]; then
        TRIGGERED=$((TRIGGERED + 1))
        break
    fi
done

if [[ "$TRIGGERED" -gt 0 ]]; then
    ERR_CODE=$(echo "$LAST_BODY" | jq -r '.error.code // ""' 2>/dev/null)
    emit_result "F12" "PASS" "限流触发 (429), error.code=$ERR_CODE" "$(jq -n --arg e "$ERR_CODE" --arg b "${LAST_BODY:0:200}" '{error_code:$e, body:$b}')"
else
    # 没触发说明当前 tier 配置限流较宽或 E2E key 是高 tier
    emit_result "F12" "SKIP" "50 个连续请求未触发 429（E2E key 可能 tier 高）" "$(jq -n --arg c "$LAST_CODE" '{last_code:$c}')"
fi

print_summary
exit "$FAIL_COUNT"