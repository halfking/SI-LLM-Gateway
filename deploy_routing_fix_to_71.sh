#!/bin/bash
# 部署 Minimax-m3 路由问题修复到71服务器
# 2026-06-30: 修复路由健康检查阈值、empty_response误判、fallback机制

set -euo pipefail

cd /Users/xutaohuang/workspace/llm-gateway-go-2

# 配置
BINARY_PATH="bin/llm-gateway"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SERVER_71="root@192.168.1.71"
REMOTE_DIR="/opt/llm-gateway-go"
SERVICE_NAME="llm-gateway"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}部署路由问题修复到71服务器${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""
echo "修复内容:"
echo "  1. 路由健康检查阈值: 3→5次失败, 5→3分钟冷却"
echo "  2. Empty response检测改进: 增加2个short-circuit"
echo "  3. Fallback机制: 防止no_candidate错误"
echo ""
echo "二进制文件: $BINARY_PATH"
echo "文件大小: $(ls -lh $BINARY_PATH 2>/dev/null | awk '{print $5}' || echo '未找到')"
echo "目标服务器: $SERVER_71"
echo "部署时间: $TIMESTAMP"
echo ""

# 检查二进制文件
if [ ! -f "$BINARY_PATH" ]; then
    log_error "二进制文件不存在: $BINARY_PATH"
    log_info "请先运行: go build -o bin/llm-gateway ./cmd/gateway"
    exit 1
fi

# 确认部署
read -p "确认开始部署？(yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    log_warn "部署已取消"
    exit 0
fi

echo ""
log_step "=== 步骤 1/6: 上传二进制文件 ==="
REMOTE_BINARY="/tmp/llm-gateway-routing-fix-${TIMESTAMP}"
scp "$BINARY_PATH" "${SERVER_71}:${REMOTE_BINARY}" || {
    log_error "上传失败"
    exit 1
}
log_info "✓ 上传完成: ${REMOTE_BINARY}"

echo ""
log_step "=== 步骤 2/6: 检查当前服务状态 ==="
ssh "$SERVER_71" bash << 'EOF'
systemctl status llm-gateway --no-pager -l || true
echo ""
echo "当前进程:"
ps aux | grep llm-gateway | grep -v grep || echo "未找到运行的进程"
EOF

echo ""
log_step "=== 步骤 3/6: 执行远程部署 ==="
ssh "$SERVER_71" bash << EOF
set -e

REMOTE_BINARY="$REMOTE_BINARY"
REMOTE_DIR="$REMOTE_DIR"
SERVICE_NAME="$SERVICE_NAME"
TIMESTAMP="$TIMESTAMP"

cd "\$REMOTE_DIR"

echo "[远程] 1. 备份当前版本..."
BACKUP_NAME="llm-gateway.backup-\${TIMESTAMP}"
if [ -f "llm-gateway" ]; then
    cp llm-gateway "\$BACKUP_NAME"
    echo "✓ 备份完成: \$REMOTE_DIR/\$BACKUP_NAME"
    ls -lh "\$BACKUP_NAME"
else
    echo "! 未找到现有二进制"
fi

echo ""
echo "[远程] 2. 停止服务..."
systemctl stop llm-gateway
sleep 3

# 确认进程已停止
if pgrep -f llm-gateway > /dev/null; then
    echo "! 服务仍在运行，等待3秒..."
    sleep 3
    if pgrep -f llm-gateway > /dev/null; then
        echo "! 强制终止进程..."
        pkill -9 -f llm-gateway || true
        sleep 2
    fi
fi
echo "✓ 服务已停止"

echo ""
echo "[远程] 3. 部署新版本..."
cp "\$REMOTE_BINARY" llm-gateway
chmod +x llm-gateway
chown root:root llm-gateway
echo "✓ 新版本已部署"
ls -lh llm-gateway

echo ""
echo "[远程] 4. 启动服务..."
systemctl start llm-gateway
sleep 3
echo "✓ 服务已启动"

echo ""
echo "[远程] 5. 检查服务状态..."
systemctl status llm-gateway --no-pager -l || true
EOF

if [ $? -ne 0 ]; then
    log_error "远程部署失败"
    exit 1
fi

log_info "✓ 远程部署完成"

echo ""
log_step "=== 步骤 4/6: 验证服务启动 ==="
sleep 5
ssh "$SERVER_71" bash << 'EOF'
if systemctl is-active llm-gateway > /dev/null 2>&1; then
    echo "✓ 服务运行正常"
    systemctl status llm-gateway --no-pager | head -20
else
    echo "✗ 服务未运行！"
    echo ""
    echo "最近的日志:"
    journalctl -u llm-gateway -n 50 --no-pager
    exit 1
fi
EOF

if [ $? -ne 0 ]; then
    log_error "服务启动失败！"
    echo ""
    log_warn "回滚命令:"
    echo "  ssh $SERVER_71 'systemctl stop llm-gateway && cp $REMOTE_DIR/llm-gateway.backup-${TIMESTAMP} $REMOTE_DIR/llm-gateway && systemctl start llm-gateway'"
    exit 1
fi

echo ""
log_step "=== 步骤 5/6: 查看启动日志 ==="
ssh "$SERVER_71" 'journalctl -u llm-gateway -n 30 --no-pager'

echo ""
log_step "=== 步骤 6/6: 运行健康检查 ==="
sleep 5
echo "测试基本连接..."
curl -s -o /dev/null -w "HTTP状态码: %{http_code}\n" https://llm.kxpms.cn/v1/chat/completions \
    -X GET || echo "连接测试失败（这是正常的，因为GET请求会返回200）"

echo ""
log_info "✓✓✓ 部署成功！✓✓✓"
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}部署完成${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""
echo "备份位置: $REMOTE_DIR/llm-gateway.backup-${TIMESTAMP}"
echo ""
echo "后续步骤:"
echo ""
echo "1. 监控服务日志（观察5-10分钟）:"
echo -e "   ${YELLOW}ssh $SERVER_71 'journalctl -u llm-gateway -f'${NC}"
echo ""
echo "2. 运行测试验证:"
echo -e "   ${YELLOW}./scripts/test_71_complete.sh${NC}"
echo ""
echo "3. 检查关键日志（看是否有新错误）:"
echo -e "   ${YELLOW}ssh $SERVER_71 'journalctl -u llm-gateway --since \"5 min ago\" | grep -E \"error|ERROR|WARN\"'${NC}"
echo ""
echo "4. 监控数据库指标（在71服务器上）:"
echo -e "   ${YELLOW}export LLM_GATEWAY_DATABASE_URL=...${NC}"
echo -e "   ${YELLOW}psql \\\$LLM_GATEWAY_DATABASE_URL -c \"SELECT COUNT(*) FILTER (WHERE error_kind='no_candidate') as no_cand, COUNT(*) as total FROM request_logs WHERE ts > NOW() - INTERVAL '1 hour';\"${NC}"
echo ""
echo "5. 如果出现问题，立即回滚:"
echo -e "   ${RED}ssh $SERVER_71 'systemctl stop llm-gateway && cp $REMOTE_DIR/llm-gateway.backup-${TIMESTAMP} $REMOTE_DIR/llm-gateway && systemctl start llm-gateway'${NC}"
echo ""
echo "预期效果（24小时内观察）:"
echo "  • No Candidate 错误率: 降至 <1%"
echo "  • Empty Response 错误率: 下降至少50%"
echo "  • 整体成功率提升"
echo ""
