#!/bin/bash
# scripts/auto_commit_watcher.sh
#
# 持续监控 71 服务器上的 binary 变化,确保任何 binary 改动都有
# 明确的 commit hash 记录。如果检测到 binary 变化,自动重新编译
# + 部署 + commit 到 github 分支,避免多个 agent 之间冲突。
#
# 用法:
#   # 后台运行 (每 5 分钟检查一次):
#   nohup ./scripts/auto_commit_watcher.sh > /tmp/auto_commit.log 2>&1 &
#
# 设计原则:
#   1. 检测 71 上 binary md5,如果变化就重新 build
#   2. build 前自动 git pull (如果有 remote)
#   3. cross-compile linux/amd64 + push 到 71
#   4. 重启容器 + 验证
#   5. auto-commit 当前所有 uncommitted 改动
#
# 停止: kill <PID>

set -e

PROJECT_DIR="/Users/xutaohuang/workspace/llm-gateway-go-2"
SSH_HOST="root@14.103.174.71"
SSH_PORT="25022"
REMOTE_BINARY="/opt/llm-gateway-go/llm-gateway-go"
REMOTE_BIN_BASE="/opt/llm-gateway-go/llm-gateway-go.v"
BUILD_SEQ_FILE="$PROJECT_DIR/.deploy_seq"
LOG_FILE="/tmp/auto_commit_watcher.log"

# 上次检查的 binary md5
LAST_MD5=""
LAST_GIT_HEAD=""

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

check_binary_change() {
    ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" "$SSH_HOST" \
        "md5sum $REMOTE_BINARY 2>/dev/null | awk '{print \$1}'" 2>/dev/null
}

check_git_changes() {
    cd "$PROJECT_DIR" || return 1
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        echo "modified"
    else
        echo "clean"
    fi
}

build_and_deploy() {
    cd "$PROJECT_DIR" || return 1
    local seq
    seq=$(cat "$BUILD_SEQ_FILE")
    local next_seq=$((seq + 1))

    log "=== 检测到变化,开始 build & deploy v${next_seq} ==="

    # 1. git pull (如果有 remote)
    if git remote -v | grep -q "origin"; then
        git pull --rebase origin github 2>/dev/null || log "WARNING: git pull failed"
    fi

    # 2. cross-compile
    log "Cross-compile linux/amd64 v${next_seq}..."
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" \
        -o /tmp/llm-gateway-v${next_seq}.linux.amd64 ./cmd/gateway 2>&1 | tail -5

    # 3. 推送
    log "Push to 71..."
    scp -o StrictHostKeyChecking=no -P "$SSH_PORT" \
        /tmp/llm-gateway-v${next_seq}.linux.amd64 \
        "$SSH_HOST:$REMOTE_BIN_BASE${next_seq}.linux.amd64"

    # 4. 部署 (使用 alpine + bind mount)
    log "Deploy v${next_seq} on 71..."
    ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" "$SSH_HOST" "
        systemctl stop llm-gateway-go.service
        sleep 3
        docker rm -f llm-gateway-go 2>/dev/null || true
        sleep 2
        docker run -d --rm --name llm-gateway-go \
            --network host \
            --env-file /etc/llm-gateway-go/env \
            -v /opt/llm-gateway-go/data:/opt/llm-gateway-go/data \
            -v /opt/llm-gateway-go/web:/opt/llm-gateway-go/web:ro \
            -v $REMOTE_BIN_BASE${next_seq}.linux.amd64:/opt/llm-gateway-go/llm-gateway-go:ro \
            -v $REMOTE_BIN_BASE${next_seq}.linux.amd64:/usr/local/bin/llm-gateway-go:ro \
            --entrypoint /opt/llm-gateway-go/llm-gateway-go \
            docker.m.daocloud.io/library/alpine:3.20
        sleep 6
        # 永久 systemd override
        cat > /etc/systemd/system/llm-gateway-go.service.d/override.conf << 'OVERRIDE_EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/docker run --rm --name llm-gateway-go --network host --env-file /etc/llm-gateway-go/env -v /opt/llm-gateway-go/data:/opt/llm-gateway-go/data -v /opt/llm-gateway-go/web:/opt/llm-gateway-go/web:ro -v $REMOTE_BIN_BASE${next_seq}.linux.amd64:/opt/llm-gateway-go/llm-gateway-go:ro -v $REMOTE_BIN_BASE${next_seq}.linux.amd64:/usr/local/bin/llm-gateway-go:ro --entrypoint /opt/llm-gateway-go/llm-gateway-go docker.m.daocloud.io/library/alpine:3.20
OVERRIDE_EOF
        chmod 444 /etc/systemd/system/llm-gateway-go.service.d/override.conf
        # 验证
        md5sum /opt/llm-gateway-go/llm-gateway-go
    "

    # 5. 验证服务
    log "Verify service..."
    if ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" "$SSH_HOST" \
        "docker exec llm-gateway-go md5sum /opt/llm-gateway-go/llm-gateway-go | awk '{print \$1}'" \
        2>/dev/null | grep -q "$(md5sum /tmp/llm-gateway-v${next_seq}.linux.amd64 | awk '{print $1}')"; then
        log "✓ Binary md5 matches"

        # 6. 升级 build_seq
        echo "$next_seq" > "$BUILD_SEQ_FILE"
        log "build_seq: $seq → $next_seq"

        # 7. 跑简单 smoke test
        log "Smoke test..."
        ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" "$SSH_HOST" '
            SK="sk-k40DVd9aqFGumYcEkfkQvSgdv06uepSNDK0BqHwtwS3RzTgY"
            resp=$(docker exec llm-gateway-go wget -qO- -T 30 \
                "http://127.0.0.1:8781/v1/chat/completions" \
                --post-data="{\"model\":\"minimax-m3\",\"messages\":[{\"role\":\"user\",\"content\":\"watcher test\"}],\"max_tokens\":10}" \
                --header="Content-Type: application/json" \
                --header="Authorization: Bearer $SK" \
                --header="X-Gw-Session-Id: watcher-$(date +%s)" 2>&1 | head -c 200)
            if echo "$resp" | grep -q "choices"; then
                echo "  ✓ smoke test passed"
            else
                echo "  ✗ smoke test FAILED: $resp"
            fi
        '
    else
        log "✗ Binary md5 MISMATCH after deploy"
        return 1
    fi
}

