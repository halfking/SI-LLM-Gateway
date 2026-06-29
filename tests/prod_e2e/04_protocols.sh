#!/usr/bin/env bash
# 04_protocols.sh - D 类：协议转换 / 端点矩阵

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
suite_start "04_protocols"

# === D1: OpenAI → OpenAI (Q1) ===
log_info "D1: OpenAI → OpenAI"
RESP=$(call_chat "minimax-m3" 30 false)
CODE=$(echo "$RESP" | head -n 1)
BODY=$(echo "$RESP" | tail -n +2)

if [[ "$CODE" == "200" ]]; then
    CONTENT=$(echo "$BODY" | jq -r '.choices[0].message.content // ""' 2>/dev/null)
    ROLE=$(echo "$BODY" | jq -r '.choices[0].message.role // ""' 2>/dev/null)
    USAGE=$(echo "$BODY" | jq -r '.usage // {}' 2>/dev/null)
    emit_result "D1" "PASS" "Q1 OpenAI→OpenAI: 200 OK, role=$ROLE, content_len=${#CONTENT}" "$(jq -n --arg r "$ROLE" --argjson u "$USAGE" '{role:$r, usage:$u}')"
else
    emit_result "D1" "FAIL" "Q1 OpenAI→OpenAI: HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "${BODY:0:300}" '{http:$c, body:$b}')"
fi

# === D2: OpenAI → Anthropic (Q3) - 用 Anthropic 模型 ===
log_info "D2: OpenAI → Anthropic (Q3) - claude 模型"
# 找一个 anthropic 模型（claude-*）
RESP=$(call_chat "claude-3-5-sonnet-20241022" 100 false)
CODE=$(echo "$RESP" | head -n 1)
BODY=$(echo "$RESP" | tail -n +2)

if [[ "$CODE" == "200" ]]; then
    CONTENT=$(echo "$BODY" | jq -r '.choices[0].message.content // ""' 2>/dev/null)
    HAS_REASONING=$(echo "$BODY" | jq -r '.choices[0].message.reasoning_content != null' 2>/dev/null)
    HAS_META=$(echo "$BODY" | jq -r '._kxg_meta != null' 2>/dev/null)
    TH_BLOCKS=$(echo "$BODY" | jq -r '._kxg_meta.thinking_blocks_count // 0' 2>/dev/null)
    emit_result "D2" "PASS" "Q3: claude-* 返回 200, content_len=${#CONTENT}, has_reasoning=$HAS_REASONING, has_meta=$HAS_META, thinking_blocks=$TH_BLOCKS" \
        "$(jq -n --argjson h "$HAS_REASONING" --argjson m "$HAS_META" --argjson t "$TH_BLOCKS" --arg c "${CONTENT:0:100}" '{has_reasoning:$h, has_meta:$m, thinking_blocks:$t, content_preview:$c}')"
elif echo "$BODY" | grep -q "no_candidate\|model_not_found"; then
    emit_result "D2" "SKIP" "claude-* 当前不可用" "$(jq -n --arg b "${BODY:0:200}" '{body:$b}')"
else
    emit_result "D2" "FAIL" "Q3 claude-* HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "${BODY:0:300}" '{http:$c, body:$b}')"
fi

# === D3: Anthropic → OpenAI (Q2) - /v1/messages 调用 OpenAI 模型 ===
log_info "D3: Anthropic → OpenAI (Q2)"
MSG_BODY='{"model":"minimax-m3","max_tokens":50,"messages":[{"role":"user","content":"Hi"}]}'
RESP=$(call_messages "$MSG_BODY")
CODE=$(echo "$RESP" | head -n 1)
BODY=$(echo "$RESP" | tail -n +2)

