#!/bin/bash
# bump-version.sh - auto-sync build_seq across all version files.
#
# Solves the long-standing pain point where operators had to manually
# edit five or six files (VERSION, version.json in two locations,
# web/public/version.json, web/dist/version.json, the gateway binary's
# ldflags, and the systemd unit) just to bump the build counter.
#
# Usage:
#   ./scripts/bump-version.sh                        # bump by 1 (default)
#   ./scripts/bump-version.sh --seq 722              # explicit target build_seq
#   ./scripts/bump-version.sh --dry-run              # show what would change
#   ./scripts/bump-version.sh --no-build             # skip rebuilding the binary
#   ./scripts/bump-version.sh --no-frontend          # skip rebuilding web SPA
#   ./scripts/bump-version.sh --no-upload            # skip upload+restart
#   ./scripts/bump-version.sh --ssh root@14.103.174.71
#
# What it does:
#   1. Read current build_seq from version.json (single source of truth).
#   2. Compute new build_seq = current + 1 (or override with --seq).
#   3. Compute new version string: <patch>-<git_sha>-<YYYYMMDD>-<build_seq>.
#   4. Update four files in lockstep: VERSION, version.json,
#      web/public/version.json, web/dist/version.json.
#   5. Rebuild Go binary with ldflags (Version / BuildNumber / GitCommit /
#      BuildTime) and cross-compile to linux/amd64.
#   6. Optionally rebuild Vue SPA so web/dist/version.json picks up the
#      new seq.
#   7. Optionally upload to a target server and restart systemd.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

VERSION_FILE="VERSION"
VERSION_JSON="version.json"
WEB_PUBLIC_VERSION_JSON="web/public/version.json"
WEB_DIST_VERSION_JSON="web/dist/version.json"

TARGET_SEQ=""
INCREMENT=1
DRY_RUN=false
SKIP_BUILD=false
SKIP_UPLOAD=false
SKIP_FRONTEND=false
SSH_TARGET=""
SSH_PORT="${SSH_PORT:-25022}"
REMOTE_DIR="/opt/llm-gateway-go"
SERVICE_NAME="llm-gateway-go.service"
BIN_NAME="llm-gateway-go.v321.linux.amd64"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

usage() {
  sed -n '2,42p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --seq)         TARGET_SEQ="$2"; shift 2 ;;
    --bump)        INCREMENT="${2:-1}"; shift 2 ;;
    --dry-run)     DRY_RUN=true; shift ;;
    --no-build)    SKIP_BUILD=true; shift ;;
    --no-upload)   SKIP_UPLOAD=true; shift ;;
    --no-frontend) SKIP_FRONTEND=true; shift ;;
    --ssh)         SSH_TARGET="$2"; shift 2 ;;
    --port)        SSH_PORT="$2"; shift 2 ;;
    --remote-dir)  REMOTE_DIR="$2"; shift 2 ;;
    --service)     SERVICE_NAME="$2"; shift 2 ;;
    --bin)         BIN_NAME="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *)             log_error "unknown arg: $1"; usage ;;
  esac
done

# Step 1: read current state from version.json (single source of truth).
if [[ ! -f "$VERSION_JSON" ]]; then
  log_error "$VERSION_JSON not found in repo root"
  exit 1
fi

CURRENT_SEQ=$(python3 -c "import json; print(json.load(open('$VERSION_JSON'))['build_seq'])")
CURRENT_GIT_SHA=$(python3 -c "import json; print(json.load(open('$VERSION_JSON')).get('git_sha','unknown'))")
CURRENT_VERSION=$(python3 -c "import json; print(json.load(open('$VERSION_JSON'))['version'])")
CURRENT_PATCH=$(echo "$CURRENT_VERSION" | cut -d- -f1)

if [[ -n "$TARGET_SEQ" ]]; then
  NEW_SEQ="$TARGET_SEQ"
else
  NEW_SEQ=$((CURRENT_SEQ + INCREMENT))
fi

HEAD_SHA="$(git rev-parse --short=8 HEAD 2>/dev/null || echo "$CURRENT_GIT_SHA")"
HEAD_DATE="$(date -u +%Y%m%d)"
NEW_VERSION="${CURRENT_PATCH}-${HEAD_SHA}-${HEAD_DATE}-${NEW_SEQ}"

