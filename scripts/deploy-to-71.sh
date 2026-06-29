#!/bin/bash
# deploy-to-71.sh — 2026-06-29 会话管理修复部署脚本
# 
# 用法：
#   ./scripts/deploy-to-71.sh [--skip-tests] [--dry-run]
#
# 选项：
#   --skip-tests    跳过测试（不推荐，仅用于紧急修复）
#   --dry-run       仅显示将要执行的命令，不实际部署

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# 生产服务器配置（敏感信息已占位化）
# 实际值通过环境变量注入：DEPLOY_HOST / DEPLOY_HOST_IP / SSHPASS
# 推荐改用 SSH 密钥认证：DEPLOY_SSH_KEY=/path/to/key
SERVER_71="${DEPLOY_HOST:-root@<PROD_HOST>}"
SERVER_71_IP="${DEPLOY_HOST_IP:-<PROD_HOST_IP>}"
REMOTE_DIR="/opt/llm-gateway-go"
SERVICE_NAME="llm-gateway"

# SSH 认证配置（敏感信息已占位化）
# 必须通过环境变量 SSHPASS 注入真实密码；推荐改用 SSH 密钥（删除 SSHPASS 即可）
export SSHPASS="${SSHPASS:-<YOUR_SSHPASS_PLACEHOLDER>}"
SSH_CMD="${DEPLOY_SSH_CMD:-sshpass -e ssh -o StrictHostKeyChecking=no}"
SCP_CMD="${DEPLOY_SSH_CMD:-sshpass -e scp -o StrictHostKeyChecking=no}"

DRY_RUN=false
SKIP_TESTS=false

# 解析参数
for arg in "$@"; do
  case $arg in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --skip-tests)
      SKIP_TESTS=true
      shift
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Usage: $0 [--skip-tests] [--dry-run]"
      exit 1
      ;;
  esac
done

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] $*"
  else
    log "执行: $*"
    eval "$*"
  fi
}

# 1. 本地测试
if [ "$SKIP_TESTS" = false ]; then
  log "运行本地测试..."
  cd "$PROJECT_ROOT"
  run_cmd "go test ./relay ./sessions ./reconnect -v | tail -20"
  log "✓ 测试通过"
else
  log "⚠️  跳过测试（--skip-tests）"
fi

# 2. 本地编译
log "编译二进制..."
cd "$PROJECT_ROOT"
run_cmd "go build -o llm-gateway-$(git rev-parse --short HEAD) ./cmd/gateway"
BINARY_NAME="llm-gateway-$(git rev-parse --short HEAD)"
log "✓ 编译完成: $BINARY_NAME"

# 3. 上传到服务器
log "上传二进制到服务器 71 (${SERVER_71_IP})..."
run_cmd "$SCP_CMD $BINARY_NAME ${SERVER_71}:${REMOTE_DIR}/"
log "✓ 上传完成"

# 4. 远程部署
log "在服务器 71 上执行部署..."

REMOTE_SCRIPT=$(cat <<'EOF'
set -euo pipefail

BINARY_NAME="$1"
REMOTE_DIR="$2"
SERVICE_NAME="$3"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

cd "$REMOTE_DIR"

# 备份当前版本
if [ -f "/usr/local/bin/$SERVICE_NAME" ]; then
  log "备份当前版本..."
  cp "/usr/local/bin/$SERVICE_NAME" "/usr/local/bin/${SERVICE_NAME}.bak.$(date +%Y%m%d_%H%M%S)"
fi

# 停止服务
log "停止服务..."
systemctl stop "$SERVICE_NAME" || true
sleep 5

# 部署新版本
log "部署新版本..."
cp "$BINARY_NAME" "/usr/local/bin/$SERVICE_NAME"
chmod +x "/usr/local/bin/$SERVICE_NAME"

# 启动服务
log "启动服务..."
systemctl start "$SERVICE_NAME"
sleep 3

# 检查状态
log "检查服务状态..."
if systemctl is-active --quiet "$SERVICE_NAME"; then
  log "✓ 服务启动成功"
  systemctl status "$SERVICE_NAME" --no-pager -l
else
  log "✗ 服务启动失败"
  journalctl -u "$SERVICE_NAME" -n 50 --no-pager
  exit 1
fi

# 健康检查
log "健康检查..."
for i in {1..10}; do
  if curl -f http://localhost:8080/health >/dev/null 2>&1; then
    log "✓ 健康检查通过"
    exit 0
  fi
  log "等待服务就绪... ($i/10)"
  sleep 2
done

log "✗ 健康检查失败"
journalctl -u "$SERVICE_NAME" -n 50 --no-pager
exit 1
EOF
)

if [ "$DRY_RUN" = true ]; then
  echo "[DRY-RUN] 将在服务器 71 上执行远程部署脚本"
  echo "$REMOTE_SCRIPT"
else
  $SSH_CMD "$SERVER_71" "bash -s" "$BINARY_NAME" "$REMOTE_DIR" "$SERVICE_NAME" <<< "$REMOTE_SCRIPT"
fi

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "部署完成！"
log ""
log "后续验证步骤："
log "1. 检查日志: ssh $SERVER_71 'journalctl -u $SERVICE_NAME -f'"
log "2. 测试会话管理: 参考 DEPLOYMENT_2026-06-29.md"
log "3. 监控 request_logs 覆盖率"
log ""
log "回滚命令（如需）:"
log "  ssh $SERVER_71 'systemctl stop $SERVICE_NAME && cp /usr/local/bin/${SERVICE_NAME}.bak.* /usr/local/bin/$SERVICE_NAME && systemctl start $SERVICE_NAME'"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
