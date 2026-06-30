# Minimax-m3 路由测试执行总结

**测试时间**: 2026-06-30  
**目标服务**: llm.kxpms.cn  
**测试模型**: minimax-m3  
**API Keys**: 
- sk-1R7IBh2THq1Id2BDWOWHstpFu2oG09Qd1kgYn9hasxFcKZw7
- sk-1vH6C2I9pywyvUXaUXj4vdMZbeYVE5VB0fBYVgqA97JrltE9

## 测试目标

检查两个主要问题：
1. **问题1**: 所有节点有效，但路由匹配不到可用节点
2. **问题2**: 某个节点失败多次，没有及时从候选节点中移除，没有及时切换节点
3. **额外关注**: NVIDIA NIM 节点的 empty_response 错误（怀疑不是延时问题）

## 已创建的测试工具

### 1. 完整测试脚本 (test_71_complete.sh)
**位置**: `./scripts/test_71_complete.sh`

**功能**:
- API层面多轮测试（默认3轮，每轮5个请求）
- 自动检测 empty_response 错误
- 自动检测路由 no_candidate 错误
- 交替使用两个API key测试
- 记录详细的请求和响应日志
- 如果有数据库连接，自动执行数据库诊断

**使用方法**:
```bash
# 在71服务器上运行（可访问数据库）
export LLM_GATEWAY_DATABASE_URL="postgresql://user:pass@host:port/dbname"
./scripts/test_71_complete.sh

# 本地运行（仅API测试）
./scripts/test_71_complete.sh

# 自定义参数
export TEST_ROUNDS=5
export REQUESTS_PER_ROUND=10
./scripts/test_71_complete.sh
```

**输出**:
- 测试日志: `./test_logs_71/test_TIMESTAMP.log`
- 响应详情: `./test_logs_71/responses_TIMESTAMP.log`

### 2. NVIDIA NIM Empty Response 诊断 (diagnose_nvidia_nim_empty_response.sh)
**位置**: `./scripts/diagnose_nvidia_nim_empty_response.sh`

**功能**:
- 分析 empty_response 错误的统计信息
- 按凭据分组统计
- 响应时间分布分析
- 对比 empty_response 和正常响应的时间差异
- 检查 NVIDIA NIM 相关凭据的状态

**使用方法** (需要在71服务器上运行):
```bash
export LLM_GATEWAY_DATABASE_URL="postgresql://user:pass@host:port/dbname"
./scripts/diagnose_nvidia_nim_empty_response.sh minimax-m3

# 自定义回溯时间
export LOOKBACK_MINUTES=120
./scripts/diagnose_nvidia_nim_empty_response.sh
```

### 3. 综合路由测试 (test_minimax_comprehensive.sh)
**位置**: `./scripts/test_minimax_comprehensive.sh`

**功能**:
- 多轮并发测试
- 每轮前后检查路由状态
- 数据库层面的节点状态检查
- 失败记录追踪
- 检测节点是否被正确移除

**使用方法**:
```bash
export API_KEY="your-api-key"
export GATEWAY_URL="https://llm.kxpms.cn"
export LLM_GATEWAY_DATABASE_URL="postgresql://..."
export ROUNDS=5
export REQUESTS_PER_ROUND=10
./scripts/test_minimax_comprehensive.sh
```

### 4. 路由问题诊断 (diagnose_routing_issue.sh)
**位置**: `./scripts/diagnose_routing_issue.sh` (已存在)

**功能**:
- 检查请求统计
- 检查候选凭据状态
- 分析成功率
- 检查探测状态
- 质量门限过滤分析

## 初步测试结果

### API测试发现

**测试样本**: 多次测试，每次1个请求
**结果**: 
- ✅ 所有测试请求均**成功返回**
- ⏱️ **响应时间较长**: 5-21秒之间
- 📝 响应内容正常，没有 empty_response

**示例响应**:
```
HTTP Code: 200
Duration: 5.509962s
Tokens: 206 (prompt: 176, completion: 30)
Model: minimax-m3
Content: 正常的AI定义文本
```

### 关键发现