log_info "Current:  seq=${CURRENT_SEQ}  version=${CURRENT_VERSION}"
log_info "Target:   seq=${NEW_SEQ}  version=${NEW_VERSION}"
log_info "Git:      ${HEAD_SHA}"

if [[ "$DRY_RUN" == "true" ]]; then
  log_info "[dry-run] would update:"
  for f in "$VERSION_FILE" "$VERSION_JSON" "$WEB_PUBLIC_VERSION_JSON" "$WEB_DIST_VERSION_JSON"; do
    log_info "  - $f"
  done
  exit 0
fi

# Step 2: rewrite all four files in lockstep.
NOW_DATE="$(date -u +%Y-%m-%d)"

update_json() {
  python3 - "$1" "$NEW_VERSION" "$NEW_SEQ" "$HEAD_SHA" "$NOW_DATE" <<'PY'
import json, sys
path, version, seq, sha, build_date = sys.argv[1:]
with open(path, 'r+') as f:
    data = json.load(f)
    data['version']    = version
    data['git_tag']    = version
    data['git_sha']    = sha
    data['build_seq']  = int(seq)
    data['build_date'] = build_date
    f.seek(0); f.truncate()
    json.dump(data, f, indent=2)
    f.write('\n')
PY
}

log_info "Updating $VERSION_FILE"
printf "%s\n" "$NEW_VERSION" > "$VERSION_FILE"

# .deploy_seq is read by /api/system/version (admin/misc.go loadDeploySeq)
# as a fallback when the VERSION string cannot be parsed for the seq
# segment. Keeping it in lockstep with version.json's build_seq is what
# makes the front-end top-bar "v3.3.3 · #721" actually show 721.
DEPLOY_SEQ_FILE=".deploy_seq"
if [[ -f "$DEPLOY_SEQ_FILE" ]]; then
  log_info "Updating $DEPLOY_SEQ_FILE"
  printf "%s\n" "$NEW_SEQ" > "$DEPLOY_SEQ_FILE"
fi

log_info "Updating $VERSION_JSON"
update_json "$VERSION_JSON"

log_info "Updating $WEB_PUBLIC_VERSION_JSON"
update_json "$WEB_PUBLIC_VERSION_JSON"

if [[ -f "$WEB_DIST_VERSION_JSON" ]]; then
  log_info "Updating $WEB_DIST_VERSION_JSON"
  update_json "$WEB_DIST_VERSION_JSON"
else
  log_warn "$WEB_DIST_VERSION_JSON missing - will be created on next npm run build"
fi

# Step 3: rebuild Go binary with ldflags.
BUILD_PATH="${BUILD_PATH:-bin/llm-gateway}"

if [[ "$SKIP_BUILD" == "true" ]]; then
  log_warn "--no-build set, skipping Go binary rebuild"
else
  log_info "Rebuilding host-arch binary at $BUILD_PATH"
  HOST_GOOS="$(uname | tr '[:upper:]' '[:lower:]')"
  HOST_GOARCH="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
  BUILD_TIME="$(date -u +'%Y-%m-%d %H:%M:%S')"

  GOOS="$HOST_GOOS" GOARCH="$HOST_GOARCH" CGO_ENABLED=0 \
    go build \
      -ldflags "-X 'main.Version=${NEW_VERSION}' -X 'main.BuildNumber=${NEW_SEQ}' -X 'main.GitCommit=${HEAD_SHA}' -X 'main.BuildTime=${BUILD_TIME}'" \
      -o "$BUILD_PATH" \
      ./cmd/gateway

  # Always cross-compile linux/amd64 for the deploy target. Production
  # server is always linux/amd64; building on macOS without this step
  # would upload a Mach-O binary that docker exec fails with
  # "exec format error".
  LINUX_PATH="${LINUX_PATH:-bin/llm-gateway-linux-amd64}"
  log_info "Cross-compiling linux/amd64 binary at $LINUX_PATH"
  GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
    go build \
      -ldflags "-X 'main.Version=${NEW_VERSION}' -X 'main.BuildNumber=${NEW_SEQ}' -X 'main.GitCommit=${HEAD_SHA}' -X 'main.BuildTime=${BUILD_TIME}'" \
      -o "$LINUX_PATH" \
      ./cmd/gateway
fi

