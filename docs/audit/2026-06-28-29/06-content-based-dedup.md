# 06 · 基于内容的请求去重（新功能）

**Commit**：`b6ea9ff6` — `feat(relay): add content-based request deduplication`
**作者**：halfking <kimmy.huang@gmail.com>
**时间**：2026-06-29 13:15 (+0800)
**优先级**：**P2**（新功能，默认关闭）
**破坏性变更**：否（默认 `ContentDedupEnabled=false`）
**前置依赖**：**必须**先 cherry-pick [`7576c021`](04-session-and-reconnect.md)（提供 `reconnect/` 包与 `reconnect.Config` 结构体）

---

## 一、问题陈述（Why）

客户端（特别是浏览器端）在网络闪断后**自动重试**，但**生成了新的 request ID**。
现有两层防护各有局限：

| 现有防护 | 文件 | 局限 |
|----------|------|------|
| `IdempotentCache`（request-ID 级） | `relay/idempotent.go` | 新 ID = 缓存未命中，重复打到 LLM |
| Pending-response 机制 | `pending/` | 需客户端主动 resume；浏览器 fetch retry 不支持 |

**业务痛点**：
- 重复调用 LLM = 成本浪费
- 失败/超时重试可能再次失败，导致用户看到"空响应"
- 模型端可能有竞态（同一对话在短时间内被处理两次）

## 二、设计目标

> 在**不要求客户端改造**的前提下，自动识别"内容相同但 ID 不同"的重试请求，
> 直接**重放缓存响应**，节省 LLM 调用 + 提升用户感知速度。

## 三、修复方案

### 3.1 新增文件

| 文件 | 行数 | 关键内容 |
|------|------|----------|
| `relay/content_dedup.go` | 214 | `ContentDedupCache` 核心实现 + `Message` 简化结构体 + `ParseMessagesForFingerprint` 工具 |
| `relay/content_dedup_test.go` | 193 | 9 个测试函数（见下） |
| `CONTENT_DEDUP_ANALYSIS.md` | 311 | 设计分析文档 |
| `CONTENT_DEDUP_IMPLEMENTATION.md` | 444 | 实现指南 |

### 3.2 修改文件

| 文件 | 改动 | 说明 |
|------|------|------|
| `relay/handler.go:158, 163, 235, 238-240, 1325-1370` | +54 行 | 在 `ChatHandler` 上加 `contentDedupCache` 字段、`SetContentDedupCache` 方法、在 ServeHTTP 早期接入 dedup |
| `reconnect/config.go:48+` | +33 行 | 追加 `ContentDedupEnabled / ContentDedupWindow / ContentDedupDepth` 三个字段 |

### 3.3 核心 API

```go
// relay/content_dedup.go
type ContentDedupCache struct {
    store  *pending.Store   // 复用现有 pending 存储
    window time.Duration    // 去重时间窗口（默认 10m）
    depth  int              // 消息深度（默认 3）
}

type Message struct {
    Role    string `json:"role"`
    Content string `json:"content"`
}

// 公开方法
func NewContentDedupCache(store *pending.Store, window time.Duration, depth int) *ContentDedupCache
func (c *ContentDedupCache) ComputeFingerprint(messages []Message, model string, stream bool) string
func (c *ContentDedupCache) CheckAndReplay(ctx, sessionID, contentHash, w) (replayed bool, err error)
func (c *ContentDedupCache) Store(ctx, sessionID, contentHash, responseBody, contentType) error
func ParseMessagesForFingerprint(body []byte) (messages []Message, model string, stream bool, err error)
```

### 3.4 指纹算法

```go
// relay/content_dedup.go:69-97
func (c *ContentDedupCache) ComputeFingerprint(messages []Message, model string, stream bool) string {
    var buf bytes.Buffer
    start := len(messages) - c.depth
    if start < 0 { start = 0 }
    for _, msg := range messages[start:] {
        buf.WriteString(msg.Role)
        buf.WriteString(":")
        // 截断过长消息避免 DoS
        content := msg.Content
        if len(content) > 10000 {
            content = content[:10000]
        }
        buf.WriteString(content)
        buf.WriteString("|")
    }
    buf.WriteString("model=")
    buf.WriteString(model)
    buf.WriteString("|stream=")
    buf.WriteString(strconv.FormatBool(stream))

    hash := sha256.Sum256(buf.Bytes())
    return hex.EncodeToString(hash[:])
}
```

