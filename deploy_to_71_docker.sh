#!/bin/bash
# 部署到71服务器 - Docker容器方式
set -euo pipefail

cd /Users/xutaohuang/workspace/llm-gateway-go-2

BINARY_PATH="bin/llm-gateway"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SSH_HOST="root@14.103.174.71"
SSH_PORT="25022"
REMOTE_DIR="/opt/llm-gateway-go"
SERVICE_NAME="llm-gateway-go.service"
CONTAINER_NAME="llm-gateway-go"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}部署路由修复到71服务器${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
log_info "目标: ${SSH_HOST}:${SSH_PORT}"
log_info "服务: ${SERVICE_NAME}"
log_info "容器: ${CONTAINER_NAME}"
log_info "时间: ${TIMESTAMP}"
echo ""

log_step "=== 步骤 1/8: 测试连接 ==="
ssh -p $SSH_PORT -o StrictHostKeyChecking=no $SSH_HOST "echo '✓ 连接成功'" || exit 1

echo ""
log_step "=== 步骤 2/8: 上传二进制 ==="
REMOTE_BINARY="$REMOTE_DIR/llm-gateway-new-${TIMESTAMP}"
scp -P $SSH_PORT "$BINARY_PATH" "${SSH_HOST}:${REMOTE_BINARY}" && log_info "✓ 上传完成" || exit 1

echo ""
log_step "=== 步骤 3/8: 检查当前状态 ==="
ssh -p $SSH_PORT $SSH_HOST << 'EOF'
echo "服务状态:"
systemctl status llm-gateway-go.service --no-pager | head -10 || true
echo ""
echo "Docker容器:"
docker ps | grep llm-gateway-go || echo "容器未运行"
echo ""
echo "当前二进制:"
ls -lh /opt/llm-gateway-go/llm-gateway 2>/dev/null || echo "未找到"
EOF

echo ""
log_step "=== 步骤 4/8: 备份当前版本 ==="
ssh -p $SSH_PORT $SSH_HOST bash << EOF
cd $REMOTE_DIR
BACKUP="llm-gateway.backup-${TIMESTAMP}"
if [ -f llm-gateway ]; then
    cp llm-gateway "\$BACKUP"
    echo "✓ 已备份: \$BACKUP"
    ls -lh "\$BACKUP"
else
    echo "! 未找到现有二进制"
fi
EOF

echo ""
log_step "=== 步骤 5/8: 停止服务 ==="
ssh -p $SSH_PORT $SSH_HOST bash << 'EOF'
systemctl stop llm-gateway-go.service
echo "✓ systemd服务已停止"
sleep 3

# 确认Docker容器已停止
if docker ps | grep -q llm-gateway-go; then
    echo "停止Docker容器..."
    docker stop llm-gateway-go || true
    sleep 2
fi
echo "✓ 服务已完全停止"
EOF

echo ""
log_step "=== 步骤 6/8: 部署新版本 ==="
ssh -p $SSH_PORT $SSH_HOST bash << EOF
cd $REMOTE_DIR
mv llm-gateway-new-${TIMESTAMP} llm-gateway
chmod +x llm-gateway
chown root:root llm-gateway
echo "✓ 新版本已部署"
ls -lh llm-gateway
EOF

echo ""
log_step "=== 步骤 7/8: 启动服务 ==="
ssh -p $SSH_PORT $SSH_HOST bash << 'EOF'
systemctl start llm-gateway-go.service
echo "✓ systemd服务已启动"
sleep 5

# 等待Docker容器启动
for i in {1..10}; do
    if docker ps | grep -q llm-gateway-go; then
        echo "✓ Docker容器已启动"
        break
    fi
    echo "等待容器启动... ($i/10)"
    sleep 2
done
EOF

echo ""
log_step "=== 步骤 8/8: 验证部署 ==="
ssh -p $SSH_PORT $SSH_HOST bash << 'EOF'
echo "=== 服务状态 ==="
systemctl status llm-gateway-go.service --no-pager | head -15

echo ""
echo "=== Docker容器 ==="
docker ps | grep llm-gateway-go || echo "! 容器未运行"

echo ""
echo "=== 最近日志 ==="
journalctl -u llm-gateway-go.service -n 20 --no-pager | tail -15

echo ""
if systemctl is-active llm-gateway-go.service > /dev/null; then
    if docker ps | grep -q llm-gateway-go; then
        echo "✓✓✓ 服务运行正常 ✓✓✓"
        exit 0
    else
        echo "✗ Docker容器未运行"
        exit 1
    fi
else
    echo "✗ 服务未激活"
    exit 1
fi
EOF

if [ $? -eq 0 ]; then
    echo ""
    log_info "✓✓✓ 部署成功！✓✓✓"
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}部署完成${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo "备份位置: $REMOTE_DIR/llm-gateway.backup-${TIMESTAMP}"
    echo ""
    echo "监控命令:"
    echo "  ssh -p $SSH_PORT $SSH_HOST 'journalctl -u llm-gateway-go.service -f'"
    echo "  ssh -p $SSH_PORT $SSH_HOST 'docker logs -f llm-gateway-go'"
    echo ""
    echo "回滚命令:"
    echo "  ssh -p $SSH_PORT $SSH_HOST 'systemctl stop llm-gateway-go.service && cp $REMOTE_DIR/llm-gateway.backup-${TIMESTAMP} $REMOTE_DIR/llm-gateway && systemctl start llm-gateway-go.service'"
    echo ""
else
    log_error "部署失败，请检查日志"
    exit 1
fi
