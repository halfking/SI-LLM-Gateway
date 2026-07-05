#!/usr/bin/env bash
# 诊断 NVIDIA NIM 节点的 empty_response 问题
# 需要在71服务器上运行以访问数据库

set -e

# 配置
MODEL="${1:-minimax-m3}"
DB_URL="${LLM_GATEWAY_DATABASE_URL}"
LOOKBACK_MINUTES="${LOOKBACK_MINUTES:-60}"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}🔍 NVIDIA NIM Empty Response 诊断${NC}"
echo -e "${CYAN}=========================================${NC}"
echo -e "模型: ${BLUE}$MODEL${NC}"
echo -e "回溯时间: ${BLUE}${LOOKBACK_MINUTES}分钟${NC}"
echo ""

if [ -z "$DB_URL" ]; then
    echo -e "${RED}错误: 未设置 LLM_GATEWAY_DATABASE_URL${NC}"
    echo "请设置数据库连接："
    echo "  export LLM_GATEWAY_DATABASE_URL='postgresql://user:pass@host:port/dbname'"
    exit 1
fi

# 1. 检查 empty_response 错误的总体情况
echo -e "${YELLOW}=== 1. Empty Response 错误统计 ===${NC}"
psql "$DB_URL" <<SQL
SELECT 
    COUNT(*) as total_empty_response,
    COUNT(DISTINCT credential_id) as affected_credentials,
    MIN(ts) as first_occurrence,
    MAX(ts) as last_occurrence,
    ROUND(AVG(EXTRACT(EPOCH FROM (ts - LAG(ts) OVER (ORDER BY ts)))), 2) as avg_interval_seconds
FROM request_logs
WHERE error_kind = 'empty_response'
  AND ts > NOW() - INTERVAL '${LOOKBACK_MINUTES} minutes'
  AND lower(client_model) = lower('$MODEL');
SQL

echo ""
echo -e "${YELLOW}=== 2. 按凭据分组的 Empty Response 统计 ===${NC}"
psql "$DB_URL" <<SQL
SELECT 
    c.id as credential_id,
    c.label,
    p.display_name as provider,
    COUNT(*) FILTER (WHERE rl.error_kind = 'empty_response') as empty_response_count,
    COUNT(*) as total_requests,
    ROUND(COUNT(*) FILTER (WHERE rl.error_kind = 'empty_response')::numeric / NULLIF(COUNT(*), 0)::numeric * 100, 1) as empty_response_rate,
    ROUND(AVG(rl.duration_ms) FILTER (WHERE rl.error_kind = 'empty_response'), 0) as avg_empty_duration_ms,
    ROUND(AVG(rl.duration_ms) FILTER (WHERE rl.success = true), 0) as avg_success_duration_ms,
    MAX(rl.ts) FILTER (WHERE rl.error_kind = 'empty_response') as last_empty_response
FROM request_logs rl
JOIN credentials c ON c.id = rl.credential_id
JOIN providers p ON p.id = c.provider_id
WHERE rl.ts > NOW() - INTERVAL '${LOOKBACK_MINUTES} minutes'
  AND lower(rl.client_model) = lower('$MODEL')
GROUP BY c.id, c.label, p.display_name
HAVING COUNT(*) FILTER (WHERE rl.error_kind = 'empty_response') > 0
ORDER BY empty_response_count DESC;
SQL

echo ""
echo -e "${YELLOW}=== 3. Empty Response 的响应时间分布 ===${NC}"
psql "$DB_URL" <<SQL
SELECT 
    CASE 
        WHEN duration_ms < 1000 THEN '< 1s'
        WHEN duration_ms < 5000 THEN '1-5s'
        WHEN duration_ms < 10000 THEN '5-10s'
        WHEN duration_ms < 30000 THEN '10-30s'
        WHEN duration_ms < 60000 THEN '30-60s'
        ELSE '> 60s'
    END as duration_range,
    COUNT(*) as count,
    ROUND(AVG(duration_ms), 0) as avg_duration_ms,
    MIN(duration_ms) as min_duration_ms,
    MAX(duration_ms) as max_duration_ms
FROM request_logs
WHERE error_kind = 'empty_response'
  AND ts > NOW() - INTERVAL '${LOOKBACK_MINUTES} minutes'
  AND lower(client_model) = lower('$MODEL')
