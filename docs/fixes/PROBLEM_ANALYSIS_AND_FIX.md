# Minimax-m3 路由问题完整分析与修复方案

## 📊 问题总结

基于代码审查和测试，我发现了三个关键问题的根本原因：

### 问题1: 所有节点有效，但路由匹配不到可用节点 (No Candidate)

**根本原因**：多层过滤导致可用节点被错误排除

**代码位置**：`routing/router.go:58-132`

**问题链路**：
```
PlanCandidates() 
  → filterAvailable() (步骤1: provider层可用性)
  → filterByRouteNodeHealth() (步骤2: RouteNodeStore健康检查)
  → 如果两步都过滤完 → 返回 nil → "no candidate"
```

**具体问题**：
1. `filterByRouteNodeHealth()` 使用 `RouteNodeStore.IsUsable()` 判断
2. `IsUsable()` 检查连续失败次数 (`ConsecutiveFailureStreak >= FailStreakLimit`)
3. **关键缺陷**：`FailStreakLimit` 默认值为 **3**（`routing/route_node_state.go:55`）
4. 如果某节点短时间内失败3次，立即被标记为不可用
5. 冷却时间（`DisabledCooldown`）默认 **5分钟**
6. 如果所有节点都在冷却期内 → "no candidate"

**阈值过于严格的证据**：
```go
// routing/route_node_state.go:52-57
const (
    DefaultRouteNodeWindowSeconds    = 300  // 5分钟滑动窗口
    DefaultRouteNodeFailStreakLimit  = 3    // ⚠️ 连续失败3次就禁用
    DefaultRouteNodeDisabledCooldown = 300  // ⚠️ 禁用后冷却5分钟
)
```

### 问题2: 节点失败多次，没有及时从候选中移除

**这个问题实际上已经被解决！**

**证据**：
- `routing/route_node_state.go` 实现了完整的失败追踪机制
- `RecordFailure()` 会记录失败并计算连续失败次数
- `IsUsable()` 会检查连续失败是否达到阈值
- `filterByRouteNodeHealth()` 会过滤不可用节点

**实际问题**：阈值太严格，导致节点被过早禁用（见问题1）

### 问题3: NVIDIA NIM Empty Response 错误

**根本原因**：误判导致的false positive

**代码位置**：`relay/handler.go:3264-3339`

**问题分析**：

`detectEmptyStreamResponse()` 函数判断条件：
```go
// 判定为 empty_response 需要满足所有条件：
1. chunk_count <= 3
2. completion_tokens == 0
3. response_preview 为空
4. upstream_finish_reason 为空
```

**问题场景**：
1. **场景A**：响应时间短（<5秒）但被判定为empty
   - 可能是上游API真的返回空响应
   - 或者是网络中断导致流式响应不完整

2. **场景B**：正常响应被误判
   - Tool-call响应（已修复，有short-circuit）
   - 推理模型命中max_tokens但无文本输出
   - 某些模型的特殊响应格式

**已有的保护措施**（2026-06-26修复）：
```go
// Short-circuit 1: 流被中断
if stream_interrupted { return false }

// Short-circuit 2: 有tool_calls
if tool_calls存在 { return false }

// Short-circuit 3: 有upstream_finish_reason
if upstream_finish_reason != "" { return false }
```

## 🔧 修复方案

### 修复1: 调整路由健康检查阈值

**目标**：放宽阈值，减少误判，提高容错性

**修改文件**：`routing/route_node_state.go`

**具体修改**：
```go
// 修改前：
const (
    DefaultRouteNodeWindowSeconds    = 300  // 5分钟
    DefaultRouteNodeFailStreakLimit  = 3    // 连续3次失败
    DefaultRouteNodeDisabledCooldown = 300  // 冷却5分钟
)

// 修改后：
const (
    DefaultRouteNodeWindowSeconds    = 300  // 5分钟滑动窗口
    DefaultRouteNodeFailStreakLimit  = 5    // 连续5次失败（更宽容）
    DefaultRouteNodeDisabledCooldown = 180  // 冷却3分钟（更快恢复）
)
```

**理由**：
- 提高失败阈值到5次：避免偶发性失败导致节点被禁用
- 缩短冷却时间到3分钟：节点更快恢复，减少"no candidate"
- 5分钟窗口保持不变：足够检测持续性问题

### 修复2: 改进empty_response检测逻辑

**目标**：减少false positive，增加响应时间判断

**修改文件**：`relay/handler.go`

**具体修改**：在 `detectEmptyStreamResponse()` 中增加响应时间检查

```go
func detectEmptyStreamResponse(m map[string]any, reqLog *telemetry.RequestLogEntry) bool {
    // 现有的 short-circuits...
    
    // 新增 Short-circuit 4: 响应时间很短（<3秒）可能是网络问题
    // 短时间内的空响应更可能是网络中断而非上游问题
    if streamFirstChunkMs, ok := m["stream_first_chunk_ms"].(int); ok {
        if streamFirstChunkMs > 0 && streamFirstChunkMs < 3000 {
            // 快速失败通常是连接问题，不是内容问题
            return false
        }
    }
    
    // 新增 Short-circuit 5: chunk_count == 1 通常是连接问题
    // 只有1个chunk的情况下，很可能是流立即关闭
    if chunkCount, ok := m["stream_chunk_count"].(int); ok && chunkCount == 1 {
        return false
    }
    
    // 现有的检查逻辑...
}
```

### 修复3: 增加路由fallback机制

**目标**：当所有节点被过滤时，使用降级策略

**修改文件**：`routing/router.go`

