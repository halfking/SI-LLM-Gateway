#!/usr/bin/env bash
# 08_concurrency.sh - H 类：并发与限流

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
suite_start "08_concurrency"

mkdir -p "$RESULTS_DIR/concurrency_tmp"

# 公共函数 - 并发发起 N 个 chat 请求
concurrency_test() {
    local name="$1" n="$2" model="$3" max_tokens="$4"
    log_info "$name: $n 并发 → $model"

    local tmpdir
    tmpdir=$(mktemp -d)
    local start end
    start=$(date +%s.%N)

    # 启动 n 个后台 curl
    local pids=()
    for i in $(seq 1 "$n"); do
        local body
        body=$(jq -n --arg m "$model" --argjson mt "$max_tokens" '{model:$m, messages:[{role:"user", content:"OK"}], max_tokens:$mt, stream:false}')
        curl --http1.1 -s -o "$tmpdir/$i.txt" -w "%{http_code}\n" -m 30 \
            -H "Authorization: Bearer $API_KEY" \
            -H "Content-Type: application/json" \
            -X POST "$API_BASE/v1/chat/completions" \
            -d "$body" > "$tmpdir/$i.code" 2>&1 &
        pids+=($!)
    done

    # 等待所有完成
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null
    done

    end=$(date +%s.%N)
    local elapsed
    elapsed=$(echo "$end $start" | awk '{printf "%.3f\n", $1-$2}')

    # 统计状态码
    local code_200=0 code_429=0 code_503=0 code_other=0
    local request_ids=()
    for i in $(seq 1 "$n"); do
        local code
        code=$(cat "$tmpdir/$i.code" 2>/dev/null)
        case "$code" in
            200) code_200=$((code_200 + 1)) ;;
            429) code_429=$((code_429 + 1)) ;;
            503) code_503=$((code_503 + 1)) ;;
            *) code_other=$((code_other + 1)) ;;
        esac
        # 收集 request_id
        local body
        body=$(cat "$tmpdir/$i.txt" 2>/dev/null)
        local rid
        rid=$(echo "$body" | jq -r '.id // ""' 2>/dev/null)
        [[ -n "$rid" ]] && request_ids+=("$rid")
    done

    # 检查重复 request_id
    local unique_ids
    unique_ids=$(printf '%s\n' "${request_ids[@]}" | sort -u | wc -l | tr -d ' ')
    local total_ids=${#request_ids[@]}
    local dup_count=$((total_ids - unique_ids))

    rm -rf "$tmpdir"

    local details
    details=$(jq -n \
        --argjson n "$n" \
        --argjson c200 "$code_200" \
        --argjson c429 "$code_429" \
        --argjson c503 "$code_503" \
        --argjson co "$code_other" \
        --argjson ti "$total_ids" \
        --argjson ui "$unique_ids" \
        --argjson dc "$dup_count" \
        --arg e "$elapsed" \
        '{total:$n, code_200:$c200, code_429:$c429, code_503:$c503, code_other:$co, total_ids:$ti, unique_ids:$ui, dup_request_ids:$dc, elapsed:$e}')

    echo "$details"
}

# === H1: 单模型 50 并发 (minimax-m3) ===
log_info "H1: 50 并发 minimax-m3"
DETAILS=$(concurrency_test "H1" 50 "minimax-m3" 15)
CODE_200=$(echo "$DETAILS" | jq -r '.code_200')
CODE_429=$(echo "$DETAILS" | jq -r '.code_429')
CODE_503=$(echo "$DETAILS" | jq -r '.code_503')
ELAPSED=$(echo "$DETAILS" | jq -r '.elapsed')
DUP=$(echo "$DETAILS" | jq -r '.dup_request_ids')

if [[ "$CODE_200" -gt 30 && "$DUP" -eq 0 ]]; then
    emit_result "H1" "PASS" "50 并发: $CODE_200/50 OK, 0 重复, ${ELAPSED}s" "$DETAILS"
elif [[ "$DUP" -gt 0 ]]; then
    emit_result "H1" "FAIL" "50 并发有重复 request_id=$DUP" "$DETAILS"
else
    emit_result "H1" "FAIL" "50 并发: 200=$CODE_200, 429=$CODE_429, 503=$CODE_503" "$DETAILS"
fi

# === H2: 4 模型混合 30 并发 ===
log_info "H2: 4 模型混合 30 并发"
tmpdir=$(mktemp -d)
start=$(date +%s.%N)
MODELS=("minimax-m3" "minimax-m2.7" "llama-3.3-70b-instruct")
pids=()
for i in $(seq 1 30); do
    MODEL="${MODELS[$((i % 3))]}"
    body=$(jq -n --arg m "$MODEL" '{model:$m, messages:[{role:"user", content:"OK"}], max_tokens:10, stream:false}')
    curl --http1.1 -s -o "$tmpdir/$i.txt" -w "%{http_code}" -m 30 \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -X POST "$API_BASE/v1/chat/completions" \
        -d "$body" > "$tmpdir/$i.code" 2>&1 &
    pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null; done
