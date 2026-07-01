#!/bin/bash
# 部署 v3.2.1: circuit key 隔离到 model 级别
# 2026-07-01
# 修复: 同一个 credential 的多个 model 变体共享 circuit 导致 false-positive circuit_open

set -e

REMOTE_HOST="root@14.103.174.71"
REMOTE_PORT="25022"
COMMIT_HASH=$(git rev-parse --short HEAD)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
VERSION="v3.2.1"
REMOTE_DIR="/opt/llm-gateway-go"
SERVICE_NAME="llm-gateway-go"

echo "=========================================="
echo "部署 $VERSION - Circuit Key Model Isolation"
echo "Commit: $COMMIT_HASH"
echo "Time: $TIMESTAMP"
echo "=========================================="

# 1. 本地编译
echo
echo "[1/6] 本地编译..."
GOOS=linux GOARCH=amd64 go build -o llm-gateway-$COMMIT_HASH ./cmd/gateway
ls -lh llm-gateway-$COMMIT_HASH

# 2. 上传二进制
echo
echo "[2/6] 上传二进制到服务器..."
scp -P $REMOTE_PORT llm-gateway-$COMMIT_HASH $REMOTE_HOST:$REMOTE_DIR/

# 3. 备份当前版本
echo
echo "[3/6] 备份当前运行版本..."
ssh -p $REMOTE_PORT $REMOTE_HOST "
  cd $REMOTE_DIR
  CURRENT_BINARY=\$(ls -t llm-gateway-go.v*.linux.amd64 2>/dev/null | head -1)
  if [ -n \"\$CURRENT_BINARY\" ]; then
    cp \$CURRENT_BINARY \${CURRENT_BINARY}.backup.$TIMESTAMP
    echo \"Backup created: \${CURRENT_BINARY}.backup.$TIMESTAMP\"
  fi
"

# 4. 替换二进制并更新 systemd
echo
echo "[4/6] 替换二进制并更新服务配置..."
ssh -p $REMOTE_PORT $REMOTE_HOST "
  cd $REMOTE_DIR
  NEW_BINARY=llm-gateway-go.v321.linux.amd64
  mv llm-gateway-$COMMIT_HASH \$NEW_BINARY
  chmod +x \$NEW_BINARY
  ls -lh \$NEW_BINARY
  
  # 更新 systemd override 使用新二进制
  mkdir -p /etc/systemd/system/${SERVICE_NAME}.service.d
  cat > /etc/systemd/system/${SERVICE_NAME}.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/docker run --rm --name llm-gateway-go --network host --env-file /etc/llm-gateway-go/env -v /opt/llm-gateway-go/data:/opt/llm-gateway-go/data -v /opt/llm-gateway-go/web:/opt/llm-gateway-go/web:ro -v /opt/llm-gateway-go/llm-gateway-go.v321.linux.amd64:/opt/llm-gateway-go/llm-gateway-go:ro -v /opt/llm-gateway-go/llm-gateway-go.v321.linux.amd64:/usr/local/bin/llm-gateway-go:ro --entrypoint /opt/llm-gateway-go/llm-gateway-go docker.m.daocloud.io/library/alpine:3.20
EOF
  
  systemctl daemon-reload
"

# 5. 重启服务
echo
echo "[5/6] 重启 $SERVICE_NAME 服务..."
ssh -p $REMOTE_PORT $REMOTE_HOST "
  systemctl restart $SERVICE_NAME
  sleep 5
  systemctl status $SERVICE_NAME --no-pager
"

# 6. 验证健康检查
echo
echo "[6/6] 验证服务健康..."
sleep 2
ssh -p $REMOTE_PORT $REMOTE_HOST "
  curl -s http://localhost:3100/health | jq .
"

echo
echo "=========================================="
echo "部署完成! $VERSION"
echo "=========================================="
echo
echo "验证步骤:"
echo "1. 观察 server log: ssh -p $REMOTE_PORT $REMOTE_HOST 'journalctl -u $SERVICE_NAME -f'"
echo "2. 压力测试: ./test_minimax_session.sh"
echo "3. 查询 request_logs: 确认无 circuit_open"
echo "4. 查询 circuit stats: curl localhost:3100/debug/circuits | jq"
echo
echo "预期行为:"
echo "- 不同 model 的 circuit 独立 (key = provider/credential/model)"
echo "- MiniMax-M2.7 失败不影响 MiniMax-M3"
echo "- circuit_open 发生率显著降低"
echo
echo "回滚命令(如需):"
echo "  ssh -p $REMOTE_PORT $REMOTE_HOST 'systemctl stop $SERVICE_NAME && cd $REMOTE_DIR && cp llm-gateway-go.v315.linux.amd64.backup.$TIMESTAMP llm-gateway-go.v315.linux.amd64 && systemctl daemon-reload && systemctl start $SERVICE_NAME'"
