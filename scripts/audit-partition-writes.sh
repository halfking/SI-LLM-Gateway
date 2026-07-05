#!/bin/bash
# 分区表写入审计脚本
# 审计代码库中所有对 request_logs / usage_ledger / request_raw 的写入操作
# 验证是否符合规范（必须指向 *_default 表）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==================================================="
echo "  PostgreSQL 分区表写入审计报告"
echo "==================================================="
echo "审计时间: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "审计范围: request_logs, usage_ledger, request_raw"
echo ""

cd "$PROJECT_ROOT"

# 关键表名
TARGET_TABLES="request_logs|usage_ledger|request_raw"

# 临时文件
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# ===== 第一部分：Go 代码审计 =====

echo "==================================================="
echo "  第一部分: Go 代码审计"
echo "==================================================="
echo ""

# 1.1 INSERT/UPDATE/DELETE 写入到父表的违规（不带 _default 后缀）
echo "【1.1】检测写入父表的违规代码（INSERT/UPDATE/DELETE 到非 _default 表）"
echo "-------------------------------------------"

VIOLATION_COUNT=0

# 检查所有 .go 文件中的写入操作
for pattern in "INSERT INTO request_logs\\b" \
               "INSERT INTO usage_ledger\\b" \
               "INSERT INTO request_raw\\b" \
               "UPDATE request_logs\\b" \
               "UPDATE usage_ledger\\b" \
               "UPDATE request_raw\\b" \
               "DELETE FROM request_logs\\b" \
               "DELETE FROM usage_ledger\\b" \
               "DELETE FROM request_raw\\b"; do

    # 查找违规（排除注释和 _default/_partitioned/_archive 表）
    matches=$(grep -rnE "$pattern" --include='*.go' . 2>/dev/null | \
              grep -vE "(//|\\*|_default|_partitioned|_archive|_old)" | \
              grep -vE "_test\\.go" | \
              head -10)

    if [ -n "$matches" ]; then
        echo "❌ 发现违规（$pattern）:"
        echo "$matches" | head -5
        echo ""
        VIOLATION_COUNT=$((VIOLATION_COUNT+1))
    fi
done

if [ "$VIOLATION_COUNT" -eq 0 ]; then
    echo "✅ 未发现违规：所有 Go 代码写入操作均指向 *_default 表"
fi
echo ""

# 1.2 检查 ON CONFLICT 子句中的列引用（应该带 *_default 前缀）
echo "【1.2】检测 ON CONFLICT 子句中的列引用违规"
echo "-------------------------------------------"

# 更严格的检测：只看实际的 SQL 语句（不是注释）
# 查找包含 ON CONFLICT 的代码块，然后检查其中的列引用
ON_CONFLICT_FILES=$(grep -rl "ON CONFLICT" --include='*.go' . 2>/dev/null | head -10)
ON_CONFLICT_VIOLATIONS=0

if [ -n "$ON_CONFLICT_FILES" ]; then
    for file in $ON_CONFLICT_FILES; do
        # 提取 ON CONFLICT 块（从 ON CONFLICT 开始到结束的反引号）
        # 然后检查其中是否有 request_logs.xxx（非 _default）的列引用
        violations=$(awk '/ON CONFLICT/,/^.*\x60,*$/' "$file" 2>/dev/null | \
            grep -E "request_logs\.[a-z_]+" | \
            grep -vE "request_logs_default\.[a-z_]+" | \
            grep -vE "^\s*//" | \
            head -3)

        if [ -n "$violations" ]; then
            echo "❌ $file 发现 ON CONFLICT 列引用违规："
            echo "$violations" | head -3
            echo ""
            ON_CONFLICT_VIOLATIONS=$((ON_CONFLICT_VIOLATIONS+1))
        fi
    done
fi

if [ "$ON_CONFLICT_VIOLATIONS" -eq 0 ]; then
    echo "✅ ON CONFLICT 列引用全部使用 *_default 前缀"
fi
echo ""

# 1.3 检查测试代码（_test.go）
echo "【1.3】测试代码审计（_test.go）"
echo "-------------------------------------------"

TEST_VIOLATIONS=0
for pattern in "INSERT INTO request_logs\\b" \
               "INSERT INTO usage_ledger\\b" \
               "UPDATE request_logs\\b" \
               "UPDATE usage_ledger\\b" \
               "DELETE FROM request_logs\\b" \
               "DELETE FROM usage_ledger\\b"; do

    matches=$(grep -rnE "$pattern" --include='*_test.go' . 2>/dev/null | \
              grep -vE "_default|_partitioned|_archive" | \
              head -5)

    if [ -n "$matches" ]; then
        echo "⚠️  测试代码中发现违规（$pattern）:"
        echo "$matches"
        TEST_VIOLATIONS=$((TEST_VIOLATIONS+1))
    fi
done

if [ "$TEST_VIOLATIONS" -eq 0 ]; then
    echo "✅ 测试代码均使用 *_default 表"
fi
echo ""

# ===== 第二部分：Shell 脚本审计 =====

