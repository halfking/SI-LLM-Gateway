#!/bin/bash
# 统一部署脚本
# 合并所有部署相关脚本，支持多目标、多模式部署

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 加载工具函数
source "$SCRIPT_DIR/utils.sh"

# ==================== 配置变量 ====================
TARGET=""
MODE=""
BINARY_PATH="$PROJECT_ROOT/bin/llm-gateway"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BUILD_NUM=""
VERSION=""
GIT_COMMIT=$(get_git_commit)

# 71服务器配置
SERVER_71_HOST="${SERVER_71_HOST:-root@14.103.174.71}"
SERVER_71_PORT="${SERVER_71_PORT:-25022}"
SERVER_71_DIR="/opt/llm-gateway-go"
SERVER_71_SERVICE="llm-gateway"

# 184服务器配置 (K8s)
SERVER_184_HOST="${SERVER_184_HOST:-root@14.103.112.184}"
SERVER_184_PORT="${SERVER_184_PORT:-25022}"
K8S_NAMESPACE="pms-test"
K8S_DEPLOYMENT="llm-gateway-go-deployment"

# Docker配置
DOCKER_REGISTRY="registry.kxpms.cn"
DOCKER_IMAGE="kx-llm-gateway-go"

# ==================== 显示帮助 ====================
show_usage() {
    cat << EOF
统一部署脚本

使用方法:
  $0 --target=<TARGET> --mode=<MODE> [选项]

目标 (TARGET):
  71       部署到71服务器 (14.103.174.71) - 生产环境
  184      部署到184服务器 (14.103.112.184) - K8s测试环境

模式 (MODE):
  binary   二进制部署 (仅71)
  docker   Docker容器部署 (仅71)
  k8s      Kubernetes部署 (仅184)

选项:
  --build-num=NUM     指定编译号
  --version=VER       指定版本号
  --skip-backup       跳过备份
  --skip-test         跳过部署后测试
  --dry-run           模拟运行，不实际部署
  -h, --help          显示此帮助信息

示例:
  # 部署到71服务器 (二进制方式)
  $0 --target=71 --mode=binary

  # 部署到71服务器 (Docker方式)
  $0 --target=71 --mode=docker

  # 部署到184服务器 (K8s方式)
  $0 --target=184 --mode=k8s --build-num=720

环境变量:
  SERVER_71_HOST      71服务器地址 (默认: root@14.103.174.71)
  SERVER_71_PORT      71服务器SSH端口 (默认: 25022)
  SERVER_184_HOST     184服务器地址
  SERVER_184_PORT     184服务器SSH端口

EOF
}

# ==================== 解析参数 ====================
parse_arguments() {
    local DRY_RUN=false
    local SKIP_BACKUP=false
    local SKIP_TEST=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --target=*)
                TARGET="${1#*=}"
                shift
                ;;
            --mode=*)
                MODE="${1#*=}"
                shift
                ;;
            --build-num=*)
                BUILD_NUM="${1#*=}"
                shift
                ;;
            --version=*)
                VERSION="${1#*=}"
                shift
                ;;
            --skip-backup)
                SKIP_BACKUP=true
                shift
                ;;
            --skip-test)
                SKIP_TEST=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # 验证必需参数
    if [ -z "$TARGET" ]; then
        log_error "必须指定部署目标 --target=71|184"
        show_usage
        exit 1
    fi
    
    if [ -z "$MODE" ]; then
        log_error "必须指定部署模式 --mode=binary|docker|k8s"
        show_usage
        exit 1
    fi
    
    # 验证目标和模式组合
    if [ "$TARGET" = "71" ] && [ "$MODE" = "k8s" ]; then
        log_error "71服务器不支持k8s模式"
        exit 1
    fi
    
    if [ "$TARGET" = "184" ] && [ "$MODE" != "k8s" ]; then
        log_error "184服务器仅支持k8s模式"
        exit 1
    fi
    
    export DRY_RUN SKIP_BACKUP SKIP_TEST
}