# Step 4: rebuild Vue SPA so web/dist/version.json picks up the new seq.
if [[ "$SKIP_FRONTEND" == "false" ]] && [[ -d "web" ]] && [[ -f "web/package.json" ]]; then
  log_info "Rebuilding Vue SPA (cd web && npm run build)"
  (cd web && npm run build 2>&1 | tail -10) || log_warn "frontend build failed; web/dist/version.json will not be updated"
  if [[ -f "$WEB_DIST_VERSION_JSON" ]]; then
    update_json "$WEB_DIST_VERSION_JSON"
    log_info "Re-mirrored $WEB_DIST_VERSION_JSON after npm run build"
  fi
fi

# Step 5: upload + restart.
if [[ -n "$SSH_TARGET" ]] && [[ "$SKIP_UPLOAD" == "false" ]]; then
  USER_HOST="$SSH_TARGET"
  REMOTE_BINARY="$REMOTE_DIR/$BIN_NAME"
  LOCAL_LINUX_BIN="${LINUX_PATH:-bin/llm-gateway-linux-amd64}"

  if [[ ! -f "$LOCAL_LINUX_BIN" ]]; then
    log_error "local linux binary $LOCAL_LINUX_BIN missing - re-run without --no-build"
    exit 1
  fi

  SCP_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P "$SSH_PORT")
  SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$SSH_PORT")
  if [[ -n "${SSHPASS:-}" ]]; then
    SCP="sshpass -e scp ${SCP_OPTS[*]}"
    SSH="sshpass -e ssh ${SSH_OPTS[*]}"
  else
    SCP="scp ${SCP_OPTS[*]}"
    SSH="ssh ${SSH_OPTS[*]}"
  fi

  # Stop the running systemd unit BEFORE overwriting the binary, because
  # the binary on disk is mmap'd by the gateway process. Trying to scp
  # over a running binary fails with "dest open ... Failure" because the
  # host kernel keeps a write lock on the executable pages.
  log_info "Stopping $SERVICE_NAME on $USER_HOST (so binary is no longer mmap'd)"
  $SSH "$USER_HOST" "systemctl stop $SERVICE_NAME; sleep 3; ls -lh $REMOTE_BINARY"

  log_info "Uploading $LOCAL_LINUX_BIN -> $USER_HOST:$REMOTE_BINARY"
  $SCP "$LOCAL_LINUX_BIN" "${USER_HOST}:${REMOTE_BINARY}"

  log_info "Uploading $VERSION_FILE -> $USER_HOST:$REMOTE_DIR/$VERSION_FILE"
  $SCP "$VERSION_FILE" "${USER_HOST}:${REMOTE_DIR}/${VERSION_FILE}"

  # .deploy_seq is read by /api/system/version as the authoritative build
  # counter (admin/misc.go loadDeploySeq), so the front-end top bar shows
  # the new seq immediately on next page reload.
  if [[ -f "$DEPLOY_SEQ_FILE" ]]; then
    log_info "Uploading $DEPLOY_SEQ_FILE -> $USER_HOST:$REMOTE_DIR/$DEPLOY_SEQ_FILE"
    $SCP "$DEPLOY_SEQ_FILE" "${USER_HOST}:${REMOTE_DIR}/${DEPLOY_SEQ_FILE}"
  fi

  # Mirror the new build_seq into web/dist so the next SPA reload
  # immediately shows the new seq.
  log_info "Uploading $WEB_DIST_VERSION_JSON -> $USER_HOST:$REMOTE_DIR/web/dist/version.json"
  $SCP "$WEB_DIST_VERSION_JSON" "${USER_HOST}:${REMOTE_DIR}/web/dist/version.json"

  log_info "Restarting $SERVICE_NAME on $USER_HOST"
  $SSH "$USER_HOST" bash -s <<REMOTE
set -e
chmod +x "$REMOTE_BINARY"
chown root:root "$REMOTE_BINARY"
systemctl start "$SERVICE_NAME"
sleep 8
systemctl is-active "$SERVICE_NAME"
ss -tlnp 2>/dev/null | grep ':8781' | head -2 || true
echo
echo '--- gateway starting log ---'
docker logs --since 30s "$SERVICE_NAME" 2>&1 | grep -E 'gateway starting' | tail -3 || true
REMOTE
fi

log_info "bump-version done: VERSION=${NEW_VERSION} build_seq=${NEW_SEQ}"
echo
echo "Next steps:"
echo "  git add $VERSION_FILE $VERSION_JSON $WEB_PUBLIC_VERSION_JSON $WEB_DIST_VERSION_JSON"
echo "  git commit -m 'chore: bump version to ${NEW_VERSION}'"
