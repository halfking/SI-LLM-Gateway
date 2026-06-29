#!/bin/bash
# minimax-prod-1 fp_slot 问题修复部署脚本
# 
# 此脚本整合了以下修复：
# 1. slot.go 添加 holder 共享快速路径（代码修复）
# 2. 调整 fp_slot_limit 从 25 → 5（数据库配置）
# 3. 增强 Transient 错误分类（errorsx 改进）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REDIS_HOST="${REDIS_HOST:-[INTERNAL_DB_HOST]}"
DB_HOST="${DB_HOST:-[SERVER]}"

echo "========================================"
echo "minimax-prod-1 fp_slot 问题修复部署"
echo "========================================"
echo ""
echo "项目目录: $PROJECT_ROOT"
echo "Redis: $REDIS_HOST"
echo "数据库: $DB_HOST"
echo ""

# 1. 检查修改的文件
echo "=== 1. 检查代码修改 ==="
echo ""
echo "修改的文件："
echo "  - credentialfpslot/slot.go (添加 holder 共享快速路径)"
echo "  - errorsx/classify.go (增强 MiniMax 错误分类)"
echo ""

git diff --stat credentialfpslot/slot.go errorsx/classify.go || true

read -p "是否继续构建和部署？(y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "部署已取消"
    exit 0
fi

# 2. 运行测试
echo ""
echo "=== 2. 运行单元测试 ==="
cd "$PROJECT_ROOT"

if go test ./credentialfpslot/... -v 2>&1 | tee /tmp/fpslot-test.log; then
    echo "✓ credentialfpslot 测试通过"
else
    echo "✗ credentialfpslot 测试失败"
    echo "查看详情: /tmp/fpslot-test.log"
    exit 1
fi

if go test ./errorsx/... -v 2>&1 | tee /tmp/errorsx-test.log; then
    echo "✓ errorsx 测试通过"
else
    echo "✗ errorsx 测试失败"
    echo "查看详情: /tmp/errorsx-test.log"
    exit 1
fi

# 3. 构建
echo ""
echo "=== 3. 构建新版本 ==="
make build || {
    echo "✗ 构建失败"
    exit 1
}

echo "✓ 构建成功"
NEW_BINARY="$PROJECT_ROOT/llm-gateway-linux-amd64"
if [ ! -f "$NEW_BINARY" ]; then
    echo "✗ 找不到构建产物: $NEW_BINARY"
    exit 1
fi

# 4. 创建部署备份点
echo ""
echo "=== 4. 创建 Git 标签（部署备份点） ==="
DEPLOY_TAG="deploy/fix-fpslot-sharing-$(date +%Y%m%d-%H%M%S)"
git tag -a "$DEPLOY_TAG" -m "Fix: fp_slot sharing for minimax-prod-1 (52% failure rate issue)"
echo "✓ 创建标签: $DEPLOY_TAG"
echo "  回滚命令: git checkout $DEPLOY_TAG"

# 5. 数据库配置修改
echo ""
echo "=== 5. 更新数据库配置 ==="
read -p "是否更新数据库 fp_slot_limit (25 → 5)？(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "执行 SQL 更新..."
    psql -h "$DB_HOST" -U postgres -d llm_gateway -f "$SCRIPT_DIR/fix-fpslot-limit.sql" || {
        echo "✗ 数据库更新失败"
        exit 1
    }
    echo "✓ 数据库配置已更新"
else
    echo "⊘ 跳过数据库更新"
fi

# 6. 部署到 [SERVER] 机器
echo ""
echo "=== 6. 部署到 [SERVER] 机器 ==="
read -p "是否部署到 [SERVER] 机器 ([PROD_DOMAIN])？(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "停止服务..."
    ssh root@[PROD_DOMAIN] 'systemctl stop llm-gateway'
    
    echo "备份当前二进制文件..."
    ssh root@[PROD_DOMAIN] 'cp /opt/llm-gateway-go/llm-gateway /opt/llm-gateway-go/llm-gateway.backup-$(date +%Y%m%d-%H%M%S)'
    
    echo "上传新版本..."
    scp "$NEW_BINARY" root@[PROD_DOMAIN]:/opt/llm-gateway-go/llm-gateway
    
    echo "启动服务..."
    ssh root@[PROD_DOMAIN] 'systemctl start llm-gateway'
    
    sleep 3
    
    echo "检查服务状态..."
    if ssh root@[PROD_DOMAIN] 'systemctl is-active llm-gateway'; then
        echo "✓ 服务已启动"
    else
        echo "✗ 服务启动失败"
        ssh root@[PROD_DOMAIN] 'journalctl -u llm-gateway -n 50 --no-pager'
        exit 1
    fi
