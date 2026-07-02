# Provider Adapter 实施计划 - 7-8个优先提供商

## 📊 当前支持的提供商清单

根据代码调研，当前系统支持以下提供商：

### Tier 1: 核心提供商（支持 Tool Calling）
1. **OpenAI** - 标准 OpenAI Chat Completions API
2. **Anthropic** - 标准 Anthropic Messages API  
3. **MiniMax** - Anthropic 格式，但使用 `tool_call_id`（已修复）
4. **智谱 AI (ZhiPu)** - 支持 tool calling

### Tier 2: 重要提供商
5. **DeepSeek** - OpenAI 兼容格式
6. **通义千问 (Qwen/Alibaba)** - OpenAI 兼容
7. **豆包 (Doubao/ByteDance)** - OpenAI 兼容
8. **Moonshot AI (Kimi)** - OpenAI 兼容

### Tier 3: 其他提供商
9. **StepFun** - OpenAI 兼容
10. **SiliconFlow** - 聚合平台，OpenAI 兼容
11. **OpenRouter** - 聚合平台，OpenAI 兼容

## 🎯 建议的实施顺序（前8个）

### Phase 1: 基础架构 + 标准协议（第1周）

**1.1 创建 Adapter 架构**
- [ ] 创建 `internal/adapter` 包
- [ ] 定义 `ProviderAdapter` 接口
- [ ] 实现 `AdapterFactory` 工厂类
- [ ] 编写基础测试框架

**1.2 实现标准 Adapter**
- [ ] `StandardAnthropicAdapter` - Anthropic 标准实现
- [ ] `StandardOpenAIAdapter` - OpenAI 标准实现
- [ ] 完整的单元测试

### Phase 2: Tool Calling 提供商（第2周）

这些提供商有特殊的 tool calling 行为，优先适配：

**2.1 MiniMax Adapter**（最高优先级）
- [ ] 创建 `MinimaxAdapter`
- [ ] 迁移现有的 `tool_call_id` 逻辑到 Adapter
- [ ] `tool_call_id` ↔ `tool_use_id` 双向转换
- [ ] 完整测试覆盖
- [ ] 集成到路由层

**2.2 智谱 AI (ZhiPu) Adapter**
- [ ] 创建 `ZhipuAdapter`
- [ ] 调研智谱的 tool calling 特殊行为
- [ ] 实现特定的参数映射
- [ ] 测试和验证

**2.3 Anthropic Adapter**（标准）
- [ ] 使用 `StandardAnthropicAdapter`
- [ ] 验证所有 Anthropic 特性正常工作

**2.4 OpenAI Adapter**（标准）
- [ ] 使用 `StandardOpenAIAdapter`
- [ ] 验证所有 OpenAI 特性正常工作

### Phase 3: 高流量提供商（第3周）

这些提供商流量大，影响面广：

**3.1 DeepSeek Adapter**
- [ ] 创建 `DeepSeekAdapter`
- [ ] 基于 OpenAI 标准，但可能有参数差异
- [ ] 调研 DeepSeek 的特殊限制（如 max_tokens）
- [ ] 测试和验证

**3.2 通义千问 (Qwen) Adapter**
- [ ] 创建 `QwenAdapter`
- [ ] 调研阿里云通义千问的特殊行为
- [ ] 参数映射和限制处理
- [ ] 测试和验证

**3.3 豆包 (Doubao) Adapter**
- [ ] 创建 `DoubaoAdapter`
- [ ] 调研字节跳动豆包的特殊行为
- [ ] 参数映射和限制处理
- [ ] 测试和验证

**3.4 Moonshot (Kimi) Adapter**
- [ ] 创建 `MoonshotAdapter`
- [ ] 调研 Moonshot 的特殊行为
- [ ] 长上下文处理优化
- [ ] 测试和验证

### Phase 4: 集成和优化（第4周）

**4.1 路由层集成**
- [ ] 在路由层注入 `AdapterFactory`
- [ ] 根据 `catalog_code` 自动选择 Adapter
- [ ] 更新请求处理流程
- [ ] 端到端测试

**4.2 监控和诊断**
- [ ] Adapter 选择的日志记录
- [ ] 每个 Adapter 的性能指标
- [ ] 错误处理和降级策略
- [ ] 诊断工具和调试接口

**4.3 文档和培训**
- [ ] 完整的 Adapter 开发指南
- [ ] 如何添加新 Adapter 的文档
- [ ] 每个提供商的特性说明
- [ ] 故障排查指南

## 🔍 每个 Adapter 需要调研的内容

对于每个提供商，需要调研和处理：

### 协议差异
- [ ] 请求格式差异（字段名、嵌套结构）
- [ ] 响应格式差异
- [ ] 错误响应格式
- [ ] 流式响应格式

