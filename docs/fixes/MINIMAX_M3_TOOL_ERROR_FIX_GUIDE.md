# MiniMax-M3 工具错误修正方案（跨版本审计指南）

**版本基线**: `2.3.3-6b9b7a9c-20260704-789`
**适用模型**: MiniMax-M3（minimax）、minimax-anthropic
**适用范围**: 所有支持 MiniMax 的网关版本，以及任何使用 OpenAI/Anthropic 兼容协议的相似 provider
**目的**: 为其他版本（v2.3.x、v2.4.x 等）的审计与修正提供统一检查清单

---

## 一、问题全景

MiniMax-M3 在生产环境暴露出 **两个独立的 bug**，都会触发上游错误 `tool result's tool id not found (2013)`，HTTP 400：

| Bug | 位置 | 性质 | 修复 commit |
|-----|------|------|-------------|
| Bug #1 | `internal/ir/serialize_openai.go` | 服务端序列化丢失 `tool_calls` 字段 | `9ce06c01` |
| Bug #2 | 客户端压缩逻辑 | 客户端删除 assistant 但保留 tool result | `6b9b7a9c`（服务端防御） |

虽然 Bug #2 根因在客户端，但 **服务端必须承担防御责任** —— 不能假设客户端永远正确。

---

## 二、数据转换链路与问题点

### 2.1 完整调用链

```
客户端（OpenAI / Anthropic 协议）
        ↓
  内部 IR（统一表示：Content + ToolCalls + ToolCallID + Role）
        ↓
  消息压缩（transform/ctx_compress.go:trimOldestPairs）
        ↓
  协议序列化（serialize_openai.go 或 serialize_anthropic.go + adapter）
        ↓
  上游 provider（minimax-M3）
```

### 2.2 IR 字段定义（关键）

在 IR 表示中，assistant 消息的 `tool_calls` 与 `content` 是 **相互独立的字段**：

```go
type Message struct {
    Role       string
    Content    []ContentBlock  // 可能为空
    ToolCalls  []ToolCall      // 可能为空
    ToolCallID string          // 仅 tool 角色使用
}
```

**关键事实**：`Content == []` 与 `ToolCalls != nil` 是 **合法的组合**，表示"模型只发起工具调用、没有附加文本"。序列化器必须同时输出两个字段。

### 2.3 Bug #1：序列化分支遗漏

**文件**：`internal/ir/serialize_openai.go`
**函数**：`serializeOpenAIMessage`（约 189–203 行）
**触发条件**：
- 消息角色 = `assistant`
- `len(msg.Content) == 0`
- `len(msg.ToolCalls) > 0`

**原代码（有缺陷）**：

```go
if len(msg.Content) == 0 {
    // ❌ 什么都不做 — tool_calls 字段丢失
} else if len(msg.Content) == 1 && msg.Content[0].Type == "text" && msg.ToolCalls == nil {
    out["content"] = msg.Content[0].Text
} else {
    content := serializeOpenAIMessageContent(msg.Content)
    out["content"] = content
    if len(msg.ToolCalls) > 0 {       // ⚠️ 只在这个分支处理 tool_calls
        out["tool_calls"] = serializeOpenAIToolCalls(msg.ToolCalls)
    }
}
```

**症状**（生产抓包）：

```json
// 实际发给 minimax-M3 的 assistant 消息
{
  "role": "assistant",
  "content": ""
  // ❌ 缺少 tool_calls
}

// 紧随其后的 tool 消息
{
  "role": "tool",
  "tool_call_id": "call_fdb0383f967843b6acf20f6e",
  "content": "..."
}
```

→ minimax-M3 找不到 `call_fdb0383f967843b6acf20f6e` 对应的 assistant tool_call，返回 `2013`。

---

### 2.4 Bug #2：客户端产生孤儿 tool result

**来源**：客户端（OpenCode / Claude Code 等）在压缩对话上下文时，只删除了 assistant 的 tool_calls 消息，但保留了对应的 tool result。

**服务端抓包示例**（request_id: `432c91467fc375bdcbf1c75afbe6e6f3`）：

```
原始请求：12 条消息
  - system × 1
  - user × 2
  - tool × 9        ← ❌ 全部孤儿，没有任何 assistant tool_calls
```

**特征**：
- 消息总数为偶数（38、40、42 … 50）
- tool 消息没有匹配的 assistant
- 出现在长对话 + 压缩触发场景

服务端无法保证客户端修复，因此必须 **在序列化阶段主动校验**。

---

## 三、解决方案与修正位置

### 3.1 修复 #1：序列化分支补全

**文件**：`internal/ir/serialize_openai.go`
**位置**：189–203 行附近

