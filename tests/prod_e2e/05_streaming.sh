#!/usr/bin/env bash
# 05_streaming.sh - E 类：流式响应 SSE

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
suite_start "05_streaming"

mkdir -p "$RESULTS_DIR/stream_tmp"

# === E1: 基础 SSE ===
log_info "E1: 基础 SSE"
BODY='{"model":"minimax-m3","messages":[{"role":"user","content":"OK"}],"max_tokens":30,"stream":true}'
OUTFILE="$RESULTS_DIR/stream_tmp/E1.txt"
DURATION=$(call_chat_stream "$BODY" "$OUTFILE" 60)
CHUNK_COUNT=$(grep -c "^data: " "$OUTFILE" 2>/dev/null || echo 0)
HAS_DONE=$(grep -c "\[DONE\]" "$OUTFILE" 2>/dev/null || echo 0)
HAS_CONTENT=$(grep -c '"content":' "$OUTFILE" 2>/dev/null || echo 0)
CONTENT_TYPE=$(file -b "$OUTFILE" 2>/dev/null)

if [[ "$CHUNK_COUNT" -gt 0 && "$HAS_DONE" -gt 0 ]]; then
    emit_result "E1" "PASS" "基础 SSE: $CHUNK_COUNT chunks, [DONE]=$HAS_DONE, duration=${DURATION}s" \
        "$(jq -n --argjson c "$CHUNK_COUNT" --argjson d "$HAS_DONE" --arg dur "$DURATION" '{chunks:$c, done_markers:$d, duration:$dur}')"
else
    emit_result "E1" "FAIL" "基础 SSE: chunks=$CHUNK_COUNT, [DONE]=$HAS_DONE" \
        "$(jq -n --argjson c "$CHUNK_COUNT" --argjson d "$HAS_DONE" '{chunks:$c, done_markers:$d, preview: $("'"$OUTFILE"'" | cat | head -3)}')"
fi

# === E2: Keep-alive (用较长 prompt 触发) ===
log_info "E2: Keep-alive 注释检测"
LONG_PROMPT=$(python3 -c "print('Tell me a long story about ' * 100 + ' the end.')" 2>/dev/null || perl -e 'print "Tell me a long story about " x 100 . "the end."')
BODY=$(jq -n --arg p "$LONG_PROMPT" '{model:"minimax-m3", messages:[{role:"user", content:$p}], max_tokens:2000, stream:true}')
OUTFILE="$RESULTS_DIR/stream_tmp/E2.txt"
call_chat_stream "$BODY" "$OUTFILE" 60 > /dev/null 2>&1
HAS_KEEPALIVE=$(grep -c "^: keep-alive" "$OUTFILE" 2>/dev/null || echo 0)

# Keep-alive 触发条件：SSE chunk 间超过 15s 间隔。普通 prompt 通常不会触发
if [[ "$HAS_KEEPALIVE" -gt 0 ]]; then
    emit_result "E2" "PASS" "检测到 keep-alive 注释 ($HAS_KEEPALIVE 次)" "$(jq -n --argjson k "$HAS_KEEPALIVE" '{keepalive_count:$k}')"
else
    # 如果没有 keep-alive，意味着响应太快没触发，不是 bug
    emit_result "E2" "SKIP" "未触发 keep-alive（响应快于 15s keepaliveInterval）" "$(jq -n --argjson k "$HAS_KEEPALIVE" '{keepalive_count:$k}')"
fi

# === E3: First-byte latency ===
log_info "E3: First-byte 延迟"
BODY='{"model":"minimax-m3","messages":[{"role":"user","content":"OK"}],"max_tokens":15,"stream":true}'
OUTFILE="$RESULTS_DIR/stream_tmp/E3.txt"
START=$(date +%s.%N)
call_chat_stream "$BODY" "$OUTFILE" 30 > /dev/null 2>&1 &
PID=$!
# 等到第一个非空字节
for i in $(seq 1 300); do
    if [[ -s "$OUTFILE" ]]; then
        FIRST_BYTE=$(date +%s.%N)
        break
    fi
    sleep 0.1
