#!/bin/bash
# deploy-71-secrets.sh — V2.0.0 (2026-07-04)
#
# Auto-load secrets from a root-only file on the 71 host into the gateway's
# systemd env-file, then restart the service.
#
# Problem this solves:
#   - "Invalid or expired API key" errors when the gateway tries to decrypt
#     provider credentials stored in the DB. Root cause is almost always that
#     the env-file's LLM_GATEWAY_CREDENTIAL_ENCRYPTION_KEY doesn't match the
#     key that was used to encrypt credentials in the DB. This script ensures
#     the env-file always has the *latest* secret values from a single source-
#     of-truth file that lives outside version control.
#
# Source file:  /root/.llm-gateway/secrets.env   (chmod 600, root:root only)
# Target file:  /etc/llm-gateway-go/env          (chmod 600)
# Mode:         merge (upsert) — existing env-file keys NOT touched unless --force
#
# Source file format (one per line, no comments mixed with values):
#   KEY=value
#   KEY="quoted value with spaces"
#   # comment line (ignored)
#   KEY=        (empty value allowed; will skip with a warning unless --keep-empty)
#
# Usage (from any host with sshpass + SSH access to 71):
#   export SSHPASS=Kaixuan2025
#   bash ~/.agents/skills/deploy-71/scripts/deploy-71-secrets.sh
#
# Flags (all optional):
#   --force             overwrite existing env-file keys (default: skip + warn)
#   --no-restart        skip systemctl restart (just write the env-file)
#   --keep-empty        allow KEY= (empty value) lines
#   --dry-run           print diff + no remote writes
#   --source PATH       override source file path (default /root/.llm-gateway/secrets.env)
#   --target PATH       override env-file path (default /etc/llm-gateway-go/env)
#
# Exit codes:
#   0  success (env-file updated, service running)
#   1  validation/source-file error
#   2  remote write failed
#   3  post-restart healthcheck failed
#
# Design notes:
#   - We scp the entire remote Python payload to /tmp/deploy-71-secrets-merge.py
#     instead of using inline heredocs. This avoids bash-quoting fragility,
#     `bash: -c: option requires an argument` warnings, and silent failures
#     when heredocs are eaten by `set -e`.
#   - We pass all configuration via explicit CLI args to the Python script,
#     NOT via shell env vars. CLI args don't get lost to `bash -c` arg-splitting.
#   - Every Python exit code propagates back through ssh and the bash $SSH
#     wrapper, so a failure CANNOT silently look like success.

set -euo pipefail

# Resolve SKILL_DIR so we can locate companion scripts (verify_secret_key.py).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SSH_TARGET="${SSH_TARGET:-root@14.103.174.71}"
SSH_PORT="${SSH_PORT:-25022}"
SERVICE_NAME="${SERVICE_NAME:-llm-gateway-go.service}"

SOURCE_FILE="${SOURCE_FILE:-/root/.llm-gateway/secrets.env}"
TARGET_FILE="${TARGET_FILE:-/etc/llm-gateway-go/env}"
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S)"

# Default behavior flags. Overridden via CLI flags below.
FORCE=0
NO_RESTART=0
KEEP_EMPTY=0
DRY_RUN=0

# ── CLI ────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)       FORCE=1; shift ;;
        --no-restart)  NO_RESTART=1; shift ;;
        --keep-empty)  KEEP_EMPTY=1; shift ;;
        --dry-run)     DRY_RUN=1; shift ;;
        --source)      SOURCE_FILE="$2"; shift 2 ;;
        --target)      TARGET_FILE="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,46p' "$0"
            exit 0
            ;;
        *)
            echo "ERROR: unknown flag: $1" >&2
            sed -n '2,46p' "$0" >&2
            exit 1
            ;;
    esac
done

# ── Colors / logging ───────────────────────────────────────────────────────
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
NC=$'\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
die()       { log_error "$@"; exit 1; }