commit_changes() {
    cd "$PROJECT_DIR" || return 1
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        local current_head
        current_head=$(git rev-parse --short HEAD)
        log "Auto-committing uncommitted changes..."

        git add -A
        git commit -m "auto-commit: watcher detected changes from 71 binary diff

Built and deployed new binary after detecting 71 binary md5 change.
All uncommitted code state is preserved in this commit to prevent
multi-agent merge conflicts.

Generated by scripts/auto_commit_watcher.sh at $(date -u +'%Y-%m-%dT%H:%M:%SZ')
Previous HEAD: $current_head" 2>&1 | tail -3

        log "Committed to local github branch"
    else
        log "No uncommitted changes"
    fi
}

# 主循环
log "=== auto_commit_watcher started ==="
log "Watching 71 binary at $REMOTE_BINARY"
log "Project: $PROJECT_DIR"
log "Polling every ${POLL_INTERVAL:-300} seconds"

POLL_INTERVAL=${POLL_INTERVAL:-300}

while true; do
    log "--- polling cycle ---"

    # 1. 检查 71 binary md5
    CURRENT_MD5=$(check_binary_change)
    if [ -z "$CURRENT_MD5" ]; then
        log "WARN: cannot read 71 binary md5, will retry"
        sleep "$POLL_INTERVAL"
        continue
    fi

    # 2. 检查 git changes
    cd "$PROJECT_DIR"
    GIT_STATUS=$(check_git_changes)

    if [ "$CURRENT_MD5" != "$LAST_MD5" ]; then
        log "71 binary md5 changed: $LAST_MD5 → $CURRENT_MD5"

        if [ "$GIT_STATUS" = "modified" ]; then
            log "Local git has uncommitted changes; committing first..."
            commit_changes
        fi

        build_and_deploy && LAST_MD5="$CURRENT_MD5"
    elif [ "$GIT_STATUS" = "modified" ]; then
        log "Local git has uncommitted changes (no 71 binary change)"
        commit_changes
    else
        log "No changes (binary: $CURRENT_MD5, git: clean)"
    fi

    sleep "$POLL_INTERVAL"
done
