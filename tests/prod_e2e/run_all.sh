#!/usr/bin/env bash
# run_all.sh - 顺序执行所有测试脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

declare -a SUITES=(
    "01_health.sh"
    "02_single_vendor.sh"
    "03_multi_cred.sh"
    "04_protocols.sh"
    "05_streaming.sh"
    "06_errors.sh"
    "07_auto_route.sh"
    "08_concurrency.sh"
    "09_edge_cases.sh"
    "10_data_correctness.sh"
)

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0

for script in "${SUITES[@]}"; do
    echo ""
    echo "=========================================="
    echo "执行: $script"
    echo "=========================================="
    bash "$SCRIPT_DIR/$script"
    rc=$?
    TOTAL_FAIL=$((TOTAL_FAIL + rc))
done

echo ""
echo "=========================================="
echo "总执行结果"
echo "=========================================="
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
for f in "$SCRIPT_DIR/results"/*.jsonl; do
    [[ -f "$f" ]] || continue
    PASS=$(grep -c '"status":"PASS"' "$f" 2>/dev/null || echo 0)
    FAIL=$(grep -c '"status":"FAIL"' "$f" 2>/dev/null || echo 0)
    SKIP=$(grep -c '"status":"SKIP"' "$f" 2>/dev/null || echo 0)
    TOTAL_PASS=$((TOTAL_PASS + PASS))
    TOTAL_FAIL=$((TOTAL_FAIL + FAIL))
    TOTAL_SKIP=$((TOTAL_SKIP + SKIP))
done

echo "总计: 总数=$((TOTAL_PASS + TOTAL_FAIL + TOTAL_SKIP))"
echo "  通过: $TOTAL_PASS"
echo "  失败: $TOTAL_FAIL"
echo "  跳过: $TOTAL_SKIP"