else
    echo "⊘ 跳过部署"
fi

# 7. 验证修复效果
echo ""
echo "=== 7. 验证修复效果 ==="
echo ""
echo "正在检查 Redis slot 使用情况（等待 10 秒让流量进入）..."
sleep 10

# 统计活跃 slot 数
ACTIVE_SLOTS=$(redis-cli -h "$REDIS_HOST" KEYS "llmgw:cred_fp_slot:6:*" | wc -l)
echo "活跃 slot 数量: $ACTIVE_SLOTS"

# 统计 holder 数量
HOLDER_COUNT=$(redis-cli -h "$REDIS_HOST" KEYS "llmgw:cred_fp_slot:6:*" | while read key; do
    [ -n "$key" ] && redis-cli -h "$REDIS_HOST" GET "$key" 2>/dev/null || true
done | grep -v "^$" | sort -u | wc -l)
echo "不同 holder 数量: $HOLDER_COUNT"

# 统计 inflight 总数
TOTAL_INFLIGHT=0
while read key; do
    if [ -n "$key" ]; then
        count=$(redis-cli -h "$REDIS_HOST" GET "$key" 2>/dev/null || echo "0")
        TOTAL_INFLIGHT=$((TOTAL_INFLIGHT + count))
    fi
done < <(redis-cli -h "$REDIS_HOST" KEYS "llmgw:cred_fp_inflight:6:*")
echo "Inflight 请求总数: $TOTAL_INFLIGHT"

echo ""
echo "预期结果（修复后）："
echo "  - 活跃 slot: 2-3 个（对应 2-3 个用户）"
echo "  - Inflight: > 0（说明共享机制生效）"
echo ""

if [ "$ACTIVE_SLOTS" -le 5 ] && [ "$TOTAL_INFLIGHT" -gt 0 ]; then
    echo "✓ 修复生效！Slot 使用合理且并发共享正常"
else
    echo "⚠ 请继续观察，可能需要等待更多流量"
fi

# 8. 查看最近日志
echo ""
echo "=== 8. 最近 50 条相关日志 ==="
ssh root@[PROD_DOMAIN] 'journalctl -u llm-gateway -n 50 --no-pager' | grep -E "cred_fp_slot|minimax-m3" | tail -20 || true

# 9. 生成部署报告
echo ""
echo "========================================"
echo "部署完成"
echo "========================================"
cat > /tmp/fpslot-deploy-report.txt <<EOF
minimax-prod-1 fp_slot 问题修复部署报告
生成时间: $(date)

1. Git 标签: $DEPLOY_TAG
   回滚命令: git checkout $DEPLOY_TAG && make build && scp llm-gateway-linux-amd64 root@[PROD_DOMAIN]:/opt/llm-gateway-go/llm-gateway

2. 代码修改:
   - credentialfpslot/slot.go: 添加 holder 共享快速路径
   - errorsx/classify.go: 增强 MiniMax 错误分类

3. 数据库修改:
   - credentials.fp_slot_limit (id=6): 25 → 5

4. 当前状态:
   - 活跃 slot: $ACTIVE_SLOTS
   - Holder 数量: $HOLDER_COUNT
   - Inflight 总数: $TOTAL_INFLIGHT

5. 监控建议:
   - 持续观察失败率（目标：从 52% 降至 < 5%）
   - 监控命令: watch -n 5 'curl -s http://[PROD_DOMAIN]/api/credentials/monitor-summary | jq ".credentials[] | select(.id==6)"'
   
6. 诊断脚本:
   - Redis 诊断: $SCRIPT_DIR/diagnose-fpslot-issue.sh
   - 数据库诊断: psql -h $DB_HOST -f $SCRIPT_DIR/diagnose-fpslot-db-queries.sql

7. 回滚步骤（如需要）:
   a. 数据库: UPDATE credentials SET fp_slot_limit = 25 WHERE id = 6;
   b. 代码: git checkout <previous-tag>
   c. 构建: make build
   d. 部署: scp llm-gateway-linux-amd64 root@[PROD_DOMAIN]:/opt/llm-gateway-go/llm-gateway
   e. 重启: ssh root@[PROD_DOMAIN] systemctl restart llm-gateway
EOF

cat /tmp/fpslot-deploy-report.txt
echo ""
echo "报告已保存到: /tmp/fpslot-deploy-report.txt"
