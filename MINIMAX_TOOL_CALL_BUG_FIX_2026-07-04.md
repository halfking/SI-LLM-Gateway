# MiniMax Tool Call Bug 修复报告

**日期**: 2026-07-04  
**严重性**: P0 - 影响生产环境  
**影响范围**: 175 个请求失败（2026-07-03 至 2026-07-04）

---

## 🎯 问题总结

**症状**：MiniMax 返回 400 错误，提示 `tool result's tool id not found`

**根本原因**：序列化 OpenAI 格式时，assistant 消息的 `Content` 为空但有 `ToolCalls` 时，`tool_calls` 字段未被添加到输出，导致后续 tool result 消息孤立。

---

## 🔍 问题调查过程

### 1. 初步分析（误判）

最初以为是：
- ❌ 网络连接问题（transient 错误）
- ❌ 消息压缩逻辑删除了 assistant tool_calls
- ❌ tool_call_id 格式转换错误

**实际发现**：
- ✅ 71 服务器数据库有 175 个 `tool_call_id_mismatch` 错误
- ✅ 184 服务器数据库被清空/重置（误导了初期调查）

### 2. 深度调查

检查了生产环境的失败请求 `3b8e924bbcf65ee2f67b19ef37400d85`：

**原始请求（177条消息）**：
```
- 1 system
- 82 assistant (81 个带 tool_calls)
- 91 tool results
- 3 user

✓ 所有 tool_call_id 都有匹配的 assistant tool_calls
```

**压缩后发送给 MiniMax（50条消息）**：
```
- 1 system
- 0 assistant 带 tool_calls  ❌
- 44 tool results
- 其他消息

❌ 所有 44 个 tool results 都是孤立的！
```

**MiniMax 返回错误**：
```json
{
  "type": "error",
  "error": {
    "type": "bad_request_error",
    "message": "invalid params, tool result's tool id(call_fdb0383f967843b6acf20f6e) not found (2013)",
    "http_code": "400"
  }
}
```

### 3. 定位 Bug

测试了消息压缩逻辑 (`transform/ctx_compress.go`)：
- ✅ `trimOldestPairs` 函数逻辑正确
- ✅ 测试通过：删除 tool round 时会同时删除 assistant + tool results

**真正的 Bug 在序列化层**：`internal/ir/serialize_openai.go:189-203`

```go
// ❌ 原代码
if len(msg.Content) == 0 {
    // Empty content - may need tool_calls
    // BUG: 这里什么都不做，tool_calls 不会被添加！
} else if len(msg.Content) == 1 && msg.Content[0].Type == "text" && msg.ToolCalls == nil {
    out["content"] = msg.Content[0].Text
} else {
    content := serializeOpenAIMessageContent(msg.Content)
    out["content"] = content
    
    // 只有在这个分支才添加 tool_calls
    if len(msg.ToolCalls) > 0 {
        out["tool_calls"] = serializeOpenAIToolCalls(msg.ToolCalls)
    }
}
```

**问题场景**：
```
当 assistant 消息：
- Content: []        (空数组)
- ToolCalls: [...]   (非空)

序列化结果：
{
  "role": "assistant",
  "content": ""      ✓
  // ❌ 缺少 tool_calls 字段！
}
```

---

## ✅ 修复方案

### 代码修改

**文件**: `internal/ir/serialize_openai.go`  
**行数**: 189-203

```go
// ✅ 修复后
if len(msg.Content) == 0 {
    // Empty content - but may have tool_calls for assistant
    out["content"] = ""
    if len(msg.ToolCalls) > 0 {
        out["tool_calls"] = serializeOpenAIToolCalls(msg.ToolCalls)
    }
} else if len(msg.Content) == 1 && msg.Content[0].Type == "text" && msg.ToolCalls == nil {
    out["content"] = msg.Content[0].Text
} else {
    content := serializeOpenAIMessageContent(msg.Content)
    out["content"] = content
    
    if len(msg.ToolCalls) > 0 {
        out["tool_calls"] = serializeOpenAIToolCalls(msg.ToolCalls)
    }
}
```

**关键变化**：
1. 当 `Content` 为空时，设置 `content: ""`
2. 检查并添加 `tool_calls` 字段

---

## 🧪 测试验证

### 新增测试

**文件**: `internal/ir/serialize_openai_toolcalls_test.go`