# Build the SSH command prefix. Use a bash array so multi-token values like
# the host name work even if they contained spaces. We never embed complex
# scripts inline — we pass them as a single base64 arg to a remote script.
SSH=(ssh -p "$SSH_PORT" -o StrictHostKeyChecking=accept-new "$SSH_TARGET")
SCP=(scp -P "$SSH_PORT" -o StrictHostKeyChecking=accept-new)

# Validate paths contain only safe characters to avoid shell injection.
# We accept A-Z, a-z, 0-9, /, ., _, -, = (no spaces, no quotes).
# IMPORTANT: bash regex sees '-' between two chars as a range, so place '-'
# at the start or end of the character class to be a literal.
if ! [[ "$SOURCE_FILE" =~ ^[-/.[:alnum:]_=]+$ ]]; then
    die "SOURCE_FILE contains unsafe chars: $SOURCE_FILE"
fi
if ! [[ "$TARGET_FILE" =~ ^[-/.[:alnum:]_=]+$ ]]; then
    die "TARGET_FILE contains unsafe chars: $TARGET_FILE"
fi
# Validate SSH target contains only safe chars (no shell metachars).
if ! [[ "$SSH_TARGET" =~ ^[-_.@[:alnum:]]+$ ]]; then
    die "SSH_TARGET contains unsafe chars: $SSH_TARGET"
