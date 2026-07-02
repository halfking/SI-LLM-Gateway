# Provider Adapter Architecture - 提供商适配器架构设计

## 问题背景

不同的大模型提供商虽然声称支持标准协议（OpenAI/Anthropic），但实际上存在各种差异：

### 已知的提供商差异

1. **MiniMax**
   - 使用 `tool_call_id` 而不是 `tool_use_id`
   - 可能有其他特定的参数要求

2. **其他提供商的潜在差异**
   - 参数名称不同
   - 默认值不同
   - 支持的功能子集不同
   - 错误响应格式不同
   - 流式响应的事件格式差异

### 当前实现的问题

```go
// 当前的硬编码方式
if targetProvider == "minimax" {
    toolResult["tool_call_id"] = msg.ToolCallID
} else {
    toolResult["tool_use_id"] = msg.ToolCallID
}
```

这种方式的问题：
- ❌ 难以扩展（每个提供商都要加 if-else）
- ❌ 职责不清晰（IR 层承担了太多提供商特定逻辑）
- ❌ 难以测试（每个组合都要测试）
- ❌ 难以维护（逻辑分散）

## 架构设计

### 核心概念：Provider Adapter（提供商适配器）

每个提供商有自己的适配器，负责：
1. **协议转换**：处理该提供商的特殊字段映射
2. **参数验证**：验证并调整参数以符合提供商要求
3. **错误处理**：转换提供商特定的错误格式
4. **功能适配**：处理不支持的功能（降级或报错）

### 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                      Gateway Layer                           │
│                   (统一的请求入口)                            │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                   Internal Request (IR)                      │
│                  (标准化的中间表示)                           │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              Provider Adapter Factory                        │
│         (根据 provider 选择对应的适配器)                      │
└──────────────────────┬──────────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┬──────────────┐
        │              │              │              │
        ▼              ▼              ▼              ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│   Standard   │ │   MiniMax    │ │    DeepSeek  │ │   Custom     │
│   Anthropic  │ │   Adapter    │ │   Adapter    │ │   Adapter    │
│   Adapter    │ │              │ │              │ │              │
└──────┬───────┘ └──────┬───────┘ └──────┬───────┘ └──────┬───────┘
       │                │                │                │
       └────────────────┴────────────────┴────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                  Upstream Provider API                       │
└─────────────────────────────────────────────────────────────┘
```

## 接口设计

### 1. ProviderAdapter 接口

```go
package adapter

import "github.com/kaixuan/llm-gateway-go/internal/ir"

// ProviderAdapter defines the interface for provider-specific adaptations
type ProviderAdapter interface {
    // Name returns the provider identifier (e.g., "minimax", "anthropic", "deepseek")
    Name() string
    
    // AdaptRequest adapts the IR to provider-specific format
    // This is called before serialization
    AdaptRequest(req *ir.InternalRequest) (*ir.InternalRequest, error)
    
    // SerializeRequest serializes the adapted IR to provider's request format
    SerializeRequest(req *ir.InternalRequest) ([]byte, error)
    
    // ParseResponse parses provider's response into IR
    ParseResponse(body []byte) (*ir.InternalResponse, error)
    
    // AdaptError converts provider-specific errors to standard format
    AdaptError(err error, body []byte) error
    
    // ValidateRequest checks if the request is supported by this provider
    ValidateRequest(req *ir.InternalRequest) error
    
    // GetCapabilities returns what features this provider supports
    GetCapabilities() ProviderCapabilities
}

// ProviderCapabilities describes what a provider supports
type ProviderCapabilities struct {
    SupportsToolCalling  bool
    SupportsStreaming    bool
    SupportsVision       bool
    SupportsThinking     bool
    MaxTokens            int
    SupportedModels      []string
    CustomParameters     map[string]any
}
```

### 2. Adapter Factory

```go
package adapter

import (
    "fmt"
    "sync"
)

// Factory manages provider adapters
type Factory struct {
    adapters map[string]ProviderAdapter
    mu       sync.RWMutex
}

// NewFactory creates a new adapter factory with default adapters
func NewFactory() *Factory {
    f := &Factory{
        adapters: make(map[string]ProviderAdapter),
    }
    
    // Register default adapters
    f.Register(NewAnthropicAdapter())
    f.Register(NewMinimaxAdapter())
    f.Register(NewDeepSeekAdapter())
    
    return f
}

// Register registers a new provider adapter
func (f *Factory) Register(adapter ProviderAdapter) {
    f.mu.Lock()
    defer f.mu.Unlock()
    f.adapters[adapter.Name()] = adapter
}

