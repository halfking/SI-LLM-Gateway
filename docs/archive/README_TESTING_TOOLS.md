# LLM Gateway 测试工具套件

## 概述

本测试工具套件专门用于诊断和测试 Minimax-m3 模型的路由和节点状态问题。

## 主要问题追踪

1. **路由匹配问题**: 所有节点有效，但路由匹配不到可用节点
2. **节点切换问题**: 某个节点失败多次，没有及时从候选节点中移除
3. **Empty Response 问题**: NVIDIA NIM 节点频繁出现 empty_response 错误

## 工具清单

### 🔧 主要测试工具

| 脚本名称 | 用途 | 需要数据库 | 推荐使用场景 |
|---------|------|-----------|-------------|
| `test_71_complete.sh` | 完整测试套件（API+DB诊断） | 可选 | ✅ 主要工具，推荐首选 |
| `diagnose_nvidia_nim_empty_response.sh` | Empty response 深度诊断 | ✅ 必需 | 分析 empty_response 问题 |
| `diagnose_routing_issue.sh` | 路由问题诊断 | ✅ 必需 | 分析路由和节点状态 |
| `test_minimax_comprehensive.sh` | 综合路由测试 | ✅ 必需 | 多轮并发测试 |
| `test_minimax_api_only.sh` | 纯API测试 | ❌ 不需要 | 快速API层面测试 |

### 📋 文档

- `TEST_EXECUTION_SUMMARY.md` - 测试执行总结和发现
- `QUICK_START_TESTING.md` - 快速开始指南
- `README_TESTING_TOOLS.md` - 本文档

## 快速开始

### 方式1: 在71服务器上完整测试（推荐）

```bash
# 1. 连接到71服务器
ssh 192.168.1.71
cd /path/to/llm-gateway-go-2

# 2. 运行完整测试（会自动检测数据库配置）
./scripts/test_71_complete.sh

# 3. 查看结果
cat test_logs_71/test_*.log
```

### 方式2: 本地API测试

```bash
# 不需要数据库连接
./scripts/test_71_complete.sh
```

## 测试工具详解

### 1. test_71_complete.sh - 完整测试套件 ⭐

**功能**:
- ✅ API多轮请求测试
- ✅ 自动检测 empty_response
- ✅ 自动检测 no_candidate 错误
- ✅ 交替使用两个API key
- ✅ 记录详细日志
- ✅ 如有数据库，自动执行深度诊断

**参数**:
```bash
export TEST_ROUNDS=3              # 测试轮数（默认3）
export REQUESTS_PER_ROUND=5       # 每轮请求数（默认5）
export GATEWAY_URL="https://llm.kxpms.cn"  # 网关地址
export LLM_GATEWAY_DATABASE_URL="..."      # 数据库连接（可选）
```

**输出**:
- `test_logs_71/test_TIMESTAMP.log` - 测试主日志
- `test_logs_71/responses_TIMESTAMP.log` - 详细响应

**示例**:
```bash
# 快速测试
./scripts/test_71_complete.sh

# 压力测试
export TEST_ROUNDS=10
export REQUESTS_PER_ROUND=20
./scripts/test_71_complete.sh
```

### 2. diagnose_nvidia_nim_empty_response.sh - Empty Response 诊断

**功能**:
- 统计 empty_response 错误
- 按凭据分组分析
- 响应时间分布
- 对比正常响应时间
- 识别问题凭据

**使用**:
```bash
export LLM_GATEWAY_DATABASE_URL="..."
./scripts/diagnose_nvidia_nim_empty_response.sh minimax-m3

# 自定义回溯时间
export LOOKBACK_MINUTES=120
./scripts/diagnose_nvidia_nim_empty_response.sh
```

**输出重点**:
- Empty response 的平均响应时间
- 如果响应时间很短（<5s），说明不是超时问题
- 如果集中在某些凭据，需要检查这些凭据配置

### 3. diagnose_routing_issue.sh - 路由诊断

**功能**:
- 检查路由候选节点
- 分析凭据状态
- 检查质量门限过滤
- 探测状态检查

**使用**:
```bash
export LLM_GATEWAY_DATABASE_URL="..."
./scripts/diagnose_routing_issue.sh minimax-m3
```

### 4. test_minimax_comprehensive.sh - 综合测试

**功能**:
- 多轮测试
- 每轮前后检查路由状态
- 数据库节点状态检查
- 失败记录追踪

**使用**:
```bash
export API_KEY="your-key"
export GATEWAY_URL="https://llm.kxpms.cn"
export LLM_GATEWAY_DATABASE_URL="..."
export ROUNDS=5
export REQUESTS_PER_ROUND=10
./scripts/test_minimax_comprehensive.sh
```

## 测试结果解读

### ✅ 成功标志

- HTTP 200 响应
- 有效的响应内容
- 正常的token统计

### ❌ 问题标志

| 错误类型 | 说明 | 可能原因 |
|---------|------|---------|
| Empty Response | HTTP 200但内容为空 | 上游API问题、流式响应中断 |
| No Candidate | 无可用路由节点 | 所有节点不可用、质量门限过滤 |
| Timeout | 请求超时 | 网络延迟、节点响应慢 |
| Other Error | 其他HTTP错误 | API错误、认证问题等 |

### 📊 响应时间参考