# ==================== 部署前检查 ====================
pre_deploy_check() {
    print_header "部署前检查"
    
    # 检查二进制文件
    if [ "$MODE" = "binary" ] || [ "$MODE" = "docker" ]; then
        if [ ! -f "$BINARY_PATH" ]; then
            log_error "二进制文件不存在: $BINARY_PATH"
            log_info "请先运行: go build -o bin/llm-gateway ./cmd/gateway"
            exit 1
        fi
        log_success "二进制文件存在: $BINARY_PATH"
        ls -lh "$BINARY_PATH"
    fi
    
    # 检查SSH连接
    if [ "$TARGET" = "71" ]; then
        test_ssh_connection "$SERVER_71_HOST" "$SERVER_71_PORT" || exit 1
    elif [ "$TARGET" = "184" ]; then
        test_ssh_connection "$SERVER_184_HOST" "$SERVER_184_PORT" || exit 1
    fi
    
    echo ""
}

# ==================== 部署到71 (二进制) ====================
deploy_71_binary() {
    print_header "部署到71服务器 (二进制模式)"
    
    log_info "目标: ${SERVER_71_HOST}:${SERVER_71_PORT}"
    log_info "Git提交: $GIT_COMMIT"
    log_info "时间: $TIMESTAMP"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY RUN 模式，不会实际部署"
        return 0
    fi
    
    # 确认部署
    if ! confirm "确认部署到71生产服务器？"; then
        log_warn "部署已取消"
        exit 0
    fi
    
    log_step "=== 步骤 1/6: 上传二进制 ==="
    local remote_binary="$SERVER_71_DIR/llm-gateway-new-${TIMESTAMP}"
    scp -P "$SERVER_71_PORT" "$BINARY_PATH" "${SERVER_71_HOST}:${remote_binary}" || {
        log_error "上传失败"
        exit 1
    }
    log_success "上传完成"
    
    log_step "=== 步骤 2/6: 检查当前状态 ==="
    check_service_status "$SERVER_71_HOST" "$SERVER_71_PORT" "$SERVER_71_SERVICE"
    
    log_step "=== 步骤 3/6: 备份当前版本 ==="
    if [ "$SKIP_BACKUP" = false ]; then
        ssh -p "$SERVER_71_PORT" "$SERVER_71_HOST" bash << EOF
cd $SERVER_71_DIR
BACKUP="llm-gateway.backup-${TIMESTAMP}"
if [ -f llm-gateway ]; then
    cp llm-gateway "\$BACKUP"
    echo "✓ 已备份: \$BACKUP"
    ls -lh "\$BACKUP"
else
    echo "! 未找到现有二进制"
fi
EOF
    else
        log_warn "跳过备份"
    fi
    
    log_step "=== 步骤 4/6: 停止服务 ==="
    ssh -p "$SERVER_71_PORT" "$SERVER_71_HOST" bash << 'EOF'
systemctl stop llm-gateway
echo "✓ 服务已停止"
sleep 3

# 确认进程已停止
if pgrep -x llm-gateway > /dev/null; then
    echo "! 服务仍在运行，强制终止..."
    pkill -9 llm-gateway || true
    sleep 2
fi
EOF
    
    log_step "=== 步骤 5/6: 部署新版本 ==="
    ssh -p "$SERVER_71_PORT" "$SERVER_71_HOST" bash << EOF
cd $SERVER_71_DIR
mv ${remote_binary} llm-gateway
chmod +x llm-gateway
chown root:root llm-gateway
echo "✓ 新版本已部署"
ls -lh llm-gateway
EOF
    
    log_step "=== 步骤 6/6: 启动服务 ==="
    ssh -p "$SERVER_71_PORT" "$SERVER_71_HOST" bash << EOF
systemctl start $SERVER_71_SERVICE
echo "✓ 服务已启动"
sleep 5

echo ""
echo "验证服务状态..."
if systemctl is-active --quiet $SERVER_71_SERVICE; then
    echo "✓ 服务运行正常"
    systemctl status $SERVER_71_SERVICE --no-pager | head -15
else
    echo "✗ 服务启动失败"
    journalctl -u $SERVER_71_SERVICE -n 30 --no-pager
    exit 1
fi
EOF
    
    if [ $? -eq 0 ]; then
        log_success "部署成功！"
        echo ""
        echo "监控命令:"
        echo "  ssh -p $SERVER_71_PORT $SERVER_71_HOST 'journalctl -u $SERVER_71_SERVICE -f'"
        echo ""
        echo "回滚命令:"
        echo "  ssh -p $SERVER_71_PORT $SERVER_71_HOST 'systemctl stop $SERVER_71_SERVICE && cp $SERVER_71_DIR/llm-gateway.backup-${TIMESTAMP} $SERVER_71_DIR/llm-gateway && systemctl start $SERVER_71_SERVICE'"
        echo ""
    else
        log_error "部署失败"
        exit 1
    fi
}