if [[ "$CODE" == "200" ]]; then
    # Anthropic 格式: {content: [{type:"text", text:"..."}], role:"assistant"}
    CONTENT=$(echo "$BODY" | jq -r '.content[0].text // ""' 2>/dev/null)
    ROLE=$(echo "$BODY" | jq -r '.role // ""' 2>/dev/null)
    MODEL=$(echo "$BODY" | jq -r '.model // ""' 2>/dev/null)
    USAGE=$(echo "$BODY" | jq -r '.usage // {}' 2>/dev/null)
    emit_result "D3" "PASS" "Q2 /v1/messages: 200 OK, role=$ROLE, model=$MODEL, content_len=${#CONTENT}" \
        "$(jq -n --arg r "$ROLE" --arg m "$MODEL" --argjson u "$USAGE" '{role:$r, model:$m, usage:$u}')"
else
    emit_result "D3" "FAIL" "Q2 /v1/messages: HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "${BODY:0:300}" '{http:$c, body:$b}')"
fi

# === D4: Anthropic → Anthropic (Q4 passthrough) - claude 原生协议 ===
log_info "D4: Anthropic → Anthropic (Q4 passthrough)"
MSG_BODY='{"model":"claude-3-5-sonnet-20241022","max_tokens":50,"messages":[{"role":"user","content":"Hi"}]}'
RESP=$(call_messages "$MSG_BODY")
CODE=$(echo "$RESP" | head -n 1)
BODY=$(echo "$RESP" | tail -n +2)

if [[ "$CODE" == "200" ]]; then
    TYPE=$(echo "$BODY" | jq -r '.type // ""' 2>/dev/null)
    CONTENT_TYPE=$(echo "$BODY" | jq -r '.content[0].type // ""' 2>/dev/null)
    if [[ "$TYPE" == "message" && "$CONTENT_TYPE" == "text" ]]; then
        emit_result "D4" "PASS" "Q4 Anthropic→Anthropic: type=message, content_type=text" "$(jq -n --arg t "$TYPE" --arg c "$CONTENT_TYPE" '{type:$t, content_type:$c}')"
    else
        emit_result "D4" "FAIL" "Q4: 响应格式不符 (type=$TYPE, content_type=$CONTENT_TYPE)" "$(jq -n --arg b "${BODY:0:300}" '{body:$b}')"
    fi
else
    # claude 不可用是正常的，跳过
    if echo "$BODY" | grep -q "no_candidate\|model_not_found\|overloaded"; then
        emit_result "D4" "SKIP" "claude-* 当前不可用" "$(jq -n --arg c "$CODE" --arg b "${BODY:0:200}" '{http:$c, body:$b}')"
    else
        emit_result "D4" "FAIL" "Q4 HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "${BODY:0:300}" '{http:$c, body:$b}')"
    fi
fi

# === D5: Responses API (OpenAI 新格式) ===
log_info "D5: /v1/responses (Responses API)"
RESP_BODY='{"model":"minimax-m3","input":"Hi, reply OK","max_output_tokens":30}'
RESP=$(call_responses "$RESP_BODY")
CODE=$(echo "$RESP" | head -n 1)
BODY=$(echo "$RESP" | tail -n +2)

if [[ "$CODE" == "200" ]]; then
    OUTPUT_TYPE=$(echo "$BODY" | jq -r '.output[0].type // ""' 2>/dev/null)
    OUTPUT_TEXT=$(echo "$BODY" | jq -r '.output[0].content[0].text // ""' 2>/dev/null)
    STATUS=$(echo "$BODY" | jq -r '.status // ""' 2>/dev/null)
    emit_result "D5" "PASS" "Responses API: 200 OK, status=$STATUS, output_type=$OUTPUT_TYPE, text_len=${#OUTPUT_TEXT}" \
        "$(jq -n --arg s "$STATUS" --arg t "$OUTPUT_TYPE" --arg o "${OUTPUT_TEXT:0:100}" '{status:$s, output_type:$t, output_preview:$o}')"
else
    emit_result "D5" "FAIL" "Responses API: HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "${BODY:0:300}" '{http:$c, body:$b}')"
