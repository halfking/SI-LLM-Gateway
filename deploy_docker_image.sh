#!/bin/bash
set -euo pipefail

BUILD_NUM="717"
VERSION="v2.3.0-3ac0638b-20260630-717"
SSH_HOST="root@14.103.174.71"
SSH_PORT="25022"
REMOTE_DIR="/opt/llm-gateway-go"
SERVICE_NAME="llm-gateway-go.service"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
GIT_COMMIT="3ac0638b"
IMAGE_TAG="gitsha-${GIT_COMMIT}-r${BUILD_NUM}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔨 1. 构建Docker镜像（编译号: $BUILD_NUM）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 在本地构建Docker镜像
docker build -t "kx-llm-gateway-go:${IMAGE_TAG}" -f Dockerfile.V2.2.9 . 2>&1 | tail -10
echo ""
echo "镜像构建完成: kx-llm-gateway-go:${IMAGE_TAG}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📤 2. 上传镜像到71服务器"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 保存镜像为tar文件
docker save "kx-llm-gateway-go:${IMAGE_TAG}" > /tmp/kx-llm-gateway-go-${BUILD_NUM}.tar
echo "镜像大小: $(ls -lh /tmp/kx-llm-gateway-go-${BUILD_NUM}.tar | awk '{print $5}')"

# 上传到服务器
scp -P $SSH_PORT /tmp/kx-llm-gateway-go-${BUILD_NUM}.tar "${SSH_HOST}:/tmp/"
echo "✓ 上传完成"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 3. 在服务器上加载镜像并部署"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ssh -p $SSH_PORT $SSH_HOST << EOF
set -e

cd $REMOTE_DIR

echo "[1] 加载新镜像..."
docker load -i /tmp/kx-llm-gateway-go-${BUILD_NUM}.tar
echo "✓ 镜像已加载"

echo ""
echo "[2] 停止当前服务..."
systemctl stop $SERVICE_NAME
sleep 3
echo "✓ 已停止"

echo ""
echo "[3] 更新systemd服务配置..."
# 备份当前配置
cp /etc/systemd/system/$SERVICE_NAME /etc/systemd/system/${SERVICE_NAME}.backup-${TIMESTAMP}

# 更新镜像标签
sed -i 's|kx-llm-gateway-go:gitsha-[a-f0-9]*|kx-llm-gateway-go:${IMAGE_TAG}|' /etc/systemd/system/$SERVICE_NAME
echo "✓ 服务配置已更新为: ${IMAGE_TAG}"

echo ""
echo "[4] 重新加载配置并启动..."
systemctl daemon-reload
systemctl start $SERVICE_NAME
sleep 5
echo "✓ 服务已启动"

echo ""
echo "[5] 验证..."
systemctl is-active $SERVICE_NAME
docker ps | grep llm-gateway-go
EOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Docker镜像部署完成"
echo "  编译号: $BUILD_NUM"
echo "  版本: $VERSION"
echo "  镜像: kx-llm-gateway-go:${IMAGE_TAG}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 清理本地tar文件
rm -f /tmp/kx-llm-gateway-go-${BUILD_NUM}.tar