- **正常**: < 5秒
- **可接受**: 5-10秒
- **较慢**: 10-20秒
- **异常**: > 20秒

## 常见问题排查

### 问题1: 路由匹配不到可用节点

**症状**: 请求返回 "no candidate" 错误

**排查步骤**:
```bash
# 1. 检查路由候选
./scripts/diagnose_routing_issue.sh minimax-m3

# 2. 查看凭据状态
psql "$LLM_GATEWAY_DATABASE_URL" -c "
SELECT c.id, c.label, c.status, v.is_routable, v.unavailable_reason
FROM credentials c
JOIN model_offers mo ON mo.credential_id = c.id
LEFT JOIN v_routable_credential_models v 
  ON v.credential_id = c.id AND v.raw_model_name = mo.raw_model_name
WHERE lower(mo.raw_model_name) = 'minimax-m3';"

# 3. 检查质量门限
# 如果 unavailable_reason 包含 "quality gate"，说明被成功率过滤了
```

**解决方案**:
- 检查凭据的 lifecycle_status 和 availability_state
- 查看是否被质量门限过滤（成功率过低）
- 检查 circuit_state 是否为 open（熔断）

### 问题2: 节点失败未及时切换

**症状**: 持续使用失败的节点

**排查步骤**:
```bash
# 1. 查看失败统计
psql "$LLM_GATEWAY_DATABASE_URL" -c "
SELECT 
    credential_id,
    COUNT(*) as total,
    COUNT(*) FILTER (WHERE success) as success,
    COUNT(*) FILTER (WHERE NOT success) as failures
FROM request_logs
WHERE client_model = 'minimax-m3'
  AND ts > NOW() - INTERVAL '10 minutes'
GROUP BY credential_id
ORDER BY failures DESC;"

# 2. 检查节点是否应该被标记为不可用
# 如果某节点失败率很高但 is_routable = true，说明有问题
```

**解决方案**:
- 检查探测机制是否正常工作
- 查看 model_probe_state 表
- 确认质量门限配置是否合理

### 问题3: Empty Response 频繁出现

**症状**: HTTP 200 但响应内容为空

**排查步骤**:
```bash
# 1. 运行专门诊断
./scripts/diagnose_nvidia_nim_empty_response.sh minimax-m3

# 2. 查看响应时间
# 如果响应时间很短，不是超时问题
# 如果响应时间接近30秒，可能是超时配置问题

# 3. 查看原始响应
cat test_logs_71/responses_*.log | grep -A 5 "Empty Response"
```

**可能原因**:
- 上游API返回空body
- 流式响应处理问题
- 网关超时设置过短
- 特定错误格式问题

## API Keys

测试使用的API密钥：
- `sk-1R7IBh2THq1Id2BDWOWHstpFu2oG09Qd1kgYn9hasxFcKZw7`
- `sk-1vH6C2I9pywyvUXaUXj4vdMZbeYVE5VB0fBYVgqA97JrltE9`

## 数据库查询示例

### 查看最近请求统计
```sql
SELECT 
    COUNT(*) as total,
    COUNT(*) FILTER (WHERE success) as success,
    COUNT(*) FILTER (WHERE error_kind = 'empty_response') as empty_resp,
    COUNT(*) FILTER (WHERE error_kind = 'no_candidate') as no_candidate,
    ROUND(AVG(duration_ms), 0) as avg_ms
FROM request_logs
WHERE client_model = 'minimax-m3'
  AND ts > NOW() - INTERVAL '1 hour';
```

### 按凭据分组统计
```sql
SELECT 
    c.id,
    c.label,
    COUNT(*) as requests,
    COUNT(*) FILTER (WHERE rl.success) as success,
    COUNT(*) FILTER (WHERE rl.error_kind = 'empty_response') as empty_resp,
    ROUND(AVG(rl.duration_ms), 0) as avg_ms
FROM request_logs rl
JOIN credentials c ON c.id = rl.credential_id
WHERE rl.client_model = 'minimax-m3'
  AND rl.ts > NOW() - INTERVAL '1 hour'
GROUP BY c.id, c.label
ORDER BY requests DESC;
```

### 响应时间分布
```sql
SELECT 
    CASE 
        WHEN duration_ms < 1000 THEN '<1s'
        WHEN duration_ms < 5000 THEN '1-5s'
        WHEN duration_ms < 10000 THEN '5-10s'
        WHEN duration_ms < 30000 THEN '10-30s'
        ELSE '>30s'
    END as range,
    COUNT(*) as count
FROM request_logs
WHERE client_model = 'minimax-m3'
  AND ts > NOW() - INTERVAL '1 hour'
GROUP BY range
ORDER BY MIN(duration_ms);
```

## 注意事项

1. **权限**: 确保脚本有执行权限 (`chmod +x scripts/*.sh`)
2. **数据库连接**: 在71服务器上运行可获得完整诊断信息
3. **日志查看**: 测试会生成详细日志，注意定期清理
4. **API限流**: 注意不要发送过多请求导致限流

## 下一步

1. 在71服务器上运行完整测试
2. 根据测试结果查看相应的诊断信息
3. 检查服务端日志获取更多细节
4. 根据发现调整配置或修复代码

## 支持

如需调整测试参数或添加新功能，请修改相应脚本的配置部分。
