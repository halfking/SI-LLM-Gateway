#!/bin/bash
# deploy-71.sh — 唯一部署 71 入口 (V3.0, 2026-07-05)
#
# 把所有 71 部署相关操作合并到一个脚本：
#   1. bind-mount (附件/日志持久化)
#   2. 密钥加载 (DB-hash guard 防护)
#   3. 版本 bump + 交叉编译 + 上传 + 重启
#   4. 部署后冒烟测试
#
# 用法：
#   export SSHPASS=Kaixuan2025
#   ./scripts/deploy-71.sh                       # 默认：bump + 全部步骤
#   ./scripts/deploy-71.sh --seq 800             # 指定 build_seq
#   ./scripts/deploy-71.sh --no-restart          # 不重启服务
#   ./scripts/deploy-71.sh --skip-bindmount      # 跳过 bind-mount（首次或修复后）
#   ./scripts/deploy-71.sh --skip-secrets        # 跳过密钥加载（debug 用）
#   ./scripts/deploy-71.sh --skip-smoke           # 跳过冒烟测试
#   ./scripts/deploy-71.sh --dry-run             # 仅显示动作，不实际执行
#
# 前置检查：
#   - 远端 env-file 必须指向 172.31.0.3 (71 本地 PG)，不可指向 172.31.0.4 (184)
#   - /root/.llm-gateway/secrets.env 必须存在且 mode=600
#   - 密钥会被 deploy-71-secrets.sh 二次校验 (DB-hash guard)
#
# 历史：
#   - v1 (pre-2026-07-04): scripts/deploy-71.sh 仅负责 bump-version
#   - v2 (2026-07-04): 拆分 deploy-71-data-bindmounts.sh，但密钥在 bind-mount 步骤丢失
#   - v3 (2026-07-05): 整合 deploy-71-data-bindmounts.sh + deploy-71-secrets.sh 逻辑，
#                      bind-mount 写入的 env-file 不再硬编码密钥，全部由 secrets 步骤
#                      统一管理；DB-hash guard 防止错误密钥覆盖 env-file
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# ── 默认值 ───────────────────────────────────────────────────────────────
SSH_TARGET="${SSH_TARGET:-root@14.103.174.71}"
SSH_PORT="${SSH_PORT:-25022}"
REMOTE_DIR="${REMOTE_DIR:-/opt/llm-gateway-go}"
SERVICE_NAME="${SERVICE_NAME:-llm-gateway-go.service}"
BIN_NAME="${BIN_NAME:-llm-gateway-go.v321.linux.amd64}"

# 71 必须用本地 PG (172.31.0.3)；184 (172.31.0.4) 是另一个独立部署
EXPECTED_71_HOSTS="${EXPECTED_71_HOSTS:-172.31.0.3}"
BANNED_HOSTS="${BANNED_HOSTS:-172.31.0.4}"

# Bind-mount 路径（必须与 env-file 中的 ATTACHMENT_STORAGE_PATH / LLM_GATEWAY_LOG_FILE 一致）
ATTACHMENT_HOST_DIR="${ATTACHMENT_HOST_DIR:-/opt/llm-gateway-go/data}"
LOG_HOST_DIR="${LOG_HOST_DIR:-/opt/llm-gateway-go/logs}"
ENV_FILE="${ENV_FILE:-/etc/llm-gateway-go/env}"
SECRETS_SOURCE_FILE="${SECRETS_SOURCE_FILE:-/root/.llm-gateway/secrets.env}"

# Deploy-71 secrets 脚本位置（优先 skill 标准位置，回退仓库内副本）
SKILL_SECRETS_SH="$HOME/.agents/skills/deploy-71/scripts/deploy-71-secrets.sh"
SKILL_SMOKE_SH="$HOME/.agents/skills/deploy-71/scripts/smoke-test.sh"
LOCAL_SECRETS_SH="$SCRIPT_DIR/deploy-71-secrets.sh"
LOCAL_VERIFY_PY="$SCRIPT_DIR/verify_secret_key.py"

# ── 标志位 ───────────────────────────────────────────────────────────────
SEQ=""
SKIP_FRONTEND="${SKIP_FRONTEND:-true}"
SKIP_DB_PRECHECK="${SKIP_DB_PRECHECK:-false}"
SKIP_BINDMOUNT="${SKIP_BINDMOUNT:-false}"
SKIP_SECRETS="${SKIP_SECRETS:-false}"
SKIP_SMOKE="${SKIP_SMOKE:-false}"
DRY_RUN=false

