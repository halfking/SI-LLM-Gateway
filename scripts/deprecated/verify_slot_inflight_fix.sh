#!/bin/bash
# verify_slot_inflight_fix.sh — V3.2.2 slot inflight 上限修复验证脚本
# 2026-07-02: 验证 MaxInflightPerSlot 限制是否生效

set -euo pipefail

# 配置
REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
CREDENTIAL_ID="${CREDENTIAL_ID:-11}"  # minimax-m3 凭据 ID
MAX_INFLIGHT_EXPECTED="${MAX_INFLIGHT_EXPECTED:-10}"  # 期望的上限

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=============================================="
echo "Slot Inflight 上限修复验证脚本 (V3.2.2)"
echo "=============================================="
echo ""
echo "配置："
echo "  Redis: ${REDIS_HOST}:${REDIS_PORT}"
echo "  凭据 ID: ${CREDENTIAL_ID}"
echo "  期望上限: ${MAX_INFLIGHT_EXPECTED}"
echo ""

# 构建 redis-cli 命令
REDIS_CMD="redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT}"
if [ -n "${REDIS_PASSWORD}" ]; then
    REDIS_CMD="${REDIS_CMD} -a ${REDIS_PASSWORD}"
fi

# 检查 Redis 连接
echo "[1/4] 检查 Redis 连接..."
if ! ${REDIS_CMD} PING > /dev/null 2>&1; then
    echo -e "${RED}✗ Redis 连接失败${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Redis 连接正常${NC}"
echo ""

# 扫描所有 slot keys
echo "[2/4] 扫描凭据 ${CREDENTIAL_ID} 的所有 slot..."
SLOT_KEYS=$(${REDIS_CMD} --scan --pattern "llmgw:cred_fp_slot:${CREDENTIAL_ID}:*" 2>/dev/null || echo "")
if [ -z "${SLOT_KEYS}" ]; then
    echo -e "${YELLOW}⚠ 未找到任何 slot（凭据可能未被使用或 Redis 数据已清空）${NC}"
    exit 0
fi

SLOT_COUNT=$(echo "${SLOT_KEYS}" | wc -l | xargs)
echo -e "${GREEN}✓ 找到 ${SLOT_COUNT} 个 slot${NC}"
echo ""

# 检查每个 slot 的 inflight 计数
echo "[3/4] 检查每个 slot 的 inflight 计数..."
MAX_INFLIGHT_FOUND=0
VIOLATIONS=0
ACTIVE_SLOTS=0

for slot_key in ${SLOT_KEYS}; do
    # 提取 slot index: llmgw:cred_fp_slot:11:0 -> 0
    slot_index=$(echo "${slot_key}" | awk -F':' '{print $NF}')
    
    # 检查 slot 是否有 holder
    holder=$(${REDIS_CMD} GET "${slot_key}" 2>/dev/null || echo "")
    if [ -z "${holder}" ]; then
        continue
    fi
    
    ACTIVE_SLOTS=$((ACTIVE_SLOTS + 1))
    
    # 检查 inflight 计数
    inflight_key="llmgw:cred_fp_inflight:${CREDENTIAL_ID}:${slot_index}"
    inflight=$(${REDIS_CMD} GET "${inflight_key}" 2>/dev/null || echo "0")
    
    # 记录最大值
    if [ "${inflight}" -gt "${MAX_INFLIGHT_FOUND}" ]; then
        MAX_INFLIGHT_FOUND=${inflight}
    fi
    
    # 检查是否违反上限
    if [ "${inflight}" -gt "${MAX_INFLIGHT_EXPECTED}" ]; then
        echo -e "${RED}  ✗ Slot #${slot_index}: inflight=${inflight} (超过上限 ${MAX_INFLIGHT_EXPECTED})${NC}"
        VIOLATIONS=$((VIOLATIONS + 1))
    else
        echo -e "${GREEN}  ✓ Slot #${slot_index}: inflight=${inflight} (正常)${NC}"
    fi
done

echo ""
echo "活跃 slot 数量: ${ACTIVE_SLOTS}"
echo "最大 inflight 值: ${MAX_INFLIGHT_FOUND}"
echo ""

# 最终结果
echo "[4/4] 验证结果"
echo "=============================================="
if [ "${VIOLATIONS}" -eq 0 ]; then
    echo -e "${GREEN}✓ 所有 slot 的 inflight 均未超过上限 ${MAX_INFLIGHT_EXPECTED}${NC}"
    echo -e "${GREEN}✓ 修复生效！${NC}"
    exit 0
else
    echo -e "${RED}✗ 发现 ${VIOLATIONS} 个 slot 的 inflight 超过上限${NC}"
    echo -e "${YELLOW}建议操作：${NC}"
    echo "  1. 检查环境变量是否设置：LLM_GATEWAY_CREDENTIAL_FP_SLOT_MAX_INFLIGHT_PER_SLOT"
    echo "  2. 确认服务是否使用新版本二进制"
    echo "  3. 查看日志：grep 'inflight limit reached' /var/log/llm-gateway/gateway.log"
    exit 1
fi