end=$(date +%s.%N)
elapsed=$(echo "$end $start" | awk '{printf "%.3f\n", $1-$2}')

c200=0; c429=0; c503=0; co=0; rids=()
for i in $(seq 1 30); do
    code=$(cat "$tmpdir/$i.code" 2>/dev/null)
    case "$code" in
        200) c200=$((c200 + 1)) ;;
        429) c429=$((c429 + 1)) ;;
        503) c503=$((c503 + 1)) ;;
        *) co=$((co + 1)) ;;
    esac
    body=$(cat "$tmpdir/$i.txt" 2>/dev/null)
    rid=$(echo "$body" | jq -r '.id // ""' 2>/dev/null)
    [[ -n "$rid" ]] && rids+=("$rid")
done
rm -rf "$tmpdir"

unique=$(printf '%s\n' "${rids[@]}" | sort -u | wc -l | tr -d ' ')
total=${#rids[@]}
dup=$((total - unique))

H2_DETAILS=$(jq -n --argjson c200 "$c200" --argjson c429 "$c429" --argjson c503 "$c503" --argjson co "$co" --argjson ti "$total" --argjson ui "$unique" --arg e "$elapsed" '{code_200:$c200, code_429:$c429, code_503:$c503, code_other:$co, total_ids:$ti, unique_ids:$ui, elapsed:$e}')

if [[ "$c200" -gt 20 ]]; then
    emit_result "H2" "PASS" "30 混合并发: $c200/30 OK, ${ELAPSED}s" "$H2_DETAILS"
else
    emit_result "H2" "FAIL" "30 混合并发: 200=$c200, 429=$c429, 503=$c503" "$H2_DETAILS"
fi

# === H7: 故意打空上游 (non-existent-fake) → 100 并发应全 503 no_candidate ===
log_info "H7: 100 并发 non-existent-fake"
tmpdir=$(mktemp -d)
start=$(date +%s.%N)
pids=()
for i in $(seq 1 100); do
    body='{"model":"non-existent-fake","messages":[{"role":"user","content":"hi"}],"max_tokens":5,"stream":false}'
    curl --http1.1 -s -o "$tmpdir/$i.txt" -w "%{http_code}" -m 30 \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -X POST "$API_BASE/v1/chat/completions" \
        -d "$body" > "$tmpdir/$i.code" 2>&1 &
    pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null; done
end=$(date +%s.%N)
elapsed=$(echo "$end $start" | awk '{printf "%.3f\n", $1-$2}')

c200=0; c503=0; co=0
for i in $(seq 1 100); do
    code=$(cat "$tmpdir/$i.code" 2>/dev/null)
    case "$code" in
        200) c200=$((c200 + 1)) ;;
        503) c503=$((c503 + 1)) ;;
        *) co=$((co + 1)) ;;
    esac
done
rm -rf "$tmpdir"

H7_DETAILS=$(jq -n --argjson c200 "$c200" --argjson c503 "$c503" --argjson co "$co" --arg e "$elapsed" '{code_200:$c200, code_503:$c503, code_other:$co, elapsed:$e}')

# 期望: 全 503 no_candidate，不应该触发限流
if [[ "$c503" -eq 100 ]]; then
    emit_result "H7" "PASS" "100 并发 non-existent-fake 全 503, ${ELAPSED}s (无错误限流)" "$H7_DETAILS"
else
    emit_result "H7" "FAIL" "100 并发: 200=$c200, 503=$c503, other=$co (期望全 503)" "$H7_DETAILS"
fi

# === H8: 流式 10 并发 ===
log_info "H8: 流式 10 并发"
tmpdir=$(mktemp -d)
start=$(date +%s.%N)
pids=()
for i in $(seq 1 10); do
    body='{"model":"minimax-m3","messages":[{"role":"user","content":"OK"}],"max_tokens":20,"stream":true}'
    curl --http1.1 -s --no-buffer -N -o "$tmpdir/$i.txt" -w "%{http_code}" -m 60 \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -X POST "$API_BASE/v1/chat/completions" \
        -d "$body" > "$tmpdir/$i.code" 2>&1 &
    pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null; done
end=$(date +%s.%N)
elapsed=$(echo "$end $start" | awk '{printf "%.3f\n", $1-$2}')

c200=0; co=0
for i in $(seq 1 10); do
    code=$(cat "$tmpdir/$i.code" 2>/dev/null)
    case "$code" in
        200) c200=$((c200 + 1)) ;;
        *) co=$((co + 1)) ;;
    esac
done
rm -rf "$tmpdir"

H8_DETAILS=$(jq -n --argjson c200 "$c200" --argjson co "$co" --arg e "$elapsed" '{code_200:$c200, code_other:$co, elapsed:$e}')

if [[ "$c200" -ge 8 ]]; then
    emit_result "H8" "PASS" "10 流式并发: $c200/10 OK, ${ELAPSED}s" "$H8_DETAILS"
else
    emit_result "H8" "FAIL" "10 流式并发: 200=$c200, other=$co" "$H8_DETAILS"
fi

print_summary
exit "$FAIL_COUNT"