// Get returns the adapter for the specified provider
func (f *Factory) Get(provider string) (ProviderAdapter, error) {
    f.mu.RLock()
    defer f.mu.RUnlock()
    
    adapter, ok := f.adapters[provider]
    if !ok {
        return nil, fmt.Errorf("unknown provider: %s", provider)
    }
    return adapter, nil
}

// GetOrDefault returns the adapter or the default Anthropic adapter
func (f *Factory) GetOrDefault(provider string) ProviderAdapter {
    adapter, err := f.Get(provider)
    if err != nil {
        // Return default Anthropic adapter
        return f.adapters["anthropic"]
    }
    return adapter
}
```

### 3. MiniMax Adapter 实现示例

```go
package adapter

import (
    "encoding/json"
    "github.com/kaixuan/llm-gateway-go/internal/ir"
)

// MinimaxAdapter handles MiniMax-specific protocol variations
type MinimaxAdapter struct {
    base *AnthropicAdapter // 继承标准 Anthropic 逻辑
}

func NewMinimaxAdapter() *MinimaxAdapter {
    return &MinimaxAdapter{
        base: NewAnthropicAdapter(),
    }
}

func (a *MinimaxAdapter) Name() string {
    return "minimax"
}

func (a *MinimaxAdapter) AdaptRequest(req *ir.InternalRequest) (*ir.InternalRequest, error) {
    // MiniMax 特定的请求适配逻辑
    adapted := *req // 浅拷贝
    
    // 标记这是 MiniMax 请求（用于序列化时的判断）
    adapted.TargetProvider = "minimax"
    
    // 其他 MiniMax 特定的调整
    // 例如：调整参数范围、添加默认值等
    
    return &adapted, nil
}

func (a *MinimaxAdapter) SerializeRequest(req *ir.InternalRequest) ([]byte, error) {
    // 调用标准 Anthropic 序列化
    body, err := ir.SerializeAnthropic(req)
    if err != nil {
        return nil, err
    }
    
    // MiniMax 特定的后处理
    var data map[string]any
    if err := json.Unmarshal(body, &data); err != nil {
        return nil, err
    }
    
    // 替换 tool_use_id 为 tool_call_id（这个逻辑可以移到这里）
    if messages, ok := data["messages"].([]any); ok {
        for _, msg := range messages {
            if msgMap, ok := msg.(map[string]any); ok {
                a.adaptToolResultFields(msgMap)
            }
        }
    }
    
    return json.Marshal(data)
}

func (a *MinimaxAdapter) adaptToolResultFields(msg map[string]any) {
    // 递归处理 content blocks，将 tool_use_id 替换为 tool_call_id
    if content, ok := msg["content"].([]any); ok {
        for _, block := range content {
            if blockMap, ok := block.(map[string]any); ok {
                if blockMap["type"] == "tool_result" {
                    if toolUseID, exists := blockMap["tool_use_id"]; exists {
                        blockMap["tool_call_id"] = toolUseID
                        delete(blockMap, "tool_use_id")
                    }
                }
            }
        }
    }
}

func (a *MinimaxAdapter) ParseResponse(body []byte) (*ir.InternalResponse, error) {
    // MiniMax 的响应格式可能也有差异
    // 先做 MiniMax 特定的预处理
    var data map[string]any
    if err := json.Unmarshal(body, &data); err != nil {
        return nil, err
    }
    
    // 将 tool_call_id 转换为 tool_use_id（标准化）
    a.normalizeToolFields(data)
    
    // 重新序列化后使用标准解析器
    normalized, _ := json.Marshal(data)
    return ir.ParseAnthropicResponse(normalized)
}

func (a *MinimaxAdapter) normalizeToolFields(data map[string]any) {
    // 将 MiniMax 的 tool_call_id 转换回标准的 tool_use_id
    // 这样 IR 层只需要处理标准格式
}

func (a *MinimaxAdapter) AdaptError(err error, body []byte) error {
    // MiniMax 特定的错误处理
    return a.base.AdaptError(err, body)
}

func (a *MinimaxAdapter) ValidateRequest(req *ir.InternalRequest) error {
    // 验证 MiniMax 是否支持该请求
    caps := a.GetCapabilities()
    
    if req.MaxTokens > caps.MaxTokens {
        return fmt.Errorf("max_tokens %d exceeds MiniMax limit %d", 
            req.MaxTokens, caps.MaxTokens)
    }
    
    // 检查模型是否支持
    supported := false
    for _, model := range caps.SupportedModels {
        if model == req.Model {
            supported = true
            break
        }
    }
    if !supported {
        return fmt.Errorf("model %s not supported by MiniMax", req.Model)
    }
    
    return nil
}