### 参数差异
- [ ] 支持的参数列表
- [ ] 参数名称映射
- [ ] 参数取值范围
- [ ] 默认值差异

### Tool Calling 差异
- [ ] Tool 定义格式
- [ ] Tool call ID 字段名（`tool_call_id` vs `tool_use_id` vs 其他）
- [ ] Tool result 格式
- [ ] Tool choice 策略

### 功能支持
- [ ] 是否支持 streaming
- [ ] 是否支持 vision
- [ ] 是否支持 thinking blocks
- [ ] 是否支持 cache control
- [ ] 最大 token 限制
- [ ] 支持的模型列表

### 错误处理
- [ ] 错误码映射
- [ ] 错误消息格式
- [ ] 限流错误处理
- [ ] 余额不足错误

## 📁 目录结构

```
internal/
├── adapter/
│   ├── adapter.go                  # 接口定义
│   ├── factory.go                  # Factory 实现
│   ├── capabilities.go             # Capabilities 类型定义
│   ├── base_anthropic.go           # 标准 Anthropic Adapter
│   ├── base_openai.go              # 标准 OpenAI Adapter
│   ├── minimax.go                  # MiniMax Adapter
│   ├── zhipu.go                    # 智谱 Adapter
│   ├── deepseek.go                 # DeepSeek Adapter
│   ├── qwen.go                     # 通义千问 Adapter
│   ├── doubao.go                   # 豆包 Adapter
│   ├── moonshot.go                 # Moonshot Adapter
│   ├── adapter_test.go             # 通用测试工具
│   ├── minimax_test.go             # MiniMax 测试
│   ├── zhipu_test.go               # 智谱测试
│   └── ...                         # 其他 Adapter 测试
├── ir/
│   ├── types.go                    # IR 类型（保持不变）
│   ├── parse_anthropic.go          # 标准解析（简化）
│   ├── serialize_anthropic.go      # 标准序列化（简化）
│   └── ...
└── ...
```

## 🧪 测试策略

### 单元测试
每个 Adapter 需要测试：
- ✅ Request adaptation
- ✅ Request serialization
- ✅ Response parsing
- ✅ Error handling
- ✅ Validation
- ✅ Capabilities

### 集成测试
- ✅ End-to-end request flow
- ✅ Tool calling flow（多轮对话）
- ✅ Streaming
- ✅ Error scenarios
- ✅ Rate limiting

### 兼容性测试
- ✅ 与现有系统的向后兼容
- ✅ 所有现有测试继续通过
- ✅ 现有功能不受影响

## 📊 成功指标

### 代码质量
- 每个 Adapter < 500 行代码
- 测试覆盖率 > 80%
- 所有 linter 检查通过

### 性能
- Adapter 选择和转换 < 1ms
- 内存开销 < 1MB per request
- 无性能退化

### 可维护性
- 新增提供商 < 1 天开发时间
- 清晰的文档和示例
- 易于调试和诊断

## ⏱️ 时间估算

| Phase | 任务 | 估计时间 | 优先级 |
|-------|------|---------|--------|
| Phase 1 | 基础架构 + 标准协议 | 3-4 天 | P0 |
| Phase 2.1 | MiniMax Adapter | 1-2 天 | P0 |
| Phase 2.2 | 智谱 Adapter | 1-2 天 | P1 |
| Phase 2.3-2.4 | OpenAI/Anthropic | 1 天 | P1 |
| Phase 3.1 | DeepSeek | 1 天 | P1 |
| Phase 3.2 | 通义千问 | 1 天 | P1 |
| Phase 3.3 | 豆包 | 1 天 | P2 |
| Phase 3.4 | Moonshot | 1 天 | P2 |
| Phase 4 | 集成优化 | 2-3 天 | P1 |
| **总计** | | **12-17 天** | |

## 🚀 即时行动项

### 今天可以开始：

1. **创建 Adapter 基础架构**
   - 定义接口
   - 实现 Factory
   - 编写第一个测试

2. **实现 MiniMax Adapter**
   - 将现有修复迁移到 Adapter
   - 完整测试

3. **文档化调研需求**
   - 为每个提供商创建调研清单
   - 分配调研任务

## 💡 建议

1. **先完成架构，再逐个迁移**：确保架构稳定后再添加 Adapter
2. **优先处理 tool calling**：这些提供商差异最大，价值最高
3. **持续集成测试**：每个 Adapter 完成后立即集成测试
4. **渐进式部署**：通过功能开关逐步启用每个 Adapter
5. **监控和反馈**：部署后密切监控，快速响应问题

## 📝 下一步

要开始实施吗？我建议：
1. 先完成 Phase 1（基础架构）
2. 然后立即做 MiniMax Adapter（已经有基础）
3. 并行开始其他提供商的调研

需要我现在就开始实现 Phase 1 吗？
