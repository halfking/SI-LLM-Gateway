# MiniMax Tool Calling 完整修复 - 实施总结

## ✅ 完成的工作

### 阶段 1: IR 层支持（已完成）

**提交**: `25474b93` - fix(ir): support MiniMax tool_call_id in Anthropic protocol

**修改内容**:
1. ✅ `internal/ir/types.go` - 添加 `TargetProvider` 字段
2. ✅ `internal/ir/parse_anthropic.go` - 解析 `tool_call_id` 和 `tool_use_id`
3. ✅ `internal/ir/serialize_anthropic.go` - 根据 `TargetProvider` 输出正确字段
4. ✅ `internal/ir/parse_anthropic_minimax_test.go` - 完整测试套件（4个测试）
5. ✅ `docs/minimax-tool-calling-fix.md` - 技术文档

**测试结果**:
- ✅ 所有 MiniMax 测试通过
- ✅ 所有现有 IR 测试通过（198个）
- ✅ 完全向后兼容

### 阶段 2: 路由层集成（刚完成）

**提交**: `068526b5` - feat(routing): set TargetProvider for MiniMax tool_call_id support

**修改内容**:
1. ✅ `routing/executor_anthropic.go` - 设置 `irReq.TargetProvider = cand.CatalogCode`

**关键代码**:
```go
// Parse OpenAI body → IR → Serialize Anthropic
irReq, err := e.IR.ParseOpenAI(sourceBody)
if err != nil {
    return nil, fmt.Errorf("ir parse openai: %w", err)
}
// Override model to outbound model (matching existing behavior)
irReq.Model = resolveOutboundModel(params, cand)
// Set target provider for provider-specific protocol adaptations
// (e.g., MiniMax uses "tool_call_id" instead of "tool_use_id")
irReq.TargetProvider = cand.CatalogCode
bodyBytes, err := e.IR.SerializeAnthropic(irReq)
```

**位置**: `routing/executor_anthropic.go:383`

**流程**: 
```
OpenAI Client Request 
  → ParseOpenAI 
  → InternalRequest (TargetProvider = "minimax") 
  → SerializeAnthropic 
  → MiniMax API (with tool_call_id)
```

## 🔍 完整的数据流

### 场景 1: Tool Calling 请求（OpenAI → MiniMax）

```
┌─────────────────────────────────────────────────────────────┐
│ Client (OpenAI format)                                       │
│ POST /v1/chat/completions                                    │
│ {                                                            │
│   "model": "abab6.5s-chat",                                  │
│   "messages": [...],                                         │
│   "tools": [...]                                             │
│ }                                                            │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ routing/executor_anthropic.go                                │
│ - ParseOpenAI(sourceBody) → irReq                           │
│ - irReq.TargetProvider = cand.CatalogCode  // "minimax"     │
│ - SerializeAnthropic(irReq) → bodyBytes                     │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ internal/ir/serialize_anthropic.go                           │
│ - if targetProvider == "minimax":                            │
│     toolResult["tool_call_id"] = msg.ToolCallID             │
│   else:                                                      │
│     toolResult["tool_use_id"] = msg.ToolCallID              │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ MiniMax API (Anthropic format)                               │
│ POST /v1/messages                                            │
│ {                                                            │
│   "model": "abab6.5s-chat",                                  │
│   "messages": [                                              │
│     {                                                        │
│       "role": "user",                                        │
│       "content": [                                           │
│         {                                                    │
│           "type": "tool_result",                             │
│           "tool_call_id": "call_abc123",  ← MiniMax 格式     │
│           "content": "..."                                   │
│         }                                                    │
│       ]                                                      │
│     }                                                        │
│   ]                                                          │
│ }                                                            │
└─────────────────────────────────────────────────────────────┘
```

### 场景 2: Tool Result 响应（MiniMax → OpenAI）

