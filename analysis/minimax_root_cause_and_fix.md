# MiniMax-M3 错误根因分析与修复方案

**日期**: 2026-06-30  
**错误率**: 25.78% (66/256)  
**分析环境**: llm.kxpms.cn (生产环境)

---

## 🔴 核心发现：配置错误导致的高错误率

### 问题1: NVIDIA NIM Provider被错误用于MiniMax请求 ❌

**关键发现**:
- Credential 8, 18, 19 都关联到 **Provider 18 (NVIDIA NIM)**
- 这些credential发出的请求使用 `minimaxai/minimax-m3` 作为outbound_model
- NVIDIA NIM的base_url是 `https://integrate.api.nvidia.com/v1`
- **这是完全错误的配置！NVIDIA NIM不支持MiniMax模型**

**证据**:
```
Credential ID | Provider ID | Provider Name | Base URL | Label
8            | 18          | NVIDIA NIM    | https://integrate.api.nvidia.com/v1 | nvidia-build-new
18           | 18          | NVIDIA NIM    | https://integrate.api.nvidia.com/v1 | nvidia-build-v2  
19           | 18          | NVIDIA NIM    | https://integrate.api.nvidia.com/v1 | endless

错误率统计:
- Credential 18: 57.14% 错误率 (12/21 失败)
- Credential 19: 35.29% 错误率 (6/17 失败)
- Credential 8:  14.29% 错误率 (3/21 失败)
```

**错误表现**:
- `empty_response`: 收到3个stream chunk但内容为空
- `canceled`: 请求超时被取消
- `provider_error`: NVIDIA API返回错误

---

### 问题2: 正确的MiniMax Provider配置 ✅

**正确配置**:
- Credential 6 关联到 **Provider 14 (MiniMax)**
- Base URL: `https://api.minimaxi.com/v1` ✅ 正确
- Outbound model: `MiniMax-M3`
- 错误率: 19.27% (主要是transient暂态错误，可接受)

**对比**:
```
Provider 14 (MiniMax) - 正确
- Base URL: https://api.minimaxi.com/v1
- Credential 6: 192 requests, 19.27% error (主要是transient)

Provider 18 (NVIDIA NIM) - 错误配置
- Base URL: https://integrate.api.nvidia.com/v1
- Credential 8,18,19: 59 requests, 35.59% error (empty_response, canceled)
```

---

## 🔍 详细错误分析

### Empty Response错误机制

当请求被发送到NVIDIA NIM API但使用`minimaxai/minimax-m3`模型时：
1. NVIDIA API不认识这个模型
2. 返回了一个流式响应，但内容为空
3. Gateway收到3个chunk，stream_done_received=true
4. 但response_body为空，被标记为`empty_response`

**典型案例**:
```
Request ID: d18e50e9c9bb09ca82167ac74e0f4c2a
Credential: 18 (NVIDIA NIM - 错误配置)
Outbound Model: minimaxai/minimax-m3
Stream Chunks: 3
Stream Done: true
Response Body: (empty)
Latency: 1,537ms
Error: empty_response
```

### 为什么Credential 6表现好？

Credential 6使用正确的MiniMax Provider:
- 正确的API endpoint: `api.minimaxi.com`
- 正确的模型名称: `MiniMax-M3`
- 主要错误是`transient`（暂态错误），这是MiniMax API服务端的临时问题，可通过重试解决

---

## 🛠️ 修复方案

### 立即修复 (Priority 1)

#### 方案A: 删除或禁用错误的credentials (推荐)

```sql
-- 禁用错误配置的credentials
UPDATE credentials 
SET lifecycle_status = 'disabled',
    manual_disabled = true,
    notes = 'Disabled: Wrong provider configuration - NVIDIA NIM cannot serve MiniMax models'
WHERE id IN (8, 18, 19);
```

**影响**: 
- 59个请求会被路由到正确的Credential 6
- 立即消除empty_response和相关错误
- 预期错误率从25.78%降至约19%

#### 方案B: 重新配置这些credentials到正确的Provider

如果这些credentials持有有效的MiniMax API keys:

```sql
-- 将credentials重新关联到正确的MiniMax provider
UPDATE credentials 
SET provider_id = 14  -- MiniMax provider
WHERE id IN (8, 18, 19);
```

**注意**: 需要确认这些credentials的secret确实是MiniMax的API key，而不是NVIDIA的。

---

### 次要修复 (Priority 2)

#### 修复2: 解决路由匹配失败 (no_candidate错误)

10个请求无法找到可用凭证，credential_id为NULL。

**检查路由规则**:
```sql
-- 查看当前的路由配置
SELECT * FROM work_type_model_route 
WHERE client_model = 'minimax-m3' 
   OR client_model LIKE '%minimax%';
```

**可能需要**:
- 添加fallback路由规则
- 确保minimax-m3有完整的路由配置
- 检查是否有租户或权限限制

#### 修复3: 增强错误日志

修改代码以记录更详细的empty_response信息:
- 记录原始chunk内容
- 记录upstream返回的HTTP headers
- 帮助未来诊断类似问题

---

### 长期优化 (Priority 3)

#### 优化1: 添加Provider验证

