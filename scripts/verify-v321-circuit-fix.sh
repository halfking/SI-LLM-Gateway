#!/bin/bash
# 验证 v3.2.1 circuit fix 效果
# 检查 circuit 是否按 model 隔离

set -e

REMOTE_HOST="root@14.103.174.71"
REMOTE_PORT="25022"

echo "=========================================="
echo "验证 v3.2.1 Circuit Fix"
echo "时间: $(date)"
echo "=========================================="

echo
echo "[1/4] 检查服务运行状态..."
ssh -p $REMOTE_PORT $REMOTE_HOST "
  docker ps | grep llm-gateway-go
  echo
  netstat -tlnp | grep llm-gateway | head -3
"

echo
echo "[2/4] 查看最近 request_logs (最近 5 分钟)..."
ssh -p $REMOTE_PORT $REMOTE_HOST "
  docker exec -i llm-gateway-pg-71-replica psql -U postgres -d llm_gateway_go -c \"
    SELECT 
      created_at,
      request_id,
      standardized_model,
      raw_model,
      status_message,
      SUBSTRING(reason, 1, 50) as reason_short
    FROM request_logs 
    WHERE created_at > NOW() - INTERVAL '5 minutes'
      AND (status_message LIKE '%circuit%' OR reason LIKE '%circuit%')
    ORDER BY created_at DESC 
    LIMIT 20;
  \"
"

echo
echo "[3/4] 查看 credential 6 的 model 绑定..."
ssh -p $REMOTE_PORT $REMOTE_HOST "
  docker exec -i llm-gateway-pg-71-replica psql -U postgres -d llm_gateway_go -c \"
    SELECT 
      credential_id,
      raw_model_name,
      outbound_model_name
    FROM credential_model_bindings
    WHERE credential_id = 6
    ORDER BY raw_model_name
    LIMIT 15;
  \"
"

echo
echo "[4/4] 监控日志 10 秒,查找 circuit 相关信息..."
timeout 10 ssh -p $REMOTE_PORT $REMOTE_HOST "docker logs -f llm-gateway-go 2>&1 | grep -i circuit" || true

echo
echo "=========================================="
echo "验证完成"
echo "=========================================="
echo
echo "检查要点:"
echo "1. 如果有 circuit_open,检查是否是不同 model"
echo "2. 预期:MiniMax-M2.7 失败不应影响 MiniMax-M3"
echo "3. circuit key 格式应该是: provider/credential/model"
echo
echo "手动检查 circuit stats:"
echo "  ssh -p $REMOTE_PORT $REMOTE_HOST 'docker exec llm-gateway-go wget -qO- http://localhost:8781/debug/circuits | jq'"