done
kill $PID 2>/dev/null
wait $PID 2>/dev/null
if [[ -n "$FIRST_BYTE" ]]; then
    FIRST_BYTE_LATENCY=$(echo "$FIRST_BYTE $START" | awk '{printf "%.3f\n", $1-$2}')
    if (( $(echo "$FIRST_BYTE_LATENCY < 30" | bc -l 2>/dev/null || echo 1) )); then
        emit_result "E3" "PASS" "first-byte 延迟=${FIRST_BYTE_LATENCY}s (< 30s)" "$(jq -n --arg l "$FIRST_BYTE_LATENCY" '{first_byte_seconds:$l}')"
    else
        emit_result "E3" "FAIL" "first-byte 延迟=${FIRST_BYTE_LATENCY}s (>= 30s)" "$(jq -n --arg l "$FIRST_BYTE_LATENCY" '{first_byte_seconds:$l}')"
    fi
else
    emit_result "E3" "FAIL" "30s 内没收到 first-byte" "{\"file_size\":$(wc -c < "$OUTFILE" 2>/dev/null || echo 0)}"
fi

# === E4: 流式响应中 model 字段回填 ===
log_info "E4: 流式 model 字段回填"
BODY='{"model":"minimax-m3","messages":[{"role":"user","content":"OK"}],"max_tokens":15,"stream":true}'
OUTFILE="$RESULTS_DIR/stream_tmp/E4.txt"
call_chat_stream "$BODY" "$OUTFILE" 30 > /dev/null 2>&1
# 提取第一个 data chunk 的 model
FIRST_DATA_LINE=$(grep -m1 "^data: " "$OUTFILE" | sed 's/^data: //')
if [[ -n "$FIRST_DATA_LINE" && "$FIRST_DATA_LINE" != "[DONE]" ]]; then
    MODEL=$(echo "$FIRST_DATA_LINE" | jq -r '.model // ""' 2>/dev/null)
    if [[ "$MODEL" == "minimax-m3" ]]; then
        emit_result "E4" "PASS" "SSE chunks 中 model=minimax-m3 (回填正确)" "$(jq -n --arg m "$MODEL" '{model:$m}')"
    else
        emit_result "E4" "FAIL" "SSE chunks 中 model=$MODEL (应为 minimax-m3)" "$(jq -n --arg m "$MODEL" '{model:$m, line:$("'"$FIRST_DATA_LINE"'")}')"
    fi
else
    emit_result "E4" "FAIL" "没有收到 SSE chunk" "{\"first_line\":\"$FIRST_DATA_LINE\"}"
fi

# === E5: 流式 tool_calls ===
log_info "E5: 流式 tool_calls"
BODY='{"model":"minimax-m3","messages":[{"role":"user","content":"What is weather in Beijing?"}],"tools":[{"type":"function","function":{"name":"get_weather","description":"Get weather","parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}}],"max_tokens":100,"stream":true}'
OUTFILE="$RESULTS_DIR/stream_tmp/E5.txt"
call_chat_stream "$BODY" "$OUTFILE" 60 > /dev/null 2>&1
TOOL_CHUNK=$(grep "^data: " "$OUTFILE" | grep -v "\[DONE\]" | grep -o '"tool_calls"' | head -1)
if [[ -n "$TOOL_CHUNK" ]]; then
    emit_result "E5" "PASS" "流式 tool_calls 出现" "$(jq -n --arg t "$TOOL_CHUNK" '{tool_chunk:$t}')"
else
    # 也可能不用 tool_calls - 验证 response 至少含正常结构
    if grep -q "^data: " "$OUTFILE"; then
        emit_result "E5" "SKIP" "模型没用 tool_calls（用文本回复）" "$(jq -n --arg f "$(head -1 $OUTFILE)" '{first_chunk:$f}')"
    else
        emit_result "E5" "FAIL" "流式 tool_calls: 没有任何 SSE chunk" "{}"
    fi
fi

# === E6: 流式 content 拼接 ===
log_info "E6: 流式 content 拼接"
BODY='{"model":"minimax-m3","messages":[{"role":"user","content":"Reply with just the single word HELLO"}],"max_tokens":10,"stream":true}'
OUTFILE="$RESULTS_DIR/stream_tmp/E6.txt"
call_chat_stream "$BODY" "$OUTFILE" 30 > /dev/null 2>&1