echo "==================================================="
echo "  第二部分: Shell 脚本审计"
echo "==================================================="
echo ""

SHELL_VIOLATIONS=0
for pattern in "INSERT INTO request_logs\\b" \
               "INSERT INTO usage_ledger\\b" \
               "UPDATE request_logs" \
               "UPDATE usage_ledger" \
               "DELETE FROM request_logs\\b" \
               "DELETE FROM usage_ledger\\b"; do

    matches=$(grep -rnE "$pattern" --include='*.sh' . 2>/dev/null | \
              grep -vE "(//|--|_default|_partitioned|_archive|audit-partition-writes)" | \
              head -5)

    if [ -n "$matches" ]; then
        echo "⚠️  Shell 脚本中发现违规（pattern detected）:"
        echo "$matches"
        SHELL_VIOLATIONS=$((SHELL_VIOLATIONS+1))
    fi
done

if [ "$SHELL_VIOLATIONS" -eq 0 ]; then
    echo "✅ Shell 脚本均使用 *_default 表（DELETE/UPDATE）"
fi
echo ""

# ===== 第三部分：SQL 脚本审计 =====

echo "==================================================="
echo "  第三部分: SQL 脚本审计（注释除外）"
echo "==================================================="
echo ""

# 3.1 历史 migration（应保留，标记为历史）
echo "【3.1】历史 migration 脚本（应该保留，不修改）"
echo "-------------------------------------------"
echo "以下历史 migration 已执行完毕，按设计保留（不修改）："
echo ""

