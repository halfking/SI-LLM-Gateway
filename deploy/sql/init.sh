#!/bin/bash
# ============================================================================
# LLM Gateway 数据库统一初始化脚本
# ============================================================================
# 用法: ./init.sh [-h HOST] [-p PORT] [-u USER] [-d DBNAME] [--skip-seed]
# ============================================================================

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-llm_gateway}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 用法说明
usage() {
    cat << EOF
用法: $0 [OPTIONS]

选项:
  -h HOST         数据库主机 (default: localhost)
  -p PORT         数据库端口 (default: 5432)
  -u USER         数据库用户 (default: postgres)
  -d NAME         数据库名 (default: llm_gateway)
  --skip-seed     跳过初始化数据
  --help          显示帮助

环境变量:
  DB_HOST, DB_PORT, DB_USER, DB_NAME, PGPASSWORD

示例:
  $0                                    # 使用默认配置
  $0 -h localhost -d llm_gateway        # 指定主机和数据库
  $0 --skip-seed                        # 跳过初始化数据
  PGPASSWORD=secret $0                  # 使用环境变量传递密码
EOF
    exit 1
}

# 解析参数
SKIP_SEED=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -h) DB_HOST="$2"; shift 2 ;;
        -p) DB_PORT="$2"; shift 2 ;;
        -u) DB_USER="$2"; shift 2 ;;
        -d) DB_NAME="$2"; shift 2 ;;
        --skip-seed) SKIP_SEED=true; shift ;;
        --help) usage ;;
        *) echo "未知选项: $1"; usage ;;
    esac
done

# 打印配置
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}LLM Gateway 数据库初始化${NC}"
echo -e "${BLUE}========================================${NC}"
echo "主机: $DB_HOST:$DB_PORT"
echo "用户: $DB_USER"
echo "数据库: $DB_NAME"
echo ""

# 执行SQL函数
exec_sql() {
    local file=$1
    PGPASSWORD="${PGPASSWORD:-}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$file" > /dev/null 2>&1
}

# 检查连接
echo -e "${YELLOW}[1/7] 检查数据库连接...${NC}"
if ! PGPASSWORD="${PGPASSWORD:-}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
    echo -e "${RED}✗ 无法连接到数据库${NC}"
    echo "  请检查数据库是否运行，以及连接配置是否正确"
    exit 1
fi
echo -e "${GREEN}✓ 数据库连接正常${NC}"

# 安装扩展
echo -e "${YELLOW}[2/7] 安装PostgreSQL扩展...${NC}"
if [[ -f "$SCRIPT_DIR/extensions/extensions.sql" ]]; then
    exec_sql "$SCRIPT_DIR/extensions/extensions.sql"
    echo -e "${GREEN}✓ 扩展安装完成${NC}"
else
    echo -e "${YELLOW}⚠ 未找到扩展定义文件${NC}"
fi

# 创建表结构
echo -e "${YELLOW}[3/7] 创建表结构...${NC}"
TABLES_CREATED=0
for category in core request credential model provider routing billing session audit tool system; do
    if [[ -d "$SCRIPT_DIR/schema/$category" ]]; then
        echo "  创建 $category 模块表..."
        for f in "$SCRIPT_DIR/schema/$category"/*.sql; do
            if [[ -f "$f" ]]; then
                exec_sql "$f"
                TABLES_CREATED=$((TABLES_CREATED + 1))
            fi
        done
    fi
done
echo -e "${GREEN}✓ 创建了 $TABLES_CREATED 张表${NC}"

# 创建函数
echo -e "${YELLOW}[4/7] 创建函数...${NC}"
FUNCTIONS_CREATED=0
for func_category in partition archive business; do
    if [[ -d "$SCRIPT_DIR/functions/$func_category" ]]; then
        for f in "$SCRIPT_DIR/functions/$func_category"/*.sql; do
            if [[ -f "$f" ]]; then
                exec_sql "$f"
                FUNCTIONS_CREATED=$((FUNCTIONS_CREATED + 1))
            fi
        done
    fi
done
echo -e "${GREEN}✓ 创建了 $FUNCTIONS_CREATED 个函数${NC}"

# 创建视图
echo -e "${YELLOW}[5/7] 创建视图...${NC}"
VIEWS_CREATED=0
if [[ -d "$SCRIPT_DIR/views" ]]; then
    for f in "$SCRIPT_DIR/views"/*.sql; do
        if [[ -f "$f" ]]; then
            exec_sql "$f"
            VIEWS_CREATED=$((VIEWS_CREATED + 1))
        fi
    done
fi
echo -e "${GREEN}✓ 创建了 $VIEWS_CREATED 个视图${NC}"

# 创建索引
echo -e "${YELLOW}[6/7] 创建索引...${NC}"
INDEXES_CREATED=0
if [[ -d "$SCRIPT_DIR/indexes" ]]; then
    for f in "$SCRIPT_DIR/indexes"/*.sql; do
        if [[ -f "$f" ]]; then
            exec_sql "$f"
            INDEXES_CREATED=$((INDEXES_CREATED + 1))
        fi
    done
fi
echo -e "${GREEN}✓ 创建了索引文件 $INDEXES_CREATED 个${NC}"

# 初始化数据
echo -e "${YELLOW}[7/7] 初始化数据...${NC}"
if [[ "$SKIP_SEED" == "false" ]]; then
    if [[ -d "$SCRIPT_DIR/seed" ]]; then
        for f in "$SCRIPT_DIR/seed"/*.sql; do
            if [[ -f "$f" ]]; then
                echo "  执行: $(basename "$f")"
                exec_sql "$f"
            fi
        done
        echo -e "${GREEN}✓ 初始化数据完成${NC}"
    fi
else
    echo -e "${YELLOW}⊘ 跳过初始化数据 (--skip-seed)${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ 数据库初始化完成!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "后续步骤:"
echo "1. 配置管理员密码"
echo "2. 配置提供商凭据"
echo "3. 验证数据库连接"
echo ""
echo "文档: deploy/sql/docs/MIGRATION_GUIDE.md"
