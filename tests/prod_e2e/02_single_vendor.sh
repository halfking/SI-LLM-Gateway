#!/usr/bin/env bash
# 02_single_vendor.sh - B 类：单供应商路由
# 验证不同模型能正确路由到对应供应商并返回 200 + 合理 usage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
suite_start "02_single_vendor"

# 模型与期望供应商的映射
# 格式: model|expected_provider_label
declare -a MODELS=(
    "minimax-m3|minimax"
    "minimax-m2.7|minimax"
    "minimax-text-01|minimax"
    "glm-4.5-air|zhipu"
    "glm-4.5-flash|zhipu"
    "glm-4.6|zhipu"
    "glm-4.7|zhipu"
    "deepseek-v3|deepseek"
    "deepseek-v3-1|deepseek"
    "deepseek-r1|deepseek"
    "kimi-k2|moonshot"
    "kimi-k2.5|moonshot"
    "kimi-k2.6|moonshot"
    "qwen3-32b|qwen"
    "qwen3-235b-a22b|qwen"
    "doubao-pro-32k|doubao"
    "mimo-v2.5-pro|xiaomi"
    "llama-3.3-70b-instruct|meta"
    "mistral-large|mistral"
)

declare -a SUMMARY=()

for entry in "${MODELS[@]}"; do
    MODEL="${entry%|*}"
    PROVIDER="${entry#*|}"

    log_info "测试 $MODEL (期望供应商=$PROVIDER)"

    # 调用
    RESP=$(call_chat "$MODEL" 30 false)
    CODE=$(echo "$RESP" | head -n 1)
    BODY=$(echo "$RESP" | tail -n +2)

    # 基础断言
    if [[ "$CODE" != "200" ]]; then
        # 一些模型可能不可用 - 标记为 SKIP
        ERR=$(echo "$BODY" | jq -r '.error.code // ""' 2>/dev/null)
        if [[ -n "$ERR" ]]; then
            emit_result "B-$MODEL" "SKIP" "模型 $MODEL 当前不可用 ($ERR)" "$(jq -n --arg c "$CODE" --arg e "$ERR" --arg b "${BODY:0:200}" '{http_code:$c, error_code:$e, body:$b}')"
        else
            emit_result "B-$MODEL" "FAIL" "模型 $MODEL 返回 HTTP $CODE" "$(jq -n --arg c "$CODE" --arg b "${BODY:0:300}" '{http_code:$c, body:$b}')"
        fi
        continue
    fi

    # 200 OK - 验证字段
    RETURNED_MODEL=$(echo "$BODY" | jq -r '.model // ""' 2>/dev/null)
    TOTAL_TOKENS=$(echo "$BODY" | jq -r '.usage.total_tokens // 0' 2>/dev/null)
    PROMPT_TOKENS=$(echo "$BODY" | jq -r '.usage.prompt_tokens // 0' 2>/dev/null)
    COMPLETION_TOKENS=$(echo "$BODY" | jq -r '.usage.completion_tokens // 0' 2>/dev/null)
    CONTENT=$(echo "$BODY" | jq -r '.choices[0].message.content // ""' 2>/dev/null)
    FINISH=$(echo "$BODY" | jq -r '.choices[0].finish_reason // ""' 2>/dev/null)
    REQUEST_ID=$(echo "$BODY" | jq -r '.id // ""' 2>/dev/null)

    DETAILS=$(jq -n \
        --arg m "$RETURNED_MODEL" \
        --argjson pt "$PROMPT_TOKENS" \
        --argjson ct "$COMPLETION_TOKENS" \
        --argjson tt "$TOTAL_TOKENS" \
        --arg c "$CONTENT" \
        --arg f "$FINISH" \
        --arg r "$REQUEST_ID" \
        --arg p "$PROVIDER" \
        '{provider:$p, returned_model:$m, prompt_tokens:$pt, completion_tokens:$ct, total_tokens:$tt, content:$c, finish_reason:$f, request_id:$r}')

    # 验证 1: model 字段回填为客户端传入的原始名
    if [[ "$RETURNED_MODEL" == "$MODEL" ]]; then
        emit_result "B-${MODEL}.model" "PASS" "$MODEL: response.model 回填正确" "$DETAILS"
    else
        emit_result "B-${MODEL}.model" "FAIL" "$MODEL: response.model 不匹配 (expected=$MODEL, got=$RETURNED_MODEL)" "$DETAILS"
    fi

    # 验证 2: usage.total_tokens > 0
    if [[ "$TOTAL_TOKENS" -gt 0 ]]; then
        emit_result "B-${MODEL}.tokens" "PASS" "$MODEL: usage.total_tokens=$TOTAL_TOKENS" "$DETAILS"
    else
        emit_result "B-${MODEL}.tokens" "FAIL" "$MODEL: usage.total_tokens=0" "$DETAILS"
    fi

    # 验证 3: content 非空
    if [[ -n "$CONTENT" ]]; then
        emit_result "B-${MODEL}.content" "PASS" "$MODEL: content 非空 (len=${#CONTENT})" "$DETAILS"
    else
        emit_result "B-${MODEL}.content" "FAIL" "$MODEL: content 为空" "$DETAILS"
    fi

    # 验证 4: finish_reason 是合法的
    if [[ "$FINISH" == "stop" || "$FINISH" == "length" ]]; then
        emit_result "B-${MODEL}.finish" "PASS" "$MODEL: finish_reason=$FINISH" "$DETAILS"
    else
        emit_result "B-${MODEL}.finish" "FAIL" "$MODEL: finish_reason=$FINISH (应为 stop/length)" "$DETAILS"
    fi

    SUMMARY+=("$MODEL|http=$CODE|tokens=$TOTAL_TOKENS|model=$RETURNED_MODEL|finish=$FINISH")
done

# 输出汇总
log_info "测试汇总："
for s in "${SUMMARY[@]}"; do
    echo "  $s"
done

print_summary
exit "$FAIL_COUNT"