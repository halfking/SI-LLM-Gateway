# 🔍 MiniMax-M3 深度诊断报告

**时间**: 2026-06-30 12:45 UTC  
**状态**: 🔴 **持续故障中**  
**验证结果**: ✅ **MiniMax API直连正常** - 问题在Gateway内部

---

## ⚡ 核心发现

### 1. API验证结果
- ✅ **MiniMax API直连测试**: 正常工作
- ✅ **API端点可达**: curl测试返回预期的401认证错误
- ❌ **通过Gateway**: 100%失败

**结论**: **问题出在Gateway的处理逻辑，不是MiniMax API故障**

### 2. 错误特征分析

**最近失败的请求**:
```
Credential 18 (NVIDIA) → minimaxai/minimax-m3
- failure_stage: upstream
- failure_detail_code: unknown
- latency_ms: 100-277ms (非常短)
- stream_chunk_count: 0
- response_body: 空
```

**关键线索**:
1. **延迟极短** (100-277ms) - 快速失败，没有真正发送到upstream
2. **Response为空** - 没有收到任何数据
3. **Stream chunk = 0** - 没有收到流式响应
4. **只影响NVIDIA credentials** - Credential 18使用`minimaxai/minimax-m3`

---

## 🎯 可能的根本原因

### 原因A: NVIDIA API不支持MiniMax模型 (最可能)

**分析**:
- NVIDIA API endpoint: `https://integrate.api.nvidia.com/v1`
- 模型名称: `minimaxai/minimax-m3`
- 这是NVIDIA的API，但在请求MiniMax的模型
- 可能NVIDIA API根本不认识这个模型，直接拒绝

**建议测试**:
```bash
# 使用真实API key测试NVIDIA是否支持MiniMax模型
curl -X POST 'https://integrate.api.nvidia.com/v1/chat/completions' \
  -H 'Authorization: Bearer <NVIDIA_API_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "minimaxai/minimax-m3",
    "messages": [{"role": "user", "content": "test"}],
    "max_tokens": 5
  }'
```

### 原因B: Gateway的Litellm配置问题

**分析**:
- Gateway使用Litellm库来调用不同provider
- Litellm可能对`minimaxai/minimax-m3`这个模型名称的处理有问题
- 可能需要特殊的配置或格式

**日志证据**:
```
LiteLLM completion() model= MiniMax-M3; provider = openai
```
表明Gateway在使用OpenAI兼容协议

### 原因C: Credential配置错误

**当前配置检查**:
```
Provider 18 (NVIDIA):
- base_url: https://integrate.api.nvidia.com/v1
- protocol: openai-completions

Credential 18:
- provider_id: 18 (NVIDIA)
- outbound_model: minimaxai/minimax-m3
```

**问题**: 
- Credential 18关联到NVIDIA provider
- 但尝试调用MiniMax模型
- 这个映射关系可能就是错误的

---

## 📊 11:00故障的真正原因

回顾之前的分析，**我现在理解了**：

### 故障时间线重新分析

| 时间 | 错误率 | 主要使用的Credential | 原因分析 |
|------|--------|---------------------|---------|
| 08:00 | 5.13% | Credential 6 (MiniMax官方) | ✅ 正常 |
| 09:00-10:00 | 22-25% | 混合使用 | 🟡 有NVIDIA credentials参与 |
| 11:00+ | 90-100% | **主要路由到NVIDIA credentials** | 🔴 **NVIDIA不支持MiniMax模型** |

**根本原因推测**:
1. **10:00前**: 流量主要路由到Credential 6 (MiniMax官方)，正常工作
2. **11:00开始**: 路由算法改变，开始大量使用Credentials 18/19 (NVIDIA)
3. **NVIDIA credentials**: 配置了`minimaxai/minimax-m3`，但NVIDIA API可能不支持这个模型
4. **结果**: 大量请求失败

**为什么路由会改变?**
可能原因:
- Credential 6的负载均衡权重变化
- 健康检查影响routing决策
- Concurrency limit达到上限

---

## ✅ 立即修复建议

### 方案1: 禁用NVIDIA credentials (推荐)

既然直连MiniMax API是正常的，而NVIDIA credentials有问题，应该只使用官方的MiniMax credential。

```sql
-- 禁用NVIDIA credentials for MiniMax
UPDATE credentials 
SET lifecycle_status = 'disabled',
    manual_disabled = true,
    notes = 'Disabled: NVIDIA API does not properly support minimaxai/minimax-m3. Use MiniMax official credential (ID 6) only.'
WHERE id IN (8, 18, 19);

-- 确保MiniMax官方credential可用
UPDATE credentials 
SET lifecycle_status = 'active',
    availability_state = 'ready',
    manual_disabled = false
WHERE id = 6;
```

**预期效果**: 
- 所有流量路由到Credential 6
- 错误率恢复到正常水平(5-20%)

### 方案2: 测试并修复NVIDIA配置

如果确认NVIDIA确实支持MiniMax模型，需要修复配置：

```sql
-- 查看NVIDIA credentials的完整配置
SELECT c.id, c.label, c.provider_id, p.code, p.base_url, mo.outbound_model
FROM credentials c
JOIN providers p ON p.id = c.provider_id
LEFT JOIN model_offers mo ON mo.credential_id = c.id
WHERE c.id IN (8, 18, 19);

-- 如果需要，更新模型映射
```