# ==================== 部署到71 (Docker) ====================
deploy_71_docker() {
    print_header "部署到71服务器 (Docker模式)"
    
    log_info "目标: ${SERVER_71_HOST}:${SERVER_71_PORT}"
    log_info "服务: ${SERVER_71_SERVICE}.service"
    log_info "Git提交: $GIT_COMMIT"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY RUN 模式，不会实际部署"
        return 0
    fi
    
    if ! confirm "确认部署到71生产服务器 (Docker模式)？"; then
        log_warn "部署已取消"
        exit 0
    fi
    
    log_step "=== 步骤 1/8: 上传二进制 ==="
    local remote_binary="$SERVER_71_DIR/llm-gateway-new-${TIMESTAMP}"
    scp -P "$SERVER_71_PORT" "$BINARY_PATH" "${SERVER_71_HOST}:${remote_binary}" || exit 1
    log_success "上传完成"
    
    log_step "=== 步骤 2/8: 检查当前状态 ==="
    ssh -p "$SERVER_71_PORT" "$SERVER_71_HOST" << 'EOF'
echo "服务状态:"
systemctl status llm-gateway.service --no-pager | head -10 || true
echo ""
echo "Docker容器:"
docker ps | grep llm-gateway || echo "容器未运行"
EOF
    
    log_step "=== 步骤 3/8: 备份当前版本 ==="
    if [ "$SKIP_BACKUP" = false ]; then
        remote_backup_file "$SERVER_71_HOST" "$SERVER_71_PORT" "$SERVER_71_DIR/llm-gateway"
    fi
    
    log_step "=== 步骤 4/8: 停止服务 ==="
    ssh -p "$SERVER_71_PORT" "$SERVER_71_HOST" bash << 'EOF'
systemctl stop llm-gateway.service
echo "✓ systemd服务已停止"
sleep 3

# 确认Docker容器已停止
if docker ps | grep -q llm-gateway; then
    echo "停止Docker容器..."
    docker stop llm-gateway || true
    sleep 2
fi
echo "✓ 服务已完全停止"
EOF
    
    log_step "=== 步骤 5/8: 部署新版本 ==="
    ssh -p "$SERVER_71_PORT" "$SERVER_71_HOST" bash << EOF
cd $SERVER_71_DIR
mv llm-gateway-new-${TIMESTAMP} llm-gateway
chmod +x llm-gateway
chown root:root llm-gateway
echo "✓ 新版本已部署"
ls -lh llm-gateway
EOF
    
    log_step "=== 步骤 6/8: 启动服务 ==="
    ssh -p "$SERVER_71_PORT" "$SERVER_71_HOST" bash << 'EOF'
systemctl start llm-gateway.service
echo "✓ systemd服务已启动"
sleep 5

# 等待Docker容器启动
for i in {1..10}; do
    if docker ps | grep -q llm-gateway; then
        echo "✓ Docker容器已启动"
        break
    fi
    echo "等待容器启动... ($i/10)"
    sleep 2
done
EOF
    
    log_step "=== 步骤 7/8: 验证部署 ==="
    ssh -p "$SERVER_71_PORT" "$SERVER_71_HOST" bash << 'EOF'
echo "=== 服务状态 ==="
systemctl status llm-gateway.service --no-pager | head -15

echo ""
echo "=== Docker容器 ==="
docker ps | grep llm-gateway || echo "! 容器未运行"

echo ""
echo "=== 最近日志 ==="
journalctl -u llm-gateway.service -n 20 --no-pager | tail -15
EOF
    
    log_step "=== 步骤 8/8: 健康检查 ==="
    wait_for_service "http://llm.kxpms.cn/health" 30 2
    
    log_success "部署成功！"
}