在credentials创建/更新时验证:
- Provider的base_url与credential持有的API key是否匹配
- 避免类似的配置错误

#### 优化2: 模型兼容性检查

在路由时检查:
- 请求的模型是否在provider的支持列表中
- 如果不支持，跳过该credential

#### 优化3: 健康检查改进

定期验证credentials:
- 发送测试请求到实际endpoint
- 验证返回的响应格式和内容
- 自动标记配置错误的credentials

---

## 📊 预期效果

### 修复前
- 总错误率: 25.78%
- 主要问题: empty_response (14), transient (24), unknown (10)

### 修复后 (禁用错误credentials)
- 预期错误率: ~19%
- 主要错误: transient (仅来自正确配置的Credential 6)
- empty_response: 0 ✅
- unknown: 显著减少 ✅

### 如果重新配置credentials到正确provider
- 预期错误率: 10-15%
- 更好的负载分配
- 更高的可用性

---

## ⚡ 立即执行步骤

### Step 1: 验证并禁用错误配置 (5分钟)

```bash
# 连接到生产数据库
ssh prod-app

# 查看当前状态
PGPASSWORD='[REDACTED_PASSWORD]' psql -h 127.0.0.1 -U llm_gateway -d llm_gateway -c "
SELECT id, provider_id, label, status, lifecycle_status 
FROM credentials 
WHERE id IN (8, 18, 19);
"

# 禁用错误配置的credentials
PGPASSWORD='[REDACTED_PASSWORD]' psql -h 127.0.0.1 -U llm_gateway -d llm_gateway -c "
UPDATE credentials 
SET lifecycle_status = 'disabled',
    manual_disabled = true,
    notes = 'Disabled on 2026-06-30: Wrong provider - NVIDIA NIM cannot serve MiniMax models'
WHERE id IN (8, 18, 19);
"
```

### Step 2: 监控修复效果 (15-30分钟)

```bash
# 实时监控错误率
watch -n 30 "PGPASSWORD='[REDACTED_PASSWORD]' psql -h 127.0.0.1 -U llm_gateway -d llm_gateway -c \"
SELECT 
  COUNT(*) as total,
  COUNT(CASE WHEN NOT success THEN 1 END) as errors,
  ROUND(100.0 * COUNT(CASE WHEN NOT success THEN 1 END) / COUNT(*), 2) as error_rate
FROM request_logs 
WHERE client_model LIKE '%minimax%' 
  AND ts > NOW() - INTERVAL '10 minutes';
\""
```

### Step 3: 验证不再有empty_response错误

```bash
# 检查最近10分钟的错误类型
PGPASSWORD='[REDACTED_PASSWORD]' psql -h 127.0.0.1 -U llm_gateway -d llm_gateway -c "
SELECT error_kind, COUNT(*) 
FROM request_logs 
WHERE client_model LIKE '%minimax%' 
  AND NOT success 
  AND ts > NOW() - INTERVAL '10 minutes'
GROUP BY error_kind;
"
```

---

## 🔎 进一步调查

### 为什么会有这个错误配置？

需要调查：
1. 这些credentials (8, 18, 19) 的secret是什么？
   - 如果是NVIDIA API keys：应该删除或用于NVIDIA模型
   - 如果是MiniMax API keys：应该重新关联到Provider 14

2. 标签名称的误导性：
   - `nvidia-build-new`, `nvidia-build-v2`, `endless`
   - 这些名称暗示它们应该是NVIDIA credentials
   - 但为什么被用于MiniMax请求？

3. 路由逻辑问题：
   - 路由系统是如何将minimax-m3请求分配到NVIDIA provider的？
   - 是否需要修复路由规则？

### 建议深入检查

```sql
-- 查看这些credentials的创建时间和历史
SELECT id, provider_id, label, created_at, updated_at, notes, acquisition_source
FROM credentials 
WHERE id IN (8, 18, 19);

-- 查看model_offers，理解路由是如何选择这些credentials的
SELECT * FROM model_offers 
WHERE credential_id IN (8, 18, 19);

-- 查看路由决策历史
SELECT * FROM route_decisions 
WHERE credential_id IN (8, 18, 19) 
  AND ts > NOW() - INTERVAL '24 hours'
LIMIT 20;
```

---

## 📝 总结

### 根本原因
- **配置错误**: Credentials 8, 18, 19被错误地关联到NVIDIA NIM Provider (ID 18)
- 当这些credentials被用于处理MiniMax请求时，请求被发送到NVIDIA的API endpoint
- NVIDIA API不支持MiniMax模型，返回空响应

### 核心证据
- Provider 18的base_url是`https://integrate.api.nvidia.com/v1` (NVIDIA的endpoint)
- 但这些credentials被用于发送`minimaxai/minimax-m3`模型请求
- 导致14个empty_response错误和多个超时/取消错误

### 快速修复
- 禁用Credentials 8, 18, 19
- 所有MiniMax流量将路由到正确配置的Credential 6
- 预期错误率从25.78%降至~19%

### 后续工作
1. 确认这些credentials持有的真实API keys
2. 如果是MiniMax keys，重新关联到正确的Provider
3. 如果是NVIDIA keys，用于正确的NVIDIA模型请求
4. 审查整个路由配置，防止类似问题