**修复后代码**：

```go
// 修复后
if len(msg.Content) == 0 {
    // 空 content 也可能是合法的纯工具调用
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

**核心规则**：**任何分支都要检查并输出 `tool_calls`**，不能依赖 `Content` 是否为空作为前置条件。

### 3.2 修复 #2：序列化前完整性校验

**文件**：`internal/ir/serialize_openai.go`
**位置**：`SerializeOpenAI` 末尾、返回 JSON 前

**新增逻辑**：

```go
// 仅当消息数 > 2 时校验，避免破坏单消息单元测试
if len(messages) > 2 {
    if err := validateToolCallIntegrity(messages); err != nil {
        return nil, fmt.Errorf("tool_call validation failed: %w", err)
    }
}
```

**校验函数**：

```go
func validateToolCallIntegrity(messages []map[string]any) error {
    toolCallIDs := make(map[string]bool)

    // 1. 收集所有 assistant 的 tool_call ID
    for _, msg := range messages {
        if role, _ := msg["role"].(string); role == "assistant" {
            if tcs, ok := msg["tool_calls"].([]any); ok {
                for _, tc := range tcs {
                    if tcMap, ok := tc.(map[string]any); ok {
                        if id, _ := tcMap["id"].(string); id != "" {
                            toolCallIDs[id] = true
                        }
                    }
                }
            }
        }
    }

    // 2. 检查 tool 消息是否都有对应 ID
    var orphans []string
    for _, msg := range messages {
        if role, _ := msg["role"].(string); role == "tool" {
            if id, _ := msg["tool_call_id"].(string); id != "" {
                if !toolCallIDs[id] {
                    orphans = append(orphans, id)
                }
            }
        }
    }

    if len(orphans) > 0 {
        return fmt.Errorf("found %d orphaned tool result(s) without matching assistant tool_calls: %v (likely client bug: assistant messages with tool_calls were removed during context compression)",
            len(orphans), orphans[:min(3, len(orphans))])
    }
    return nil
}
```

**返回错误的好处**：
- 阻止畸形请求打到上游
- 错误信息直接提示客户端开发者（`likely client bug`）
- 不会浪费一次重试或计费

### 3.3 Anthropic 适配器的特殊处理（参考）

MiniMax 同时走 Anthropic 兼容协议，**`tool_result` 块使用 `tool_call_id` 而非标准的 `tool_use_id`**。已在两处处理：

**位置 A**：`internal/ir/serialize_anthropic.go:166-171`

```go
if targetProvider == "minimax" {
    toolResult["tool_call_id"] = msg.ToolCallID
} else {
    toolResult["tool_use_id"] = msg.ToolCallID
}
```

**位置 B**：`internal/adapter/minimax.go` — `ensureToolCallID` 兜底重写

> 当 `TargetProvider` 未设置时，对序列化后的 JSON 做一次防御性 `tool_use_id → tool_call_id` 重写。

**审计要点**：如果未来新增 provider 复用了 Anthropic 协议但字段名不同，需要在 `serialize_anthropic.go` 同步增加分支。

---

## 四、跨版本审计清单

> **适用范围**：v2.3.x 全系、v2.4.x、未来 v3.x。审计按以下顺序执行。

### 4.1 必查代码点

| # | 检查项 | 文件 / 位置 | 期望状态 |
|---|--------|-------------|---------|
| 1 | `serializeOpenAIMessage` 中空 content 分支是否补 `tool_calls` | `internal/ir/serialize_openai.go` | ✅ 已补全 |
| 2 | `SerializeOpenAI` 末尾是否调用 `validateToolCallIntegrity` | `internal/ir/serialize_openai.go` | ✅ 已添加 |
| 3 | 是否有同样的 bug 出现在 Gemini / 其他协议序列化器 | `internal/ir/serialize_*.go` | ⏳ 待审 |
| 4 | `serializeAnthropicMessage` 对 `minimax` provider 的 tool_call_id 分支 | `internal/ir/serialize_anthropic.go:166-171` | ✅ 已处理 |
| 5 | `Minimax.SerializeRequest` 是否调用 `ensureToolCallID` 兜底 | `internal/adapter/minimax.go:48` | ✅ 已添加 |

### 4.2 通用审计规则（推广到任何 provider）

任何 provider 的序列化器，在处理 assistant 消息时，必须满足：

- [ ] **规则 A**：assistant 消息只要 `ToolCalls != nil`，输出 JSON 必须包含 `tool_calls` 字段
- [ ] **规则 B**：assistant 消息即使 `Content == nil/[]`，也要输出 `content` 字段（空串或占位），避免协议层缺字段报错
- [ ] **规则 C**：序列化器末尾、发送上游前，**必须**对所有 `tool` 消息做孤儿校验
- [ ] **规则 D**：校验失败时返回清晰错误（含孤儿 ID 与原因提示），不要把畸形请求打到上游
- [ ] **规则 E**：错误信息中必须包含 `likely client bug` 或等价提示，帮助客户端开发者定位

### 4.3 Anthropic 兼容 provider 额外检查

- [ ] `tool_result` 块的 ID 字段名是否符合 provider 协议（`tool_use_id` / `tool_call_id` / 其他）
- [ ] 是否需要 `ensure*ID` 兜底重写函数
- [ ] `AdaptRequest` 是否正确设置 `TargetProvider`，以触发序列化器分支

### 4.4 数据库 / 监控侧审计

- [ ] 错误分类 `KindToolCallIdMismatch` 是否在 `errorsx/classify.go` 定义
- [ ] 数据库是否记录 `upstream_status_code`、`failure_stage`、`response_body`
- [ ] 是否能按 `error_kind = 'tool_call_id_mismatch'` 聚合查询

---

## 五、测试与验证策略

### 5.1 必跑测试

```bash
# 单元测试
go test ./internal/ir/...           # serialize_openai、serialize_anthropic
go test ./internal/adapter/...      # minimax adapter
go test ./transform/...             # ctx_compress
```

### 5.2 关键测试用例（参考现有文件，可平移到其他版本）

| 测试文件 | 用例 | 覆盖场景 |
|---------|------|---------|
| `serialize_openai_toolcalls_test.go` | `TestSerializeOpenAI_EmptyContentWithToolCalls` | 单 tool_call + 空 content |
| `serialize_openai_toolcalls_test.go` | `TestSerializeOpenAI_MultipleToolCallsWithEmptyContent` | 多 tool_call + 空 content |
| `serialize_openai_validation_test.go` | `TestSerializeOpenAI_OrphanedToolResults` | 全孤儿 tool result |
| `serialize_openai_validation_test.go` | `TestSerializeOpenAI_ValidToolCalls` | 正常链路 |
| `serialize_openai_validation_test.go` | `TestSerializeOpenAI_PartialOrphans` | 部分孤儿 |
| `ctx_compress_orphan_test.go` | `TestTrimOldestPairs_ToolCallOrphaning` | 压缩不产生孤儿 |
| `ctx_compress_massive_test.go` | `TestTrimOldestPairs_MassiveToolRounds` | 40+ tool round 大规模 |
| `minimax_roundtrip_test.go` | `TestMiniMax_FullToolCallingRoundTrip` | minimax 全链路往返 |
| `minimax_test.go` | `TestMinimax_AdaptRequest_SetsTargetProvider` | TargetProvider 设置验证 |
| `minimax_test.go` | `TestMinimax_SerializeRequest_ToolCallID` | tool_call_id 转换验证 |

### 5.3 端到端验证步骤

1. **本地构建**：`go build ./...`
2. **本地测试栈**：启动本地 gateway，发送带 50+ tool_call 的长对话请求
3. **抓包核对**：用 `tcpdump` 或日志检查发往上游的 JSON：
   - assistant 消息是否含 `tool_calls` 数组
   - tool 消息是否全部能找到匹配的 assistant ID
4. **错误注入测试**：故意构造孤儿 tool result，验证网关返回 `tool_call validation failed` 错误

### 5.4 生产灰度指标

部署后 24–48 小时重点观察：

```sql
-- 1. 修复前的主要错误应清零
SELECT COUNT(*) FROM request_logs
WHERE error_kind = 'tool_call_id_mismatch'
  AND provider_code LIKE '%minimax%'
  AND ts > NOW() - INTERVAL '1 hour';