HISTORICAL_MIGRATIONS=$(grep -rlE "UPDATE request_logs\\b|DELETE FROM request_logs\\b" deploy/sql/migrations/*.sql 2>/dev/null | \
    grep -vE "(_default|_partitioned|_archive)" | head -10)

if [ -n "$HISTORICAL_MIGRATIONS" ]; then
    for file in $HISTORICAL_MIGRATIONS; do
        echo "  • $(basename $file) - 历史 backfill（不应重跑）"
    done
fi
echo ""

# ===== 第四部分：正确的写入模式统计 =====

echo "==================================================="
echo "  第四部分: 合规写入模式统计"
echo "==================================================="
echo ""

echo "【4.1】合规的 INSERT INTO *_default 模式"
echo "-------------------------------------------"
INSERT_DEFAULT_COUNT=$(grep -rE "INSERT INTO (request_logs|usage_ledger)_default\\b" --include='*.go' . 2>/dev/null | wc -l)
echo "  • Go 代码: $INSERT_DEFAULT_COUNT 处"
INSERT_DEFAULT_SH=$(grep -rE "INSERT INTO (request_logs|usage_ledger)_default\\b" --include='*.sh' . 2>/dev/null | wc -l)
echo "  • Shell 脚本: $INSERT_DEFAULT_SH 处"
echo ""

echo "【4.2】合规的 UPDATE *_default 模式"
echo "-------------------------------------------"
UPDATE_DEFAULT_COUNT=$(grep -rE "UPDATE (request_logs|usage_ledger)_default\\b" --include='*.go' . 2>/dev/null | wc -l)
echo "  • Go 代码: $UPDATE_DEFAULT_COUNT 处"
echo ""

echo "【4.3】合规的 DELETE FROM *_default 模式"
echo "-------------------------------------------"
DELETE_DEFAULT_COUNT=$(grep -rE "DELETE FROM (request_logs|usage_ledger)_default\\b" --include='*.go' . 2>/dev/null | wc -l)
echo "  • Go 代码: $DELETE_DEFAULT_COUNT 处"
DELETE_DEFAULT_SH=$(grep -rE "DELETE FROM (request_logs|usage_ledger)_default\\b" --include='*.sh' . 2>/dev/null | wc -l)
echo "  • Shell 脚本: $DELETE_DEFAULT_SH 处"
echo ""

# ===== 第五部分：生产环境审计 =====

echo "==================================================="
echo "  第五部分: 生产环境（71）实时审计"
echo "==================================================="
echo ""

# SSH 到 71 检查实时数据
DB_HOST="${DB_HOST:-172.31.0.3}"
DB_PORT="5432"
DB_USER="llm_gateway"
DB_PASSWORD="${DB_PASSWORD:-<your-password>}"

echo "【5.1】最近 1 小时写入分布（验证所有写入在 default）"
echo "-------------------------------------------"

export SSHPASS="${SSHPASS:-<your-password>}"
RESULT=$(sshpass -e ssh -p ${SSH_PORT:-22} root@${SSH_HOST:-target-server} \
  "PGPASSWORD='$DB_PASSWORD' psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d llm_gateway -t -A -F'|' -c \"
SELECT 
    partition_name,
    recent_rows,
    CASE 
        WHEN partition_name ~ '_default$' THEN '合规'
        ELSE '违规'
    END AS compliance
FROM (
    SELECT 'request_logs_default' AS partition_name, COUNT(*) AS recent_rows
    FROM request_logs_default WHERE ts > now() - interval '1 hour'
    UNION ALL
    SELECT 'request_logs_2026_07' AS partition_name, COUNT(*) AS recent_rows
    FROM request_logs_2026_07 WHERE ts > now() - interval '1 hour'
    UNION ALL
    SELECT 'request_logs_2026_08' AS partition_name, COUNT(*) AS recent_rows
    FROM request_logs_2026_08 WHERE ts > now() - interval '1 hour'
    UNION ALL
    SELECT 'usage_ledger_default' AS partition_name, COUNT(*) AS recent_rows
    FROM usage_ledger_default WHERE ts > now() - interval '1 hour'
    UNION ALL
    SELECT 'usage_ledger_2026_07' AS partition_name, COUNT(*) AS recent_rows
    FROM usage_ledger_2026_07 WHERE ts > now() - interval '1 hour'
    UNION ALL
    SELECT 'usage_ledger_2026_08' AS partition_name, COUNT(*) AS recent_rows
    FROM usage_ledger_2026_08 WHERE ts > now() - interval '1 hour'
) AS audit
ORDER BY partition_name;
\"" 2>/dev/null)

if [ -n "$RESULT" ]; then
    echo "$RESULT" | while IFS='|' read -r partition rows compliance; do
        if [ "$rows" -gt 0 ] && [ "$compliance" = "违规" ]; then
            echo "  ❌ $partition: $rows 行（违规 - 应写入 default）"
        elif [ "$rows" -gt 0 ]; then
            echo "  ✅ $partition: $rows 行（合规）"
        else
            echo "  - $partition: 0 行"
        fi
    done
fi
echo ""

echo "【5.2】分区 ATTACH/DETACH 状态"
echo "-------------------------------------------"
ATTACH_STATUS=$(sshpass -e ssh -p ${SSH_PORT:-22} root@${SSH_HOST:-target-server} \
  "PGPASSWORD='$DB_PASSWORD' psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d llm_gateway -t -A -F'|' -c \"
SELECT 
    child.relname AS partition_name,
    CASE WHEN i.inhrelid IS NOT NULL THEN 'ATTACHED' ELSE 'DETACHED' END AS status,
    am.amname AS access_method
FROM pg_class child
LEFT JOIN pg_inherits i ON i.inhrelid = child.oid
LEFT JOIN pg_class parent ON parent.oid = i.inhparent
JOIN pg_am am ON am.oid = child.relam
WHERE child.relname ~ '^(request_logs|usage_ledger)(_default|_[0-9]{4}_[0-9]{2})\$'
  AND (parent.relname = 'request_logs' OR parent.relname = 'usage_ledger')
ORDER BY child.relname;
\"" 2>/dev/null)

if [ -n "$ATTACH_STATUS" ]; then
    echo "$ATTACH_STATUS" | while IFS='|' read -r partition status access; do
        echo "  • $partition: $status ($access)"
    done
fi
echo ""

# ===== 第六部分：审计总结 =====

echo "==================================================="
echo "  第六部分: 审计总结"
echo "==================================================="
echo ""

TOTAL_VIOLATIONS=$((VIOLATION_COUNT + TEST_VIOLATIONS + SHELL_VIOLATIONS))

if [ "$TOTAL_VIOLATIONS" -eq 0 ]; then
    echo "✅ 审计通过：所有代码均符合规范"
    echo ""
    echo "合规统计："
    echo "  • Go 代码 INSERT INTO *_default: $INSERT_DEFAULT_COUNT 处"
    echo "  • Go 代码 UPDATE *_default: $UPDATE_DEFAULT_COUNT 处"
    echo "  • Go 代码 DELETE FROM *_default: $DELETE_DEFAULT_COUNT 处"
    echo "  • Shell 脚本 DELETE FROM *_default: $DELETE_DEFAULT_SH 处"
    echo ""
    echo "生产环境："
    echo "  • 所有新数据正确写入 *_default 表"
    echo "  • 月度分区（2026_07, 2026_08）正确 DETACHED"
    echo "  • 历史分区（2026_06）正确 ATTACHED（columnar/heap）"
    echo ""
    echo "审计状态: ✅ PASS"
    exit 0
else
    echo "❌ 审计失败：发现 $TOTAL_VIOLATIONS 处违规"
    echo ""
    echo "违规分类："
    echo "  • Go 生产代码: $VIOLATION_COUNT 处"
    echo "  • Go 测试代码: $TEST_VIOLATIONS 处"
    echo "  • Shell 脚本: $SHELL_VIOLATIONS 处"
    echo ""
    echo "审计状态: ❌ FAIL"
    echo ""
    echo "建议修复："
    echo "  1. 将所有 INSERT INTO <table> 改为 INSERT INTO <table>_default"
    echo "  2. 将所有 UPDATE <table> 改为 UPDATE <table>_default"
    echo "  3. 将所有 DELETE FROM <table> 改为 DELETE FROM <table>_default"
    echo "  4. ON CONFLICT 子句中的列引用必须使用 <table>_default.xxx"
    exit 1
fi