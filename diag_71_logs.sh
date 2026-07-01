#!/bin/bash
# 在 192.168.1.71 上直接跑这一段（不要脚本），把输出贴回来
# 用法：ssh root@192.168.1.71  → 粘贴以下所有行  →  复制粘贴输出

echo "=========== 1. 找 PG 容器和凭据 ==========="
docker ps --format 'table {{.Names}}\t{{.Image}}' | grep -iE 'postgres|pg' || true
echo "--- /opt/llm-gateway-go 下的 .env ---"
ls -la /opt/llm-gateway-go/.env* 2>/dev/null || ls -la /opt/llm-gateway-go/*.env 2>/dev/null || echo "no env file in /opt/llm-gateway-go"
find /opt/llm-gateway-go -maxdepth 3 -name '.env*' 2>/dev/null | head -5
echo "--- LLM_GATEWAY_DB_DSN / DB_HOST 等环境变量（从运行中的 gateway 容器取）---"
GW_CTN=$(docker ps --filter "name=gateway" --format "{{.Names}}" | head -1)
echo "Gateway container: ${GW_CTN:-<未找到>}"
if [ -n "$GW_CTN" ]; then
  docker exec "$GW_CTN" env 2>/dev/null | grep -iE 'DB_|POSTGRES|PG_|REDIS_' | head -20
fi

echo
echo "=========== 2. request_logs 是否有最新数据（不限租户） ==========="
# 用 gateway 容器里的 PG 客户端（如果有），或者外部 psql
PG_CTN=$(docker ps --format '{{.Names}}' | grep -iE 'postgres|^pg_' | head -1)
echo "PG container: ${PG_CTN:-<未找到>}"
if [ -n "$PG_CTN" ]; then
  # 尝试用 gateway 容器里配置的 DSN
  DSN=$(docker exec "$GW_CTN" sh -c 'echo $LLM_GATEWAY_DB_DSN' 2>/dev/null)
  if [ -z "$DSN" ]; then
    # fallback: 用 postgres 容器默认用户
    docker exec -e PGPASSWORD=postgres "$PG_CTN" psql -U postgres -d llm_gateway -c "
      SELECT now() AS db_now,
             MAX(ts) AS latest_request_ts,
             MAX(ts) > now() - interval '5 minutes' AS has_5min_data,
             COUNT(*) FILTER (WHERE ts > now() - interval '1 hour') AS last_1h,
             COUNT(*) FILTER (WHERE ts > now() - interval '5 minutes') AS last_5m
      FROM request_logs;
    " 2>&1 | head -20
  else
    echo "DSN=$DSN"
    docker exec "$GW_CTN" psql "$DSN" -c "
      SELECT now() AS db_now,
             MAX(ts) AS latest_request_ts,
             MAX(ts) > now() - interval '5 minutes' AS has_5min_data,
             COUNT(*) FILTER (WHERE ts > now() - interval '1 hour') AS last_1h,
             COUNT(*) FILTER (WHERE ts > now() - interval '5 minutes') AS last_5m
      FROM request_logs;
    " 2>&1 | head -20
  fi
fi

echo
echo "=========== 3. gateway 日志中的 telemetry 错误 ==========="
if [ -n "$GW_CTN" ]; then
  echo "--- 查找 'telemetry request db persist failed' ---"
  docker logs --since 10m "$GW_CTN" 2>&1 | grep -i "telemetry request db persist failed" | tail -10
  echo "--- 查找 'telemetry request sync persist failed' ---"
  docker logs --since 10m "$GW_CTN" 2>&1 | grep -i "telemetry request sync persist failed" | tail -10
  echo "--- 查找 'dropping request log' / 'request_logs' / 'postgres disabled' ---"
  docker logs --since 10m "$GW_CTN" 2>&1 | grep -iE "dropping|request_logs|postgres disabled|ensureRequestLogSchema" | tail -20
  echo "--- gateway 启动 banner（取最近 50 行） ---"
  docker logs --since 30m "$GW_CTN" 2>&1 | grep -E '"msg":"(postgres connected|postgres disabled|ensureRequestLogSchema|model_policy|API key authentication|routing executor|Phase 2|Phase 3|Checkpoint)' | tail -30
fi

echo
echo "=========== 4. listLogs 直接 SQL（用你登录的 token 调一次） ==========="
echo "在浏览器登录后，从 DevTools Network 找到 /api/logs 请求 URL，把 from/to 拼上立刻复现："
echo "  curl -s 'https://llm.kxpms.cn/api/logs?from=$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)&to=$(date -u +%Y-%m-%dT%H:%M:%SZ)&page_size=20' -H 'Authorization: Bearer <你的token>' | head -200"
echo "如果直接把 from 改成更早的 7 天前能看到数据，就是默认 24h 窗口的问题。"

echo
echo "=========== 5. 当前时间 + 网关时间对照（确认时区一致） ==========="
echo "Host: $(date -u +%FT%TZ)"
if [ -n "$GW_CTN" ]; then
  echo "Gateway container: $(docker exec $GW_CTN date -u +%FT%TZ 2>&1)"
fi