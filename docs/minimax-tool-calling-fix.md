# MiniMax Tool Calling 修复方案

## 问题描述

MiniMax 在处理 tool calling 时返回错误：
```
tool result's tool id(call_xxx) not found
```

## 根本原因

MiniMax 使用的 Anthropic 格式协议与标准 Anthropic 协议有细微差异：

- **标准 Anthropic**: 在 `tool_result` 中使用 `tool_use_id` 字段
- **MiniMax**: 在 `tool_result` 中使用 `tool_call_id` 字段

当前的实现只解析了标准的 `tool_use_id`，导致从 MiniMax 响应中解析 tool_result 时丢失了 tool_call_id，进而导致后续请求中的 tool result 无法与之前的 tool call 匹配。

## 修复方案

### 1. 添加 TargetProvider 字段

在 `internal/ir/types.go` 中的 `InternalRequest` 结构添加 `TargetProvider` 字段：

```go
// TargetProvider is an optional hint for the serializer to handle provider-specific
// protocol variations. For example, "minimax" uses "tool_call_id" instead of the
// standard "tool_use_id" in Anthropic-format requests.
TargetProvider string
```

### 2. 解析时同时支持两种字段

在 `internal/ir/parse_anthropic.go` 中修改 `tool_result` 解析逻辑（两处）：

```go
case "tool_result":
    // MiniMax uses "tool_call_id" instead of standard "tool_use_id"
    toolUseID, _ := blockMap["tool_use_id"].(string)
    if toolUseID == "" {
        // Fallback to tool_call_id for MiniMax compatibility
        toolUseID, _ = blockMap["tool_call_id"].(string)
    }
    // ... rest of the code
```

修改位置：
- `parseAnthropicContentBlocks` 函数 (~280行)
- `parseAnthropicContentBlock` 函数 (~365行)

### 3. 序列化时根据 TargetProvider 输出正确字段

在 `internal/ir/serialize_anthropic.go` 中修改消息序列化逻辑：

1. 更新 `serializeAnthropicMessages` 函数签名，传递 `TargetProvider`：
```go
func serializeAnthropicMessages(req *InternalRequest) []map[string]any {
    messages := make([]map[string]any, 0, len(req.Messages))
    for _, msg := range req.Messages {
        messages = append(messages, serializeAnthropicMessage(msg, req.TargetProvider))
    }
    return messages
}
```

2. 更新 `serializeAnthropicMessage` 函数，根据 provider 选择字段名：
```go
func serializeAnthropicMessage(msg Message, targetProvider string) map[string]any {
    if msg.Role == "tool" {
        // ...
        if msg.ToolCallID != "" {
            // MiniMax uses "tool_call_id" instead of standard "tool_use_id"
            if targetProvider == "minimax" {
                toolResult["tool_call_id"] = msg.ToolCallID
            } else {
                toolResult["tool_use_id"] = msg.ToolCallID
            }
        }
        // ...
    }
    // ...
}
```

## 测试覆盖

创建了完整的测试套件 `internal/ir/parse_anthropic_minimax_test.go`：

1. `TestParseAnthropic_MinimaxToolCallID` - 测试解析 MiniMax 的 `tool_call_id`
2. `TestParseAnthropic_StandardToolUseID` - 测试标准 Anthropic 的 `tool_use_id` 仍然正常工作
3. `TestSerializeAnthropic_MinimaxToolCallID` - 测试序列化时为 MiniMax 输出 `tool_call_id`
4. `TestSerializeAnthropic_StandardToolUseID` - 测试标准 Anthropic 序列化仍然正常

所有测试均通过，且没有破坏现有的任何测试。

## 使用方法

在创建 `InternalRequest` 时，设置 `TargetProvider` 字段：

```go
req := &InternalRequest{
    Model:          "abab6.5s-chat",
    MaxTokens:      1024,
    TargetProvider: "minimax",  // 指定目标提供商
    Messages:       messages,
}
```

如果不设置或设置为空字符串，则使用标准 Anthropic 协议。

## 兼容性

- ✅ 完全向后兼容
- ✅ 不影响现有的 Anthropic 集成
- ✅ 不影响 OpenAI 格式
- ✅ 所有现有测试通过

## 待办事项

1. **集成到请求处理流程**: 需要在实际的请求处理代码中设置 `TargetProvider` 字段（可能在路由层或转换层）
2. **端到端测试**: 使用真实的 MiniMax API 进行集成测试
3. **文档更新**: 更新 API 文档说明 MiniMax 的特殊处理

## 相关文件

- `internal/ir/types.go` - 添加 TargetProvider 字段
- `internal/ir/parse_anthropic.go` - 解析 tool_call_id
- `internal/ir/serialize_anthropic.go` - 序列化 tool_call_id
- `internal/ir/parse_anthropic_minimax_test.go` - 测试套件