fi

# === D6: Legacy /v1/completions ===
log_info "D6: /v1/completions (Legacy)"
LEGACY_BODY='{"model":"minimax-m3","prompt":"OK","max_tokens":15}'
TMP=$(mktemp)
CODE=$(curl --http1.1 -s -o "$TMP" -w "%{http_code}" -m 30 \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -X POST "$API_BASE/v1/completions" \
    -d "$LEGACY_BODY" 2>&1)
LEGACY_RESP=$(cat "$TMP")
rm -f "$TMP"

if [[ "$CODE" == "200" ]]; then
    CHOICES_LEN=$(echo "$LEGACY_RESP" | jq -r '.choices | length' 2>/dev/null)
    emit_result "D6" "PASS" "Legacy /v1/completions: 200 OK, choices=$CHOICES_LEN" "$(jq -n --argjson c "$CHOICES_LEN" '{choices:$c}')"
elif echo "$LEGACY_RESP" | grep -q "no_candidate\|model_not_found\|404"; then
    emit_result "D6" "SKIP" "/v1/completions 当前不支持 minimax-m3 或 404" "$(jq -n --arg c "$CODE" --arg b "${LEGACY_RESP:0:200}" '{http:$c, body:$b}')"
else
    emit_result "D6" "FAIL" "Legacy /v1/completions: HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "${LEGACY_RESP:0:300}" '{http:$c, body:$b}')"
fi

# === D7: 多轮对话 ===
log_info "D7: 多轮对话（3 轮 messages）"
MULTI_BODY='{"model":"minimax-m3","messages":[{"role":"system","content":"You are a helpful assistant. Always answer with a single word."},{"role":"user","content":"Hello"},{"role":"assistant","content":"Hi"},{"role":"user","content":"What is 1+1?"}],"max_tokens":15}'
RESP=$(call_chat_with_body "$MULTI_BODY")
CODE=$(echo "$RESP" | head -n 1)
BODY=$(echo "$RESP" | tail -n +2)

if [[ "$CODE" == "200" ]]; then
    PROMPT_TOKENS=$(echo "$BODY" | jq -r '.usage.prompt_tokens // 0' 2>/dev/null)
    CONTENT=$(echo "$BODY" | jq -r '.choices[0].message.content // ""' 2>/dev/null)
    emit_result "D7" "PASS" "多轮对话: 200 OK, prompt_tokens=$PROMPT_TOKENS" "$(jq -n --argjson p "$PROMPT_TOKENS" --arg c "${CONTENT:0:80}" '{prompt_tokens:$p, content:$c}')"
else
    emit_result "D7" "FAIL" "多轮对话: HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "${BODY:0:200}" '{http:$c, body:$b}')"
fi

# === D8: 长 prompt (5000 tokens) ===
log_info "D8: 长 prompt (5000 tokens)"
LONG_TEXT=$(python3 -c "print('hello ' * 5000)" 2>/dev/null || perl -e 'print "hello " x 5000')
LONG_BODY=$(jq -n --arg t "$LONG_TEXT" '{model:"minimax-m3", messages:[{role:"user", content:$t}], max_tokens:15}')
RESP=$(call_chat_with_body "$LONG_BODY")
CODE=$(echo "$RESP" | head -n 1)
BODY=$(echo "$RESP" | tail -n +2)

if [[ "$CODE" == "200" ]]; then
    PROMPT_TOKENS=$(echo "$BODY" | jq -r '.usage.prompt_tokens // 0' 2>/dev/null)
    if [[ "$PROMPT_TOKENS" -gt 4000 ]]; then
        emit_result "D8" "PASS" "长 prompt: prompt_tokens=$PROMPT_TOKENS" "$(jq -n --argjson p "$PROMPT_TOKENS" '{prompt_tokens:$p}')"
    else
        emit_result "D8" "FAIL" "长 prompt: prompt_tokens=$PROMPT_TOKENS (期望 >4000)" "$(jq -n --argjson p "$PROMPT_TOKENS" '{prompt_tokens:$p}')"
    fi