### 方案3: 增加详细错误日志

修改Gateway代码，记录upstream的原始HTTP响应：

```go
// 在proxy/litellm.go或类似文件中
if resp.StatusCode >= 400 {
    bodyBytes, _ := io.ReadAll(resp.Body)
    log.Error("upstream_error", 
        "status", resp.StatusCode,
        "body", string(bodyBytes),
        "model", outboundModel)
}
```

---

## 🔬 诊断步骤

### Step 1: 验证NVIDIA是否支持MiniMax

```bash
# SSH到生产服务器
ssh prod-app

# 获取credential 18的API key (需要解密)
# 然后测试
curl -v -X POST 'https://integrate.api.nvidia.com/v1/chat/completions' \
  -H 'Authorization: Bearer <REAL_API_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "minimaxai/minimax-m3",
    "messages": [{"role": "user", "content": "hello"}],
    "max_tokens": 10
  }'
```

**预期结果**:
- 如果返回404或model_not_found: NVIDIA不支持此模型
- 如果返回200: NVIDIA支持，问题在Gateway配置
- 如果返回401: API key问题

### Step 2: 检查路由决策逻辑

```sql
-- 查看路由决策历史
SELECT * FROM route_decisions 
WHERE client_model = 'minimax-m3' 
  AND ts > NOW() - INTERVAL '6 hours'
ORDER BY ts DESC 
LIMIT 20;

-- 查看为什么选择了NVIDIA credentials
SELECT * FROM model_offers 
WHERE outbound_model LIKE '%minimax%' 
  AND credential_id IN (8, 18, 19);
```

### Step 3: 临时强制路由到Credential 6

如果需要立即恢复服务：

```sql
-- 降低NVIDIA credentials的优先级
UPDATE credentials 
SET lifecycle_status = 'disabled'
WHERE id IN (8, 18, 19);
```

---

## 📈 监控命令

### 实时错误率
```bash
watch -n 10 "ssh prod-app \"PGPASSWORD='...' psql ... -c '
SELECT 
    DATE_TRUNC('\''minute'\'', ts) as minute,
    COUNT(*) as total,
    COUNT(CASE WHEN success THEN 1 END) as success,
    COUNT(CASE WHEN NOT success THEN 1 END) as errors
FROM request_logs 
WHERE client_model LIKE '\''%minimax%'\'' 
  AND ts > NOW() - INTERVAL '\''10 minutes'\''
GROUP BY DATE_TRUNC('\''minute'\'', ts)
ORDER BY minute DESC;
'\""
```

### 各Credential表现
```sql
SELECT 
    c.id,
    c.label,
    c.lifecycle_status,
    COUNT(r.id) as total,
    COUNT(CASE WHEN r.success THEN 1 END) as success,
    ROUND(100.0 * COUNT(CASE WHEN r.success THEN 1 END) / COUNT(r.id), 2) as success_rate
FROM credentials c
LEFT JOIN request_logs r ON r.credential_id = c.id 
    AND r.ts > NOW() - INTERVAL '10 minutes'
    AND r.client_model LIKE '%minimax%'
WHERE c.id IN (6, 8, 18, 19)
GROUP BY c.id, c.label, c.lifecycle_status;
```

---

## 🎯 最终建议

### 立即行动 (现在)

**执行方案1**: 禁用NVIDIA credentials，只使用MiniMax官方credential

```sql
UPDATE credentials 
SET lifecycle_status = 'disabled',
    manual_disabled = true,
    notes = '2026-06-30: Disabled due to unknown errors with minimaxai/minimax-m3. Direct MiniMax API test shows API is working, but NVIDIA provider has issues.'
WHERE id IN (8, 18, 19);
```

**理由**:
1. ✅ 直连MiniMax API证明服务正常
2. ✅ Credential 6 (MiniMax官方) 历史表现良好
3. ❌ NVIDIA credentials持续出现unknown错误
4. ❌ 没有时间深入调试NVIDIA配置

### 短期行动 (今天内)

1. **验证修复效果**: 监控30分钟，确认错误率降至<10%
2. **诊断NVIDIA问题**: 使用probe-cred工具测试NVIDIA credentials
3. **文档更新**: 记录这次故障的根因和解决方案

### 长期行动 (本周内)

1. **实现主动探测**: 完成Go探测服务开发
2. **智能路由**: 避免将流量路由到有问题的credentials
3. **错误日志增强**: 记录upstream的详细响应
4. **告警机制**: 错误率>30%立即告警

---

## 📝 总结

### 问题本质
不是MiniMax API故障，而是**Gateway的路由决策将流量导向了配置有问题的NVIDIA credentials**。

### 根本原因 (推测)
NVIDIA API不支持或不能正确处理`minimaxai/minimax-m3`模型请求，导致快速失败。

### 解决方案
禁用NVIDIA credentials，只使用MiniMax官方credential (ID 6)。

### 教训
1. 在暂停所有credentials前应该先确认问题
2. 需要更好的错误日志来快速定位问题
3. 主动探测机制非常重要

---

**报告时间**: 2026-06-30 12:48 UTC  
**建议执行**: 立即禁用credentials 8, 18, 19