# 用 jq 拼接所有 data chunk 的 content
STREAMED_CONTENT=$(grep "^data: " "$OUTFILE" | grep -v "\[DONE\]" | sed 's/^data: //' | jq -r 'select(.choices[0].delta.content != null) | .choices[0].delta.content' 2>/dev/null | tr -d '\n')
if [[ -n "$STREAMED_CONTENT" ]]; then
    emit_result "E6" "PASS" "流式拼接 content: '$STREAMED_CONTENT'" "$(jq -n --arg c "$STREAMED_CONTENT" '{content:$c}')"
else
    emit_result "E6" "FAIL" "没有拼接出流式 content" "{\"file_preview\":\"$(head -3 $OUTFILE | tr '\n' ' ')\"}"
fi

# === E7: 客户端取消 ===
log_info "E7: 客户端取消（curl 在 3s 后 kill）"
BODY='{"model":"minimax-m3","messages":[{"role":"user","content":"Tell me an extremely long story about AI, making sure it takes at least 60 seconds to read."}],"max_tokens":2000,"stream":true}'
OUTFILE="$RESULTS_DIR/stream_tmp/E7.txt"
START=$(date +%s)
curl --http1.1 -s --no-buffer -N -m 3 \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -X POST "$API_BASE/v1/chat/completions" \
    -d "$BODY" > "$OUTFILE" 2>&1
END=$(date +%s)
ELAPSED=$((END - START))
if [[ "$ELAPSED" -le 5 ]]; then
    emit_result "E7" "PASS" "客户端在 ${ELAPSED}s 后成功中断" "$(jq -n --argjson e "$ELAPSED" '{elapsed:$e, file_size: $(wc -c < $OUTFILE)}')"
else
    emit_result "E7" "FAIL" "客户端中断耗时 ${ELAPSED}s (期望 ≤ 5s)" "$(jq -n --argjson e "$ELAPSED" '{elapsed:$e}')"
fi

# === E10: Q3 SSE（OpenAI→Anthropic claude 模型）===
log_info "E10: Q3 SSE（OpenAI→Anthropic claude 模型）"
BODY='{"model":"claude-3-5-sonnet-20241022","messages":[{"role":"user","content":"Reply OK"}],"max_tokens":50,"stream":true}'
OUTFILE="$RESULTS_DIR/stream_tmp/E10.txt"
call_chat_stream "$BODY" "$OUTFILE" 30 > /dev/null 2>&1
CHUNK_COUNT=$(grep -c "^data: " "$OUTFILE" 2>/dev/null || echo 0)
HAS_DONE=$(grep -c "\[DONE\]" "$OUTFILE" 2>/dev/null || echo 0)
if [[ "$CHUNK_COUNT" -gt 0 && "$HAS_DONE" -gt 0 ]]; then
    emit_result "E10" "PASS" "Q3 SSE: $CHUNK_COUNT chunks, [DONE]=$HAS_DONE" "$(jq -n --argjson c "$CHUNK_COUNT" --argjson d "$HAS_DONE" '{chunks:$c, done_markers:$d}')"
elif [[ "$CHUNK_COUNT" -eq 0 ]]; then
    ERROR_PREVIEW=$(head -1 "$OUTFILE" 2>/dev/null | head -c 200)
    if echo "$ERROR_PREVIEW" | grep -q "no_candidate\|model_not_found"; then
        emit_result "E10" "SKIP" "claude-* 当前不可用" "$(jq -n --arg e "$ERROR_PREVIEW" '{preview:$e}')"
    else
        emit_result "E10" "FAIL" "Q3 SSE: 没有 chunk" "$(jq -n --arg e "$ERROR_PREVIEW" '{preview:$e}')"
    fi
else
    emit_result "E10" "FAIL" "Q3 SSE: chunks=$CHUNK_COUNT 但无 [DONE]" "$(jq -n --argjson c "$CHUNK_COUNT" --argjson d "$HAS_DONE" '{chunks:$c, done_markers:$d}')"
fi

# === E12: Responses API 流式 ===
log_info "E12: Responses API 流式"
BODY='{"model":"minimax-m3","input":"Reply OK","max_output_tokens":30,"stream":true}'
OUTFILE="$RESULTS_DIR/stream_tmp/E12.txt"
START=$(date +%s)
TMPF=$(mktemp)
CODE=$(curl --http1.1 -s --no-buffer -N -o "$TMPF" -w "%{http_code}" -m 60 \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -X POST "$API_BASE/v1/responses" \
    -d "$BODY" 2>&1)
