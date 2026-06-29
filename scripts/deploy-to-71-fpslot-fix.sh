#!/bin/bash
# 自动化部署脚本 - minimax-prod-1 fp_slot 问题修复
# 用法：./deploy-to-71-fpslot-fix.sh

set -euo pipefail

echo "======================================"
echo "minimax-prod-1 fp_slot 修复部署"
echo "======================================"
echo ""

# 配置
PROJECT_ROOT="/Users/xutaohuang/workspace/llm-gateway-go-2"
BINARY_NAME="llm-gateway-fpslot-fix-20260629-181208"
SERVER_71="root@llm.kxpms.cn"
REMOTE_DIR="/opt/llm-gateway-go"
SERVICE_NAME="llm-gateway"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 1. 检查本地二进制文件
log_info "检查二进制文件..."
cd "$PROJECT_ROOT"
if [ ! -f "$BINARY_NAME" ]; then
    log_error "二进制文件不存在: $BINARY_NAME"
    exit 1
fi
log_info "✓ 二进制文件存在 ($(ls -lh $BINARY_NAME | awk '{print $5}'))"

# 2. 确认部署
echo ""
echo "即将部署到 71 机器 (llm.kxpms.cn)"
echo "二进制文件: $BINARY_NAME"
echo "Git 标签: deploy/fix-fpslot-sharing-20260629-181208"
echo ""
read -p "确认继续部署？(yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    log_warn "部署已取消"
    exit 0
fi

# 3. 上传二进制文件
log_info "上传二进制文件到 71 机器..."
scp "$BINARY_NAME" "${SERVER_71}:${REMOTE_DIR}/" || {
    log_error "上传失败"
    exit 1
}
log_info "✓ 上传完成"

# 4. 远程部署
log_info "执行远程部署..."
ssh "$SERVER_71" bash << 'REMOTE_DEPLOY'
set -e

BINARY_NAME="llm-gateway-fpslot-fix-20260629-181208"
REMOTE_DIR="/opt/llm-gateway-go"
SERVICE_NAME="llm-gateway"

echo "[远程] 开始部署..."
cd "$REMOTE_DIR"

# 备份当前版本（与 systemd ExecStart 同目录）
echo "[远程] 备份当前版本..."
BACKUP_NAME="llm-gateway.backup-$(date +%Y%m%d-%H%M%S)"
TARGET="$REMOTE_DIR/$SERVICE_NAME"
if [ -f "$TARGET" ]; then
    cp "$TARGET" "$REMOTE_DIR/$BACKUP_NAME"
    echo "[远程] ✓ 备份完成: $REMOTE_DIR/$BACKUP_NAME"
else
    echo "[远程] ! 未找到现有二进制文件，跳过备份"
fi

# 停止服务
echo "[远程] 停止服务..."
systemctl stop "$SERVICE_NAME" || true
sleep 5

# 检查进程是否真的停止
if pgrep -x "$SERVICE_NAME" > /dev/null; then
    echo "[远程] ! 服务仍在运行，强制终止..."
    pkill -9 "$SERVICE_NAME" || true
    sleep 2
fi
echo "[远程] ✓ 服务已停止"

# 部署新版本
echo "[远程] 部署新版本..."
cp "$BINARY_NAME" "$TARGET"
chmod +x "$TARGET"
echo "[远程] ✓ 新版本已部署"

# 启动服务
echo "[远程] 启动服务..."
systemctl start "$SERVICE_NAME"
sleep 3

# 检查状态
echo "[远程] 检查服务状态..."
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "[远程] ✓ 服务启动成功"
    systemctl status "$SERVICE_NAME" --no-pager -l | head -20
else
    echo "[远程] ✗ 服务启动失败"
    journalctl -u "$SERVICE_NAME" -n 50 --no-pager
    exit 1
fi

