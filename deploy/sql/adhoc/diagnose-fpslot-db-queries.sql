-- minimax-prod-1 fp_slot 问题诊断 SQL 查询
-- 连接到 184 数据库执行

\echo '=== 1. 检查凭据配置 ==='
SELECT 
    id,
    label,
    concurrency_limit,
    concurrency_limit_auto,
    fp_slot_limit,
    status,
    availability_state,
    manual_disabled,
    consecutive_failures
FROM credentials
WHERE id = 6;

\echo ''
\echo '=== 2. 最近 24 小时失败率趋势（按小时） ==='
SELECT 
    date_trunc('hour', ts) AS hour,
    COUNT(*) AS total_requests,
    COUNT(*) FILTER (WHERE success) AS successes,
    COUNT(*) FILTER (WHERE NOT success) AS failures,
    ROUND(COUNT(*) FILTER (WHERE NOT success)::numeric / COUNT(*) * 100, 2) AS failure_rate_pct,
    COUNT(*) FILTER (WHERE error_kind = 'no_candidates') AS no_candidates_count,
    COUNT(*) FILTER (WHERE error_kind = 'no_candidate') AS no_candidate_count,
    COUNT(*) FILTER (WHERE error_kind = 'transient') AS transient_count
FROM request_logs
WHERE credential_id = 6
  AND client_model = 'minimax-m3'
  AND ts > NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC
LIMIT 24;

\echo ''
\echo '=== 3. 并发峰值统计（最近 24 小时，按 peak_concurrent 降序） ==='
SELECT 
    window_start,
    total_calls,
    success_calls,
    failed_calls,
    ROUND(failed_calls::numeric / NULLIF(total_calls, 0) * 100, 2) AS failure_rate_pct,
    avg_concurrent,
    peak_concurrent,
    error_concurrent_count,
    error_network_count,
    error_other_count
FROM credential_model_call_history
WHERE credential_id = 6
  AND raw_model = 'minimax-m3'
  AND window_start > NOW() - INTERVAL '24 hours'
ORDER BY peak_concurrent DESC
LIMIT 20;

\echo ''
\echo '=== 4. Transient 错误详情（最近 24 小时） ==='
SELECT 
    ts,
    request_id,
    error_kind,
    request_status,
    latency_ms,
    LEFT(response_preview, 150) AS response_snippet
FROM request_logs
WHERE credential_id = 6
  AND client_model = 'minimax-m3'
  AND error_kind = 'transient'
  AND ts > NOW() - INTERVAL '24 hours'
ORDER BY ts DESC
LIMIT 30;

\echo ''
\echo '=== 5. Candidate failure logs 详细信息（最近 24 小时） ==='
SELECT 
    ts,
    credential_id,
    raw_model_name,
    error_kind,
    upstream_status_code,
    LEFT(upstream_response_preview, 200) AS upstream_error,
    attempt_count
FROM candidate_failure_logs
WHERE credential_id = 6
  AND raw_model_name ILIKE '%m3%'
  AND ts > NOW() - INTERVAL '24 hours'
ORDER BY ts DESC
LIMIT 50;

\echo ''
\echo '=== 6. 错误类型分布汇总（最近 24 小时） ==='
SELECT 
    error_kind,
    COUNT(*) AS error_count,
    ROUND(COUNT(*)::numeric / SUM(COUNT(*)) OVER () * 100, 2) AS percentage
FROM request_logs
WHERE credential_id = 6
  AND client_model = 'minimax-m3'
  AND NOT success
  AND ts > NOW() - INTERVAL '24 hours'
GROUP BY error_kind
ORDER BY error_count DESC;

\echo ''
\echo '=== 7. 整体成功率（最近 72 小时，按天） ==='
SELECT 
    date_trunc('day', ts) AS day,
    COUNT(*) AS total_requests,
    COUNT(*) FILTER (WHERE success) AS successes,
    ROUND(COUNT(*) FILTER (WHERE success)::numeric / COUNT(*) * 100, 2) AS success_rate_pct
FROM request_logs
WHERE credential_id = 6
  AND client_model = 'minimax-m3'
  AND ts > NOW() - INTERVAL '72 hours'
GROUP BY day
ORDER BY day DESC;

\echo ''
\echo '=== 诊断完成 ==='
\echo '如果 peak_concurrent < 20 但 failure_rate > 30%，说明瓶颈是 fp_slot 而非 concurrency_limit'
