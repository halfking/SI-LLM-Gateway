#!/bin/bash
# deploy-71-data-bindmounts.sh — V2.3.3 (2026-07-02)
#
# Ensure that on the 71 server the running gateway container has the
# attachment + log directories bind-mounted from the host, so files
# survive container restarts. Without these mounts:
#   - attachments land in /data/attachments on the alpine rootfs (lost
#     on every restart, breaks /api/admin/attachments/{id} downloads).
#   - log files land in /logs on the alpine rootfs (lost on every
#     restart, debugging post-incident impossible).
#
# After this script runs, the systemd unit override.conf ExecStart will
# include both bind-mounts AND the env-file will contain
# ATTACHMENT_STORAGE_PATH + LLM_GATEWAY_LOG_FILE pointing at the same
# host paths.
#
# Idempotent: re-running this script overwrites the override.conf and
# env-file with the canonical contents and restarts the service.

set -euo pipefail

SSH_TARGET="${SSH_TARGET:-root@target-server}"
SSH_PORT="${SSH_PORT:-22}"
REMOTE_DIR="${REMOTE_DIR:-/opt/llm-gateway-go}"
SERVICE_NAME="${SERVICE_NAME:-llm-gateway-go.service}"
BIN_NAME="${BIN_NAME:-llm-gateway-go.v321.linux.amd64}"

ATTACHMENT_HOST_DIR="${ATTACHMENT_HOST_DIR:-/opt/llm-gateway-go/data}"
LOG_HOST_DIR="${LOG_HOST_DIR:-/opt/llm-gateway-go/logs}"
ENV_FILE="${ENV_FILE:-/etc/llm-gateway-go/env}"

GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
NC=$'\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

