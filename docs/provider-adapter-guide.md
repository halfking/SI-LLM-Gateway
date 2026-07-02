# Provider Adapter 架构使用指南

## 概述

Provider Adapter 是 llm-gateway-go 的提供商协议适配层，位于 IR（中间表示）和上游提供商 API 之间。它负责处理不同提供商之间的协议差异，使得 IR 层可以保持纯粹的标准化逻辑。

```
Client Request
    │
    ▼
┌─────────────┐     ┌─────────────┐     ┌──────────────────────┐
│ IR Parser    │────▶│ InternalReq │────▶│ Provider Adapter     │
│ (OpenAI/     │     │ (标准化)     │     │ (提供商特化)          │
│  Anthropic)  │     │             │     │                      │
└─────────────┘     └─────────────┘     │ Anthropic  OpenAI     │
                                        │ MiniMax    DeepSeek   │
                                        │ Qwen  Doubao  Zhipu   │
                                        │ Moonshot              │
                                        └──────────┬───────────┘
                                                   │
                                                   ▼
                                        ┌──────────────────────┐
                                        │ Upstream Provider API │
                                        └──────────────────────┘
```

## 已支持的提供商

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

## 如何使用

### 1. 创建 Factory

```go
import "github.com/kaixuan/llm-gateway-go/internal/adapter"

factory := adapter.NewFactory()
// 自动注册所有内置 adapter
```

### 2. 获取 Adapter

```go
// 按 catalog_code 精确获取
pa, err := factory.Get("minimax")

// 按 catalog_code + protocol 获取（带 fallback）
// 未知 catalog_code 会根据 protocol 回退到标准 adapter
pa := factory.GetOrDefault(cand.CatalogCode, cand.Protocol)
```

### 3. 适配请求

```go
// ParseOpenAI → IR → AdaptRequest → SerializeAnthropic
irReq, err := ir.ParseOpenAI(clientBody)
pa := factory.GetOrDefault(cand.CatalogCode, cand.Protocol)
irReq, err = pa.AdaptRequest(irReq)
bodyBytes, err := ir.SerializeAnthropic(irReq)
```

### 4. 查询能力

```go
caps := pa.GetCapabilities()
if !caps.SupportsToolCalling {
    return errors.New("provider does not support tool calling")
}
if irReq.MaxTokens > caps.MaxTokens {
    // handle or clamp
}
```

## 如何添加新提供商

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

### 完成！

新提供商现在会自动被 Factory 识别，无需修改路由层或 IR 层代码。

## 测试

### 运行所有测试

```bash
go test ./internal/adapter/ -v
```

### 测试覆盖

| 类别 | 测试数 | 内容 |
|------|--------|------|
| 单元测试 | 16 | 各提供商 AdaptRequest 逻辑 |
| Factory 测试 | 3 | 路由 + 别名 + fallback |
| 端到端测试 | 6 | 完整 Parse→Adapt→Serialize 流程 |
| 编译检查 | 8 | 接口合规性 |
| **总计** | **33** | |

## 架构设计原则

1. **组合优于继承** — adapter 通过匿名嵌入复用基类逻辑
2. **接口驱动** — ProviderAdapter 接口定义清晰契约
3. **零破坏** — AdapterFactory 为 nil 时完全回退到原有逻辑
4. **防御性编程** — MiniMax 双保险（IR 层 TargetProvider + body rewrite）
5. **可测试** — 每个 adapter 可以独立测试，不需要真实 API

## 文件结构

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
