# 03 · P1 missing_model 错误码修正（400 而非 503）

**Commit**：`a1417474` — `fix(handler): P1 missing_model returns 400 instead of 503 no_candidate`
**作者**：halfking <kimmy.huang@gmail.com>
**时间**：2026-06-29 11:34 (+0800)
**优先级**：**P1**（错误码一致性 + 提前拒绝）
**破坏性变更**：**行为变更**（错误码从 503 → 400；客户端依赖原 503 的需要适配，但语义上更正确）
**依赖**：无

---

## 一、问题陈述（Why）

2026-06-29 prod_e2e F2 子测试发现：

> `POST /v1/chat/completions` 当 `model` 字段缺失 / 为空 / 仅为空白 / 显式 `null` 时，**返回 `503 no_candidate`**。

| 输入 | 期望 | 实际（修复前） |
|------|------|----------------|
| `model` 字段缺失 | 400 missing_model | ❌ 503 no_candidate |
| `model: ""` | 400 missing_model | ❌ 503 no_candidate |
| `model: "   "` | 400 missing_model | ❌ 503 no_candidate |
| `model: null` | 400 missing_model | ❌ 503 no_candidate |

**业务痛点**：
- `503` 在网关语义里表示"上游不可用"，误导客户端走重试逻辑
- 实际是**客户端请求非法**，应走 4xx 拒绝路径
- Anthropic（`relay/messages.go:243`）和 Responses（`relay/responses.go:217`）handler 早已返回 400，仅 chat handler 缺失该检查

## 二、根因分析（Root Cause）

`relay/handler.go` 的 `ServeHTTP` 入口未对 `model` 字段做早校验，请求一路走到 routing 层后因找不到空 model 的候选 credential 而返回 `503 no_candidate`。

## 三、修复方案（Solution）

**关键文件**：`relay/handler.go`
**改动位置**：
- `handler.go:453-490` — 新增 peek-and-replace 校验块
- `handler.go:854-862, 2212, 2258` — 配套日志/错误码分支

**策略**：在 `ServeHTTP` 入口**一次性读 body 到 buffer**，复用 `io.NopCloser` 包装，**先 peek JSON 检查 model 字段**，再交给下游 `serveWithExecutor`（`handler.go:795`）按原逻辑 `io.ReadAll(io.LimitReader)` 重读。

```go
// relay/handler.go:453-490（修复后）
// or empty "model" field fails fast with 400 missing_model instead of
// reaching the routing layer (which would otherwise return 503 no_candidate).
//
// We need to peek at the body to validate, so we do a one-shot read.
// The executor will re-read the body via io.NopCloser+Reset below;
var peekBuf []byte
peekBuf, _ = io.ReadAll(r.Body)
if len(peekBuf) > 0 {
    r.Body = io.NopCloser(bytes.NewReader(peekBuf))
}
if len(peekBuf) > 0 && len(peekBuf) <= maxBodySize {
    var peek struct {
        Model string `json:"model"`
    }
    if json.Unmarshal(peekBuf, &peek) == nil && strings.TrimSpace(peek.Model) == "" {
        logCtx.SetError("missing_model", "model is required")
        logCtx.EmitFailure("missing_model", "model is required", nil, nil)
        // 400 invalid_request / missing_model
        writeError(w, http.StatusBadRequest,
            "model is required", "invalid_request", "missing_model")
        return
    }
}
```

### 关键设计点

| 点 | 决策 | 原因 |
|----|------|------|
| body 一次性读 | `io.ReadAll(r.Body)` | 避免下游重复读失败 |
| 用 `io.NopCloser` 包装 | `r.Body = io.NopCloser(bytes.NewReader(peekBuf))` | 下游 `io.ReadAll(io.LimitReader)` 可重读 |
| 错误码 | `400 invalid_request / missing_model` | 与 messages / responses handler 完全一致 |
| 字段判空 | `strings.TrimSpace(peek.Model) == ""` | 覆盖空串、空白、`null`（null 解析后为空串） |
| 字节数上限 | `len(peekBuf) <= maxBodySize`（32 MB） | 防止 OOM，对超大 body 跳过 peek 走下游 |

## 四、测试覆盖

| 测试文件 | 测试函数 | 覆盖用例 |
|----------|----------|----------|
| `relay/handler_missing_model_test.go` | `TestChatHandler_MissingModelReturns400` | 缺失 / 空串 / 空白 / null 共 4 子用例 |

**生产验证**（`https://llm.kxpms.cn`）：

| F2 子用例 | HTTP 状态 | 响应时间 |
|-----------|-----------|----------|
| F2 Test 1（缺失） | **400** | 0.102641s |
| F2 Test 2（空串） | **400** | 0.068865s |
| F2 Test 3（空白） | **400** | 0.085518s |
| F2 Test 4（null） | **400** | 0.100694s |

**prod_e2e 总成绩**：92 PASS / 12 FAIL / 12 SKIP（修复前 90 / 14 / 12，多通过 2 个 F2 用例）。

## 五、跨分支同步要点（Sync Notes）

### 5.1 必带文件

```
relay/handler.go                       # 改动 +59 行
relay/handler_missing_model_test.go    # 新增 68 行
```

### 5.2 验证步骤（最小重现）

```bash
# 1. 单元测试
go test ./relay/... -run TestChatHandler_MissingModelReturns400 -v

# 2. 编译
go build ./...

# 3. 手工验证（需运行中的网关）
curl -sS -o /dev/null -w "%{http_code}\n" -X POST https://gateway/v1/chat/completions \
  -H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"hi"}]}'  # 期望 400
```

### 5.3 兼容性

- ⚠️ **行为变更**：错误码从 503 改为 400
- ✅ 错误体格式不变（`{error: {type, code, message}}`）
- ✅ 已有 4xx 处理逻辑的客户端无需改动
- ⚠️ 依赖 503 no_candidate 走重试的客户端需要适配（语义上修正是正确的）

### 5.4 关联改动

`handler.go:854-862, 2212, 2258` 是配套日志/指标扩展，与本次核心修复一同 cherry-pick 即可。

## 六、风险与回滚（Risk & Rollback）

| 维度 | 评估 |
|------|------|
| 影响面 | 全部 `/v1/chat/completions` 入口 |
| 可逆性 | 高（注释 `handler.go:475-489` 的 4 个 return 块即可） |
| 监控指标 | `metrics: error_code_total{code="missing_model"}` 应大幅上升（这部分客户端错误以前被归到 503） |
| 灰度 | 不建议灰度：错误码一致性是契约性改动，全量一致切换最佳 |

## 七、未来优化（Future Improvements）

1. **统一三个 handler 的 model 校验**：将 peek-and-replace 抽到 `relay/request_context.go` 的 `validateModelField()` 工具函数，messages / responses 改用同一份实现。
2. **校验其他必填字段**：`max_tokens` 缺失（已有 `missing_max_tokens` 错误码但未在 chat handler 检查）、`messages` 为空数组（F3 已知 bug，仍触发上游挂起，详见 [`02-P0` 卡](02-P0-upstream-hard-timeout.md)）。
3. **peek 性能**：当前每次请求都解析 JSON；高频 chat 流下可考虑用 sync.Pool 复用 `peek` struct。