usage() {
    cat <<USAGE
Usage: SSH_TARGET=root@target-server ./scripts/deploy-71-data-bindmounts.sh

Environment overrides:
  SSH_TARGET          (default root@target-server)
  SSH_PORT            (default 22)
  REMOTE_DIR          (default /opt/llm-gateway-go)
  SERVICE_NAME        (default llm-gateway-go.service)
  BIN_NAME            (default llm-gateway-go.v321.linux.amd64)
  ATTACHMENT_HOST_DIR (default /opt/llm-gateway-go/data)
  LOG_HOST_DIR        (default /opt/llm-gateway-go/logs)
  ENV_FILE            (default /etc/llm-gateway-go/env)
USAGE
    exit 1
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

SSH="ssh -p $SSH_PORT -o StrictHostKeyChecking=accept-new $SSH_TARGET"

log_info "Target:        $SSH_TARGET:$SSH_PORT"
log_info "Remote dir:    $REMOTE_DIR"
log_info "Service:       $SERVICE_NAME"
log_info "Attachment:    $ATTACHMENT_HOST_DIR -> /opt/llm-gateway-go/data"
log_info "Log:           $LOG_HOST_DIR -> /opt/llm-gateway-go/logs"
log_info "Env file:      $ENV_FILE"
echo

# ── 1. Ensure host directories exist with correct ownership ────────────
log_info "[1/5] 创建主机挂载点目录..."
$SSH "mkdir -p '$ATTACHMENT_HOST_DIR/attachments' '$LOG_HOST_DIR' '\$(dirname '$ENV_FILE')' && chmod 755 '$ATTACHMENT_HOST_DIR' '$LOG_HOST_DIR' && ls -ld '$ATTACHMENT_HOST_DIR' '$LOG_HOST_DIR'"
log_info "  ✓ 目录就绪"
echo

# ── 2. Migrate any orphaned container-internal files to the host path ─
log_info "[2/5] 迁移容器内历史附件（仅首次）..."
$SSH bash -lc '
set -e
if docker inspect llm-gateway-go >/dev/null 2>&1; then
    echo "  检测到 llm-gateway-go 容器在运行；将尝试在线复制"
    docker cp llm-gateway-go:/opt/llm-gateway-go/data/attachments/. '"$ATTACHMENT_HOST_DIR"'/attachments/ 2>/dev/null \
        && echo "  ✓ 迁移容器内附件完成" \
        || echo "  容器内附件目录为空或不存在"
    docker cp llm-gateway-go:/opt/llm-gateway-go/logs/. '"$LOG_HOST_DIR"'/ 2>/dev/null \
        && echo "  ✓ 迁移容器内日志完成" \
        || echo "  容器内日志目录为空或不存在"
else
    echo "  容器未运行，无需迁移"
fi
' || log_warn "  迁移步骤失败，跳过（非阻塞）"
echo

# ── 3. Write env file (skeleton only — secrets load step writes the keys) ──
# SAFETY: if env-file already exists with custom overrides (e.g. ADMIN_API_KEY,
# SECRET_KEY), back it up first and SKIP overwrite. v2.4.0 secrets migration is
# only intended for first-time bootstrap. Re-running this script must not
# silently wipe out a previously restored env.
log_info "[3/5] 写入 $ENV_FILE (skeleton)..."
$SSH "mkdir -p '\$(dirname \"$ENV_FILE\")' && {
  if [[ -f \"$ENV_FILE\" ]]; then
    BAK=\"\$ENV_FILE.bak-\$(date +%Y%m%d-%H%M%S)-skipped-overwrite\"
    cp \"$ENV_FILE\" \"\$BAK\"
    echo \"  ⚠️  env-file 已存在，备份到 \$BAK 并跳过覆盖\"
    echo \"      （如确需重新生成骨架，先手动 rm \$ENV_FILE 再重跑本脚本）\"
  else
    cat > \"$ENV_FILE\" <<'SKELETON_EOF'
# /etc/llm-gateway-go/env — 2026-07-04 V2.4.0
# Consumed by 'docker run --env-file $ENV_FILE' in the systemd unit.
# These env vars override the gateway built-in defaults.
#
# Secrets (LLM_GATEWAY_SECRET_KEY, LLM_GATEWAY_CREDENTIAL_ENCRYPTION_KEY,
# and any LLM_GATEWAY_<PROVIDER>_API_KEY) are injected by
#   ~/.agents/skills/deploy-71/scripts/deploy-71-secrets.sh
# which reads from /root/.llm-gateway/secrets.env on each deploy. They are
# NOT hard-coded here so they can be rotated without re-running this script.
# Below are SAFE-TO-COMMIT defaults that get bootstrapped into
# /root/.llm-gateway/secrets.env on first run (so existing 71 hosts don't
# brick — rotate them by editing secrets.env + re-running deploy-71-secrets.sh).

# Database connection (required for routing executor, API key auth, request_logs)
# WARNING: The actual password and secret keys MUST be injected via deploy-71-secrets.sh.
# The values below are SAFE-TO-COMMIT bootstrap defaults; rotate immediately if used.
LLM_GATEWAY_DATABASE_URL=postgres://llm_gateway:${LLM_GATEWAY_DB_PASSWORD:?}@${LLM_GATEWAY_DB_HOST:-172.31.0.3}:5432/llm_gateway?sslmode=disable

# Secrets (required for API key verification and credential decryption).
LLM_GATEWAY_SECRET_KEY="${LLM_GATEWAY_SECRET_KEY:-change-me-in-secrets-env}"
LLM_GATEWAY_CREDENTIAL_ENCRYPTION_KEY="${LLM_GATEWAY_CREDENTIAL_ENCRYPTION_KEY:-change-me-in-secrets-env}"

# Attachment storage (must match the host bind-mount in override.conf)
ATTACHMENT_ENABLED=true
ATTACHMENT_STORAGE_PATH=/opt/llm-gateway-go/data/attachments
ATTACHMENT_MAX_SIZE_MB=10

# Rotated log file (must match the host bind-mount in override.conf)
LLM_GATEWAY_LOG_FILE=/opt/llm-gateway-go/logs/gateway.log
LLM_GATEWAY_LOG_MAX_SIZE_MB=100
LLM_GATEWAY_LOG_MAX_BACKUPS=10
LLM_GATEWAY_LOG_MAX_AGE_DAYS=0
LLM_GATEWAY_LOG_COMPRESS=true

# Static SPA bundle path (must be absolute inside container; working dir is /)
LLM_GATEWAY_STATIC_DIR=/opt/llm-gateway-go/web/dist
SKELETON_EOF
    chmod 600 \"$ENV_FILE\"
    echo \"  ✓ env 文件已写入\"
  fi
}"
echo

# ── 3b. Bootstrap /root/.llm-gateway/secrets.env (one-time, idempotent) ──
log_info "[3b/5] 引导 /root/.llm-gateway/secrets.env (首次迁移, 幂等)..."
$SSH bash -lc '
set -e
mkdir -p /root/.llm-gateway
chmod 700 /root/.llm-gateway
SECRETS=/root/.llm-gateway/secrets.env
ENVFILE='"$ENV_FILE"'

if [[ -f "$SECRETS" ]]; then
    echo "  ✓ secrets.env 已存在 ($SECRETS)，跳过引导"
    exit 0
fi
echo "  ⚠️  secrets.env 不存在，从 env-file 抽取密钥行（仅首次）..."

# Extract just the secret-related lines from the env-file.
# Pulls LLM_GATEWAY_SECRET_KEY + LLM_GATEWAY_CREDENTIAL_ENCRYPTION_KEY values.
cat > "$SECRETS.tmp" <<EOF
# /root/.llm-gateway/secrets.env — bootstrapped '"$(date +%Y-%m-%d)"'
# Source of truth for runtime secrets on this host.
# Managed by ~/.agents/skills/deploy-71/scripts/deploy-71-secrets.sh.
# DO NOT commit this file. Rotate by editing and re-running that script.
EOF
grep -E "^(LLM_GATEWAY_SECRET_KEY|LLM_GATEWAY_CREDENTIAL_ENCRYPTION_KEY)=" "$ENVFILE" >> "$SECRETS.tmp" || true
mv "$SECRETS.tmp" "$SECRETS"
chmod 600 "$SECRETS"

echo "  ✓ 已引导 $SECRETS："
sed -E "s/(KEY|TOKEN)=[^[:space:]]+=.*/\1=<redacted>/" "$SECRETS" | grep -v "^\$"
' || log_warn "  引导失败（非阻塞）— 你可以手动创建 /root/.llm-gateway/secrets.env"
echo

# ── 4. Write systemd override.conf with bind-mounts ────────────────────
log_info "[4/5] 写入 systemd override (含 bind-mount + env-file)..."
$SSH "mkdir -p /etc/systemd/system/${SERVICE_NAME}.service.d && cat > /etc/systemd/system/${SERVICE_NAME}.service.d/override.conf <<'EOF'
[Service]
# 2026-07-02 V2.3.3: bind-mount both attachment + log dirs from host,
# so files survive container restarts. See
# scripts/deploy-71-data-bindmounts.sh.
ExecStart=
ExecStart=/usr/bin/docker run --rm --name llm-gateway-go --network host \\
    --env-file $ENV_FILE \\
    -v $ATTACHMENT_HOST_DIR:/opt/llm-gateway-go/data \\
    -v $LOG_HOST_DIR:/opt/llm-gateway-go/logs \\
    -v $REMOTE_DIR/web:/opt/llm-gateway-go/web:ro \\
    -v $REMOTE_DIR/$BIN_NAME:/opt/llm-gateway-go/llm-gateway-go:ro \\
    -v $REMOTE_DIR/$BIN_NAME:/usr/local/bin/llm-gateway-go:ro \\
    --entrypoint /opt/llm-gateway-go/llm-gateway-go \\
    docker.m.daocloud.io/library/alpine:3.20
EOF
systemctl daemon-reload
echo '  ✓ override.conf 已写入'
cat /etc/systemd/system/${SERVICE_NAME}.service.d/override.conf"
echo

# ── 5. Restart and verify ──────────────────────────────────────────────
log_info "[5/5] 重启服务并验证..."
$SSH "systemctl restart '$SERVICE_NAME'
sleep 8
echo '--- service status ---'
systemctl is-active '$SERVICE_NAME'
echo
echo '--- gateway starting log ---'
docker logs --since 30s '$SERVICE_NAME' 2>&1 | grep -E 'gateway starting|attachment manager|log:' | tail -10 || true
echo
echo '--- bind-mount 校验 ---'
docker exec '$SERVICE_NAME' ls -la /opt/llm-gateway-go/data 2>/dev/null | head -8 || echo 'data 目录挂载校验失败'
docker exec '$SERVICE_NAME' ls -la /opt/llm-gateway-go/logs 2>/dev/null | head -8 || echo 'logs 目录挂载校验失败'
echo
echo '--- 健康检查 ---'
curl -fsS http://localhost:8781/healthz && echo ''
echo
echo '--- 新增 storage-stats 端点（无需鉴权可达性测试） ---'
curl -fsS -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:8781/api/admin/data-lifecycle/storage-stats || true"
echo
log_info "✅ bind-mount 部署完成"
echo
echo "验证清单："
echo "  1. 附件：docker exec llm-gateway-go ls /opt/llm-gateway-go/data/attachments"
echo "  2. 日志：docker exec llm-gateway-go ls /opt/llm-gateway-go/logs"
echo "  3. 数据生命周期：浏览器访问 /admin/data-lifecycle，应看到存储管理卡片"
echo
echo "重要提示：env-file 中的 ATTACHMENT_STORAGE_PATH 与 override.conf 中的"
echo "bind-mount 路径必须保持一致，否则文件写入会落到容器 rootfs 上。"