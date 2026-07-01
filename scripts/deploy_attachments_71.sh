#!/bin/bash
# 附件归档功能部署脚本 (2026-07-01)
# 部署到 192.168.1.71 生产服务器
# 使用方法：
#   1. 将此脚本、二进制、审计报告打包上传到 /tmp/
#   2. ssh root@192.168.1.71
#   3. cd /tmp && sudo bash deploy_attachments_71.sh

set -euo pipefail

# ============================================================
# 配置区
# ============================================================
BINARY_SRC="/tmp/llm-gateway-linux-amd64"
DEPLOY_DIR="/opt/llm-gateway-go"
BINARY_DEST="$DEPLOY_DIR/llm-gateway"
SERVICE_NAME="llm-gateway"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="llm-gateway.backup.$TIMESTAMP"
ATTACHMENT_STORAGE_DIR="$DEPLOY_DIR/data/attachments"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# 辅助函数
# ============================================================
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }
log_check() { echo -e "${BLUE}[CHECK]${NC} $1"; }

confirm() {
    read -p "$(echo -e ${YELLOW}[确认]${NC} $1 '(y/N): ')" response
    [[ "$response" =~ ^[Yy]$ ]]
}

# ============================================================
# 前置检查
# ============================================================
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}附件归档功能部署 (2026-07-01)${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo "部署内容："
echo "  1. 图片归档到磁盘+DB（旁观者模式，不修改body）"
echo "  2. 修复 3 个严重的图片转换 bug"
echo "  3. Admin 附件下载 API"
echo "  4. request_logs 新增 has_attachments/attachment_count"
echo ""
echo "风险评估："
echo "  🟡 中等风险（新功能 + 严重bug修复，向后兼容）"
echo "  ✅ 回滚简单（备份二进制 → systemctl restart）"
echo "  ✅ 功能可关闭（ATTACHMENT_ENABLED=false）"
echo ""

if ! confirm "已阅读审计报告，确认开始部署？"; then
    log_error "部署已取消"
    exit 1
fi
echo ""

# 检查权限
log_check "检查运行权限..."
if [[ $EUID -ne 0 ]]; then
   log_error "需要 root 权限运行"
   exit 1
fi
log_info "✓ 权限检查通过"

# 检查二进制文件
log_check "检查二进制文件..."
if [[ ! -f "$BINARY_SRC" ]]; then
    log_error "找不到二进制文件: $BINARY_SRC"
    exit 1
fi
log_info "✓ 二进制文件存在: $(ls -lh $BINARY_SRC | awk '{print $5}')"

# 检查目标目录
log_check "检查部署目录..."
if [[ ! -d "$DEPLOY_DIR" ]]; then
    log_error "部署目录不存在: $DEPLOY_DIR"
    exit 1
fi
log_info "✓ 部署目录存在"

# 检查服务状态
log_check "检查服务状态..."
if ! systemctl is-active --quiet $SERVICE_NAME; then
    log_warn "服务未运行，将在部署后启动"
    SERVICE_WAS_RUNNING=false
else
    log_info "✓ 服务正在运行"
    SERVICE_WAS_RUNNING=true
fi

# 检查数据库连接
log_check "检查数据库连接..."
if sudo -u postgres psql -d llm_gateway -c "SELECT 1;" > /dev/null 2>&1; then
    log_info "✓ 数据库连接正常"
    
    # 检查 request_logs 表
    if sudo -u postgres psql -d llm_gateway -c "\d request_logs" > /dev/null 2>&1; then
        log_info "✓ request_logs 表存在"
    else
        log_error "request_logs 表不存在，无法部署"
        exit 1
    fi
else
    log_error "数据库连接失败"
    exit 1
fi

echo ""
log_step "前置检查完成，准备部署..."
echo ""

# ============================================================
# 数据库迁移检查
# ============================================================
log_step "检查数据库 schema..."

# 检查 request_logs 是否有新字段
HAS_ATTACHMENT_FIELDS=$(sudo -u postgres psql -d llm_gateway -t -c "
    SELECT COUNT(*) 
    FROM information_schema.columns 
    WHERE table_name='request_logs' 
      AND column_name IN ('has_attachments', 'attachment_count');
" | tr -d ' ')

if [[ "$HAS_ATTACHMENT_FIELDS" == "2" ]]; then
    log_info "✓ request_logs 已有 attachment 字段"
else
    log_warn "request_logs 缺少 attachment 字段"
    echo ""
    echo "需要执行以下 SQL："
    echo ""
    echo "  ALTER TABLE request_logs"
    echo "      ADD COLUMN IF NOT EXISTS has_attachments BOOLEAN,"
    echo "      ADD COLUMN IF NOT EXISTS attachment_count INTEGER;"
    echo ""
    
    if confirm "现在执行数据库迁移？"; then
        log_step "执行数据库迁移..."
        sudo -u postgres psql -d llm_gateway <<EOF
ALTER TABLE request_logs
    ADD COLUMN IF NOT EXISTS has_attachments BOOLEAN,
    ADD COLUMN IF NOT EXISTS attachment_count INTEGER;
EOF
        log_info "✓ 数据库迁移完成"
    else
        log_error "数据库迁移被跳过，部署终止"
        exit 1
    fi
fi

# 检查 attachments 表（由网关自动创建，这里只检查）
ATTACHMENTS_TABLE_EXISTS=$(sudo -u postgres psql -d llm_gateway -t -c "
    SELECT COUNT(*) 
    FROM information_schema.tables 
    WHERE table_name='attachments';
" | tr -d ' ')

if [[ "$ATTACHMENTS_TABLE_EXISTS" == "1" ]]; then
    log_info "✓ attachments 表已存在"
else
    log_warn "attachments 表不存在（网关启动时会自动创建）"
fi

echo ""

# ============================================================
# 备份当前二进制
# ============================================================
log_step "备份当前二进制..."
if [[ -f "$BINARY_DEST" ]]; then
    cp "$BINARY_DEST" "$DEPLOY_DIR/$BACKUP_NAME"
    log_info "✓ 备份完成: $DEPLOY_DIR/$BACKUP_NAME"
    
    # 显示当前版本
    CURRENT_VERSION=$("$BINARY_DEST" --version 2>&1 | head -1 || echo "unknown")
    log_info "  当前版本: $CURRENT_VERSION"
else
    log_warn "当前二进制不存在，跳过备份"
fi
echo ""

# ============================================================
# 创建附件存储目录
# ============================================================
log_step "创建附件存储目录..."
mkdir -p "$ATTACHMENT_STORAGE_DIR"
chown -R $(stat -c '%U:%G' "$DEPLOY_DIR" 2>/dev/null || echo "root:root") "$ATTACHMENT_STORAGE_DIR"
chmod 755 "$ATTACHMENT_STORAGE_DIR"
log_info "✓ 目录创建完成: $ATTACHMENT_STORAGE_DIR"
echo ""

# ============================================================
# 停止服务
# ============================================================
if $SERVICE_WAS_RUNNING; then
    log_step "停止服务..."
    systemctl stop $SERVICE_NAME
    sleep 2
    log_info "✓ 服务已停止"
    echo ""
fi

# ============================================================
# 部署新二进制
# ============================================================
log_step "部署新二进制..."
cp "$BINARY_SRC" "$BINARY_DEST"
chmod +x "$BINARY_DEST"
chown $(stat -c '%U:%G' "$DEPLOY_DIR" 2>/dev/null || echo "root:root") "$BINARY_DEST"
log_info "✓ 二进制部署完成"

# 显示新版本
NEW_VERSION=$("$BINARY_DEST" --version 2>&1 | head -1 || echo "unknown")
log_info "  新版本: $NEW_VERSION"
echo ""

# ============================================================
# 配置环境变量
# ============================================================
log_step "配置环境变量..."

SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
if [[ -f "$SERVICE_FILE" ]]; then
    log_info "检查 systemd service 配置..."
    
    # 检查是否已有 ATTACHMENT_ENABLED
    if grep -q "ATTACHMENT_ENABLED" "$SERVICE_FILE"; then
        log_info "✓ ATTACHMENT_ENABLED 已配置"
    else
        log_warn "ATTACHMENT_ENABLED 未配置"
        echo ""
        echo "建议在 $SERVICE_FILE 的 [Service] 区块添加："
        echo ""
        echo "  Environment=\"ATTACHMENT_ENABLED=true\""
        echo "  Environment=\"ATTACHMENT_STORAGE_PATH=$ATTACHMENT_STORAGE_DIR\""
        echo "  Environment=\"ATTACHMENT_MAX_SIZE_MB=10\""
        echo ""
        
        if confirm "现在编辑 service 文件？"; then
            ${EDITOR:-vi} "$SERVICE_FILE"
            systemctl daemon-reload
            log_info "✓ systemd 配置已重载"
        else
            log_warn "环境变量配置被跳过（功能将被禁用）"
        fi
    fi
else
    log_warn "systemd service 文件不存在: $SERVICE_FILE"
fi
echo ""

# ============================================================
# 启动服务
# ============================================================
log_step "启动服务..."
systemctl start $SERVICE_NAME
sleep 3

if systemctl is-active --quiet $SERVICE_NAME; then
    log_info "✓ 服务启动成功"
else
    log_error "服务启动失败"
    echo ""
    echo "查看日志："
    echo "  journalctl -u $SERVICE_NAME -n 50"
    echo ""
    echo "回滚命令："
    echo "  systemctl stop $SERVICE_NAME"
    echo "  cp $DEPLOY_DIR/$BACKUP_NAME $BINARY_DEST"
    echo "  systemctl start $SERVICE_NAME"
    exit 1
fi
echo ""

# ============================================================
# 启动后检查
# ============================================================
log_step "启动后检查..."
sleep 2

# 检查日志
log_info "检查启动日志（最近 20 行）..."
echo ""
journalctl -u $SERVICE_NAME -n 20 --no-pager
echo ""

# 检查关键日志
log_info "检查附件管理器状态..."
if journalctl -u $SERVICE_NAME --since '1 minute ago' | grep -q "attachment manager enabled"; then
    log_info "✓ 附件管理器已启用"
    STORAGE_PATH=$(journalctl -u $SERVICE_NAME --since '1 minute ago' | grep "attachment manager enabled" | tail -1)
    echo "  $STORAGE_PATH"
else
    log_warn "附件管理器未启用（可能 ATTACHMENT_ENABLED=false）"
fi

if journalctl -u $SERVICE_NAME --since '1 minute ago' | grep -q "attachment download API enabled"; then
    log_info "✓ 附件下载 API 已注册"
else
    log_warn "附件下载 API 未注册"
fi

# 检查错误
ERROR_COUNT=$(journalctl -u $SERVICE_NAME --since '1 minute ago' | grep -i "error\|fatal" | wc -l)
if [[ $ERROR_COUNT -gt 0 ]]; then
    log_warn "发现 $ERROR_COUNT 条错误日志"
    echo ""
    journalctl -u $SERVICE_NAME --since '1 minute ago' | grep -i "error\|fatal"
    echo ""
else
    log_info "✓ 无错误日志"
fi

echo ""

# ============================================================
# 验证测试
# ============================================================
log_step "基础健康检查..."

# 检查端口监听
LISTEN_PORT=$(ss -tlnp | grep llm-gateway | awk '{print $4}' | cut -d: -f2 | head -1)
if [[ -n "$LISTEN_PORT" ]]; then
    log_info "✓ 服务监听端口: $LISTEN_PORT"
else
    log_error "服务未监听端口"
fi

# 检查 /healthz
if curl -f -s http://localhost:${LISTEN_PORT:-8080}/healthz > /dev/null 2>&1; then
    log_info "✓ /healthz 健康检查通过"
else
    log_error "/healthz 健康检查失败"
fi

echo ""

# ============================================================
# 部署总结
# ============================================================
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}部署完成！${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo "备份位置: $DEPLOY_DIR/$BACKUP_NAME"
echo ""
echo "📋 后续验证步骤："
echo ""
echo "1. 持续监控日志（建议 30 分钟）："
echo "   journalctl -u $SERVICE_NAME -f"
echo ""
echo "2. 发送带图片的测试请求："
echo "   参见 DEPLOYMENT_AUDIT_REPORT_2026-07-01_attachments.md"
echo "   「验证测试」章节"
echo ""
echo "3. 检查数据库记录："
echo "   psql -d llm_gateway -c \"SELECT request_id, has_attachments, attachment_count FROM request_logs WHERE has_attachments = true ORDER BY ts DESC LIMIT 5;\""
echo "   psql -d llm_gateway -c \"SELECT id, request_id, media_type, file_size FROM attachments ORDER BY created_at DESC LIMIT 5;\""
echo ""
echo "4. 测试附件下载 API："
echo "   curl -H 'Authorization: Bearer <admin-jwt>' http://localhost:$LISTEN_PORT/api/admin/attachments/{id}"
echo ""
echo "5. 检查磁盘空间："
echo "   df -h $ATTACHMENT_STORAGE_DIR"
echo ""
echo "🔄 回滚命令（如需要）："
echo "   systemctl stop $SERVICE_NAME"
echo "   cp $DEPLOY_DIR/$BACKUP_NAME $BINARY_DEST"
echo "   systemctl start $SERVICE_NAME"
echo ""
echo "📊 监控关键指标（24小时）："
echo "  • 请求成功率无下降"
echo "  • 图片请求响应时间 <+200ms"
echo "  • attachments 表有增长（发送图片请求后）"
echo "  • 无 'attachment archival failed' 错误（偶发可接受）"
echo ""
