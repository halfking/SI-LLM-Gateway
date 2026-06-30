#!/bin/bash
set -euo pipefail

cd /Users/xutaohuang/workspace/llm-gateway-go-2

BINARY_PATH="bin/llm-gateway"
BUILD_NUM="20260630142002"
VERSION="v2.3.1-routing-fix"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SSH_HOST="root@14.103.174.71"
SSH_PORT="25022"
REMOTE_DIR="/opt/llm-gateway-go"
SERVICE_NAME="llm-gateway-go.service"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}部署新版本到71服务器${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
log_info "版本: $VERSION"
log_info "编译号: $BUILD_NUM"
log_info "Git提交: edaca68b"
echo ""

log_step "=== 1/7: 上传新版本 ==="
REMOTE_BINARY="$REMOTE_DIR/llm-gateway-$BUILD_NUM"
scp -P $SSH_PORT "$BINARY_PATH" "${SSH_HOST}:${REMOTE_BINARY}" && log_info "✓ 上传完成"

log_step "=== 2/7: 备份当前版本 ==="
ssh -p $SSH_PORT $SSH_HOST "cd $REMOTE_DIR && [ -f llm-gateway ] && cp llm-gateway llm-gateway.backup-$TIMESTAMP && echo '✓ 已备份'"

log_step "=== 3/7: 停止服务 ==="
ssh -p $SSH_PORT $SSH_HOST "systemctl stop $SERVICE_NAME && sleep 3 && echo '✓ 服务已停止'"

log_step "=== 4/7: 部署新版本 ==="
ssh -p $SSH_PORT $SSH_HOST "cd $REMOTE_DIR && mv llm-gateway-$BUILD_NUM llm-gateway && chmod +x llm-gateway && echo '✓ 新版本已部署' && ls -lh llm-gateway"

log_step "=== 5/7: 启动服务 ==="
ssh -p $SSH_PORT $SSH_HOST "systemctl start $SERVICE_NAME && sleep 5 && echo '✓ 服务已启动'"

log_step "=== 6/7: 验证部署 ==="
ssh -p $SSH_PORT $SSH_HOST "systemctl is-active $SERVICE_NAME && docker ps | grep llm-gateway-go && echo '✓ 服务运行正常'"

log_step "=== 7/7: 查看版本信息 ==="
ssh -p $SSH_PORT $SSH_HOST "docker logs llm-gateway-go --tail 30 2>&1 | head -20"

echo ""
log_info "✓✓✓ 部署完成！✓✓✓"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "版本: $VERSION"
echo "编译号: $BUILD_NUM"
echo "备份: $REMOTE_DIR/llm-gateway.backup-$TIMESTAMP"
echo ""
echo "监控: ssh -p $SSH_PORT $SSH_HOST 'docker logs -f llm-gateway-go'"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
