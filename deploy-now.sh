#!/bin/bash
# 部署到 71 机器 - minimax-prod-1 fp_slot 修复
# 使用最新编译的二进制文件

set -euo pipefail

cd /Users/xutaohuang/workspace/llm-gateway-go-2

BINARY_NAME="llm-gateway-0c75b62a-fpslot-fix-20260629-185854"
SERVER_71="root@llm.kxpms.cn"
REMOTE_DIR="/opt/llm-gateway-go"
SERVICE_NAME="llm-gateway"

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "======================================"
echo "部署到 71 机器 (llm.kxpms.cn)"
echo "======================================"
echo ""
echo "二进制文件: $BINARY_NAME"
echo "Commit: 0c75b62a (包含 fpslot 修复)"
echo "文件大小: $(ls -lh $BINARY_NAME | awk '{print $5}')"
echo ""

# 检查二进制文件是否存在
if [ ! -f "$BINARY_NAME" ]; then
    log_error "二进制文件不存在: $BINARY_NAME"
    exit 1
fi

read -p "确认开始部署？(yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    log_warn "部署已取消"
    exit 0
fi

echo ""
log_info "=== Step 1: 上传二进制文件 ==="
scp "$BINARY_NAME" "${SERVER_71}:${REMOTE_DIR}/" || {
    log_error "上传失败"
    exit 1
}
log_info "✓ 上传完成"

echo ""
log_info "=== Step 2: 执行远程部署 ==="
ssh "$SERVER_71" bash << EOF
set -e

BINARY_NAME="$BINARY_NAME"
REMOTE_DIR="$REMOTE_DIR"
SERVICE_NAME="$SERVICE_NAME"

cd "\$REMOTE_DIR"

echo "[远程] 1. 备份当前版本（与 systemd ExecStart 同目录）..."
BACKUP_NAME="llm-gateway.backup-\$(date +%Y%m%d-%H%M%S)"
TARGET="\$REMOTE_DIR/\$SERVICE_NAME"
if [ -f "\$TARGET" ]; then
    cp "\$TARGET" "\$REMOTE_DIR/\$BACKUP_NAME"
    echo "✓ 备份完成: \$REMOTE_DIR/\$BACKUP_NAME"
else
    echo "! 未找到现有二进制，跳过备份"
fi

echo ""
echo "[远程] 2. 停止服务..."
systemctl stop "\$SERVICE_NAME" || true
sleep 5

# 确认进程已停止
if pgrep -x "\$SERVICE_NAME" > /dev/null; then
    echo "! 服务仍在运行，强制终止..."
    pkill -9 "\$SERVICE_NAME" || true
    sleep 2
fi
echo "✓ 服务已停止"

echo ""
echo "[远程] 3. 部署新版本..."
cp "\$BINARY_NAME" "\$TARGET"
chmod +x "\$TARGET"
echo "✓ 新版本已部署"

echo ""
echo "[远程] 4. 启动服务..."
systemctl start "\$SERVICE_NAME"
sleep 3

echo ""
echo "[远程] 5. 检查服务状态..."
if systemctl is-active --quiet "\$SERVICE_NAME"; then
    echo "✓ 服务启动成功"
    systemctl status "\$SERVICE_NAME" --no-pager -l | head -15
else
    echo "✗ 服务启动失败"
    journalctl -u "\$SERVICE_NAME" -n 30 --no-pager
    exit 1
fi

echo ""
echo "[远程] 6. 健康检查..."
for i in {1..10}; do
    if curl -f http://localhost:8080/health >/dev/null 2>&1; then
        echo "✓ 健康检查通过"
        exit 0
    fi
    echo "等待服务就绪... (\$i/10)"
    sleep 2
done

echo "⚠️ 健康检查超时（服务可能仍在启动）"
journalctl -u "\$SERVICE_NAME" -n 20 --no-pager
EOF

DEPLOY_EXIT_CODE=$?

if [ $DEPLOY_EXIT_CODE -eq 0 ]; then
    echo ""
    log_info "✓ 部署完成！"
else
    echo ""
    log_error "部署失败，退出码: $DEPLOY_EXIT_CODE"
    exit 1
fi

# 初步验证
echo ""
log_info "=== Step 3: 初步验证 ==="

log_info "查看最近 10 条日志..."
ssh "$SERVER_71" 'journalctl -u llm-gateway -n 10 --no-pager' | tail -10

echo ""
log_info "检查 slot 复用日志（最近 1 分钟）..."
REUSE_COUNT=$(ssh "$SERVER_71" 'journalctl -u llm-gateway --since "1 min ago" | grep -c "reused existing slot" || echo 0')
if [ "$REUSE_COUNT" -gt 0 ]; then
    log_info "✓ 发现 $REUSE_COUNT 次 slot 复用（共享机制已生效！）"
else
    log_warn "! 暂未发现 slot 复用日志（可能需要等待流量进入）"
fi

echo ""
echo "======================================"
echo "部署成功！"
echo "======================================"
echo ""
echo "接下来请："
echo "1. 运行诊断脚本: ./scripts/diagnose-fpslot-issue.sh"
echo "2. 监控失败率（至少 1 小时）:"
echo "   watch -n 10 'curl -s http://llm.kxpms.cn/api/credentials/monitor-summary | jq \".credentials[] | select(.id==6)\"'"
echo ""
echo "回滚命令（如需要）:"
echo "   ssh $SERVER_71 'systemctl stop llm-gateway && cp /opt/llm-gateway-go/llm-gateway.backup-* /opt/llm-gateway-go/llm-gateway && systemctl start llm-gateway'"
echo ""
