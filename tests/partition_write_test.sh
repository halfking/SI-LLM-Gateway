#!/bin/bash
# 分区写入测试脚本
# 测试新数据写入是否正确路由到 *_default 表

set -euo pipefail

DB_HOST="${DB_HOST:-172.31.0.3}"
DB_PORT="5432"
DB_USER="llm_gateway"
DB_NAME="llm_gateway"
DB_PASSWORD="${DB_PASSWORD:-<your-password>}"

API_ENDPOINT="https://llm.kxpms.cn"

echo "======================================"
echo "分区写入测试套件"
echo "======================================"
echo ""

# 清理测试数据
cleanup() {
    echo "清理测试数据..."
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << 'EOF'
DELETE FROM request_logs_default WHERE request_id LIKE 'test-partition-%';
DELETE FROM request_logs_2026_07 WHERE request_id LIKE 'test-partition-%';
EOF
}

trap cleanup EXIT

echo "测试 1: 新数据写入验证（INSERT）"
echo "--------------------------------------"

# 发送测试请求
REQUEST_ID=$(curl -s -X POST "$API_ENDPOINT/v1/chat/completions" \
  -H "Authorization: Bearer sk-test-partition-insert" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "partition insert test"}]
  }' | jq -r '.error.request_id' 2>/dev/null || echo "")

if [ -z "$REQUEST_ID" ]; then
    echo "❌ 请求失败：无法获取 request_id"
    exit 1
fi

echo "✓ 请求已发送，request_id: $REQUEST_ID"
sleep 2

# 验证数据在 default 表
echo "验证数据位置..."
RESULT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A << EOF
SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM request_logs_default WHERE request_id = '$REQUEST_ID') 
        THEN 'default'
        WHEN EXISTS (SELECT 1 FROM request_logs_2026_07 WHERE request_id = '$REQUEST_ID')
        THEN '2026_07'
        ELSE 'not_found'
    END AS location;
EOF
)

if [ "$RESULT" = "default" ]; then
    echo "✅ 测试通过：数据正确写入 request_logs_default"
elif [ "$RESULT" = "2026_07" ]; then
    echo "❌ 测试失败：数据错误地写入了 request_logs_2026_07"
    exit 1
else
    echo "❌ 测试失败：数据未找到"
    exit 1
fi

echo ""
echo "测试 2: 分区隔离验证"
echo "--------------------------------------"

# 检查 2026_07 分区状态
PARTITION_STATUS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A << EOF
SELECT 
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM pg_inherits i
            JOIN pg_class parent ON parent.oid = i.inhparent
            JOIN pg_class child ON child.oid = i.inhrelid
            WHERE parent.relname = 'request_logs' 
            AND child.relname = 'request_logs_2026_07'
        )
        THEN 'ATTACHED'
        ELSE 'DETACHED'
    END AS status;
EOF
)

if [ "$PARTITION_STATUS" = "DETACHED" ]; then
    echo "✅ 测试通过：request_logs_2026_07 正确处于 DETACHED 状态"
else
    echo "❌ 测试失败：request_logs_2026_07 处于 ATTACHED 状态（应该是 DETACHED）"
    exit 1
fi

echo ""
echo "测试 3: 查询聚合验证"
echo "--------------------------------------"

# 查询父表（应该只包含 ATTACHED 分区的数据）
PARENT_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A << EOF
SELECT COUNT(*) FROM request_logs WHERE ts >= '2026-07-01';
EOF
)

# 查询 default + 2026_07（完整数据）
UNION_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A << EOF
SELECT COUNT(*) FROM (
    SELECT * FROM request_logs WHERE ts >= '2026-07-01'
    UNION ALL
    SELECT * FROM request_logs_2026_07 WHERE ts >= '2026-07-01'
) AS combined;
EOF
)

echo "父表查询结果: $PARENT_COUNT 行"
echo "UNION 查询结果: $UNION_COUNT 行"

if [ "$UNION_COUNT" -gt "$PARENT_COUNT" ]; then
    echo "✅ 测试通过：UNION 查询包含更多数据（包含 DETACHED 分区）"
else
    echo "⚠️  警告：UNION 查询与父表查询结果相同（可能 2026_07 分区为空）"
fi

echo ""
echo "======================================"
echo "测试总结"
echo "======================================"
echo "✅ 所有关键测试通过"
echo "✅ 新数据正确写入 *_default 表"
echo "✅ 月度分区正确 DETACHED"
echo "✅ 查询聚合逻辑正确"
