# Provider Adapter 架构指南

**文档版本**: 1.0  
**创建日期**: 2026-07-04  
**状态**: ✅ 已实施并验证

---

## 1. 概述

Provider Adapter 是 llm-gateway-go 的提供商协议适配层，位于 IR（中间表示）和上游提供商 API 之间。它负责处理不同提供商之间的协议差异，使得 IR 层可以保持纯粹的标准化逻辑。

### 1.1 架构图

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

---

## 2. 已支持的提供商

| 提供商 | catalog_code | 协议 | 特殊处理 |
|--------|-------------|------|---------|
| Anthropic | `anthropic` | anthropic-messages | 标准基类 |
| OpenAI | `openai` | openai-completions | 标准基类 |
| MiniMax | `minimax` | anthropic-messages | `tool_call_id` 替代 `tool_use_id` |
| DeepSeek | `deepseek` | openai-completions | max_tokens ≤ 8192 |
| 通义千问 | `qwen` `qwen2` `qwen3` `qwq` | openai-completions | max_tokens ≤ 8192, temperature/top_p 互斥 |
| 豆包 | `doubao` | openai-completions | max_tokens ≤ 4096, temperature ∈ [0,1] |
| Moonshot | `moonshot` `kimi` | openai-completions | max_tokens ≤ 8192 |
| 智谱AI | `zhipu` `glm` | openai-completions | max_tokens ≤ 8192 |

---

## 3. 接口设计

### 3.1 ProviderAdapter 接口

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

### 3.2 Adapter Factory

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

---

## 4. MiniMax 适配示例

### 4.1 问题背景

MiniMax 使用非标准的 `tool_call_id` 字段（标准 Anthropic 使用 `tool_use_id`）。

### 4.2 解决方案

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
    
    // 替换 tool_use_id 为 tool_call_id
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
    }
}
```

---

## 5. 使用方式

### 5.1 创建 Factory

```go
import "github.com/kaixuan/llm-gateway-go/internal/adapter"

factory := adapter.NewFactory()
// 自动注册所有内置 adapter
```

### 5.2 获取 Adapter

```go
// 按 catalog_code 精确获取
pa, err := factory.Get("minimax")

// 按 catalog_code + protocol 获取（带 fallback）
pa := factory.GetOrDefault(cand.CatalogCode, cand.Protocol)
```

### 5.3 适配请求

```go
// ParseOpenAI → IR → AdaptRequest → SerializeAnthropic
irReq, err := ir.ParseOpenAI(clientBody)
pa := factory.GetOrDefault(cand.CatalogCode, cand.Protocol)
irReq, err = pa.AdaptRequest(irReq)
bodyBytes, err := ir.SerializeAnthropic(irReq)
```

### 5.4 查询能力

```go
caps := pa.GetCapabilities()
if !caps.SupportsToolCalling {
    return errors.New("provider does not support tool calling")
}
if irReq.MaxTokens > caps.MaxTokens {
    // handle or clamp
}
```

---

## 6. 如何添加新提供商

### 步骤 1: 创建 Adapter 文件

创建 `internal/adapter/newvendor.go`:

```go
package adapter

import "github.com/kaixuan/llm-gateway-go/internal/ir"

// NewVendor speaks OpenAI Chat Completions with minor quirks.
type NewVendor struct {
    StandardOpenAI  // 匿名嵌入标准 OpenAI adapter
}

func NewNewVendor() *NewVendor { return &NewVendor{} }

func (n *NewVendor) Name() string           { return "newvendor" }
func (n *NewVendor) CatalogCodes() []string { return []string{"newvendor", "nv"} }

func (n *NewVendor) AdaptRequest(req *ir.InternalRequest) (*ir.InternalRequest, error) {
    adapted := clampMaxTokens(req, 4096)  // 限制 max_tokens
    out := *adapted
    out.TargetProvider = "newvendor"
    return &out, nil
}

func (n *NewVendor) GetCapabilities() Capabilities {
    return Capabilities{
        SupportsToolCalling:  true,
        SupportsStreaming:    true,
        SupportsVision:       false,
        SupportsThinking:     false,
        SupportsCacheControl: false,
        MaxTokens:            4096,
        ToolIDField:          "tool_call_id",
    }
}
```

### 步骤 2: 注册到 Factory

在 `internal/adapter/standard.go` 的 `defaultAdapters()` 中添加:

```go
func defaultAdapters() []ProviderAdapter {
    return []ProviderAdapter{
        StandardAnthropic{},
        StandardOpenAI{},
        NewMinimax(),
        // ... existing adapters ...
        NewNewVendor(),  // ← 新增
    }
}
```

### 步骤 3: 编写测试

创建 `internal/adapter/newvendor_test.go`:

```go
func TestNewVendor_AdaptRequest_ClampsMaxTokens(t *testing.T) {
    n := NewNewVendor()
    req := &ir.InternalRequest{MaxTokens: 10000}
    out, err := n.AdaptRequest(req)
    if err != nil { t.Fatalf("AdaptRequest: %v", err) }
    if out.MaxTokens != 4096 {
        t.Errorf("MaxTokens = %d, want 4096", out.MaxTokens)
    }
}
```

---

## 7. 测试

### 7.1 运行所有测试

```bash
go test ./internal/adapter/ -v
```

### 7.2 测试覆盖

| 类别 | 测试数 | 内容 |
|------|--------|------|
| 单元测试 | 16 | 各提供商 AdaptRequest 逻辑 |
| Factory 测试 | 3 | 路由 + 别名 + fallback |
| 端到端测试 | 6 | 完整 Parse→Adapt→Serialize 流程 |
| 编译检查 | 8 | 接口合规性 |
| **总计** | **33** | |

---

## 8. 架构设计原则

1. **组合优于继承** — adapter 通过匿名嵌入复用基类逻辑
2. **接口驱动** — ProviderAdapter 接口定义清晰契约
3. **零破坏** — AdapterFactory 为 nil 时完全回退到原有逻辑
4. **防御性编程** — MiniMax 双保险（IR 层 TargetProvider + body rewrite）
5. **可测试** — 每个 adapter 可以独立测试，不需要真实 API

---

## 9. 文件结构

```
internal/adapter/
├── adapter.go              # ProviderAdapter 接口 + Capabilities
├── factory.go              # Factory（路由 + 别名 + fallback）
├── standard.go             # StandardAnthropic + StandardOpenAI 基类
├── minimax.go              # MiniMax adapter
├── providers.go            # DeepSeek/Qwen/Doubao/Moonshot/Zhipu
├── minimax_test.go         # MiniMax + Factory 测试
├── providers_test.go       # 各提供商适配测试
├── e2e_test.go             # 端到端集成测试
└── adapter_compile_test.go # 编译时接口检查
```

---

## 10. 实施计划

### Phase 1: 基础架构 + 标准协议（第1周）
- 创建 Adapter 基础架构
- 实现 StandardAnthropicAdapter
- 实现 StandardOpenAIAdapter

### Phase 2: Tool Calling 提供商（第2周）
- MiniMax Adapter（最高优先级）
- 智谱 AI Adapter
- Anthropic/OpenAI Adapter

### Phase 3: 高流量提供商（第3周）
- DeepSeek Adapter
- 通义千问 Adapter
- 豆包 Adapter
- Moonshot Adapter

### Phase 4: 集成和优化（第4周）
- 路由层集成
- 监控和诊断
- 文档和培训

---

**文档所有权**: Infrastructure Team  
**最后更新**: 2026-07-04