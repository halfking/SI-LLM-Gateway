#!/bin/bash
# 部署到71服务器 (14.103.174.71:25022)
set -euo pipefail

cd /Users/xutaohuang/workspace/llm-gateway-go-2

BINARY_PATH="bin/llm-gateway"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SSH_HOST="root@14.103.174.71"
SSH_PORT="25022"
REMOTE_DIR="/opt/llm-gateway-go"
SERVICE_NAME="llm-gateway"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}部署路由修复到71服务器${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
log_info "目标: ${SSH_HOST}:${SSH_PORT}"
log_info "时间: ${TIMESTAMP}"
echo ""

log_step "=== 步骤 1/6: 测试连接 ==="
if ssh -p $SSH_PORT -o ConnectTimeout=10 -o StrictHostKeyChecking=no $SSH_HOST "echo '连接成功'" 2>&1; then
    log_info "✓ SSH连接正常"
else
    log_error "SSH连接失败"
    exit 1
fi

echo ""
log_step "=== 步骤 2/6: 上传二进制 ==="
REMOTE_BINARY="/tmp/llm-gateway-${TIMESTAMP}"
if scp -P $SSH_PORT -o StrictHostKeyChecking=no "$BINARY_PATH" "${SSH_HOST}:${REMOTE_BINARY}"; then
    log_info "✓ 上传完成"
else
    log_error "上传失败"
    exit 1
fi

echo ""
log_step "=== 步骤 3/6: 检查当前状态 ==="
ssh -p $SSH_PORT $SSH_HOST "systemctl status $SERVICE_NAME --no-pager | head -15 || true"

echo ""
log_step "=== 步骤 4/6: 执行部署 ==="
ssh -p $SSH_PORT $SSH_HOST bash << EOF
set -e
cd $REMOTE_DIR
BACKUP="llm-gateway.backup-${TIMESTAMP}"
[ -f llm-gateway ] && cp llm-gateway \$BACKUP && echo "✓ 已备份: \$BACKUP"
systemctl stop $SERVICE_NAME && echo "✓ 服务已停止"
sleep 3
cp $REMOTE_BINARY llm-gateway && chmod +x llm-gateway && echo "✓ 已部署新版本"
systemctl start $SERVICE_NAME && echo "✓ 服务已启动"
sleep 5
EOF

echo ""
log_step "=== 步骤 5/6: 验证服务 ==="
ssh -p $SSH_PORT $SSH_HOST "systemctl is-active $SERVICE_NAME && echo '✓ 服务运行中' || (echo '✗ 服务异常' && exit 1)"

echo ""
log_step "=== 步骤 6/6: 查看日志 ==="
ssh -p $SSH_PORT $SSH_HOST "journalctl -u $SERVICE_NAME -n 20 --no-pager"

echo ""
log_info "✓✓✓ 部署完成！✓✓✓"
echo ""
echo "监控: ssh -p $SSH_PORT $SSH_HOST 'journalctl -u $SERVICE_NAME -f'"
echo "回滚: ssh -p $SSH_PORT $SSH_HOST 'systemctl stop $SERVICE_NAME && cp $REMOTE_DIR/llm-gateway.backup-${TIMESTAMP} $REMOTE_DIR/llm-gateway && systemctl start $SERVICE_NAME'"
echo ""
