#!/bin/bash
set -euo pipefail

BUILD_NUM="717"
VERSION="v2.3.0-3ac0638b-20260630-717"
SSH_HOST="root@14.103.174.71"
SSH_PORT="25022"
REMOTE_DIR="/opt/llm-gateway-go"
SERVICE_NAME="llm-gateway-go.service"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 部署新版本"
echo "  编译号: $BUILD_NUM (从716递增)"
echo "  版本: $VERSION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "[1/6] 上传二进制..."
scp -P $SSH_PORT bin/llm-gateway "${SSH_HOST}:${REMOTE_DIR}/llm-gateway-${BUILD_NUM}"

echo "[2/6] 备份当前版本..."
ssh -p $SSH_PORT $SSH_HOST "cd $REMOTE_DIR && cp llm-gateway llm-gateway.backup-$TIMESTAMP && echo '备份: llm-gateway.backup-$TIMESTAMP'"

echo "[3/6] 停止服务..."
ssh -p $SSH_PORT $SSH_HOST "systemctl stop $SERVICE_NAME && sleep 3 && echo '已停止'"

echo "[4/6] 部署新版本..."
ssh -p $SSH_PORT $SSH_HOST "cd $REMOTE_DIR && mv llm-gateway-$BUILD_NUM llm-gateway && chmod +x llm-gateway && echo '已部署: 编译号 $BUILD_NUM'"

echo "[5/6] 启动服务..."
ssh -p $SSH_PORT $SSH_HOST "systemctl start $SERVICE_NAME && sleep 5 && echo '已启动'"

echo "[6/6] 验证部署..."
echo ""
echo "=== 服务状态 ==="
ssh -p $SSH_PORT $SSH_HOST "systemctl is-active $SERVICE_NAME && docker ps | grep llm-gateway-go"
echo ""
echo "=== 启动日志（版本信息）==="
ssh -p $SSH_PORT $SSH_HOST "docker logs llm-gateway-go --tail 30 2>&1 | grep -E 'gateway starting|build_number|version' | head -5"
echo ""
echo "=== API版本验证 ==="
curl -s https://llm.kxpms.cn/ | head -1
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 部署完成"
echo "  编译号: $BUILD_NUM (新增)"
echo "  版本: $VERSION"
echo "  备份: llm-gateway.backup-$TIMESTAMP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
