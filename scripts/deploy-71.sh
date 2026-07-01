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
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SSH_TARGET="${SSH_TARGET:-root@14.103.174.71}"
SSH_PORT="${SSH_PORT:-25022}"
REMOTE_DIR="${REMOTE_DIR:-/opt/llm-gateway-go}"
SERVICE_NAME="${SERVICE_NAME:-llm-gateway-go.service}"
BIN_NAME="${BIN_NAME:-llm-gateway-go.v321.linux.amd64}"

SEQ="${SEQ:-}"
SKIP_FRONTEND="${SKIP_FRONTEND:-true}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }

log_info "Deploying to $SSH_TARGET"
log_info "  remote dir:  $REMOTE_DIR"
log_info "  service:     $SERVICE_NAME"
log_info "  binary name: $BIN_NAME"
echo

extra_flags=()
if [[ -n "$SEQ" ]]; then
  extra_flags+=(--seq "$SEQ")
fi
if [[ "$SKIP_FRONTEND" == "true" ]]; then
  extra_flags+=(--no-frontend)
fi

exec ./scripts/bump-version.sh \
  --ssh "$SSH_TARGET" \
  --port "$SSH_PORT" \
  --remote-dir "$REMOTE_DIR" \
  --service "$SERVICE_NAME" \
  --bin "$BIN_NAME" \
  "${extra_flags[@]}" \
  "$@"