# ── 颜色 / 日志 ──────────────────────────────────────────────────────────
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_err()   { echo -e "${RED}[ERR]${NC}   $*" >&2; }
log_step()  { echo -e "${CYAN}[STEP]${NC}  $*"; }

# ── Usage ────────────────────────────────────────────────────────────────
usage() {
    sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --seq)              SEQ="$2"; shift 2 ;;
        --no-frontend)      SKIP_FRONTEND=true; shift ;;
        --with-frontend)    SKIP_FRONTEND=false; shift ;;
        --skip-bindmount)   SKIP_BINDMOUNT=true; shift ;;
        --skip-secrets)     SKIP_SECRETS=true; shift ;;
        --skip-smoke)       SKIP_SMOKE=true; shift ;;
        --skip-db-precheck) SKIP_DB_PRECHECK=true; shift ;;
        --dry-run)          DRY_RUN=true; shift ;;
        -h|--help)          usage ;;
        *)                  log_err "unknown arg: $1"; usage ;;
    esac
done

SSH="ssh -p $SSH_PORT -o StrictHostKeyChecking=accept-new $SSH_TARGET"

log_info "Target:          $SSH_TARGET:$SSH_PORT"
log_info "Remote dir:      $REMOTE_DIR"
log_info "Service:         $SERVICE_NAME"
log_info "Binary:          $BIN_NAME"
log_info "Build seq:       ${SEQ:-auto (current+1)}"
log_info "Skip frontend:   $SKIP_FRONTEND"
log_info "Skip bind-mount: $SKIP_BINDMOUNT"
log_info "Skip secrets:    $SKIP_SECRETS"
log_info "Skip smoke:      $SKIP_SMOKE"
log_info "Dry run:         $DRY_RUN"
echo

# ── 工具函数 ─────────────────────────────────────────────────────────────
run_ssh() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY] ssh $SSH_TARGET -- $*"
    else
        $SSH "$@"
    fi
}

# ── [Step 0] Preflight: DB host check ───────────────────────────────────
# 71 必须用本地 PG (172.31.0.3)，不可指向 184 (172.31.0.4)。
# 若 env 已存在且 host 不在白名单 → abort。
if [[ "$SKIP_DB_PRECHECK" != "true" ]]; then
    log_step "[0/4] Preflight: 检查远端 DB host..."
    if $SSH "test -f '$ENV_FILE'" >/dev/null 2>&1; then
        DB_URL=$(run_ssh "grep '^LLM_GATEWAY_DATABASE_URL=' '$ENV_FILE' 2>/dev/null | head -1 | cut -d= -f2-")
        if [[ -n "$DB_URL" ]]; then
            HOST=$(echo "$DB_URL" | sed -n 's|^postgres://[^@]*@||p' | sed 's|:.*||')
            PORT=$(echo "$DB_URL" | sed -n 's|^postgres://[^@]*@[^:]*:||p' | sed 's|/.*||')
            log_info "  LLM_GATEWAY_DATABASE_URL host=$HOST port=$PORT"

            banned=0
            for b in $BANNED_HOSTS; do
                if [[ "$HOST" == "$b" ]]; then
                    log_err "ABORT: env 指向 banned host $HOST (71 vs 184 schema 独立，不可共享)"
                    log_err "expected: $EXPECTED_71_HOSTS"
                    log_err "bypass:   --skip-db-precheck"
                    exit 2
                fi
            done
            ok=0
            for e in $EXPECTED_71_HOSTS; do
                if [[ "$HOST" == "$e" ]]; then ok=1; break; fi
            done
            [[ $ok -eq 0 ]] && log_warn "DB host $HOST 不在白名单 $EXPECTED_71_HOSTS（继续，看后续步骤是否能恢复）"
        else
            log_warn "env-file 中无 LLM_GATEWAY_DATABASE_URL（首次部署或被清空）"
        fi
    else
        log_warn "env-file 不存在 ($ENV_FILE)，将在 bind-mount 步骤创建"
    fi
fi
echo

