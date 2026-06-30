#!/bin/bash
# 在71服务器上执行此脚本完成部署
# 使用方法: 
#   1. 上传 llm-gateway 二进制和此脚本到 /tmp/
#   2. ssh 192.168.1.71
#   3. cd /tmp && sudo bash deploy_on_71.sh

set -euo pipefail

# 配置
BINARY_PATH="/tmp/llm-gateway"
REMOTE_DIR="/opt/llm-gateway-go"
SERVICE_NAME="llm-gateway"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

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
echo -e "${CYAN}部署路由问题修复${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""
echo "修复内容:"
echo "  1. 路由健康检查阈值: 3→5次失败, 5→3分钟冷却"
echo "  2. Empty response检测改进: 减少false positive"
echo "  3. Fallback机制: 防止no_candidate错误"
echo ""

# 检查二进制文件
if [ ! -f "$BINARY_PATH" ]; then
    log_error "二进制文件不存在: $BINARY_PATH"
    log_info "请先上传二进制文件到 /tmp/llm-gateway"
    exit 1
fi

log_info "二进制文件大小: $(ls -lh $BINARY_PATH | awk '{print $5}')"
echo ""

# 确认
read -p "确认开始部署？(yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    log_warn "部署已取消"
    exit 0
fi

echo ""
log_step "=== 步骤 1/5: 检查当前状态 ==="
systemctl status $SERVICE_NAME --no-pager -l || true
echo ""
log_info "当前二进制:"
ls -lh $REMOTE_DIR/llm-gateway 2>/dev/null || echo "未找到"

echo ""
log_step "=== 步骤 2/5: 备份当前版本 ==="
cd $REMOTE_DIR
BACKUP_NAME="llm-gateway.backup-${TIMESTAMP}"
if [ -f "llm-gateway" ]; then
    cp llm-gateway "$BACKUP_NAME"
    log_info "✓ 备份完成: $REMOTE_DIR/$BACKUP_NAME"
    ls -lh "$BACKUP_NAME"
else
    log_warn "未找到现有二进制文件"
fi

echo ""
log_step "=== 步骤 3/5: 停止服务 ==="
systemctl stop $SERVICE_NAME
sleep 3

# 确认进程已停止
if pgrep -f llm-gateway > /dev/null; then
    log_warn "服务仍在运行，等待5秒..."
    sleep 5
    if pgrep -f llm-gateway > /dev/null; then
        log_warn "强制终止进程..."
        pkill -9 -f llm-gateway || true
        sleep 2
    fi
fi
log_info "✓ 服务已停止"

echo ""
log_step "=== 步骤 4/5: 部署新版本 ==="
cp $BINARY_PATH $REMOTE_DIR/llm-gateway
chmod +x $REMOTE_DIR/llm-gateway
chown root:root $REMOTE_DIR/llm-gateway 2>/dev/null || true
log_info "✓ 新版本已部署"
ls -lh $REMOTE_DIR/llm-gateway

echo ""
log_step "=== 步骤 5/5: 启动服务 ==="
systemctl start $SERVICE_NAME
sleep 5

# 检查服务状态
if systemctl is-active $SERVICE_NAME > /dev/null 2>&1; then
    log_info "✓ 服务启动成功"
    systemctl status $SERVICE_NAME --no-pager | head -20
else
    log_error "✗ 服务启动失败！"
    echo ""
    log_error "最近的日志:"
    journalctl -u $SERVICE_NAME -n 50 --no-pager
    echo ""
    log_warn "回滚命令:"
    echo "  systemctl stop $SERVICE_NAME"
    echo "  cp $REMOTE_DIR/$BACKUP_NAME $REMOTE_DIR/llm-gateway"
    echo "  systemctl start $SERVICE_NAME"
    exit 1
fi

echo ""
log_info "✓✓✓ 部署成功！✓✓✓"
echo ""
echo "查看最近日志:"
journalctl -u $SERVICE_NAME -n 30 --no-pager | tail -20
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}部署完成${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""
echo "备份位置: $REMOTE_DIR/$BACKUP_NAME"
echo ""
echo "后续步骤:"
echo ""
echo "1. 持续监控日志（建议观察10-30分钟）:"
echo "   journalctl -u $SERVICE_NAME -f"
echo ""
echo "2. 检查关键指标:"
echo "   journalctl -u $SERVICE_NAME --since '5 min ago' | grep -i 'error\\|warn\\|no_candidate\\|empty_response'"
echo ""
echo "3. 运行测试验证:"
echo "   cd /path/to/llm-gateway-go-2"
echo "   ./scripts/test_71_complete.sh"
echo ""
echo "4. 如果出现问题，立即回滚:"
echo "   systemctl stop $SERVICE_NAME"
echo "   cp $REMOTE_DIR/$BACKUP_NAME $REMOTE_DIR/llm-gateway"
echo "   systemctl start $SERVICE_NAME"
echo ""
echo "预期效果（24小时内观察）:"
echo "  • No Candidate 错误率降至 <1%"
echo "  • Empty Response 错误率下降至少50%"
echo "  • 整体成功率提升"
echo ""
