#!/bin/bash
# minimax-prod-1 fp_slot 问题诊断脚本
# 用途：收集 Redis slot 使用情况和日志数据

set -euo pipefail

REDIS_HOST="${REDIS_HOST:-172.31.0.4}"
CREDENTIAL_ID=6
OUTPUT_DIR="/tmp/fpslot-diagnosis-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$OUTPUT_DIR"
echo "诊断数据将保存到: $OUTPUT_DIR"

# 1. 检查当前所有活跃的 slot
echo "=== 1. 收集 Redis slot 使用情况 ==="
redis-cli -h "$REDIS_HOST" KEYS "llmgw:cred_fp_slot:${CREDENTIAL_ID}:*" > "$OUTPUT_DIR/slot_keys.txt"

echo "活跃 slot 数量: $(wc -l < "$OUTPUT_DIR/slot_keys.txt")"

# 详细的 slot 信息
{
    echo "Slot,Holder,TTL"
    while IFS= read -r key; do
        if [ -n "$key" ]; then
            holder=$(redis-cli -h "$REDIS_HOST" GET "$key" 2>/dev/null || echo "EMPTY")
            ttl=$(redis-cli -h "$REDIS_HOST" TTL "$key" 2>/dev/null || echo "-1")
            echo "$key,$holder,$ttl"
        fi
    done < "$OUTPUT_DIR/slot_keys.txt"
} > "$OUTPUT_DIR/slot_details.csv"

echo "Slot 详情已保存到: $OUTPUT_DIR/slot_details.csv"

# 2. 统计不同 holder 的数量
echo ""
echo "=== 2. 统计 holder 数量 ==="
redis-cli -h "$REDIS_HOST" KEYS "llmgw:cred_fp_slot:${CREDENTIAL_ID}:*" | while read key; do
    [ -n "$key" ] && redis-cli -h "$REDIS_HOST" GET "$key" 2>/dev/null || true
done | grep -v "^$" | sort -u > "$OUTPUT_DIR/unique_holders.txt"

holder_count=$(wc -l < "$OUTPUT_DIR/unique_holders.txt")
echo "不同的 holder 数量: $holder_count"
echo "Holder 列表:"
cat "$OUTPUT_DIR/unique_holders.txt"

# 3. 检查 inflight 计数
echo ""
echo "=== 3. 检查 inflight 计数 ==="
redis-cli -h "$REDIS_HOST" KEYS "llmgw:cred_fp_inflight:${CREDENTIAL_ID}:*" > "$OUTPUT_DIR/inflight_keys.txt"

total_inflight=0
{
    echo "InflightKey,Count"
    while IFS= read -r key; do
        if [ -n "$key" ]; then
            count=$(redis-cli -h "$REDIS_HOST" GET "$key" 2>/dev/null || echo "0")
            echo "$key,$count"
            total_inflight=$((total_inflight + count))
        fi
    done < "$OUTPUT_DIR/inflight_keys.txt"
} > "$OUTPUT_DIR/inflight_details.csv"

echo "Inflight 总数: $total_inflight"
echo "Inflight 详情已保存到: $OUTPUT_DIR/inflight_details.csv"

# 4. 检查 pin 映射
echo ""
echo "=== 4. 检查 pin 映射 (holder -> slot) ==="
redis-cli -h "$REDIS_HOST" KEYS "llmgw:sess_cred_fp:*:${CREDENTIAL_ID}" > "$OUTPUT_DIR/pin_keys.txt"

{
    echo "PinKey,Holder,SlotIndex,TTL"
    while IFS= read -r key; do
        if [ -n "$key" ]; then
            # 从 key 中提取 holder (llmgw:sess_cred_fp:<holder>:6)
            holder=$(echo "$key" | sed -E 's/llmgw:sess_cred_fp:(.+):[0-9]+$/\1/')
            slot=$(redis-cli -h "$REDIS_HOST" GET "$key" 2>/dev/null || echo "-1")
            ttl=$(redis-cli -h "$REDIS_HOST" TTL "$key" 2>/dev/null || echo "-1")
            echo "$key,$holder,$slot,$ttl"
        fi
    done < "$OUTPUT_DIR/pin_keys.txt"
} > "$OUTPUT_DIR/pin_details.csv"

echo "Pin 映射已保存到: $OUTPUT_DIR/pin_details.csv"

# 5. 查看最近的网关日志
echo ""
echo "=== 5. 收集最近 24 小时的相关日志 ==="
if command -v journalctl &> /dev/null; then
    journalctl -u llm-gateway --since "24 hours ago" | \
        grep -E "cred_fp_slot|no_candidate|minimax-m3" | \
        tail -200 > "$OUTPUT_DIR/gateway_logs.txt" || true
    echo "日志已保存到: $OUTPUT_DIR/gateway_logs.txt"
else
    echo "journalctl 不可用，跳过日志收集"
fi

# 6. 生成汇总报告
echo ""
echo "=== 诊断汇总 ==="
cat > "$OUTPUT_DIR/summary.txt" <<EOF
minimax-prod-1 (credential_id=6) fp_slot 诊断报告
生成时间: $(date)

1. Slot 使用情况:
   - 活跃 slot 数量: $(wc -l < "$OUTPUT_DIR/slot_keys.txt")
   - 不同 holder 数量: $holder_count
   - Inflight 总请求数: $total_inflight

2. 理论值:
   - 实际用户: 2-3 个
   - 预期 slot 占用: 2-3 个 (每个用户 1 个)
   - fp_slot_limit: 25

3. 问题判断:
EOF

# 判断问题
slot_count=$(wc -l < "$OUTPUT_DIR/slot_keys.txt")
if [ "$slot_count" -gt 10 ] && [ "$holder_count" -le 3 ]; then
    echo "   ❌ 异常: $holder_count 个用户占用了 $slot_count 个 slot" >> "$OUTPUT_DIR/summary.txt"
    echo "   → 说明并发请求没有共享 slot，每个请求都占用新 slot" >> "$OUTPUT_DIR/summary.txt"
elif [ "$slot_count" -le 5 ] && [ "$holder_count" -le 3 ]; then
    echo "   ✓ 正常: slot 占用数量合理" >> "$OUTPUT_DIR/summary.txt"
else
    echo "   ⚠ 待确认: slot=$slot_count, holder=$holder_count" >> "$OUTPUT_DIR/summary.txt"
fi

if [ "$total_inflight" -eq 0 ] && [ "$slot_count" -gt 0 ]; then
    echo "   ❌ 异常: 有活跃 slot 但 inflight=0" >> "$OUTPUT_DIR/summary.txt"
    echo "   → 说明 Acquire 时没有增加 inflight 计数" >> "$OUTPUT_DIR/summary.txt"
fi

cat "$OUTPUT_DIR/summary.txt"

echo ""
echo "====================================="
echo "诊断完成！所有数据已保存到: $OUTPUT_DIR"
echo "====================================="
echo ""
echo "请将以下文件内容提供给开发人员："
echo "  - $OUTPUT_DIR/summary.txt"
echo "  - $OUTPUT_DIR/slot_details.csv"
echo "  - $OUTPUT_DIR/unique_holders.txt"
echo "  - $OUTPUT_DIR/inflight_details.csv"