# ── [Step 1] Bind-mount (幂等) ──────────────────────────────────────────
if [[ "$SKIP_BINDMOUNT" != "true" ]]; then
    log_step "[1/4] 配置 bind-mount (幂等)..."

    # 1a. 主机目录
    log_info "  [1a] 创建主机挂载点..."
    run_ssh "mkdir -p '$ATTACHMENT_HOST_DIR/attachments' '$LOG_HOST_DIR' \
        && chmod 755 '$ATTACHMENT_HOST_DIR' '$LOG_HOST_DIR' \
        && ls -ld '$ATTACHMENT_HOST_DIR' '$LOG_HOST_DIR'"

    # 1b. 迁移容器内历史文件（仅首次）
    log_info "  [1b] 迁移容器内历史附件/日志（仅首次）..."
    run_ssh bash -lc '
        set -e
        if docker inspect llm-gateway-go >/dev/null 2>&1; then
            docker cp llm-gateway-go:/opt/llm-gateway-go/data/attachments/. "$ATTACHMENT_HOST_DIR/attachments/" 2>/dev/null \
                && echo "    ✓ 容器内附件已迁移" || echo "    容器内附件目录为空或不存在"
            docker cp llm-gateway-go:/opt/llm-gateway-go/logs/. "$LOG_HOST_DIR/" 2>/dev/null \
                && echo "    ✓ 容器内日志已迁移" || echo "    容器内日志目录为空或不存在"
        else
            echo "    容器未运行，跳过"
        fi
    ' || log_warn "  迁移步骤失败（非阻塞）"

    # 1c. env-file 模板（**关键：不写密钥，全部由 Step 2 注入**）
    # 注意：SECRET_KEY 等敏感字段绝对不写在此处，避免覆盖 secrets.env 注入的值。
    log_info "  [1c] 写入 env-file 模板（密钥由 Step 2 注入）..."
    run_ssh "mkdir -p '\$(dirname '$ENV_FILE')' && cat > '$ENV_FILE' <<'ENVEOF'
# $ENV_FILE — managed by scripts/deploy-71.sh
# Secrets are injected by Step 2 (deploy-71-secrets.sh) with DB-hash guard.
# Do NOT hardcode LLM_GATEWAY_SECRET_KEY or LLM_GATEWAY_CREDENTIAL_ENCRYPTION_KEY here.

# Database (71 本地 PG，不可指向 184)
LLM_GATEWAY_DATABASE_URL=postgres://llm_gateway:4Q92cFTaYY8Z3AO07XTBBH-1g7kceaxg@172.31.0.3:5432/llm_gateway?sslmode=disable

# Static files
LLM_GATEWAY_STATIC_DIR=/opt/llm-gateway-go/web/dist

# Attachment storage (must match bind-mount below)
ATTACHMENT_ENABLED=true
ATTACHMENT_STORAGE_PATH=/opt/llm-gateway-go/data/attachments
ATTACHMENT_MAX_SIZE_MB=10

# Log rotation (must match bind-mount below)
LLM_GATEWAY_LOG_FILE=/opt/llm-gateway-go/logs/gateway.log
LLM_GATEWAY_LOG_MAX_SIZE_MB=100
LLM_GATEWAY_LOG_MAX_BACKUPS=10
LLM_GATEWAY_LOG_MAX_AGE_DAYS=0
LLM_GATEWAY_LOG_COMPRESS=true
ENVEOF
chmod 600 '$ENV_FILE'
echo '    ✓ env-file 模板已写入 (mode=600)'"

    # 1d. systemd override.conf（含 bind-mount）
    log_info "  [1d] 写入 systemd override.conf..."
    run_ssh "mkdir -p /etc/systemd/system/${SERVICE_NAME}.service.d \
        && cat > /etc/systemd/system/${SERVICE_NAME}.service.d/override.conf <<'OVEOF'
[Service]
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
OVEOF
systemctl daemon-reload
echo '    ✓ override.conf 已写入'"
    log_info "  bind-mount 配置完成（env-file 密钥待 Step 2 注入）"
else
    log_warn "[1/4] 跳过 bind-mount 配置"
fi
echo

