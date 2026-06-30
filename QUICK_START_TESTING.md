# 快速开始测试指南

## 在71服务器上执行测试（推荐）

### 步骤1: 连接到71服务器
```bash
ssh 192.168.1.71
cd /path/to/llm-gateway-go-2
```

### 步骤2: 设置环境变量
```bash
# 数据库连接（从服务配置中获取）
export LLM_GATEWAY_DATABASE_URL="postgresql://user:pass@host:port/llm_gateway_production"

# 或者让脚本自动检测
# 脚本会尝试从 /etc/systemd/system/llm-gateway.service 中读取
```

### 步骤3: 运行完整测试
```bash
# 使用默认参数（3轮，每轮5个请求）
./scripts/test_71_complete.sh

# 或自定义参数
export TEST_ROUNDS=5
export REQUESTS_PER_ROUND=10
./scripts/test_71_complete.sh
```

### 步骤4: 查看结果
```bash
# 查看测试日志
ls -lt test_logs_71/
cat test_logs_71/test_*.log | tail -50

# 查看详细响应
cat test_logs_71/responses_*.log
```

### 步骤5: 运行诊断（如果发现问题）
```bash
# Empty response 诊断
./scripts/diagnose_nvidia_nim_empty_response.sh minimax-m3

# 路由问题诊断
./scripts/diagnose_routing_issue.sh minimax-m3
```

## 在本地执行测试（仅API层面）

如果无法连接71服务器，可以在本地测试API：

```bash
cd /path/to/llm-gateway-go-2

# 运行简化测试
./scripts/test_71_complete.sh

# 查看结果
cat test_logs_71/test_*.log
cat test_logs_71/responses_*.log
```

**注意**: 本地测试不包含数据库诊断部分。

## 快速检查命令

### 检查最近的empty_response
```bash
psql "$LLM_GATEWAY_DATABASE_URL" -c "
SELECT COUNT(*), MAX(ts) as last_occurrence
FROM request_logs
WHERE error_kind = 'empty_response'
  AND client_model = 'minimax-m3'
  AND ts > NOW() - INTERVAL '1 hour';
"
```

### 检查路由候选节点
```bash
psql "$LLM_GATEWAY_DATABASE_URL" -c "
SELECT c.id, c.label, v.is_routable, v.unavailable_reason
FROM credentials c
JOIN model_offers mo ON mo.credential_id = c.id
LEFT JOIN v_routable_credential_models v 
  ON v.credential_id = c.id AND v.raw_model_name = mo.raw_model_name
WHERE lower(mo.raw_model_name) = 'minimax-m3'
ORDER BY c.id;
"
```

### 实时监控测试
```bash
# 终端1: 运行测试
./scripts/test_71_complete.sh

# 终端2: 监控服务日志
tail -f /var/log/llm-gateway/app.log

# 终端3: 监控数据库
watch -n 2 "psql \$LLM_GATEWAY_DATABASE_URL -c 'SELECT COUNT(*) as total, COUNT(*) FILTER (WHERE success) as success FROM request_logs WHERE ts > NOW() - INTERVAL '\''5 minutes'\'''"
```