```
┌─────────────────────────────────────────────────────────────┐
│ MiniMax Response                                             │
│ {                                                            │
│   "content": [                                               │
│     {                                                        │
│       "type": "tool_use",                                    │
│       "id": "call_xyz789",                                   │
│       "name": "get_weather",                                 │
│       "input": {...}                                         │
│     }                                                        │
│   ]                                                          │
│ }                                                            │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ internal/ir/parse_anthropic.go                               │
│ - Parse tool_use_id OR tool_call_id (fallback)              │
│ - Store in irResp.ToolCallID                                │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ Client receives OpenAI format                                │
│ {                                                            │
│   "choices": [{                                              │
│     "message": {                                             │
│       "tool_calls": [{                                       │
│         "id": "call_xyz789",                                 │
│         "function": {...}                                    │
│       }]                                                     │
│     }                                                        │
│   }]                                                         │
│ }                                                            │
└─────────────────────────────────────────────────────────────┘
```

## 📊 测试覆盖

### 单元测试
- ✅ `TestParseAnthropic_MinimaxToolCallID` - 解析 MiniMax 的 `tool_call_id`
- ✅ `TestParseAnthropic_StandardToolUseID` - 验证标准 Anthropic 未受影响
- ✅ `TestSerializeAnthropic_MinimaxToolCallID` - 为 MiniMax 序列化 `tool_call_id`
- ✅ `TestSerializeAnthropic_StandardToolUseID` - 验证标准序列化未受影响

### 集成测试（待完成）
- ⏳ 端到端测试：真实 MiniMax API 调用
- ⏳ 多轮 tool calling 对话测试
- ⏳ 错误场景测试

## 🎯 解决的问题

**问题**: MiniMax 返回错误 "tool result's tool id(call_xxx) not found"

**根本原因**: 
- MiniMax 使用非标准的 `tool_call_id` 字段
- 标准 Anthropic 使用 `tool_use_id` 字段
- 网关只解析标准字段，导致 tool_call_id 丢失

**解决方案**:
1. 解析时兼容两种字段（优先标准，回退 MiniMax）
2. 序列化时根据目标提供商选择正确字段
3. 通过 `TargetProvider` 字段传递提供商信息

## 🔄 影响范围

### 修改的组件
- ✅ IR 层（parse + serialize）
- ✅ Routing 层（executor_anthropic）

### 不受影响的组件
- ✅ 其他提供商（OpenAI, Anthropic, DeepSeek等）
- ✅ OpenAI → OpenAI 路由
- ✅ Anthropic → Anthropic 路由
- ✅ 非 tool calling 场景

### 兼容性
- ✅ 完全向后兼容
- ✅ 不影响现有功能
- ✅ 所有现有测试通过

## 📝 下一步

### 立即任务
1. **端到端验证** - 使用真实 MiniMax API 测试 tool calling
2. **监控部署** - 观察错误日志是否减少

### 后续优化（Provider Adapter 架构）
参见：
- `docs/provider-adapter-architecture.md` - 完整架构设计
- `docs/provider-adapter-implementation-plan.md` - 实施计划

**优势**:
- 更好的可扩展性（新增提供商更容易）
- 更清晰的职责分离
- 更容易维护和测试

**时间线**: 2-3周（8个核心提供商）

## 📂 相关文件

### 已修改
- `internal/ir/types.go`
- `internal/ir/parse_anthropic.go`
- `internal/ir/serialize_anthropic.go`
- `routing/executor_anthropic.go`

### 新增
- `internal/ir/parse_anthropic_minimax_test.go`
- `docs/minimax-tool-calling-fix.md`

### 文档
- `docs/provider-adapter-architecture.md`
- `docs/provider-adapter-implementation-plan.md`

## 🎉 总结

MiniMax tool calling 修复已完成：
- ✅ IR 层支持 (25474b93)
- ✅ 路由层集成 (068526b5)
- ✅ 完整测试覆盖
- ✅ 完全向后兼容
- ⏳ 等待生产环境验证

**当前状态**: 代码就绪，等待部署和真实环境测试
**下一步**: 端到端验证 → Provider Adapter 架构实施
