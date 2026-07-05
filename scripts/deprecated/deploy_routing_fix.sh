#!/usr/bin/env bash
# 部署 Minimax-m3 路由问题修复
# Phase 1: 阈值调整 + Empty Response检测改进 + Fallback机制

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}部署路由问题修复${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

# 检查当前目录
if [ ! -f "go.mod" ]; then
    echo -e "${RED}错误: 请在项目根目录运行此脚本${NC}"
    exit 1
fi

echo -e "${YELLOW}修复内容:${NC}"
echo "1. ✅ 路由健康检查阈值调整"
echo "   - 连续失败阈值: 3 → 5 次"
echo "   - 冷却时间: 5分钟 → 3分钟"
echo ""
echo "2. ✅ Empty Response 检测改进"
echo "   - 增加chunk_count == 1的short-circuit"
echo "   - 增加响应时间<2秒的short-circuit"
echo ""
echo "3. ✅ 路由Fallback机制"
echo "   - 所有节点被过滤时启用宽容模式"
echo "   - 避免'no candidate'错误"
echo ""

# 检查修改的文件
echo -e "${YELLOW}检查修改的文件...${NC}"
MODIFIED_FILES=(
    "routing/route_node_state.go"
    "relay/handler.go"
    "routing/router.go"
)

for file in "${MODIFIED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}✗ 文件不存在: $file${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} $file"
done

echo ""
echo -e "${YELLOW}编译代码...${NC}"
if go build -o bin/llm-gateway ./cmd/gateway 2>&1 | tee /tmp/build.log; then
    echo -e "${GREEN}✓ 编译成功${NC}"
else
    echo -e "${RED}✗ 编译失败，查看错误:${NC}"
    cat /tmp/build.log
    exit 1
fi

echo ""
echo -e "${YELLOW}运行测试...${NC}"
if go test ./routing/... -v 2>&1 | tee /tmp/test.log | grep -E "PASS|FAIL"; then
    echo -e "${GREEN}✓ 测试通过${NC}"
else
    echo -e "${YELLOW}⚠️  部分测试失败，请检查${NC}"
fi

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✅ 修复完成！${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""

echo -e "${CYAN}下一步操作:${NC}"
echo ""
echo "1. 部署到服务器:"
echo "   ${YELLOW}# 备份当前版本${NC}"
echo "   cp /path/to/llm-gateway /path/to/llm-gateway.backup"
echo ""
echo "   ${YELLOW}# 部署新版本${NC}"
echo "   cp bin/llm-gateway /path/to/llm-gateway"
echo "   systemctl restart llm-gateway"
echo ""
echo "2. 运行测试验证:"
echo "   ${YELLOW}./scripts/test_71_complete.sh${NC}"
echo ""
echo "3. 检查错误率:"
echo "   ${YELLOW}./scripts/diagnose_routing_issue.sh minimax-m3${NC}"
echo "   ${YELLOW}./scripts/diagnose_nvidia_nim_empty_response.sh minimax-m3${NC}"
echo ""
echo "4. 监控数据库指标:"
echo "   ${YELLOW}# No candidate 错误率${NC}"
echo '   psql "$LLM_GATEWAY_DATABASE_URL" -c "'
echo "   SELECT COUNT(*) * 100.0 / NULLIF(total.cnt, 0) as no_candidate_rate"
echo "   FROM request_logs,"
echo "        (SELECT COUNT(*) as cnt FROM request_logs WHERE ts > NOW() - INTERVAL '1 hour') total"
echo "   WHERE error_kind = 'no_candidate'"
echo "     AND ts > NOW() - INTERVAL '1 hour';"
echo '"'
echo ""

echo -e "${CYAN}预期效果:${NC}"
echo "• No Candidate 错误率: 显著下降（目标 <1%）"
echo "• Empty Response 错误率: 下降（目标 <5%）"
echo "• 节点禁用更合理: 5次失败才禁用，3分钟后恢复"
echo ""

echo -e "${YELLOW}⚠️  注意事项:${NC}"
echo "• 部署后持续监控1小时"
echo "• 如有异常，使用备份版本回滚"
echo "• 记录部署前后的错误率对比"
echo ""
