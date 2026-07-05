#!/bin/bash
# 通用工具函数库
# 提供日志、颜色、连接测试等通用函数

# ==================== 颜色定义 ====================
export GREEN='\033[0;32m'
export RED='\033[0;31m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

# ==================== 日志函数 ====================
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅${NC} $1"
}

log_fail() {
    echo -e "${RED}❌${NC} $1"
}

# ==================== SSH 连接测试 ====================
test_ssh_connection() {
    local host="$1"
    local port="${2:-22}"
    
    log_step "测试SSH连接: ${host}:${port}"
    if ssh -p "$port" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$host" "echo '连接成功'" >/dev/null 2>&1; then
        log_success "SSH连接正常"
        return 0
    else
        log_error "SSH连接失败"
        return 1
    fi
}

# ==================== 数据库连接测试 ====================
test_db_connection() {
    local db_url="${1:-$DATABASE_URL}"
    
    log_step "测试数据库连接"
    if [ -z "$db_url" ]; then
        log_error "数据库URL未设置"
        return 1
    fi
    
    if psql "$db_url" -c "SELECT 1;" >/dev/null 2>&1; then
        log_success "数据库连接正常"
        return 0
    else
        log_error "数据库连接失败"
        return 1
    fi
}

# ==================== Redis 连接测试 ====================
test_redis_connection() {
    log_step "测试Redis连接"
    
    if ! command -v redis-cli &> /dev/null; then
        log_warn "redis-cli 未安装"
        return 1
    fi
    
    if redis-cli ping >/dev/null 2>&1; then
        log_success "Redis连接正常"
        return 0
    else
        log_error "Redis连接失败或未启动"
        return 1
    fi
}

# ==================== 服务状态检查 ====================
check_service_status() {
    local host="$1"
    local port="$2"
    local service_name="$3"
    
    log_step "检查服务状态: $service_name"
    ssh -p "$port" "$host" "systemctl status $service_name --no-pager | head -15 || true"
}

# ==================== 等待服务就绪 ====================
wait_for_service() {
    local url="$1"
    local max_attempts="${2:-30}"
    local interval="${3:-2}"
    
    log_step "等待服务就绪: $url"
    
    for i in $(seq 1 "$max_attempts"); do
        if curl -f -s "$url" >/dev/null 2>&1; then
            log_success "服务已就绪"
            return 0
        fi
        echo "等待服务启动... ($i/$max_attempts)"
        sleep "$interval"
    done
    
    log_error "服务启动超时"
    return 1
}

# ==================== 备份文件 ====================
backup_file() {
    local source="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup="${source}.backup-${timestamp}"
    
    if [ -f "$source" ]; then
        cp "$source" "$backup"
        log_success "已备份: $backup"
        echo "$backup"
        return 0
    else
        log_warn "源文件不存在: $source"
        return 1
    fi
}

# ==================== 远程备份文件 ====================
remote_backup_file() {
    local host="$1"
    local port="$2"
    local source="$3"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup="${source}.backup-${timestamp}"
    
    log_step "远程备份文件: $source"
    ssh -p "$port" "$host" "[ -f '$source' ] && cp '$source' '$backup' && echo '✓ 已备份: $backup' || echo '! 文件不存在'"
}

# ==================== 打印分隔线 ====================
print_separator() {
    local char="${1:-=}"
    local width="${2:-60}"
    printf '%*s\n' "$width" '' | tr ' ' "$char"
}

print_header() {
    local title="$1"
    echo ""
    print_separator "=" 60
    echo "$title"
    print_separator "=" 60
    echo ""
}

# ==================== 确认提示 ====================
confirm() {
    local prompt="$1"
    local default="${2:-no}"
    
    if [ "$default" = "yes" ]; then
        read -p "$prompt (Y/n): " -n 1 -r
    else
        read -p "$prompt (y/N): " -n 1 -r
    fi
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# ==================== 检查必需命令 ====================
require_command() {
    local cmd="$1"
    local hint="$2"
    
    if ! command -v "$cmd" &> /dev/null; then
        log_error "$cmd 命令不可用"
        if [ -n "$hint" ]; then
            echo "   $hint"
        fi
        return 1
    fi
    return 0
}

# ==================== 检查环境变量 ====================
require_env() {
    local var_name="$1"
    local hint="$2"
    
    if [ -z "${!var_name}" ]; then
        log_error "环境变量 $var_name 未设置"
        if [ -n "$hint" ]; then
            echo "   $hint"
        fi
        return 1
    fi
    return 0
}

# ==================== 获取Git信息 ====================
get_git_commit() {
    git rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

get_git_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"
}

# ==================== 执行远程命令 ====================
remote_exec() {
    local host="$1"
    local port="$2"
    shift 2
    local command="$*"
    
    ssh -p "$port" "$host" "$command"
}

# ==================== 显示帮助信息 ====================
show_help() {
    local script_name="$1"
    local usage="$2"
    local description="$3"
    
    cat << EOF
使用方法: $script_name $usage

$description

选项:
  -h, --help     显示此帮助信息

示例:
  请查看脚本内的示例说明

EOF
}

# ==================== 解析命令行参数 ====================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                return 1
                ;;
            *)
                shift
                ;;
        esac
    done
    return 0
}
