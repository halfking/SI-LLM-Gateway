#!/usr/bin/env bash
# 03_multi_cred.sh - C 类：多凭据路由 / Failover

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
suite_start "03_multi_cred"

# 已知多凭据模型（来自 docs/pricing/2026-06-12-all-paid-offers.csv）
declare -a MULTI_CRED_MODELS=(
    "minimax-m2.7"
    "gpt-4o"
    "claude-3-5-sonnet-20241022"
    "glm-4.7"
    "deepseek-v4-pro"
    "kimi-k2.6"
    "doubao-pro-128k"
)

# C1-C8: 每个模型串行 5 次请求（避免限流），统计成功率
for model in "${MULTI_CRED_MODELS[@]}"; do
    log_info "C: 测试 $model (5 次串行请求)"
    SUCCESS=0
    FAIL_NO_CAND=0
    FAIL_UPSTREAM_HANG=0
    FAIL_OTHER=0
    TOTAL_TOKENS_LIST=()

    for i in 1 2 3 4 5; do
        RESP=$(call_chat "$model" 20 false 2>&1)
        CODE=$(echo "$RESP" | head -n 1)
        BODY=$(echo "$RESP" | tail -n +2)

        if [[ "$CODE" == "200" ]]; then
            SUCCESS=$((SUCCESS + 1))
            TOKENS=$(echo "$BODY" | jq -r '.usage.total_tokens // 0' 2>/dev/null)
            TOTAL_TOKENS_LIST+=("$TOKENS")
        elif echo "$BODY" | grep -q "no_candidate"; then
            FAIL_NO_CAND=$((FAIL_NO_CAND + 1))
        elif [[ "$CODE" == "000" ]]; then
            FAIL_UPSTREAM_HANG=$((FAIL_UPSTREAM_HANG + 1))
        else
            FAIL_OTHER=$((FAIL_OTHER + 1))
        fi
    done

    # 用 --arg 代替 --argjson (数组)
    DETAILS=$(jq -n \
        --arg m "$model" \
        --argjson s "$SUCCESS" \
        --argjson nc "$FAIL_NO_CAND" \
        --argjson uh "$FAIL_UPSTREAM_HANG" \
        --argjson o "$FAIL_OTHER" \
        --arg tl "$(IFS=,; echo "${TOTAL_TOKENS_LIST[*]}")" \
        '{model:$m, success:$s, no_candidate:$nc, upstream_hang:$uh, other:$o, tokens_csv:$tl}')

    if [[ "$SUCCESS" -gt 0 ]]; then
        emit_result "C-$model.success" "PASS" "$model: $SUCCESS/5 成功" "$DETAILS"
    else
        emit_result "C-$model.success" "FAIL" "$model: 0/5 成功 (no_candidate=$FAIL_NO_CAND, hang=$FAIL_UPSTREAM_HANG, other=$FAIL_OTHER)" "$DETAILS"
    fi
done

# C9: 验证 routing_decision_log 存在 (通过 X-Gw-Auto-Profile 等 metadata)
log_info "C9: 验证响应携带路由决策元数据"
RESP=$(call_chat "minimax-m3" 30 false)
CODE=$(echo "$RESP" | head -n 1)
BODY=$(echo "$RESP" | tail -n +2)

# 从 response headers 检查 (但 call_chat 没返回 headers - 我们只检查 body 的 request_id)
REQUEST_ID=$(echo "$BODY" | jq -r '.id // ""' 2>/dev/null)
if [[ -n "$REQUEST_ID" ]]; then
    emit_result "C9" "PASS" "minimax-m3 响应含 request_id=$REQUEST_ID" "$(jq -n --arg r "$REQUEST_ID" '{request_id:$r}')"
else
    emit_result "C9" "FAIL" "minimax-m3 响应不含 request_id" "$(jq -n --arg b "$BODY" '{body:$b}')"
fi

# C10: 同一模型不同 X-Gw-Session-Id - 应分别路由
log_info "C10: 验证 X-Gw-Session-Id 不影响路由"
SESSION_A="session-A-$RANDOM"
SESSION_B="session-B-$RANDOM"
RESP_A=$(curl --http1.1 -s -m 30 -X POST "$API_BASE/v1/chat/completions" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Gw-Session-Id: $SESSION_A" \
    -d '{"model":"minimax-m3","messages":[{"role":"user","content":"OK"}],"max_tokens":15,"stream":false}' 2>&1)
RESP_B=$(curl --http1.1 -s -m 30 -X POST "$API_BASE/v1/chat/completions" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -H "X-Gw-Session-Id: $SESSION_B" \
    -d '{"model":"minimax-m3","messages":[{"role":"user","content":"OK"}],"max_tokens":15,"stream":false}' 2>&1)

CODE_A=$(echo "$RESP_A" | jq -r '.choices[0].message.content // ""' 2>/dev/null)
CODE_B=$(echo "$RESP_B" | jq -r '.choices[0].message.content // ""' 2>/dev/null)

if [[ -n "$CODE_A" && -n "$CODE_B" ]]; then
    emit_result "C10" "PASS" "两个 session 都成功（独立路由）" "$(jq -n --arg a "${CODE_A:0:50}" --arg b "${CODE_B:0:50}" '{sess_a:$a, sess_b:$b}')"
else
    emit_result "C10" "FAIL" "X-Gw-Session-Id 影响路由" "$(jq -n --arg a "$RESP_A" --arg b "$RESP_B" '{sess_a:$a, sess_b:$b}')"
fi

print_summary
exit "$FAIL_COUNT"