func (a *MinimaxAdapter) GetCapabilities() ProviderCapabilities {
    return ProviderCapabilities{
        SupportsToolCalling: true,
        SupportsStreaming:   true,
        SupportsVision:      true,
        SupportsThinking:    false,
        MaxTokens:           8192,
        SupportedModels: []string{
            "abab6.5s-chat",
            "abab6.5-chat",
            "abab5.5-chat",
        },
        CustomParameters: map[string]any{
            "tool_id_field": "tool_call_id", // 标记使用的字段名
        },
    }
}
```

## 使用方式

### 在路由层集成

```go
package relay

import (
    "github.com/kaixuan/llm-gateway-go/adapter"
    "github.com/kaixuan/llm-gateway-go/internal/ir"
)

type Handler struct {
    adapterFactory *adapter.Factory
}

func NewHandler() *Handler {
    return &Handler{
        adapterFactory: adapter.NewFactory(),
    }
}

func (h *Handler) HandleRequest(req *ir.InternalRequest, provider string) ([]byte, error) {
    // 1. 获取对应的适配器
    adapter, err := h.adapterFactory.Get(provider)
    if err != nil {
        return nil, err
    }
    
    // 2. 验证请求
    if err := adapter.ValidateRequest(req); err != nil {
        return nil, fmt.Errorf("request validation failed: %w", err)
    }
    
    // 3. 适配请求
    adaptedReq, err := adapter.AdaptRequest(req)
    if err != nil {
        return nil, fmt.Errorf("request adaptation failed: %w", err)
    }
    
    // 4. 序列化
    body, err := adapter.SerializeRequest(adaptedReq)
    if err != nil {
        return nil, fmt.Errorf("serialization failed: %w", err)
    }
    
    // 5. 发送到上游
    respBody, err := h.sendToUpstream(provider, body)
    if err != nil {
        // 6. 错误适配
        return nil, adapter.AdaptError(err, respBody)
    }
    
    // 7. 解析响应
    resp, err := adapter.ParseResponse(respBody)
    if err != nil {
        return nil, err
    }
    
    return resp, nil
}
```

## 优势分析

### ✅ 可扩展性
- 新增提供商只需实现一个 Adapter
- 不需要修改 IR 核心代码
- 可以独立测试每个 Adapter

### ✅ 职责清晰
- IR 层：只负责标准化的中间表示
- Adapter 层：负责提供商特定的转换
- 路由层：负责选择和使用 Adapter

### ✅ 易于维护
- 每个提供商的逻辑集中在一个文件
- 容易定位和修复问题
- 代码结构清晰

### ✅ 易于测试
- 可以 mock Adapter 接口
- 每个 Adapter 可以独立测试
- 容易添加集成测试

### ✅ 功能丰富
- Capabilities 系统可以动态检查功能支持
- 可以实现功能降级策略
- 支持运行时动态注册 Adapter

## 迁移路径

### Phase 1: 创建基础架构
1. 定义 ProviderAdapter 接口
2. 创建 Factory
3. 实现 StandardAnthropicAdapter

### Phase 2: 迁移 MiniMax
1. 创建 MinimaxAdapter
2. 将现有的 MiniMax 特殊处理逻辑移到 Adapter
3. 更新测试

### Phase 3: 集成到路由层
1. 在路由层注入 AdapterFactory
2. 根据 provider 参数选择 Adapter
3. 更新请求处理流程

### Phase 4: 扩展到其他提供商
1. 为每个提供商创建 Adapter
2. 逐步迁移现有的特殊处理逻辑
3. 完善测试覆盖

## 目录结构建议

```
internal/
├── adapter/
│   ├── adapter.go              # 接口定义
│   ├── factory.go              # Factory 实现
│   ├── base_anthropic.go       # 标准 Anthropic Adapter
│   ├── minimax.go              # MiniMax Adapter
│   ├── deepseek.go             # DeepSeek Adapter
│   ├── openai_compatible.go    # 通用 OpenAI 兼容 Adapter
│   └── adapter_test.go         # 测试
├── ir/
│   ├── types.go                # IR 类型定义
│   ├── parse_anthropic.go      # 标准 Anthropic 解析
│   ├── serialize_anthropic.go  # 标准 Anthropic 序列化
│   └── ...
└── ...
```

## 总结

使用 Provider Adapter 模式可以：
1. **解耦**: IR 层不再需要知道具体提供商的差异
2. **扩展**: 轻松添加新的提供商支持
3. **维护**: 每个提供商的逻辑集中管理
4. **测试**: 更容易编写和维护测试
5. **灵活**: 支持运行时动态配置和热更新

这是一个更加优雅和可维护的架构设计。