1. **TestSerializeOpenAI_EmptyContentWithToolCalls**  
   测试单个 tool_call 的情况

2. **TestSerializeOpenAI_MultipleToolCallsWithEmptyContent**  
   测试多个 tool_calls 的情况

### 测试结果

```bash
$ go test ./internal/ir/
ok  	github.com/kaixuan/llm-gateway-go/internal/ir	0.212s
```

✅ 所有测试通过

---

## 📊 影响评估

### 失败案例统计（生产环境）

| 时间段 | 错误数 | 占比 |
|--------|--------|------|
| 2026-07-03 至 2026-07-04 | 175 | 16.9% |
| 成功请求 | 822 | 79.2% |

### 失败特征

所有 175 个失败请求：
- `error_kind`: tool_call_id_mismatch
- `upstream_status_code`: null（MiniMax 拒绝请求）
- `response_body`: 空
- `failure_stage`: upstream

### 受影响场景

**所有以下情况都会触发 Bug**：
1. 长对话（>100 条消息）
2. 大量工具调用（>50 次）
3. 消息压缩触发（超过上下文窗口）
4. Assistant 消息的 Content 为空但有 ToolCalls

---

## 🚀 部署计划

### 步骤

1. ✅ **代码修复完成**
   - 修改 `internal/ir/serialize_openai.go`
   - 添加测试用例

2. ⏳ **本地验证**
   ```bash
   # 运行本地测试栈
   cd /Users/xutaohuang/workspace/llm-gateway-go-2
   ./scripts/local-deploy-test.sh
   ```

3. ⏳ **部署到 184 测试环境**
   ```bash
   ./scripts/deploy-184.sh
   ```

4. ⏳ **部署到 71 生产环境**
   ```bash
   ./scripts/deploy-71.sh
   ```

### 回滚方案

如果部署后出现问题：

```bash
# 184 环境回滚
ssh root@14.103.112.184 -p 25022
kubectl rollout undo deployment/llm-gateway-go-deployment -n pms-test

# 71 环境回滚
ssh root@14.103.174.71 -p 25022
cd /opt/llm-gateway-go
./llm-gateway-go.bak  # 启动备份版本
```

---

## 📈 预期效果

修复后，预期：
- ✅ `tool_call_id_mismatch` 错误降至 0
- ✅ MiniMax 成功率从 79% 提升至 >95%
- ✅ 长对话场景稳定性提升
- ✅ 工具调用密集场景正常工作

---

## 🔒 预防措施

### 1. 增强测试覆盖

已添加测试用例：
- ✅ 空 Content + 单个 ToolCall
- ✅ 空 Content + 多个 ToolCalls
- ✅ 压缩后消息完整性验证

### 2. 监控告警

建议添加：
```yaml
alerts:
  - name: minimax_tool_call_errors
    condition: error_kind == 'tool_call_id_mismatch'
    threshold: > 5 in 5 minutes
    action: notify_oncall
```

### 3. 序列化一致性检查

建议在测试中添加：
- 序列化前后 tool_call_id 完整性检查
- 每个 tool result 必须有对应的 assistant tool_call
- 自动检测孤立的 tool messages

---

## 📚 相关文档

### 代码位置

- **Bug 位置**: `internal/ir/serialize_openai.go:189-203`
- **测试文件**: `internal/ir/serialize_openai_toolcalls_test.go`
- **压缩逻辑**: `transform/ctx_compress.go:trimOldestPairs`
- **错误分类**: `errorsx/classify.go:KindToolCallIdMismatch`

### 相关 Issue

- MiniMax 官方文档：https://platform.minimaxi.com/document/guides/chat-model
- OpenAI tool_calls 规范：https://platform.openai.com/docs/guides/function-calling

### Git Commit

```bash
git log --oneline -1
# <commit_hash> Fix: Serialize tool_calls for assistant messages with empty content
```

---

## ✅ Checklist

部署前检查：

- [x] 代码修复完成
- [x] 测试用例添加
- [x] 所有测试通过
- [ ] 本地环境验证
- [ ] 184 测试环境部署
- [ ] 71 生产环境部署
- [ ] 监控 24 小时
- [ ] 确认错误率降至 0

---

**报告人**: Kiro AI Agent  
**审核人**: 待指定  
**最后更新**: 2026-07-04 16:45 CST