1. **路由正常工作**: 
   - 没有出现 "no candidate" 错误
   - 请求能够成功路由到可用节点

2. **响应时间波动大**:
   - 最快: 5.5秒
   - 最慢: 21秒
   - 这种波动可能与节点健康状况或负载有关

3. **没有发现 empty_response**:
   - 在当前测试中未复现 empty_response 问题
   - 需要更大规模测试或特定条件触发

## 下一步行动建议

### 立即执行（在71服务器上）

1. **设置数据库连接并运行完整测试**:
```bash
ssh 192.168.1.71
cd /path/to/llm-gateway-go-2
export LLM_GATEWAY_DATABASE_URL="postgresql://..."
./scripts/test_71_complete.sh
```

2. **查看最近的 empty_response 情况**:
```bash
./scripts/diagnose_nvidia_nim_empty_response.sh minimax-m3
```

3. **检查路由状态和节点健康**:
```bash
./scripts/diagnose_routing_issue.sh minimax-m3
```

### 深度调查

4. **查看服务端日志**:
```bash
# 查找对应 request_id 的详细日志
grep "chatcmpl-3da4fa38" /var/log/llm-gateway/*.log

# 实时监控
tail -f /var/log/llm-gateway/app.log
```

5. **检查 request_logs 表**:
```sql
-- 最近的 empty_response 记录
SELECT 
    ts, request_id, credential_id, duration_ms, 
    failure_stage, response_preview
FROM request_logs
WHERE error_kind = 'empty_response'
  AND ts > NOW() - INTERVAL '1 hour'
ORDER BY ts DESC
LIMIT 20;

-- 响应时间分析
SELECT 
    CASE 
        WHEN duration_ms < 1000 THEN '<1s'
        WHEN duration_ms < 5000 THEN '1-5s'
        WHEN duration_ms < 10000 THEN '5-10s'
        WHEN duration_ms < 30000 THEN '10-30s'
        ELSE '>30s'
    END as duration_range,
    COUNT(*) as count,
    COUNT(*) FILTER (WHERE success) as success,
    COUNT(*) FILTER (WHERE error_kind = 'empty_response') as empty_resp
FROM request_logs
WHERE client_model = 'minimax-m3'
  AND ts > NOW() - INTERVAL '1 hour'
GROUP BY duration_range
ORDER BY MIN(duration_ms);
```

6. **压力测试（检测节点切换）**:
```bash
# 高并发测试，看是否能触发问题
export ROUNDS=10
export REQUESTS_PER_ROUND=20
./scripts/test_71_complete.sh
```

## 问题分析

### 关于响应时间长的可能原因

1. **冷启动**: 模型或节点可能需要预热
2. **网络延迟**: 到上游API的网络连接问题
3. **队列等待**: 节点负载高，请求在队列中等待
4. **Token缓存**: 第一次请求没有缓存（看到 cached_tokens: 144）

### 关于 empty_response 的推测

基于你提到"响应延时并不长"，如果 empty_response 发生时响应时间较短（如<5秒），可能的原因：

1. **上游返回空body**: API返回200但body为空
2. **流式响应处理问题**: SSE流被过早关闭
3. **超时配置问题**: 网关或客户端的读超时设置过短
4. **特定错误格式**: 某些错误情况下返回格式不符合预期

## 工具文件清单

```
scripts/
├── test_71_complete.sh              # 主测试脚本（推荐）
├── diagnose_nvidia_nim_empty_response.sh  # Empty response 诊断
├── test_minimax_comprehensive.sh    # 综合测试（需数据库）
├── test_minimax_api_only.sh        # 纯API测试
├── diagnose_routing_issue.sh       # 路由诊断（已存在）
└── test_minimax_routing.sh         # 路由测试（已存在）

test_logs_71/                        # 测试日志目录
├── test_TIMESTAMP.log              # 测试主日志
└── responses_TIMESTAMP.log         # 详细响应日志
```

## 联系与支持

如需调整测试参数或添加新的诊断功能，可以修改脚本中的配置部分。

所有脚本都包含详细的注释和帮助信息。
