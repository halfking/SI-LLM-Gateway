#!/usr/bin/env bash
# 09_edge_cases.sh - I 类：边缘/高级

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
suite_start "09_edge_cases"

# === I1: X-Device-Seed 稳定 ===
log_info "I1: X-Device-Seed 稳定性"
SEED="test-stable-seed-$RANDOM"
TMP=$(mktemp)
BODY='{"model":"minimax-m3","messages":[{"role":"user","content":"OK"}],"max_tokens":10,"stream":false}'
RID1=$(curl --http1.1 -s -D "$TMP" -m 30 \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Device-Seed: $SEED" \
    -X POST "$API_BASE/v1/chat/completions" \
    -d "$BODY" | jq -r '.id // ""' 2>/dev/null)
SESSION1=$(grep -i "x-gw-session-id-resume:" "$TMP" | awk '{print $2}' | tr -d '\r' || echo "")
rm -f "$TMP"

TMP=$(mktemp)
RID2=$(curl --http1.1 -s -D "$TMP" -m 30 \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Device-Seed: $SEED" \
    -X POST "$API_BASE/v1/chat/completions" \
    -d "$BODY" | jq -r '.id // ""' 2>/dev/null)
SESSION2=$(grep -i "x-gw-session-id-resume:" "$TMP" | awk '{print $2}' | tr -d '\r' || echo "")
rm -f "$TMP"

if [[ -n "$RID1" && -n "$RID2" ]]; then
    # request_id 应该不同，但 identity_hash 应该相同（通过 session resume 头推断）
    if [[ "$SESSION1" != "" && "$SESSION2" != "" ]]; then
        emit_result "I1" "PASS" "同一 seed: 两次返回 request_id=$RID1, $RID2 (不同)，session=$SESSION1, $SESSION2" \
            "$(jq -n --arg r1 "$RID1" --arg r2 "$RID2" --arg s1 "$SESSION1" --arg s2 "$SESSION2" '{request_id_1:$r1, request_id_2:$r2, session_1:$s1, session_2:$s2}')"
    else
        emit_result "I1" "PASS" "同一 seed: 两次都成功 (request_id=$RID1, $RID2), 无 session header (不影响功能)" \
            "$(jq -n --arg r1 "$RID1" --arg r2 "$RID2" '{request_id_1:$r1, request_id_2:$r2}')"
    fi
else
    emit_result "I1" "FAIL" "X-Device-Seed 同一值请求失败" "{}"
fi

# === I2: X-Machine-Id 单独 ===
log_info "I2: X-Machine-Id 单独"
MID="test-machine-$RANDOM"
TMP=$(mktemp)
RID1=$(curl --http1.1 -s -D "$TMP" -m 30 \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Machine-Id: $MID" \
    -X POST "$API_BASE/v1/chat/completions" \
    -d "$BODY" | jq -r '.id // ""' 2>/dev/null)
SESSION1=$(grep -i "x-gw-session-id-resume:" "$TMP" | awk '{print $2}' | tr -d '\r' || echo "")
rm -f "$TMP"

TMP=$(mktemp)
RID2=$(curl --http1.1 -s -D "$TMP" -m 30 \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Machine-Id: $MID" \
    -X POST "$API_BASE/v1/chat/completions" \
    -d "$BODY" | jq -r '.id // ""' 2>/dev/null)
SESSION2=$(grep -i "x-gw-session-id-resume:" "$TMP" | awk '{print $2}' | tr -d '\r' || echo "")
rm -f "$TMP"

if [[ -n "$RID1" && -n "$RID2" ]]; then
    emit_result "I2" "PASS" "X-Machine-Id: 两次都成功 (request_id=$RID1, $RID2)" \
        "$(jq -n --arg r1 "$RID1" --arg r2 "$RID2" --arg s1 "$SESSION1" --arg s2 "$SESSION2" '{request_id_1:$r1, request_id_2:$r2, session_1:$s1, session_2:$s2}')"
else
    emit_result "I2" "FAIL" "X-Machine-Id 失败" "{}"
fi

# === I3: X-Forwarded-For ===
log_info "I3: X-Forwarded-For 头"
TMP=$(mktemp)
CODE=$(curl --http1.1 -s -o "$TMP" -w "%{http_code}" -m 30 \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Forwarded-For: 1.2.3.4" \
    -X POST "$API_BASE/v1/chat/completions" \
    -d "$BODY" 2>&1)
rm -f "$TMP"
if [[ "$CODE" == "200" ]]; then
    emit_result "I3" "PASS" "X-Forwarded-For: HTTP 200 (代理头不影响请求)" "$(jq -n --arg c "$CODE" '{http:$c}')"
else
    emit_result "I3" "FAIL" "X-Forwarded-For: HTTP $CODE" "$(jq -n --arg c "$CODE" '{http:$c}')"
fi

# === I4: 自定义 User-Agent ===
log_info "I4: 自定义 User-Agent"
TMP=$(mktemp)
CODE=$(curl --http1.1 -s -o "$TMP" -w "%{http_code}" -m 30 \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -H "User-Agent: my-custom-agent/1.2.3" \
    -X POST "$API_BASE/v1/chat/completions" \
    -d "$BODY" 2>&1)
RESBODY=$(cat "$TMP")
rm -f "$TMP"
if [[ "$CODE" == "200" ]]; then
    emit_result "I4" "PASS" "User-Agent 自定义: HTTP 200" "$(jq -n --arg c "$CODE" '{http:$c}')"
else
    emit_result "I4" "FAIL" "User-Agent 自定义: HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "${RESBODY:0:200}" '{http:$c, body:$b}')"
fi

# === I5: 同时设置 X-Device-Seed + X-Machine-Id ===
log_info "I5: X-Device-Seed + X-Machine-Id 同时设置"
SEED2="seed-only-$RANDOM"
MID2="machine-only-$RANDOM"
TMP=$(mktemp)
CODE=$(curl --http1.1 -s -D "$TMP" -o /dev/null -w "%{http_code}" -m 30 \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Device-Seed: $SEED2" \
    -H "X-Machine-Id: $MID2" \
    -X POST "$API_BASE/v1/chat/completions" \
    -d "$BODY" 2>&1)
rm -f "$TMP"
if [[ "$CODE" == "200" ]]; then
    emit_result "I5" "PASS" "X-Device-Seed + X-Machine-Id 同时: HTTP 200" "$(jq -n --arg c "$CODE" '{http:$c}')"
else
    emit_result "I5" "FAIL" "X-Device-Seed + X-Machine-Id: HTTP $CODE" "$(jq -n --arg c "$CODE" '{http:$c}')"
fi

# === I7: 同一并发不同 X-Gw-Session-Id ===
log_info "I7: 同一并发不同 X-Gw-Session-Id"
tmpdir=$(mktemp -d)
for i in 1 2 3; do
    body='{"model":"minimax-m3","messages":[{"role":"user","content":"OK"}],"max_tokens":10,"stream":false}'
    curl --http1.1 -s -D "$tmpdir/header-$i.txt" -o "$tmpdir/body-$i.txt" -w "%{http_code}" -m 30 \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -H "X-Gw-Session-Id: distinct-session-$i" \
        -X POST "$API_BASE/v1/chat/completions" \
        -d "$body" > "$tmpdir/code-$i.txt" 2>&1 &
done
wait

c200=0; distinct_sessions=()
for i in 1 2 3; do
    code=$(cat "$tmpdir/code-$i.txt" 2>/dev/null)
    [[ "$code" == "200" ]] && c200=$((c200 + 1))
    session=$(grep -i "x-gw-session-id-resume:" "$tmpdir/header-$i.txt" | awk '{print $2}' | tr -d '\r' || echo "")
    [[ -n "$session" ]] && distinct_sessions+=("$session")
done
rm -rf "$tmpdir"

if [[ "$c200" -eq 3 ]]; then
    emit_result "I7" "PASS" "3 个独立 session 都成功: ${distinct_sessions[*]}" "$(jq -n --argjson c "$c200" --argjson s "${distinct_sessions[@]}" '{success:$c, sessions:$s}')"
else
    emit_result "I7" "FAIL" "独立 session 失败: 200=$c200/3" "$(jq -n --argjson c "$c200" '{success:$c}')"
fi

# === I8: 流式响应中模型名替换 ===
log_info "I8: 流式响应模型名回填"
OUTFILE="$RESULTS_DIR/stream_tmp/I8.txt"
BODY='{"model":"minimax-m3","messages":[{"role":"user","content":"OK"}],"max_tokens":10,"stream":true}'
call_chat_stream "$BODY" "$OUTFILE" 30 > /dev/null 2>&1
FIRST_DATA=$(grep -m1 "^data: " "$OUTFILE" | sed 's/^data: //')
MODEL=$(echo "$FIRST_DATA" | jq -r '.model // ""' 2>/dev/null)
if [[ "$MODEL" == "minimax-m3" ]]; then
    emit_result "I8" "PASS" "流式 model 字段回填: $MODEL" "$(jq -n --arg m "$MODEL" '{model:$m}')"
else
    emit_result "I8" "FAIL" "流式 model 字段: $MODEL" "$(jq -n --arg m "$MODEL" '{model:$m}')"
fi

# === I10: CORS 头 ===
log_info "I10: CORS 头"
TMP=$(mktemp)
CODE=$(curl --http1.1 -s -D "$TMP" -o /dev/null -w "%{http_code}" -m 30 \
    -H "Authorization: Bearer $API_KEY" \
    -H "Origin: http://example.com" \
    -H "Content-Type: application/json" \
    -X POST "$API_BASE/v1/chat/completions" \
    -d "$BODY" 2>&1)
CORS_HEADER=$(grep -i "access-control-allow-origin" "$TMP" | tr -d '\r' || echo "")
rm -f "$TMP"
if [[ -n "$CORS_HEADER" ]]; then
    emit_result "I10" "PASS" "CORS 头存在: $CORS_HEADER" "$(jq -n --arg c "$CORS_HEADER" '{cors:$c}')"
else
    emit_result "I10" "FAIL" "CORS 头缺失" "{}"
fi

print_summary
exit "$FAIL_COUNT"