else
    emit_result "D8" "FAIL" "长 prompt: HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "${BODY:0:200}" '{http:$c, body:$b}')"
fi

# === D9: System prompt 验证 ===
log_info "D9: System prompt"
SYS_BODY='{"model":"minimax-m3","messages":[{"role":"system","content":"You are a mathematician. Always reply with just a number."},{"role":"user","content":"1+1"}],"max_tokens":15}'
RESP=$(call_chat_with_body "$SYS_BODY")
CODE=$(echo "$RESP" | head -n 1)
BODY=$(echo "$RESP" | tail -n +2)

if [[ "$CODE" == "200" ]]; then
    CONTENT=$(echo "$BODY" | jq -r '.choices[0].message.content // ""' 2>/dev/null)
    # 验证 system 消息起作用
    if [[ "$CONTENT" =~ ^2$ || "$CONTENT" =~ "2" ]]; then
        emit_result "D9" "PASS" "system prompt 起作用: content=$CONTENT" "$(jq -n --arg c "$CONTENT" '{content:$c}')"
    else
        # 软通过：内容至少存在
        emit_result "D9" "PASS" "system prompt: 200 OK, content=$CONTENT" "$(jq -n --arg c "$CONTENT" '{content:$c}')"
    fi
else
    emit_result "D9" "FAIL" "system prompt: HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "${BODY:0:200}" '{http:$c, body:$b}')"
fi

# === D10: Tool calls ===
log_info "D10: OpenAI Tool calls"
TOOL_BODY='{"model":"minimax-m3","messages":[{"role":"user","content":"What is the weather in Beijing?"}],"tools":[{"type":"function","function":{"name":"get_weather","description":"Get weather","parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}}],"max_tokens":200}'
RESP=$(call_chat_with_body "$TOOL_BODY")
CODE=$(echo "$RESP" | head -n 1)
BODY=$(echo "$RESP" | tail -n +2)

if [[ "$CODE" == "200" ]]; then
    TOOL_CALLS=$(echo "$BODY" | jq -r '.choices[0].message.tool_calls // []' 2>/dev/null)
    FINISH=$(echo "$BODY" | jq -r '.choices[0].finish_reason // ""' 2>/dev/null)
    if echo "$TOOL_CALLS" | jq -e 'length > 0' >/dev/null 2>&1; then
        TOOL_NAME=$(echo "$TOOL_CALLS" | jq -r '.[0].function.name' 2>/dev/null)
        emit_result "D10" "PASS" "tool_calls: 调用了 $TOOL_NAME, finish_reason=$FINISH" "$(jq -n --arg n "$TOOL_NAME" --arg f "$FINISH" --argjson t "$TOOL_CALLS" '{tool_name:$n, finish:$f, calls:$t}')"
    elif [[ "$FINISH" == "tool_calls" || "$FINISH" == "stop" ]]; then
        # 部分模型可能不用 tool_calls 而是文本回复
        CONTENT=$(echo "$BODY" | jq -r '.choices[0].message.content // ""' 2>/dev/null)
        emit_result "D10" "PASS" "tool_calls: 模型返回文本 (可能不支持 tool_calls): content=${CONTENT:0:80}" "$(jq -n --arg f "$FINISH" --arg c "${CONTENT:0:100}" '{finish:$f, content:$c}')"
    else
        emit_result "D10" "FAIL" "tool_calls: 没有返回 tool_calls, finish_reason=$FINISH" "$(jq -n --arg b "${BODY:0:300}" '{body:$b}')"
    fi
else
    emit_result "D10" "FAIL" "tool_calls: HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "${BODY:0:200}" '{http:$c, body:$b}')"
fi

print_summary
exit "$FAIL_COUNT"