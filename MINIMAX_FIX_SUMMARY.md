# MiniMax Tool Call Bug 修复总结

## 🎯 问题

175 个 MiniMax 请求失败，错误信息：`tool result's tool id not found (2013)`

## 🔍 根本原因

**Bug 位置**: `internal/ir/serialize_openai.go:189-203`

当 assistant 消息的 `Content` 为空但有 `ToolCalls` 时，序列化时**未添加 `tool_calls` 字段**，导致后续的 tool result 消息孤立。

```go
// ❌ 原代码
if len(msg.Content) == 0 {
    // Empty content - may need tool_calls
    // BUG: 什么都不做，tool_calls 丢失！
} else {
    // 只有这个分支才添加 tool_calls
    if len(msg.ToolCalls) > 0 {
        out["tool_calls"] = serializeOpenAIToolCalls(msg.ToolCalls)
    }
}
```

## ✅ 修复

```go
// ✅ 修复后
if len(msg.Content) == 0 {
    out["content"] = ""
    if len(msg.ToolCalls) > 0 {
        out["tool_calls"] = serializeOpenAIToolCalls(msg.ToolCalls)
    }
} else {
    // ... 其他分支也添加 tool_calls
}
```

## 📊 影响

- **失败请求**: 175 个（16.9%）
- **触发场景**: 长对话 + 大量工具调用 + 消息压缩
- **受影响时段**: 2026-07-03 至 2026-07-04

## 🧪 验证

```bash
$ go test ./internal/ir/
ok  	github.com/kaixuan/llm-gateway-go/internal/ir	0.212s
```

✅ 所有测试通过  
✅ 新增 2 个测试用例覆盖此场景  
✅ 编译成功

## 🚀 下一步

1. ⏳ 本地测试栈验证
2. ⏳ 部署到 184 测试环境
3. ⏳ 部署到 71 生产环境
4. ⏳ 监控 24 小时确认修复

## 📝 修改文件

- ✅ `internal/ir/serialize_openai.go` (修复)
- ✅ `internal/ir/serialize_openai_toolcalls_test.go` (新增测试)
- ✅ `transform/ctx_compress_orphan_test.go` (验证压缩逻辑)
- ✅ `transform/ctx_compress_massive_test.go` (验证大规模场景)

---

**预期效果**: tool_call_id_mismatch 错误降至 0，MiniMax 成功率从 79% 提升至 >95%