**指纹组成**：`SHA-256(role:lastN_content + "|" + model + stream)`

| 维度 | 选择 | 原因 |
|------|------|------|
| Hash 算法 | SHA-256 | 性能 ~1-5μs；足够防冲突 |
| 消息深度 | last N（默认 3） | 太深：用户长对话命中率低；太浅：上下文微调即不命中 |
| 内容截断 | 10000 chars | 防 DoS 巨型 hash |
| 包含字段 | role + content + model + stream | role 区分 system/user/assistant；model 区分 vendor；stream 影响响应格式 |

### 3.5 缓存命中响应头

| Header | 值 | 用途 |
|--------|-----|------|
| `X-Gw-Content-Replay` | `true` | 客户端可识别为"重放" |
| `X-Gw-Cache-Hit` | `content-hash` | 调试用 |
| `X-Gw-Cached-At` | RFC3339 时间戳 | 调试用 |
| `X-Gw-Cache-Key` | truncated hash (16 chars) | 调试用 |

### 3.6 集成点

**`relay/handler.go:1325-1370`**（ServeHTTP 早期）：

```go
if h.contentDedupCache != nil && sessionID != "" {
    // 1. ParseMessagesForFingerprint 从 body 提取消息
    // 2. ComputeFingerprint 计算 hash
    // 3. CheckAndReplay 检查并尝试重放
    // 4. 命中：return（已写入响应）
    // 5. 未命中：继续下游流程；响应完成后由 Store() 写入缓存
}
```

## 四、配置项

在 `reconnect/config.go` 上**追加**（非替换）：

```go
// reconnect/config.go:48+（b6ea9ff6 中追加）
ContentDedupEnabled bool          // 默认 false
ContentDedupWindow  time.Duration // 默认 10m
ContentDedupDepth   int           // 默认 3
```

**启用方式**（推荐生产用 HTTP API）：

```bash
curl -X POST http://gateway/api/reconnect/config \
  -H "Content-Type: application/json" \
  -d '{"content_dedup_enabled": true}'
```

## 五、测试覆盖

| 测试函数 | 验证目标 |
|----------|----------|
| `TestComputeFingerprint_SameContent` | 同内容生成相同 hash |
| `TestComputeFingerprint_DifferentModel` | 模型不同 → hash 不同 |
| `TestComputeFingerprint_DifferentStream` | stream 标志不同 → hash 不同 |
| `TestComputeFingerprint_OnlyLastN` | 仅 last N 参与（depth=3） |
| `TestComputeFingerprint_TruncatesLongContent` | 超过 10000 chars 截断 |
| `TestCheckAndReplay_CacheMiss` | 未命中返回 false |
| `TestCheckAndReplay_NilCache` | nil cache 安全降级 |
| `TestParseMessagesForFingerprint` | JSON 解析正确性 |
| `TestParseMessagesForFingerprint_InvalidJSON` | 非法 JSON 错误处理 |
| `TestNewContentDedupCache_Defaults` | 默认值生效 |
| `TestContentDedupCache_EndToEnd` | 端到端 Store→CheckAndReplay |

**合计 9-11 个测试函数，全部通过。**

## 六、性能指标

| 指标 | 数值 |
|------|------|
| Fingerprint 计算 | ~1-5μs（微秒级） |
| Cache check overhead | < 3ms |
| Cache hit 响应 | instant（vs 2-10s LLM 调用） |
| **预期命中率** | 60-80%（网络重试场景） |
| **预期 LLM 调用减少** | ~20% |
| **重试响应时间** | ↓ 90% |
| **预期影响** | 消除"空响应"错误 |

## 七、跨分支同步要点（Sync Notes）

### 7.1 ⚠️ 前置依赖（关键！）

```
[必须] 7576c021  ← 提供 reconnect/ 包和 reconnect.Config 结构体
[目标] b6ea9ff6  ← 追加 ContentDedup* 字段到该结构体
```

**绝对不可调换顺序**！`b6ea9ff6` 直接修改 `reconnect/config.go` 中的 `Config` 结构体，
如目标分支没有 `reconnect/` 包，cherry-pick 会失败。