-- 2. 成功率应恢复到 > 95%
SELECT
  100.0 * COUNT(*) FILTER (WHERE success) / COUNT(*) AS success_rate
FROM request_logs
WHERE provider_code LIKE '%minimax%'
  AND ts > NOW() - INTERVAL '1 hour';

-- 3. 客户端 bug 暴露（通过新的 validation 错误）
SELECT COUNT(*) FROM error_logs
WHERE message LIKE '%orphaned tool result%'
  AND ts > NOW() - INTERVAL '1 hour';
```

---

## 六、部署与回滚

### 6.1 部署顺序

```
本地 → 184 测试环境 → 71 生产环境
```

### 6.2 回滚要点

- 保留上一版本二进制（`llm-gateway-go.bak`）
- 184 用 `kubectl rollout undo`
- 71 用 `systemctl stop && ./llm-gateway-go.bak`

### 6.3 关键监控告警

```yaml
alerts:
  - name: minimax_tool_call_errors
    condition: error_kind == 'tool_call_id_mismatch'
    threshold: > 0 in 5 minutes
    action: notify_oncall

  - name: minimax_success_rate_low
    condition: success_rate < 90% over 10 minutes
    action: notify_oncall

  - name: minimax_orphaned_tool_results
    condition: error message contains "orphaned tool result" count > 5 / 10min
    action: notify_client_team