GROUP BY duration_range
ORDER BY MIN(duration_ms);
SQL

echo ""
echo -e "${YELLOW}=== 4. 检查 NVIDIA NIM 相关的凭据 ===${NC}"
psql "$DB_URL" <<SQL
SELECT 
    c.id,
    c.label,
    p.display_name as provider,
    c.status,
    c.lifecycle_status,
    c.availability_state,
    c.circuit_state,
    mo.available as model_offer_available,
    v.is_routable,
    v.unavailable_reason
FROM credentials c
JOIN providers p ON p.id = c.provider_id
JOIN model_offers mo ON mo.credential_id = c.id
LEFT JOIN v_routable_credential_models v
    ON v.credential_id = c.id
    AND v.raw_model_name = mo.raw_model_name
WHERE (lower(p.display_name) LIKE '%nvidia%' OR lower(c.label) LIKE '%nvidia%' OR lower(c.label) LIKE '%nim%')
  AND (lower(mo.raw_model_name) = lower('$MODEL') OR lower(mo.standardized_name) = lower('$MODEL'))
ORDER BY c.id;
SQL

echo ""
echo -e "${YELLOW}=== 5. 最近10个 Empty Response 的详细信息 ===${NC}"
psql "$DB_URL" <<SQL
SELECT 
    rl.ts,
    rl.request_id,
    c.label as credential,
    rl.duration_ms,
    rl.failure_stage,
    rl.failure_detail_code,
    LEFT(rl.response_preview, 100) as response_preview,
    rl.http_status_code
FROM request_logs rl
JOIN credentials c ON c.id = rl.credential_id
WHERE rl.error_kind = 'empty_response'
  AND rl.ts > NOW() - INTERVAL '${LOOKBACK_MINUTES} minutes'
  AND lower(rl.client_model) = lower('$MODEL')
ORDER BY rl.ts DESC
LIMIT 10;
SQL

echo ""
echo -e "${YELLOW}=== 6. 对比：Empty Response vs 正常响应的时间对比 ===${NC}"
psql "$DB_URL" <<SQL
SELECT 
    CASE 
        WHEN error_kind = 'empty_response' THEN 'Empty Response'
        WHEN success = true THEN 'Success'
        ELSE 'Other Error'
    END as result_type,
    COUNT(*) as count,
    ROUND(AVG(duration_ms), 0) as avg_duration_ms,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_ms), 0) as median_duration_ms,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_ms), 0) as p95_duration_ms,
    MIN(duration_ms) as min_duration_ms,
    MAX(duration_ms) as max_duration_ms
FROM request_logs
WHERE ts > NOW() - INTERVAL '${LOOKBACK_MINUTES} minutes'
  AND lower(client_model) = lower('$MODEL')
GROUP BY result_type
ORDER BY count DESC;
SQL

echo ""
echo -e "${YELLOW}=== 7. 检查是否有超时配置问题 ===${NC}"
psql "$DB_URL" <<SQL
-- 查看配置的超时设置（如果有这样的表）
SELECT 
    c.id,
    c.label,
    c.timeout_seconds,
    c.read_timeout_seconds
FROM credentials c
JOIN providers p ON p.id = c.provider_id
JOIN model_offers mo ON mo.credential_id = c.id
WHERE (lower(mo.raw_model_name) = lower('$MODEL') OR lower(mo.standardized_name) = lower('$MODEL'))
  AND (c.timeout_seconds IS NOT NULL OR c.read_timeout_seconds IS NOT NULL)
ORDER BY c.id;
SQL

echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}📊 诊断总结${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""
echo -e "${YELLOW}关键发现：${NC}"
echo -e "1. 如果 Empty Response 的平均响应时间 ${RED}很短${NC}（< 5s），说明不是超时问题"
echo -e "2. 如果 Empty Response 集中在某些凭据，需要检查这些凭据的配置"
echo -e "3. 如果响应时间接近30秒，可能是客户端或网关的超时设置问题"
echo ""
echo -e "${YELLOW}建议检查：${NC}"
echo -e "- 查看服务端日志中对应 request_id 的详细错误信息"
echo -e "- 检查 NVIDIA NIM 节点的实际响应"
echo -e "- 验证网关的超时配置是否合理"
echo -e "- 查看是否有网络层面的连接问题"