### 7.2 必带文件

```
relay/content_dedup.go              # 新增 214 行
relay/content_dedup_test.go         # 新增 193 行
relay/handler.go                    # 修改 +54 行
reconnect/config.go                 # 修改 +33 行（追加字段）
CONTENT_DEDUP_ANALYSIS.md           # 新增 311 行（设计文档）
CONTENT_DEDUP_IMPLEMENTATION.md     # 新增 444 行（实现指南）
```

### 7.3 验证步骤

```bash
# 1. 单元测试
go test ./relay/... -run "TestComputeFingerprint|TestCheckAndReplay|TestParseMessagesForFingerprint|TestNewContentDedupCache|TestContentDedupCache" -v
go test ./reconnect/... -v

# 2. 编译
go build ./...

# 3. 功能验证
# 步骤 1：开启 dedup
curl -X POST http://gateway/api/reconnect/config \
  -d '{"content_dedup_enabled": true, "content_dedup_window": "10m", "content_dedup_depth": 3}'

# 步骤 2：发请求 A
curl -X POST http://gateway/v1/chat/completions -H "X-Gw-Session-Id: gw_$(uuidgen)" \
  -d '{"model":"qwen3-235b-a22b","messages":[{"role":"user","content":"hello"}]}' \
  -i  # 记录完整响应 + 头（应无 X-Gw-Content-Replay）

# 步骤 3：发请求 B（同内容，新 X-Request-Id）
curl -X POST http://gateway/v1/chat/completions -H "X-Gw-Session-Id: gw_<同session>" \
  -H "X-Request-Id: <新ID>" \
  -d '{"model":"qwen3-235b-a22b","messages":[{"role":"user","content":"hello"}]}' \
  -i  # 期望 X-Gw-Content-Replay: true；响应体一致
```

### 7.4 兼容性

- ✅ **100% 向后兼容**：默认 `ContentDedupEnabled=false`，行为零变化
- ✅ 不修改任何 HTTP 请求/响应格式（仅在命中时加 4 个响应头）
- ✅ 不影响限流、计费、审计（审计仍记录每次请求）
- ✅ Redis 不可用时自动降级（`Store` / `Get` 错误仅 slog.Warn，不影响主流程）

### 7.5 安全考虑

| 风险 | 缓解 |
|------|------|
| 用户 A 通过相同内容访问用户 B 的响应 | ✅ Session 隔离（key 含 `sessionID`） |
| 巨型消息导致 hash 慢 | ✅ 内容截断到 10000 chars |
| Hash 冲突 | ✅ SHA-256 实际不可能；即使冲突，响应的 Content-Type / status 也一致 |
| 缓存污染（恶意请求高频写入） | ⚠️ 当前未限流；建议叠加现有的 pending.Store TTL 与 LRU |
| 跨租户泄漏 | ✅ Session 隔离天然防跨租户 |

## 八、风险与回滚（Risk & Rollback）

| 维度 | 评估 |
|------|------|
| 影响面 | `/v1/chat/completions`（仅在 ChatHandler 上挂载，未覆盖 messages / responses） |
| 可逆性 | 极高（删除 `relay/content_dedup.go` + 还原 `handler.go` + 还原 `reconnect/config.go` 字段即可） |
| 降级开关 | `ContentDedupEnabled=false` 即可立即停用 |
| 数据 | `pending.Store` 中会积累 dedup 缓存；关闭后随 TTL 自然过期（默认 7d） |

## 九、未来优化（Future Improvements）

作者 commit message 与 `CONTENT_DEDUP_ANALYSIS.md` 中提到：

1. **覆盖 messages / responses handler**：当前仅 ChatHandler 接入；messages/responses 也有同样痛点。
2. **自适应深度**：根据对话历史动态调整 depth（短对话 depth=1 即可，长对话需要 depth>3）。
3. **跨 session dedup**：在某些场景下可放开 session 隔离（如 service-token 调用）。
4. **命中率埋点**：建议在 `metrics.go` 暴露 `content_dedup_hit_total{session}` / `content_dedup_miss_total`。
5. **BatchStore**：当前 Store 每次单独写；可改造为批量写入（与 BatchStats 类似）。
6. **测试覆盖扩展**：极长消息、多语言（中文 emoji）、并发竞争等边界可补充。