```

---

## 七、常见问题与排查指引

| 现象 | 可能原因 | 排查方向 |
|------|---------|---------|
| 仍有 `tool_call_id_mismatch` 错误 | 序列化器未修复或版本未升级 | 检查 `serialize_openai.go` 是否含修复 + 二进制版本 |
| 出现新 `tool_call validation failed` 错误 | 客户端发送畸形请求（正常拦截） | 通知客户端，错误信息已指明孤儿 ID |
| Anthropic 协议走 minimax 失败 | `TargetProvider` 未设置 | 检查 `AdaptRequest` 与 `ensureToolCallID` 兜底 |
| 压缩后消息数量异常 | `trimOldestPairs` 未成对删除 | 跑 `ctx_compress_orphan_test.go` |

---

## 八、变更摘要（用于版本回溯）

| Commit | 文件 | 关键变更 |
|--------|------|---------|
| `9ce06c01` | `internal/ir/serialize_openai.go` | 空 content 分支补 `tool_calls` 输出 |
| `9ce06c01` | `internal/ir/serialize_openai_toolcalls_test.go` | 新增 2 个测试 |
| `9ce06c01` | `transform/ctx_compress_orphan_test.go` | 压缩孤儿测试 |
| `9ce06c01` | `transform/ctx_compress_massive_test.go` | 大规模压缩测试 |
| `6b9b7a9c` | `internal/ir/serialize_openai.go` | 新增 `validateToolCallIntegrity` |
| `6b9b7a9c` | `internal/ir/serialize_openai_validation_test.go` | 3 个校验测试 |

---

## 九、其他版本的审计操作指南

### 9.1 一键审计脚本（建议）

```bash
#!/bin/bash
# audit-tool-call-fix.sh — 在目标版本根目录执行
set -e

echo "=== 1. 检查 serialize_openai.go 的空 content 分支 ==="
grep -n "len(msg.Content) == 0" internal/ir/serialize_openai.go || echo "❌ 未找到空 content 分支"

echo "=== 2. 检查 tool_calls 是否在空分支输出 ==="
awk '/len\(msg\.Content\) == 0/,/^[[:space:]]*}[[:space:]]*else/' \
  internal/ir/serialize_openai.go | grep -q "tool_calls" \
  && echo "✅ 空分支含 tool_calls 输出" \
  || echo "❌ 空分支缺少 tool_calls 输出"

echo "=== 3. 检查 validateToolCallIntegrity 是否存在 ==="
grep -q "func validateToolCallIntegrity" internal/ir/serialize_openai.go \
  && echo "✅ 已存在完整性校验" \
  || echo "❌ 缺少完整性校验"

echo "=== 4. 检查 SerializeOpenAI 是否调用校验 ==="
grep -A 3 "validateToolCallIntegrity(messages)" internal/ir/serialize_openai.go \
  && echo "✅ 已在序列化末尾调用" \
  || echo "❌ 未在序列化末尾调用"

echo "=== 5. 跑测试 ==="
go test ./internal/ir/... ./internal/adapter/... ./transform/...

echo ""
echo "=== 6. 人工验证（如果自动检查不确定） ==="
echo "请手动检查 internal/ir/serialize_openai.go 的 serializeOpenAIMessage 函数："
echo "  - 空 content 分支（len(msg.Content) == 0）是否设置 out[\"content\"] = \"\""
echo "  - 空 content 分支是否检查并添加 tool_calls"
echo "  - validateToolCallIntegrity 是否在 SerializeOpenAI 末尾被调用"
```

### 9.2 审计结论模板

```
版本: <version>
审计日期: <date>
审计人: <name>

□ 序列化分支完整性（Bug #1 修复）
□ 完整性校验（Bug #2 防御）
□ Anthropic 协议特殊处理
□ 测试覆盖
□ 监控告警

结论: PASS / FAIL
待办: ...
```

---

**文档版本**: v1.1（基于 2.3.3-6b9b7a9c，审计修正版）
**最后更新**: 2026-07-04 18:30 CST
**适用**: 所有支持 MiniMax-M3 的网关版本

**变更记录**：
- v1.1 (2026-07-04 18:30): 补充完整测试用例清单、增强审计脚本人工验证步骤
- v1.0 (2026-07-04 17:00): 初始版本