fi
# Validate SERVICE_NAME contains only safe chars.
if ! [[ "$SERVICE_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
    die "SERVICE_NAME contains unsafe chars: $SERVICE_NAME"
fi

log_info "Target host:        $SSH_TARGET:$SSH_PORT"
log_info "Source secrets:     $SSH_TARGET:$SOURCE_FILE"
log_info "Target env-file:    $TARGET_FILE"
MODE_DESC="merge (upsert)"
[[ $FORCE == 1 ]] && MODE_DESC="FORCED overwrite"
log_info "Mode:               $MODE_DESC"
log_info "Restart after:      $([[ $NO_RESTART == 1 ]] && echo no || echo yes)"
[[ $DRY_RUN == 1 ]] && log_warn "DRY RUN — no remote writes"
echo

# ── 1. Read + validate the source file ON THE REMOTE HOST ────────────────
# Pull the source file via scp to a local tmp. scp is more robust than
# `ssh cat` because it preserves binary safety and doesn't suffer from
# shell-quoting issues with multi-line content.
ORIG_SOURCE_FILE="$SOURCE_FILE"
log_info "[1/6] 从 $SSH_TARGET:$SOURCE_FILE 拉取源文件..."

# Pre-check: file exists, mode is 600/400.
REMOTE_FILE_CHECK=$("${SSH[@]}" "stat -c '%a %s' '$ORIG_SOURCE_FILE' 2>/dev/null || stat -f '%Lp %z' '$ORIG_SOURCE_FILE' 2>/dev/null" 2>&1) || {
    # If stat fails, the file may not exist. Use a separate check.
    if ! "${SSH[@]}" "test -f '$ORIG_SOURCE_FILE'"; then
        die "远端源文件不存在: $SSH_TARGET:$ORIG_SOURCE_FILE"
    fi
    die "无法 stat 远端文件: $ORIG_SOURCE_FILE"
}
REMOTE_MODE=$(echo "$REMOTE_FILE_CHECK" | awk '{print $1}')
REMOTE_SIZE=$(echo "$REMOTE_FILE_CHECK" | awk '{print $2}')
if [[ "$REMOTE_MODE" != "600" && "$REMOTE_MODE" != "400" ]]; then
    die "远端源文件权限不安全 (mode=$REMOTE_MODE, want 600/400): $ORIG_SOURCE_FILE"
fi
log_info "  ✓ 远端文件就绪 (mode=$REMOTE_MODE size=${REMOTE_SIZE}B)"

# scp the source file to a local tmp. We use a fresh tmp path and clean up
# on exit so secrets don't linger on the deploy host's filesystem.
SRC_LOCAL=$(mktemp -t secrets-XXXXXX.env)
SECRETS_TMP_FILES=("$SRC_LOCAL")
cleanup() { rm -f "${SECRETS_TMP_FILES[@]}"; }
trap cleanup EXIT
"${SCP[@]}" "${SSH_TARGET}:${ORIG_SOURCE_FILE}" "$SRC_LOCAL" >/dev/null 2>&1 || die "scp 远端源文件失败"
chmod 600 "$SRC_LOCAL"
log_info "  ✓ 已拉取到 $SRC_LOCAL (mode=600)"
SOURCE_FILE="$SRC_LOCAL"

# ── Parse + validate lines locally ───────────────────────────────────────
SRC_KEY_COUNT=0
SRC_BAD_LINES=0
SRC_EMPTY_LINES=0
declare -a SOURCE_KEYS=()
# Validated KEY=VAL payload (newline-separated). Written as bytes (no quotes)
# because we control the parser.
SOURCE_BODY="$(mktemp)"
SECRETS_TMP_FILES+=("$SOURCE_BODY")

while IFS= read -r line || [[ -n "$line" ]]; do
    # Strip trailing CR (in case file was edited on Windows).
    line="${line%$'\r'}"
    # Skip blank lines and full-line comments.
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    # Allow inline comments only after a value, not the start. We strip simple
    # trailing "#"-comments if there's whitespace before them — but to keep the
    # parser foolproof, require NO inline comments. Reject any line containing
    # a # not at the start:
    if [[ "$line" == *'#'* ]]; then
        # Allow # inside a quoted value: heuristic — count quotes before #.
        left="${line%%#*}"
        qcnt=$(tr -cd '"' <<<"$left" | wc -c)
        if (( qcnt % 2 == 0 )); then
            log_warn "跳过注释行: $line"
            continue
        fi
    fi
    # Must be KEY=value where KEY matches ^[A-Z][A-Z0-9_]*$
    if ! [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]]; then
        log_warn "非法行 (跳过): $line"
        SRC_BAD_LINES=$((SRC_BAD_LINES + 1))
        continue
    fi
    KEY="${BASH_REMATCH[1]}"
    VAL="${BASH_REMATCH[2]}"
    # Strip surrounding quotes if present (single or double).
    if [[ "$VAL" =~ ^\"(.*)\"$ ]] || [[ "$VAL" =~ ^\'(.*)\'$ ]]; then
        VAL="${BASH_REMATCH[1]}"
    fi
    if [[ -z "$VAL" && $KEEP_EMPTY -ne 1 ]]; then
        log_warn "空值 (跳过，使用 --keep-empty 启用): $KEY="
        SRC_EMPTY_LINES=$((SRC_EMPTY_LINES + 1))
        continue
    fi
    SOURCE_KEYS+=("$KEY")
    SRC_KEY_COUNT=$((SRC_KEY_COUNT + 1))
    # Write the sanitized KEY=VAL line into the temp body.
    printf '%s=%s\n' "$KEY" "$VAL" >> "$SOURCE_BODY"
done < "$SOURCE_FILE"

if [[ $SRC_KEY_COUNT -eq 0 ]]; then
    die "源文件中没有可用的密钥行 (bad=$SRC_BAD_LINES empty=$SRC_EMPTY_LINES)"
fi
log_info "  ✓ 解析到 $SRC_KEY_COUNT 个密钥 (bad=$SRC_BAD_LINES empty=$SRC_EMPTY_LINES)"
echo

# ── 2. Stage the merge payload + helper scripts on the remote ──────────────
# We build the full set of remote operations as a single self-contained
# Python script that we scp to /tmp. The Python script:
#   1. Reads the existing env-file (or fails loud if missing — script [4]
#      will create it if missing, but Python must NOT silently write to a
#      different path)
#   2. Parses the merged payload (passed as a file, NOT inline)
#   3. Writes atomically via temp file + rename
#   4. Always reports final env-file key count to stdout
#
# This eliminates the entire class of "silent python failure" bugs from
# inline heredocs.
log_info "[2/6] 准备远端 helper 脚本..."

# Build the helper script. We use a heredoc with single-quote-style EOF to
# prevent bash expansion of $variables inside the Python source.
MERGE_SCRIPT="$(mktemp -t merge-XXXXXX.py)"
SECRETS_TMP_FILES+=("$MERGE_SCRIPT")
cat > "$MERGE_SCRIPT" <<'PYTHON_EOF'
#!/usr/bin/env python3
"""
merge_env.py — atomic upsert of KEY=VAL pairs into an existing env-file.

Contract:
  - argv[1] = target env-file path
  - argv[2] = source KEY=VAL body file path (newline-separated KEY=value)
  - argv[3] = 'force' or 'merge'
  - On success: prints 4 lines: added=... replaced=... skipped=... total=...
  - On failure: prints ERROR=... to stderr and exits non-zero.
  - Atomic write: writes to <target>.tmp, then os.replace(tmp, target).
  - Always reads target file from disk, never from in-memory cache.
"""
import os
import sys

def err(msg):
    print(f"ERROR={msg}", file=sys.stderr)
    sys.exit(2)

if len(sys.argv) != 4:
    err(f"usage: merge_env.py TARGET BODY MODE  (got {len(sys.argv)-1} args)")

target = sys.argv[1]
body_path = sys.argv[2]
mode = sys.argv[3]  # 'force' or 'merge'
force = (mode == 'force')

if not os.path.isfile(body_path):
    err(f"body file not found: {body_path}")

# Read existing env-file. Must exist — caller pre-created if needed.
if not os.path.isfile(target):
    err(f"target env-file not found: {target}")

try:
    with open(target, 'r', encoding='utf-8') as f:
        existing = f.readlines()
except Exception as e:
    err(f"read target failed: {e}")

# Build a map KEY -> existing line index (preserving comments + blank lines).
existing_map = {}
for i, line in enumerate(existing):
    s = line.rstrip('\n')
    if s.startswith('#') or not s.strip():
        continue
    if '=' in s and not s.lstrip().startswith('#'):
        k = s.split('=', 1)[0].strip()
        existing_map[k] = i

# Parse the body into KEY=VAL pairs.
try:
    with open(body_path, 'r', encoding='utf-8') as f:
        new_body = f.read()
except Exception as e:
    err(f"read body failed: {e}")

new_pairs = {}
for line in new_body.splitlines():
    if not line or '=' not in line:
        continue
    k, v = line.split('=', 1)
    new_pairs[k.strip()] = v

added, replaced, skipped = [], [], []
for k, v in new_pairs.items():
    if k in existing_map:
        existing_val = existing[existing_map[k]].split('=', 1)[1].rstrip('\n')
        if existing_val == v:
            skipped.append(k)
            continue
        if not force:
            skipped.append(k)
            continue
        existing[existing_map[k]] = f'{k}={v}\n'
        replaced.append(k)
    else:
        existing.append(f'{k}={v}\n')
        existing_map[k] = len(existing) - 1
        added.append(k)

text = ''.join(existing)
if not text.endswith('\n'):
    text += '\n'

# Atomic write.
tmp = target + '.tmp'
try:
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write(text)
    os.chmod(tmp, 0o600)
    os.replace(tmp, target)
except Exception as e:
    err(f"atomic write failed: {e}")

print(f"added={' '.join(added) if added else '(none)'}")
print(f"replaced={' '.join(replaced) if replaced else '(none)'}")
print(f"skipped={' '.join(skipped) if skipped else '(none)'}")
print(f"total={len(existing_map)}")
PYTHON_EOF
chmod 700 "$MERGE_SCRIPT"
log_info "  ✓ 合并脚本就绪 (mode=700)"

# scp the helper + the body to the remote /tmp. Use deterministic remote
# paths so a partial failure is detectable and we don't litter /tmp.
REMOTE_HELPER="/tmp/deploy-71-secrets-merge.py"
REMOTE_VERIFIER="/tmp/deploy-71-secrets-verify.py"
REMOTE_BODY="/tmp/deploy-71-secrets-body.env"

# First, scrub any stale files from previous failed runs (best-effort).
"${SSH[@]}" "rm -f '$REMOTE_HELPER' '$REMOTE_VERIFIER' '$REMOTE_BODY' '$REMOTE_HELPER.lock' 2>/dev/null; true"

# scp helper script. Stderr captured; we want clean output.
"${SCP[@]}" "$MERGE_SCRIPT" "${SSH_TARGET}:${REMOTE_HELPER}" >/dev/null 2>&1 \
    || die "scp helper 脚本到 71 失败: $REMOTE_HELPER"
log_info "  ✓ merge helper 已传输: $SSH_TARGET:$REMOTE_HELPER"

# scp the verifier (DB-hash guard) script.
"${SCP[@]}" "$SKILL_DIR/scripts/verify_secret_key.py" "${SSH_TARGET}:${REMOTE_VERIFIER}" >/dev/null 2>&1 \
    || die "scp verifier 脚本到 71 失败: $REMOTE_VERIFIER"
log_info "  ✓ db-hash verifier 已传输: $SSH_TARGET:$REMOTE_VERIFIER"

# scp the body (KEY=VAL payload).
"${SCP[@]}" "$SOURCE_BODY" "${SSH_TARGET}:${REMOTE_BODY}" >/dev/null 2>&1 \
    || die "scp body 到 71 失败: $REMOTE_BODY"
log_info "  ✓ body 已传输: $SSH_TARGET:$REMOTE_BODY (mode=600)"

# Remote chmod 600 the body so it doesn't leak via /tmp.
"${SSH[@]}" "chmod 600 '$REMOTE_BODY'" >/dev/null 2>&1 \
    || die "chmod 600 on remote body 失败"
echo

# ── 2.5. DB-hash guard (NEW 2026-07-05): verify SECRET_KEY alignment ────
# This guard PREVENTS the exact "Invalid or expired API key" bug that hit 71
# on 2026-07-05. Root cause was a stale /root/.llm-gateway/secrets.env with
# an LLM_GATEWAY_SECRET_KEY that didn't match the value originally used to
# hash api_keys.key_hash in PostgreSQL. The fix: compute HMAC-SHA256 of the
# admin api_key with both the CURRENT and NEW SECRET_KEY, and refuse the
# merge if either doesn't match the DB row.
log_info "[2.5/6] DB-hash guard: 校验 LLM_GATEWAY_SECRET_KEY 与 DB 对齐..."
if [[ $DRY_RUN -eq 1 ]]; then
    log_warn "DRY: 跳过 DB-hash guard"
else
    # Read CURRENT values from the remote env-file (read-only — we haven't
    # written anything yet). Read NEW values from the staged body file.
    GUARD_PREP=$("${SSH[@]}" "
        echo '__CURRENT_SECRET__'
        awk -F= '/^LLM_GATEWAY_SECRET_KEY=/{print \$2; exit}' '$TARGET_FILE'
        echo '__CURRENT_ADMIN__'
        awk -F= '/^LLM_GATEWAY_ADMIN_API_KEY=/{print \$2; exit}' '$TARGET_FILE'
    " 2>&1) || die "读取远端 CURRENT 值失败"

    CURRENT_SECRET=$(echo "$GUARD_PREP" | sed -n '/^__CURRENT_SECRET__$/!{p;}' | sed -n '/__CURRENT_ADMIN__/q;p' | head -1)
    CURRENT_ADMIN=$(echo "$GUARD_PREP" | awk '/^__CURRENT_ADMIN__$/{flag=1; next} flag')

    NEW_SECRET=$(grep -E '^LLM_GATEWAY_SECRET_KEY=' "$SOURCE_BODY" | head -1 | cut -d= -f2-)
    if [[ -z "$NEW_SECRET" ]]; then
        log_warn "BODY 中无 LLM_GATEWAY_SECRET_KEY，跳过 DB-hash guard"
    elif [[ -z "$CURRENT_SECRET" ]]; then
        log_warn "env-file 缺 LLM_GATEWAY_SECRET_KEY，跳过 DB-hash guard"
    elif [[ -z "$CURRENT_ADMIN" ]]; then
        log_warn "env-file 缺 LLM_GATEWAY_ADMIN_API_KEY，跳过 DB-hash guard"
    else
        DBURL=$("${SSH[@]}" "awk -F= '/^LLM_GATEWAY_DATABASE_URL=/{print \$2; exit}' '$TARGET_FILE'" 2>&1) \
            || die "读取 DATABASE_URL 失败"
        # Run the verifier on the REMOTE (DB lives on remote).
        GUARD_OUT=$("${SSH[@]}" "DATABASE_URL='$DBURL' python3 '$REMOTE_VERIFIER' '$CURRENT_SECRET' '$NEW_SECRET' '$CURRENT_ADMIN'" 2>&1) \
            || { log_error "DB-hash guard 失败 (refusing to overwrite):"; echo "$GUARD_OUT" | sed 's/^/  /'; exit 2; }
        log_info "  ✓ $GUARD_OUT"
    fi
fi
echo

# ── 3. Backup the target env-file on the remote ──────────────────────────
log_info "[3/6] 备份远端 env-file..."
if [[ $DRY_RUN -eq 1 ]]; then
    log_warn "DRY: 跳过备份"
else
    BACKUP_OUT=$("${SSH[@]}" "cp '$TARGET_FILE' '$TARGET_FILE.bak.$BACKUP_SUFFIX' && chmod 600 '$TARGET_FILE.bak.$BACKUP_SUFFIX' && echo '$TARGET_FILE.bak.$BACKUP_SUFFIX'" 2>&1) \
        || die "备份 env-file 失败: $BACKUP_OUT"
    log_info "  ✓ 备份完成: $BACKUP_OUT"
fi
echo

# ── 4. Run the merge ──────────────────────────────────────────────────────
log_info "[4/6] 合并密钥到 env-file..."
# Ensure the target env-file exists on the remote. If missing, we create
# an empty one with proper mode — the Python script requires the file to
# exist already.
"${SSH[@]}" "test -f '$TARGET_FILE' || { mkdir -p \$(dirname '$TARGET_FILE') && : > '$TARGET_FILE' && chmod 600 '$TARGET_FILE'; }" >/dev/null 2>&1 \
    || die "无法创建目标 env-file: $TARGET_FILE"

# Build mode arg.
[[ $FORCE == 1 ]] && MODE_ARG="force" || MODE_ARG="merge"

# Run the merge. Capture both stdout and stderr so any ERROR= line surfaces.
# Use --no-restart / --dry-run to short-circuit the write.
if [[ $DRY_RUN -eq 1 ]]; then
    # Dry-run: don't actually write. Just show what WOULD change.
    # We do this by copying env-file to a tmp location, running merge there,
    # then diff'ing.
    log_warn "DRY: 在 $REMOTE_BODY.diff 里看 diff"
    DRY_TARGET="/tmp/deploy-71-secrets-dryrun.env"
    "${SSH[@]}" "cp '$TARGET_FILE' '$DRY_TARGET' && chmod 600 '$DRY_TARGET'" >/dev/null 2>&1 \
        || die "DRY: 复制目标失败"
    DRY_OUT=$("${SSH[@]}" "python3 '$REMOTE_HELPER' '$DRY_TARGET' '$REMOTE_BODY' '$MODE_ARG'" 2>&1) \
        || { log_error "DRY: 合并预演失败: $DRY_OUT"; exit 2; }
    echo "$DRY_OUT" | sed 's/^/  /'
    log_warn "DRY: 删除临时演练文件"
    "${SSH[@]}" "rm -f '$DRY_TARGET'" >/dev/null 2>&1 || true
else
    MERGE_OUT=$("${SSH[@]}" "python3 '$REMOTE_HELPER' '$TARGET_FILE' '$REMOTE_BODY' '$MODE_ARG'" 2>&1) \
        || { log_error "远端合并失败:"; echo "$MERGE_OUT" | sed 's/^/  /'; exit 2; }
    echo "$MERGE_OUT" | sed 's/^/  /'
fi
echo

# ── 5. Restart the service (unless --no-restart) ──────────────────────────
if [[ $NO_RESTART -eq 1 || $DRY_RUN -eq 1 ]]; then
    log_info "[5/6] 跳过重启 ($([ $NO_RESTART == 1 ] && echo --no-restart || echo --dry-run))"
else
    log_info "[5/6] 重启 systemd 服务..."
    # Use a single remote invocation that does stop, restart, wait, is-active.
    # If systemctl restart fails (exit non-zero), we catch it here.
    RESTART_OUT=$("${SSH[@]}" "systemctl restart '$SERVICE_NAME' 2>&1; rc=\$?; sleep 6; systemctl is-active '$SERVICE_NAME' || true; exit \$rc" 2>&1) \
        || { log_error "systemctl restart 失败: $RESTART_OUT"; exit 2; }
    log_info "  ✓ 服务已重启: $RESTART_OUT"
fi
echo

# ── 6. Verify ─────────────────────────────────────────────────────────────
log_info "[6/6] 校验 env-file 健康..."

# Verify required keys are present + non-empty.
VERIFY_OUT=$("${SSH[@]}" "
    echo '--- env-file 包含的 KEY 名称（值不展示） ---'
    grep -oE '^[A-Z][A-Z0-9_]*=' '$TARGET_FILE' | sed 's/=//' | sort -u
    echo
    echo '--- 必需密钥检查 ---'
    missing=0
    for k in LLM_GATEWAY_SECRET_KEY LLM_GATEWAY_CREDENTIAL_ENCRYPTION_KEY; do
        if grep -q \"^\$k=\" '$TARGET_FILE' && [[ -n \"\$(grep \"^\$k=\" '$TARGET_FILE' | head -1 | cut -d= -f2-)\" ]]; then
            echo \"OK  \$k\"
        else
            echo \"MISSING \$k\"
            missing=\$((missing + 1))
        fi
    done
    if [[ \$missing -gt 0 ]]; then exit 1; fi
" 2>&1) || {
    log_warn "缺必需密钥。请将 $ORIG_SOURCE_FILE 至少包含:"
    echo "    LLM_GATEWAY_SECRET_KEY=<your-secret>"
    echo "    LLM_GATEWAY_CREDENTIAL_ENCRYPTION_KEY=<your-base64-key>"
    exit 3
}
echo "$VERIFY_OUT" | sed 's/^/  /'

# Healthcheck (only if we actually restarted).
if [[ $NO_RESTART -eq 0 && $DRY_RUN -eq 0 ]]; then
    log_info "Gateway 健康检查:"
    HEALTHZ=$("${SSH[@]}" "curl -fsS --max-time 5 http://localhost:8781/healthz 2>&1" 2>&1) \
        || log_warn "healthz 暂时不通（服务可能在启动中），等 5-10 秒再手动验证"
    if [[ -n "$HEALTHZ" ]]; then
        log_info "  ✓ healthz: $(echo "$HEALTHZ" | head -c 80)..."
    fi
fi

# Cleanup remote temp files (best-effort). We don't fail on errors here
# because the merge is already done — leftover /tmp files are a soft leak.
"${SSH[@]}" "rm -f '$REMOTE_HELPER' '$REMOTE_VERIFIER' '$REMOTE_BODY' 2>/dev/null; true" >/dev/null 2>&1 || true

log_info "✅ 密钥加载完成"
echo
echo "下一步:"
echo "  1. 浏览器访问 https://llm.kxpms.cn 验证登录"
echo "  2. 若仍有 'Invalid or expired API key'："
echo "     - 比对 71 上 $TARGET_FILE 与 DB 中 provider_credentials.encrypted_key 的加密密钥"
echo "     - 密钥不一致时 DB 里的密文无法解密，gateway 会返回 Invalid"