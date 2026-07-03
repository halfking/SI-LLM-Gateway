#!/bin/bash
# deploy-71.sh - full deploy to 71 in one command.
#
# Replaces ad-hoc scripts/deploy_new_version.sh + deploy_to_71_final.sh
# + manual scp + restart gymnastics. Just run:
#
#   ./scripts/deploy-71.sh
#
# The bump-version.sh script handles file sync + cross-compile + upload
# + restart; deploy-71.sh wraps it with sane defaults so a deploy is one
# command. Override anything via env vars or flags; everything else is
# inherited from bump-version.sh.
#
# Pre-flight: checks that the remote env points to 71's OWN local PG
# (172.31.0.3), not 184's PG (172.31.0.4). The two servers run
# independent schemas and must not share data.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SSH_TARGET="${SSH_TARGET:-root@14.103.174.71}"
SSH_PORT="${SSH_PORT:-25022}"
REMOTE_DIR="${REMOTE_DIR:-/opt/llm-gateway-go}"
SERVICE_NAME="${SERVICE_NAME:-llm-gateway-go.service}"
BIN_NAME="${BIN_NAME:-llm-gateway-go.v321.linux.amd64}"

# Expected 71 hosts (any of these is acceptable)
EXPECTED_71_HOSTS="${EXPECTED_71_HOSTS:-172.31.0.3}"
# Banned hosts (would mean we are accidentally pointing at the wrong server)
BANNED_HOSTS="${BANNED_HOSTS:-172.31.0.4}"

SEQ="${SEQ:-}"
SKIP_FRONTEND="${SKIP_FRONTEND:-true}"
SKIP_DB_PRECHECK="${SKIP_DB_PRECHECK:-false}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_err()  { echo -e "${RED}[ERR]${NC}  $*" >&2; }

log_info "Deploying to $SSH_TARGET"
log_info "  remote dir:  $REMOTE_DIR"
log_info "  service:     $SERVICE_NAME"
log_info "  binary name: $BIN_NAME"
echo

# ── Pre-flight: DB host check ─────────────────────────────────────────
# 71 must use its OWN local PG (172.31.0.3). If env points to 184
# (172.31.0.4) or anywhere else, abort before doing damage.
if [[ "$SKIP_DB_PRECHECK" != "true" ]]; then
  log_info "[preflight] checking remote env's LLM_GATEWAY_DATABASE_URL host…"
  DB_URL=$(ssh -p "$SSH_PORT" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SSH_TARGET" \
    "grep '^LLM_GATEWAY_DATABASE_URL=' /etc/llm-gateway-go/env 2>/dev/null | head -1 | cut -d= -f2-")

  if [[ -z "$DB_URL" ]]; then
    log_err "[preflight] cannot read LLM_GATEWAY_DATABASE_URL from /etc/llm-gateway-go/env on $SSH_TARGET"
    log_err "[preflight] did you run scripts/deploy-71-data-bindmounts.sh yet?"
    exit 1
  fi
  log_info "[preflight] LLM_GATEWAY_DATABASE_URL = ${DB_URL}"

  HOST=$(echo "$DB_URL" | sed -n 's|^postgres://[^@]*@||p' | sed 's|:.*||')
  PORT=$(echo "$DB_URL" | sed -n 's|^postgres://[^@]*@[^:]*:||p' | sed 's|/.*||')

  # Check banned list first (most dangerous)
  for banned in $BANNED_HOSTS; do
    if [[ "$HOST" == "$banned" ]]; then
      log_err "[preflight] ABORT: env points to $HOST which is in the banned list!"
      log_err "[preflight] 71 and 184 have independent PG schemas — they must NOT share."
      log_err "[preflight] expected one of: $EXPECTED_71_HOSTS"
      log_err "[preflight] to bypass: SKIP_DB_PRECHECK=true ./scripts/deploy-71.sh"
      exit 2
    fi
  done

  # Check expected list
  ok=0
  for expected in $EXPECTED_71_HOSTS; do
    if [[ "$HOST" == "$expected" ]]; then ok=1; break; fi
  done
  if [[ "$ok" -eq 0 ]]; then
    log_warn "[preflight] DB host '$HOST' is not in expected list: $EXPECTED_71_HOSTS"
    log_warn "[preflight] continuing — set EXPECTED_71_HOSTS to whitelist or BANNED_HOSTS to block"
  fi

  # TCP reachability check (best effort)
  log_info "[preflight] TCP probe ${HOST}:${PORT} via ${SSH_TARGET}…"
  if ssh -p "$SSH_PORT" \
       -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
       "$SSH_TARGET" \
       "(echo > /dev/tcp/$HOST/$PORT) 2>/dev/null && echo OK || echo FAIL" \
       | grep -q OK; then
    log_info "[preflight] TCP OK"
  else
    log_err "[preflight] ABORT: cannot TCP-reach $HOST:$PORT from $SSH_TARGET"
    log_err "[preflight] fix LLM_GATEWAY_DATABASE_URL or check network/firewall first"
    exit 3
  fi
fi

extra_flags=()
if [[ -n "${SEQ:-}" ]]; then
  extra_flags+=(--seq "$SEQ")
fi
if [[ "${SKIP_FRONTEND:-true}" == "true" ]]; then
  extra_flags+=(--no-frontend)
fi

# exec with optional extra_flags (avoid set -u unbound on empty array)
if [[ ${#extra_flags[@]} -gt 0 ]]; then
  exec ./scripts/bump-version.sh \
    --ssh "$SSH_TARGET" \
    --port "$SSH_PORT" \
    --remote-dir "$REMOTE_DIR" \
    --service "$SERVICE_NAME" \
    --bin "$BIN_NAME" \
    "${extra_flags[@]}" \
    "$@"
else
  exec ./scripts/bump-version.sh \
    --ssh "$SSH_TARGET" \
    --port "$SSH_PORT" \
    --remote-dir "$REMOTE_DIR" \
    --service "$SERVICE_NAME" \
    --bin "$BIN_NAME" \
    "$@"
fi