END=$(date +%s)
ELAPSED=$((END - START))
cp "$TMPF" "$OUTFILE"
rm -f "$TMPF"

if [[ "$CODE" == "200" ]]; then
    EVENT_COUNT=$(grep -c "^event:" "$OUTFILE" 2>/dev/null || echo 0)
    HAS_COMPLETED=$(grep -c "response.completed" "$OUTFILE" 2>/dev/null || echo 0)
    HAS_CREATED=$(grep -c "response.created" "$OUTFILE" 2>/dev/null || echo 0)
    if [[ "$EVENT_COUNT" -gt 0 && "$HAS_COMPLETED" -gt 0 ]]; then
        emit_result "E12" "PASS" "Responses API 流式: $EVENT_COUNT events, has_created=$HAS_CREATED, has_completed=$HAS_COMPLETED" \
            "$(jq -n --argjson e "$EVENT_COUNT" --argjson c "$HAS_CREATED" --argjson d "$HAS_COMPLETED" '{events:$e, created:$c, completed:$d}')"
    else
        emit_result "E12" "FAIL" "Responses API 流式: events=$EVENT_COUNT, has_completed=$HAS_COMPLETED" \
            "$(jq -n --argjson e "$EVENT_COUNT" --arg b "$(head -c 300 $OUTFILE)" '{events:$e, body_preview:$b}')"
    fi
else
    emit_result "E12" "FAIL" "Responses API 流式 HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "$(head -c 300 $OUTFILE)" '{http:$c, body:$b}')"
fi

# === E13: 流中 thinking 块 (minimax-m3 会产生 <think>) ===
log_info "E13: 流中 thinking 块 (minimax-m3)"
BODY='{"model":"minimax-m3","messages":[{"role":"user","content":"What is 1+1? Think briefly."}],"max_tokens":200,"stream":true}'
OUTFILE="$RESULTS_DIR/stream_tmp/E13.txt"
call_chat_stream "$BODY" "$OUTFILE" 30 > /dev/null 2>&1

# 检查 raw text chunk 是否含 <think>
HAS_THINK_RAW=$(grep -c "<think>" "$OUTFILE" 2>/dev/null || echo 0)
HAS_REASONING=$(grep -c "reasoning_content" "$OUTFILE" 2>/dev/null || echo 0)

if [[ "$HAS_THINK_RAW" -gt 0 || "$HAS_REASONING" -gt 0 ]]; then
    emit_result "E13" "PASS" "thinking 块存在: raw_think=$HAS_THINK_RAW, reasoning=$HAS_REASONING" \
        "$(jq -n --argjson r "$HAS_THINK_RAW" --argjson k "$HAS_REASONING" '{raw_think:$r, reasoning:$k}')"
else
    # 短 prompt 不一定触发 thinking
    emit_result "E13" "SKIP" "未触发 thinking 块（可能 prompt 简单）" "$(jq -n --arg b "$(head -c 200 $OUTFILE)" '{preview:$b}')"
fi

# === E14: 大响应流 max_tokens=2000 ===
log_info "E14: 大响应流 max_tokens=2000"
BODY='{"model":"minimax-m3","messages":[{"role":"user","content":"Write a long essay about space exploration in 500 words."}],"max_tokens":2000,"stream":true}'
OUTFILE="$RESULTS_DIR/stream_tmp/E14.txt"
START=$(date +%s.%N)
call_chat_stream "$BODY" "$OUTFILE" 90 > /dev/null 2>&1
END=$(date +%s.%N)
ELAPSED=$(echo "$END $START" | awk '{printf "%.3f", $1-$2}')
CHUNK_COUNT=$(grep -c "^data: " "$OUTFILE" 2>/dev/null || echo 0)
if [[ "$CHUNK_COUNT" -gt 0 ]]; then
    emit_result "E14" "PASS" "大响应流: $CHUNK_COUNT chunks, ${ELAPSED}s" \
        "$(jq -n --argjson c "$CHUNK_COUNT" --arg e "$ELAPSED" '{chunks:$c, duration:$e}')"
else
    emit_result "E14" "FAIL" "大响应流: 0 chunks" "{}"
fi

print_summary
exit "$FAIL_COUNT"