#!/bin/bash
# 部署 V2.2.9-session-fix 到 71 服务器
set -euo pipefail

SERVER="root@llm.kxpms.cn"
REMOTE_PATH="/opt/llm-gateway-go"
VERSION="V2.2.9-session-fix"
BINARY_NAME="llm-gateway-${VERSION}"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "=========================================="
log "部署 ${VERSION} 到 71 服务器"
log "=========================================="

# 1. 检查本地二进制是否存在
if [ ! -f "$BINARY_NAME" ]; then
  log "❌ 本地二进制不存在: $BINARY_NAME"
  exit 1
fi

log "✓ 本地二进制: $BINARY_NAME ($(ls -lh $BINARY_NAME | awk '{print $5}'))"

# 2. 上传二进制到服务器
log "上传二进制到服务器..."
scp "$BINARY_NAME" "${SERVER}:${REMOTE_PATH}/"
log "✓ 上传完成"

# 3. 远程部署
log "在服务器上执行部署..."
ssh "$SERVER" bash -s << REMOTE_SCRIPT
set -euo pipefail

cd "$REMOTE_PATH"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$*"
}

# 备份当前版本
if [ -f "llm-gateway" ]; then
  BACKUP_NAME="llm-gateway.backup.\$(date +%Y%m%d_%H%M%S)"
  log "备份当前版本: \$BACKUP_NAME"
  cp llm-gateway "\$BACKUP_NAME"
fi

# 停止服务
log "停止服务..."
systemctl stop llm-gateway || true
sleep 3

# 部署新版本
log "部署新版本..."
cp "$BINARY_NAME" llm-gateway
chmod +x llm-gateway

# 启动服务
log "启动服务..."
systemctl start llm-gateway
sleep 5

# 检查状态
if systemctl is-active --quiet llm-gateway; then
  log "✓ 服务启动成功"
  systemctl status llm-gateway --no-pager -l | head -15
else
  log "❌ 服务启动失败"
  journalctl -u llm-gateway -n 50 --no-pager
  exit 1
fi

# 健康检查
log "健康检查..."
for i in {1..10}; do
  if curl -f http://localhost:8080/health >/dev/null 2>&1; then
    log "✓ 健康检查通过"
    exit 0
  fi
  log "等待服务就绪... (\$i/10)"
  sleep 2
done

log "❌ 健康检查失败"
journalctl -u llm-gateway -n 50 --no-pager
exit 1
REMOTE_SCRIPT

log "=========================================="
log "部署完成！版本: ${VERSION}"
log "=========================================="