# ==================== 部署到184 (K8s) ====================
deploy_184_k8s() {
    print_header "部署到184服务器 (K8s模式)"
    
    log_info "目标: ${SERVER_184_HOST}:${SERVER_184_PORT}"
    log_info "命名空间: $K8S_NAMESPACE"
    log_info "部署: $K8S_DEPLOYMENT"
    log_info "Git提交: $GIT_COMMIT"
    echo ""
    
    if [ -z "$BUILD_NUM" ]; then
        log_error "K8s部署必须指定 --build-num"
        exit 1
    fi
    
    local IMAGE_TAG="gitsha-${GIT_COMMIT}-r${BUILD_NUM}"
    log_info "镜像标签: $IMAGE_TAG"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY RUN 模式，不会实际部署"
        return 0
    fi
    
    if ! confirm "确认部署到184测试环境？"; then
        log_warn "部署已取消"
        exit 0
    fi
    
    log_step "=== 步骤 1/6: 构建Docker镜像 ==="
    cd "$PROJECT_ROOT"
    docker build -t "${DOCKER_IMAGE}:${IMAGE_TAG}" -f Dockerfile . || {
        log_error "镜像构建失败"
        exit 1
    }
    log_success "镜像构建完成"
    
    log_step "=== 步骤 2/6: 推送到镜像仓库 ==="
    docker tag "${DOCKER_IMAGE}:${IMAGE_TAG}" "${DOCKER_REGISTRY}/${DOCKER_IMAGE}:${IMAGE_TAG}"
    docker push "${DOCKER_REGISTRY}/${DOCKER_IMAGE}:${IMAGE_TAG}" || {
        log_error "镜像推送失败"
        exit 1
    }
    log_success "镜像已推送到仓库"
    
    log_step "=== 步骤 3/6: 同步镜像到184服务器 ==="
    ssh -p "$SERVER_184_PORT" "$SERVER_184_HOST" bash << EOF
docker pull ${DOCKER_REGISTRY}/${DOCKER_IMAGE}:${IMAGE_TAG}
docker tag ${DOCKER_REGISTRY}/${DOCKER_IMAGE}:${IMAGE_TAG} 127.0.0.1:5000/${DOCKER_IMAGE}:${IMAGE_TAG}
docker push 127.0.0.1:5000/${DOCKER_IMAGE}:${IMAGE_TAG}
echo "✓ 镜像已同步到本地仓库"
EOF
    
    log_step "=== 步骤 4/6: 更新K8s部署 ==="
    ssh -p "$SERVER_184_PORT" "$SERVER_184_HOST" bash << EOF
kubectl set image deployment/${K8S_DEPLOYMENT} \
    llm-gateway-go=127.0.0.1:5000/${DOCKER_IMAGE}:${IMAGE_TAG} \
    -n ${K8S_NAMESPACE}
echo "✓ K8s镜像已更新"
EOF
    
    log_step "=== 步骤 5/6: 等待部署完成 ==="
    ssh -p "$SERVER_184_PORT" "$SERVER_184_HOST" bash << EOF
kubectl rollout status deployment/${K8S_DEPLOYMENT} -n ${K8S_NAMESPACE} --timeout=5m
EOF
    
    log_step "=== 步骤 6/6: 验证部署 ==="
    ssh -p "$SERVER_184_PORT" "$SERVER_184_HOST" bash << EOF
echo "=== Pod状态 ==="
kubectl get pods -n ${K8S_NAMESPACE} -l app=llm-gateway-go

echo ""
echo "=== 最近日志 ==="
kubectl logs -n ${K8S_NAMESPACE} -l app=llm-gateway-go --tail=20
EOF
    
    log_success "部署成功！"
    echo ""
    echo "查看日志:"
    echo "  ssh -p $SERVER_184_PORT $SERVER_184_HOST 'kubectl logs -n $K8S_NAMESPACE -l app=llm-gateway-go -f'"
    echo ""
}

# ==================== 主函数 ====================
main() {
    parse_arguments "$@"
    
    print_header "LLM Gateway 统一部署工具"
    log_info "目标: $TARGET"
    log_info "模式: $MODE"
    log_info "Git提交: $GIT_COMMIT"
    echo ""
    
    pre_deploy_check
    
    # 根据目标和模式执行部署
    if [ "$TARGET" = "71" ]; then
        if [ "$MODE" = "binary" ]; then
            deploy_71_binary
        elif [ "$MODE" = "docker" ]; then
            deploy_71_docker
        fi
    elif [ "$TARGET" = "184" ]; then
        if [ "$MODE" = "k8s" ]; then
            deploy_184_k8s
        fi
    fi
    
    print_header "部署完成"
    log_success "所有步骤已成功执行"
}

main "$@"
