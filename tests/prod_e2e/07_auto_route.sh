#!/usr/bin/env bash
# 07_auto_route.sh - G 类：自动路由 (model="auto")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
suite_start "07_auto_route"

# === G1: 默认 smart profile + 简单 chat ===
log_info "G1: model=auto + 简单 chat"
BODY='{"model":"auto","messages":[{"role":"user","content":"OK"}],"max_tokens":30,"stream":false}'
RESP=$(call_chat_with_body "$BODY")
CODE=$(echo "$RESP" | head -n 1)
RESBODY=$(echo "$RESP" | tail -n +2)
CHOSEN_MODEL=$(echo "$RESBODY" | jq -r '.model // ""' 2>/dev/null)
if [[ "$CODE" == "200" ]]; then
    emit_result "G1" "PASS" "auto chat: 200 OK, 选中模型=$CHOSEN_MODEL" "$(jq -n --arg m "$CHOSEN_MODEL" '{chosen_model:$m}')"
else
    emit_result "G1" "FAIL" "auto chat: HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "${RESBODY:0:300}" '{http:$c, body:$b}')"
fi

# === G2: 显式 X-Gw-Auto-Profile: smart ===
log_info "G2: X-Gw-Auto-Profile=smart"
BODY='{"model":"auto","messages":[{"role":"user","content":"Hello"}],"max_tokens":30,"stream":false}'
TMP=$(mktemp)
CODE=$(curl --http1.1 -s -o "$TMP" -w "%{http_code}" -m 30 \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Gw-Auto-Profile: smart" \
    -X POST "$API_BASE/v1/chat/completions" \
    -d "$BODY" 2>&1)
RESBODY=$(cat "$TMP")
rm -f "$TMP"
CHOSEN_MODEL=$(echo "$RESBODY" | jq -r '.model // ""' 2>/dev/null)
if [[ "$CODE" == "200" ]]; then
    emit_result "G2" "PASS" "auto profile=smart: 200 OK, 选中=$CHOSEN_MODEL" "$(jq -n --arg m "$CHOSEN_MODEL" '{chosen_model:$m}')"
else
    emit_result "G2" "FAIL" "auto profile=smart: HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "${RESBODY:0:300}" '{http:$c, body:$b}')"
fi

# === G3: reasoning prompt ===
log_info "G3: reasoning prompt"
BODY='{"model":"auto","messages":[{"role":"user","content":"求解方程 2x+5=13, 推导过程"}],"max_tokens":300,"stream":false}'
RESP=$(call_chat_with_body "$BODY")
CODE=$(echo "$RESP" | head -n 1)
RESBODY=$(echo "$RESP" | tail -n +2)
CHOSEN_MODEL=$(echo "$RESBODY" | jq -r '.model // ""' 2>/dev/null)
CONTENT=$(echo "$RESBODY" | jq -r '.choices[0].message.content // ""' 2>/dev/null)
if [[ "$CODE" == "200" ]]; then
    emit_result "G3" "PASS" "auto reasoning: 200 OK, 选中=$CHOSEN_MODEL" "$(jq -n --arg m "$CHOSEN_MODEL" --arg c "${CONTENT:0:100}" '{chosen_model:$m, content_preview:$c}')"
else
    emit_result "G3" "FAIL" "auto reasoning: HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "${RESBODY:0:300}" '{http:$c, body:$b}')"
fi

# === G4: code prompt ===
log_info "G4: code prompt"
BODY='{"model":"auto","messages":[{"role":"user","content":"用 Python 写一个快速排序算法"}],"max_tokens":500,"stream":false}'
RESP=$(call_chat_with_body "$BODY")
CODE=$(echo "$RESP" | head -n 1)
RESBODY=$(echo "$RESP" | tail -n +2)
CHOSEN_MODEL=$(echo "$RESBODY" | jq -r '.model // ""' 2>/dev/null)
CONTENT=$(echo "$RESBODY" | jq -r '.choices[0].message.content // ""' 2>/dev/null)
if [[ "$CODE" == "200" ]]; then
    emit_result "G4" "PASS" "auto code: 200 OK, 选中=$CHOSEN_MODEL" "$(jq -n --arg m "$CHOSEN_MODEL" --arg c "${CONTENT:0:100}" '{chosen_model:$m, content_preview:$c}')"
else
    emit_result "G4" "FAIL" "auto code: HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "${RESBODY:0:300}" '{http:$c, body:$b}')"
fi

# === G7: X-Gw-Task-Hint=reasoning ===
log_info "G7: X-Gw-Task-Hint=reasoning"
BODY='{"model":"auto","messages":[{"role":"user","content":"hi"}],"max_tokens":50,"stream":false}'
TMP=$(mktemp)
CODE=$(curl --http1.1 -s -o "$TMP" -w "%{http_code}" -m 30 \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Gw-Task-Hint: reasoning" \
    -X POST "$API_BASE/v1/chat/completions" \
    -d "$BODY" 2>&1)
RESBODY=$(cat "$TMP")
rm -f "$TMP"
CHOSEN_MODEL=$(echo "$RESBODY" | jq -r '.model // ""' 2>/dev/null)
if [[ "$CODE" == "200" ]]; then
    emit_result "G7" "PASS" "auto hint=reasoning: 200 OK, 选中=$CHOSEN_MODEL" "$(jq -n --arg m "$CHOSEN_MODEL" '{chosen_model:$m}')"
else
    emit_result "G7" "FAIL" "auto hint=reasoning: HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "${RESBODY:0:300}" '{http:$c, body:$b}')"
fi

# === G8: 同一 session 多次请求 - 保持稳定 ===
log_info "G8: 同一 session 多次请求"
SESSION_ID="test-session-$RANDOM"
declare -a CHOICES=()
for i in 1 2 3; do
    BODY='{"model":"auto","messages":[{"role":"user","content":"OK"}],"max_tokens":15,"stream":false}'
    TMP=$(mktemp)
    CODE=$(curl --http1.1 -s -o "$TMP" -w "%{http_code}" -m 30 \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -H "X-Gw-Session-Id: $SESSION_ID" \
        -X POST "$API_BASE/v1/chat/completions" \
        -d "$BODY" 2>&1)
    RESBODY=$(cat "$TMP")
    rm -f "$TMP"
    CHOSEN_MODEL=$(echo "$RESBODY" | jq -r '.model // ""' 2>/dev/null)
    CHOICES+=("$CHOSEN_MODEL")
done

if [[ "${#CHOICES[@]}" -gt 0 ]]; then
    UNIQUE_COUNT=$(printf '%s\n' "${CHOICES[@]}" | sort -u | wc -l | tr -d ' ')
    emit_result "G8" "PASS" "session 内 3 次请求, 选中=${CHOICES[*]}, 不同=$UNIQUE_COUNT" \
        "$(jq -n --argjson c "${CHOICES[@]}" --argjson u "$UNIQUE_COUNT" '{choices:$c, unique:$u}')"
else
    emit_result "G8" "FAIL" "session 多次请求失败" "{}"
fi

print_summary
exit "$FAIL_COUNT"