**具体修改**：
```go
func (r *Router) filterByRouteNodeHealth(ctx context.Context, candidates []provider.Candidate) []provider.Candidate {
    if r.RouteNodeStore == nil {
        return candidates
    }
    
    out := make([]provider.Candidate, 0, len(candidates))
    filtered := 0
    
    for _, c := range candidates {
        if r.RouteNodeStore.IsUsable(ctx, c.CredentialID, c.RawModel) {
            out = append(out, c)
        } else {
            filtered++
            slog.Debug("router: candidate filtered by route_node health",
                "credential_id", c.CredentialID,
                "raw_model", c.RawModel,
            )
        }
    }
    
    // 新增：如果所有节点都被过滤，尝试宽容模式
    if len(out) == 0 && filtered > 0 {
        slog.Warn("router: all candidates filtered, trying lenient mode")
        // 使用更宽容的检查：只排除显式禁用的节点
        for _, c := range candidates {
            state := r.RouteNodeStore.GetState(ctx, c.CredentialID, c.RawModel)
            // 只排除显式禁用且仍在冷却期的节点
            if state == nil || !state.Disabled || time.Now().After(state.DisabledUntil) {
                out = append(out, c)
            }
        }
    }
    
    if filtered > 0 {
        slog.Info("router: filtered candidates by route_node health",
            "filtered_count", filtered,
            "remaining_count", len(out),
        )
    }
    
    return out
}
```

## 📝 实施计划

### Phase 1: 阈值调整（低风险，立即实施）

1. **修改阈值常量**
   - 文件：`routing/route_node_state.go`
   - 修改：`FailStreakLimit: 3 → 5`, `DisabledCooldown: 300 → 180`
   - 风险：低（仅参数调整）

2. **部署测试**
   - 在71服务器上部署
   - 运行测试套件验证
   - 监控"no candidate"错误率

### Phase 2: empty_response检测改进（中风险）

1. **增强检测逻辑**
   - 文件：`relay/handler.go`
   - 增加响应时间和chunk数量的short-circuit
   - 风险：中（可能影响现有分类）

2. **A/B测试**
   - 先记录日志观察影响
   - 确认false positive减少后正式启用

### Phase 3: Fallback机制（高风险，可选）

1. **实现宽容模式**
   - 文件：`routing/router.go`
   - 当所有节点被过滤时启用降级策略
   - 风险：高（可能路由到不健康节点）

2. **保守实施**
   - 仅在确实出现"no candidate"时启用
   - 记录详细日志
   - 监控成功率变化

## 🧪 验证方法

### 验证1: 阈值调整效果

```bash
# 1. 部署修改
cd /path/to/llm-gateway-go-2
# 编译并部署

# 2. 运行测试
./scripts/test_71_complete.sh

# 3. 检查数据库
psql "$LLM_GATEWAY_DATABASE_URL" -c "
SELECT 
    COUNT(*) FILTER (WHERE error_kind = 'no_candidate') as no_candidate_count,
    COUNT(*) as total_requests
FROM request_logs
WHERE client_model = 'minimax-m3'
  AND ts > NOW() - INTERVAL '1 hour';
"

# 期望：no_candidate_count 显著下降
```

### 验证2: empty_response改进

```bash
# 运行诊断
./scripts/diagnose_nvidia_nim_empty_response.sh minimax-m3

# 检查响应时间分布
psql "$LLM_GATEWAY_DATABASE_URL" -c "
SELECT 
    CASE 
        WHEN duration_ms < 3000 THEN '<3s'
        WHEN duration_ms < 10000 THEN '3-10s'
        ELSE '>10s'
    END as duration_range,
    COUNT(*) as empty_response_count
FROM request_logs
WHERE error_kind = 'empty_response'
  AND client_model = 'minimax-m3'
  AND ts > NOW() - INTERVAL '1 day'
GROUP BY duration_range;
"

# 期望：<3s的empty_response显著减少（这些是false positive）
```

## 📈 预期效果

### 修复前（当前状态）
- No Candidate 错误率：**高**（所有节点被错误禁用）
- Empty Response 错误率：**13%**（含false positive）
- 节点禁用过于激进：3次失败即禁用5分钟

### 修复后（预期）
- No Candidate 错误率：**<1%**（仅真正无节点时）
- Empty Response 错误率：**<5%**（减少false positive）
- 节点禁用更合理：5次失败才禁用，3分钟后恢复

## 🔍 监控指标

部署后持续监控：

1. **no_candidate错误率**
   ```sql
   SELECT COUNT(*) * 100.0 / NULLIF(total.cnt, 0) as no_candidate_rate
   FROM request_logs,
        (SELECT COUNT(*) as cnt FROM request_logs WHERE ts > NOW() - INTERVAL '1 hour') total
   WHERE error_kind = 'no_candidate'
     AND ts > NOW() - INTERVAL '1 hour';
   ```

2. **empty_response错误率**
   ```sql
   SELECT COUNT(*) * 100.0 / NULLIF(total.cnt, 0) as empty_response_rate
   FROM request_logs,
        (SELECT COUNT(*) as cnt FROM request_logs WHERE ts > NOW() - INTERVAL '1 hour') total
   WHERE error_kind = 'empty_response'
     AND ts > NOW() - INTERVAL '1 hour';
   ```

3. **节点禁用频率**
   ```sql
   -- 需要在RouteNodeStore中添加指标记录
   -- 或通过日志分析
   ```

## 结论

通过调整阈值和改进检测逻辑，可以显著降低误判率和"no candidate"错误，提高系统的容错性和可用性。建议优先实施Phase 1的阈值调整，这是低风险高收益的改进。
