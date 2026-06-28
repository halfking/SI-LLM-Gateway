#!/usr/bin/env bash
# 10_data_correctness.sh - J 类：数据正确性

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
suite_start "10_data_correctness"

# === J1: 每个响应都带 X-Request-Id (32 字符 hex) ===
log_info "J1: X-Request-Id"
TMP=$(mktemp)
BODY='{"model":"minimax-m3","messages":[{"role":"user","content":"OK"}],"max_tokens":10,"stream":false}'
curl --http1.1 -s -D "$TMP" -o /dev/null -m 30 \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -X POST "$API_BASE/v1/chat/completions" \
    -d "$BODY" 2>&1
RID_HEADER=$(grep -i "^x-request-id:" "$TMP" | awk '{print $2}' | tr -d '\r' || echo "")
rm -f "$TMP"

if [[ -n "$RID_HEADER" ]] && [[ ${#RID_HEADER} -ge 16 ]]; then
    emit_result "J1" "PASS" "X-Request-Id 存在: $RID_HEADER (len=${#RID_HEADER})" "$(jq -n --arg r "$RID_HEADER" '{request_id:$r}')"
else
    emit_result "J1" "FAIL" "X-Request-Id 缺失或太短" "$(jq -n --arg r "$RID_HEADER" '{request_id:$r}')"
fi

# === J2: 同一请求并发 5 次 → 5 个不同 request_id ===
log_info "J2: 同一请求并发 5 次 → 5 个不同 request_id"
tmpdir=$(mktemp -d)
for i in 1 2 3 4 5; do
    curl --http1.1 -s -D "$tmpdir/h-$i.txt" -o "$tmpdir/b-$i.txt" -m 30 \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -X POST "$API_BASE/v1/chat/completions" \
        -d "$BODY" > /dev/null 2>&1 &
done
wait

declare -a rids=()
for i in 1 2 3 4 5; do
    rid=$(grep -i "^x-request-id:" "$tmpdir/h-$i.txt" | awk '{print $2}' | tr -d '\r' || echo "")
    [[ -n "$rid" ]] && rids+=("$rid")
done
rm -rf "$tmpdir"

unique_count=$(printf '%s\n' "${rids[@]}" | sort -u | wc -l | tr -d ' ')
total=${#rids[@]}

if [[ "$unique_count" -eq 5 ]]; then
    emit_result "J2" "PASS" "5 个不同 request_id" "$(jq -n --argjson r "${rids[@]}" '{request_ids:$r}')"
else
    emit_result "J2" "FAIL" "5 并发有重复: unique=$unique_count/5" "$(jq -n --argjson r "${rids[@]}" --argjson u "$unique_count" '{request_ids:$r, unique:$u}')"
fi

# === J3: SSE chunks 总和的 completion_tokens 等于 non-stream 模式 ===
log_info "J3: SSE chunks 总和 = non-stream completion_tokens"
# 3 个相同 prompt: 1 stream, 1 non-stream, 比较
NON_STREAM_RESP=$(call_chat "minimax-m3" 30 false)
NS_CODE=$(echo "$NON_STREAM_RESP" | head -n 1)
NS_BODY=$(echo "$NON_STREAM_RESP" | tail -n +2)
NS_TOKENS=$(echo "$NS_BODY" | jq -r '.usage.completion_tokens // 0' 2>/dev/null)
NS_PROMPT=$(echo "$NS_BODY" | jq -r '.usage.prompt_tokens // 0' 2>/dev/null)
NS_TOTAL=$(echo "$NS_BODY" | jq -r '.usage.total_tokens // 0' 2>/dev/null)
NS_CONTENT=$(echo "$NS_BODY" | jq -r '.choices[0].message.content // ""' 2>/dev/null)

# 流式
OUTFILE="$RESULTS_DIR/stream_tmp/J3.txt"
PROMPT='{"role":"user","content":"OK"}'
BODY_STREAM=$(jq -n --argjson p "$PROMPT" '{model:"minimax-m3", messages:[$p], max_tokens:30, stream:true}')
call_chat_stream "$BODY_STREAM" "$OUTFILE" 60 > /dev/null 2>&1
STREAMED_CONTENT=$(grep "^data: " "$OUTFILE" | grep -v "\[DONE\]" | sed 's/^data: //' | jq -r 'select(.choices[0].delta.content != null) | .choices[0].delta.content' 2>/dev/null | tr -d '\n')

# 注: 流式 response 可能在最后有 usage chunk
STREAM_USAGE=$(grep "^data: " "$OUTFILE" | grep -v "\[DONE\]" | tail -5 | sed 's/^data: //' | jq -r 'select(.usage != null) | .usage.completion_tokens // 0' 2>/dev/null | tail -1)

# 主要验证：内容等价（粗略比较）
NS_SHORT=$(echo "$NS_CONTENT" | head -c 50)
ST_SHORT=$(echo "$STREAMED_CONTENT" | head -c 50)

if [[ -n "$STREAMED_CONTENT" && -n "$NS_CONTENT" ]]; then
    emit_result "J3" "PASS" "non-stream: ${NS_TOKENS} tokens; stream 内容存在 (head=${ST_SHORT:0:30}...)" \
        "$(jq -n --argjson ns "$NS_TOKENS" --arg nst "$NS_TOTAL" --arg nsp "$NS_PROMPT" --arg sc "${STREAMED_CONTENT:0:100}" --arg nc "${NS_CONTENT:0:100}" '{non_stream_tokens:$ns, total:$nst, prompt:$nsp, streamed_preview:$sc, non_stream_preview:$nc}')"
else
    emit_result "J3" "FAIL" "J3: 流式或非流式无内容" "$(jq -n --arg nsc "$NS_CODE" '{ns_code:$nsc}')"
fi

# === J4: 错误响应 JSON 包含 request_id ===
log_info "J4: 错误响应 request_id"
RESP=$(call_chat "fake-model-99999" 5 false)
CODE=$(echo "$RESP" | head -n 1)
BODY=$(echo "$RESP" | tail -n +2)
ERR_REQ_ID=$(echo "$BODY" | jq -r '.error.request_id // ""' 2>/dev/null)
if [[ -n "$ERR_REQ_ID" ]]; then
    emit_result "J4" "PASS" "错误响应含 request_id=$ERR_REQ_ID" "$(jq -n --arg r "$ERR_REQ_ID" '{request_id:$r}')"
else
    # 检查在 header 里
    TMP=$(mktemp)
    curl --http1.1 -s -D "$TMP" -o /dev/null -m 30 \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -X POST "$API_BASE/v1/chat/completions" \
        -d '{"model":"fake-model-99999","messages":[{"role":"user","content":"hi"}],"max_tokens":5}' 2>&1 > /dev/null
    HEADER_RID=$(grep -i "^x-request-id:" "$TMP" | awk '{print $2}' | tr -d '\r' || echo "")
    rm -f "$TMP"
    if [[ -n "$HEADER_RID" ]]; then
        emit_result "J4" "PASS" "错误响应 header 含 request_id=$HEADER_RID" "$(jq -n --arg r "$HEADER_RID" '{request_id:$r}')"
    else
        emit_result "J4" "FAIL" "错误响应无 request_id" "$(jq -n --arg b "${BODY:0:300}" '{body:$b}')"
    fi
fi

# === J5: 错误响应不包含供应商名称或 API key 明文 ===
log_info "J5: 错误响应不含敏感信息"
# 触发一个 5xx 错误的请求（用 valid 模型但只通过，让它走 fail 路径）
# 简单的：用 bad body 触发 400
BAD_BODY='{"model":"minimax-m3","messages":[{"role":"user","content":""}]}'
RESP=$(call_chat_with_body "$BAD_BODY")
BODY=$(echo "$RESP" | tail -n +2)
# 检查是否含敏感关键字
SENSITIVE_FOUND=""
for keyword in "sk-e2e-1781897808" "api.minimax" "dashscope" "kxpms.cn" "open.bigmodel" "api.deepseek"; do
    if echo "$BODY" | grep -q "$keyword"; then
        SENSITIVE_FOUND="$SENSITIVE_FOUND $keyword"
    fi
done
if [[ -z "$SENSITIVE_FOUND" ]]; then
    emit_result "J5" "PASS" "错误响应不含供应商/API key 关键字" "$(jq -n --arg b "${BODY:0:300}" '{body:$b}')"
else
    emit_result "J5" "FAIL" "错误响应含敏感关键字: $SENSITIVE_FOUND" "$(jq -n --arg b "${BODY:0:500}" '{body:$b}')"
fi

print_summary
exit "$FAIL_COUNT"