# ── [Step 2] 加载密钥 (DB-hash guard 防护) ──────────────────────────────
if [[ "$SKIP_SECRETS" != "true" ]]; then
    log_step "[2/4] 加载密钥到 env-file (DB-hash guard)..."

    # 优先 skill 标准位置，回退仓库内副本
    SECRETS_SH=""
    if [[ -x "$SKILL_SECRETS_SH" ]]; then
        SECRETS_SH="$SKILL_SECRETS_SH"
    elif [[ -x "$LOCAL_SECRETS_SH" ]]; then
        SECRETS_SH="$LOCAL_SECRETS_SH"
    else
        log_err "找不到 deploy-71-secrets.sh："
        log_err "  - $SKILL_SECRETS_SH"
        log_err "  - $LOCAL_SECRETS_SH"
        exit 1
    fi
    log_info "  使用 secrets 脚本: $SECRETS_SH"

    # 源文件存在性 + 权限检查
    if ! $SSH "test -f '$SECRETS_SOURCE_FILE'"; then
        log_err "源文件不存在: $SSH_TARGET:$SECRETS_SOURCE_FILE"
        log_err "请在 71 上手动创建: ssh $SSH_TARGET 'install -m 600 /dev/null $SECRETS_SOURCE_FILE && \$EDITOR $SECRETS_SOURCE_FILE'"
        exit 1
    fi
    SRC_MODE=$(run_ssh "stat -c '%a' '$SECRETS_SOURCE_FILE' 2>/dev/null || stat -f '%Lp' '$SECRETS_SOURCE_FILE' 2>/dev/null" | tr -d '[:space:]')
    if [[ "$SRC_MODE" != "600" && "$SRC_MODE" != "400" ]]; then
        log_err "源文件权限不安全 (mode=$SRC_MODE, want 600/400): $SECRETS_SOURCE_FILE"
        log_err "修复: ssh $SSH_TARGET 'chmod 600 $SECRETS_SOURCE_FILE'"
        exit 1
    fi

    SECRETS_ARGS=()
    [[ "$DRY_RUN" == "true" ]] && SECRETS_ARGS+=(--dry-run)
    # 默认 merge 模式：保留 env-file 中已有且相同的 key
    # 仅在用户明确请求时才用 --force
    SSH_TARGET="$SSH_TARGET" SSH_PORT="$SSH_PORT" \
        bash "$SECRETS_SH" "${SECRETS_ARGS[@]}"
    log_info "  ✓ 密钥加载完成"
else
    log_warn "[2/4] 跳过密钥加载（env-file 中可能无 SECRET_KEY）"
fi
echo

# ── [Step 3] Bump version + upload + restart ─────────────────────────────
log_step "[3/4] Bump version + cross-compile + upload + restart..."

extra_flags=()
[[ -n "$SEQ" ]] && extra_flags+=(--seq "$SEQ")
[[ "$SKIP_FRONTEND" == "true" ]] && extra_flags+=(--no-frontend)

if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "[DRY] 跳过 bump-version + upload + restart"
else
    bash "$REPO_ROOT/scripts/bump-version.sh" \
        --ssh "$SSH_TARGET" \
        --port "$SSH_PORT" \
        --remote-dir "$REMOTE_DIR" \
        --service "$SERVICE_NAME" \
        --bin "$BIN_NAME" \
        "${extra_flags[@]}"
fi
echo

# ── [Step 4] 部署后冒烟测试 ─────────────────────────────────────────────
if [[ "$SKIP_SMOKE" != "true" ]]; then
    log_step "[4/4] 部署后冒烟测试..."
    SMOKE_SH=""
    if [[ -x "$SKILL_SMOKE_SH" ]]; then
        SMOKE_SH="$SKILL_SMOKE_SH"
    elif [[ -x "$SCRIPT_DIR/../smoke-test.sh" ]]; then
        # 仓库内可能在未来添加一份 smoke-test.sh
        SMOKE_SH="$SCRIPT_DIR/../smoke-test.sh"
    fi

    if [[ -z "$SMOKE_SH" ]]; then
        log_warn "找不到 smoke-test.sh，跳过冒烟测试"
    elif [[ "$DRY_RUN" == "true" ]]; then
        log_warn "[DRY] 跳过 smoke-test"
    else
        SSH_TARGET="$SSH_TARGET" SSH_PORT="$SSH_PORT" bash "$SMOKE_SH"
    fi
else
    log_warn "[4/4] 跳过冒烟测试"
fi
echo

log_info "✅ 部署完成"
echo
echo "下一步验证（手动或脚本）："
echo "  1. API 探活:  curl -fsS http://localhost:8781/healthz"
echo "  2. 版本检查: curl -fsS http://localhost:8781/api/system/version"
echo "  3. LLM 请求:  curl -X POST https://llm.kxpms.cn/v1/chat/completions \\"
echo "                  -H 'Authorization: Bearer sk-...' \\"
echo "                  -H 'Content-Type: application/json' \\"
echo "                  -d '{\"model\":\"minimax-m3\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}'"
echo
echo "完整测试套件："
echo "  ./scripts/test_71_complete.sh        # API 压力 + DB 诊断"
echo "  ./scripts/test_71_routing.sh         # 路由诊断"
echo "  ./scripts/diagnose_request_logs_71.sh"
echo "  ./scripts/fix_71_routing_complete.sh"