# 健康检查
echo "[远程] 健康检查..."
for i in {1..10}; do
    if curl -f http://localhost:8080/health >/dev/null 2>&1; then
        echo "[远程] ✓ 健康检查通过"
        exit 0
    fi
    echo "[远程] 等待服务就绪... ($i/10)"
    sleep 2
done

echo "[远程] ⚠️ 健康检查超时（可能需要更多时间）"
echo "[远程] 最近日志："
journalctl -u "$SERVICE_NAME" -n 20 --no-pager
exit 0
REMOTE_DEPLOY

DEPLOY_EXIT_CODE=$?

if [ $DEPLOY_EXIT_CODE -eq 0 ]; then
    log_info "✓ 远程部署完成"
else
    log_error "远程部署失败，退出码: $DEPLOY_EXIT_CODE"
    exit 1
fi

# 5. 初步验证
echo ""
log_info "执行初步验证..."

# 5.1 检查服务日志
log_info "查看最近 20 条日志..."
ssh "$SERVER_71" 'journalctl -u llm-gateway -n 20 --no-pager' | tail -10

# 5.2 检查是否有 slot 复用日志
echo ""
log_info "检查 slot 复用日志（10秒内）..."
REUSE_COUNT=$(ssh "$SERVER_71" 'journalctl -u llm-gateway --since "1 min ago" | grep -c "reused existing slot" || echo 0')
if [ "$REUSE_COUNT" -gt 0 ]; then
    log_info "✓ 发现 $REUSE_COUNT 次 slot 复用（共享机制已生效）"
else
    log_warn "! 暂未发现 slot 复用日志（可能需要等待流量进入）"
fi

# 6. 生成部署报告
echo ""
echo "======================================"
echo "部署完成"
echo "======================================"
cat > /tmp/fpslot-deploy-report-$(date +%Y%m%d-%H%M%S).txt << EOF
minimax-prod-1 fp_slot 修复部署报告
生成时间: $(date)

1. 部署信息:
   - 目标机器: 71 (llm.kxpms.cn)
   - 二进制文件: $BINARY_NAME
   - Git 标签: deploy/fix-fpslot-sharing-20260629-181208
   - 部署时间: $(date)

2. 服务状态:
   - 服务名称: llm-gateway
   - 启动状态: $(ssh "$SERVER_71" 'systemctl is-active llm-gateway')

3. 下一步验证:
   a. 监控失败率（持续 1 小时）:
      watch -n 10 'curl -s http://llm.kxpms.cn/api/credentials/monitor-summary | jq ".credentials[] | select(.id==6) | {label, aggregated_success_rate}"'
   
   b. 检查 Redis slot 使用:
      cd $PROJECT_ROOT && ./scripts/diagnose-fpslot-issue.sh
   
   c. 查看实时日志:
      ssh $SERVER_71 'journalctl -u llm-gateway -f | grep -E "cred_fp_slot|minimax-m3"'

4. 回滚步骤（如需要）:
   ssh $SERVER_71 << 'ROLLBACK'
   systemctl stop llm-gateway
   cp $REMOTE_DIR/llm-gateway.backup-* $REMOTE_DIR/llm-gateway
   systemctl start llm-gateway
   ROLLBACK

5. 数据库配置:
   ⚠️  记得执行数据库更新（如未执行）:
   
   ssh root@<184-host>
   psql -U postgres -d llm_gateway << 'SQL'
   UPDATE credentials SET fp_slot_limit = 5 WHERE id = 6;
   SQL
EOF

REPORT_FILE="/tmp/fpslot-deploy-report-$(date +%Y%m%d-%H%M%S).txt"
echo ""
log_info "部署报告已保存: $REPORT_FILE"
cat "$REPORT_FILE"

echo ""
echo "======================================"
log_info "接下来请执行："
echo "1. 数据库配置更新（如未执行）"
echo "2. 运行诊断脚本: ./scripts/diagnose-fpslot-issue.sh"
echo "3. 监控失败率至少 1 小时"
echo "======================================"
