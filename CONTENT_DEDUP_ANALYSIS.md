# 缓存重放功能分析与改进建议

## 当前实现现状

### ✅ 已实现的功能

#### 1. **IdempotentCache - 短期重复检测**
- **位置**: `relay/idempotent.go`
- **作用**: 检测 5 分钟内的重复 requestID
- **行为**: 返回 202 Accepted，告诉客户端请求正在处理中
- **局限**: 
  - ❌ 不返回实际响应内容
  - ❌ 只适用于并发重试（同一个 requestID）
  - ❌ 不能处理"不同 requestID，相同内容"的情况

```go
// relay/handler.go:1285
if h.idempotentCache.CheckAndMark(sessionID, requestID) {
    // 返回 202 + in_progress 状态
    // 客户端需要重新轮询
}
```

#### 2. **Pending-Response Cache - 长期响应缓存**
- **位置**: `pending/pending.go`
- **作用**: 缓存已完成的响应（TTL 7天）
- **行为**: 存储完整的响应体
- **使用方式**: 
  - ✅ 前端主动调用 `GET /v1/sessions/:id/pending-response`
  - ✅ 前端根据 `shouldTryCacheResume()` 判断是否尝试恢复
  
```typescript
// web/src/composables/useChatCompletions.ts:226
if (candidateSid && shouldTryCacheResume(opts)) {
    const cached = await getPendingResponse(candidateSid, opts.apiKey)
    if (cached.status === 'completed' && cached.body) {
        // 重放缓存的 SSE 流
    }
}
```

#### 3. **前端判断逻辑**
```typescript
// shouldTryCacheResume: 满足以下任一条件
// 1. 显式请求: forceResumeFromCache = true
// 2. 最后一条是用户消息（暗示上次助手回复可能丢失）
```

### ❌ 缺失的功能

**您提出的需求：后端自动检测相同内容的重复请求**

当前实现**不能**自动处理以下场景：

```
场景：
1. 用户发送请求 A（requestID: req-001, content: "你好"）
2. LLM 返回响应，但网络中断，前端未收到
3. 前端重试，生成新的 requestID: req-002，内容仍是"你好"
```

**问题**:
- IdempotentCache 检测不到（requestID 不同）
- Pending-Response 缓存存在，但需要前端主动查询
- 后端不会自动比对消息内容并返回缓存

---

## 改进方案：内容幂等性检测

### 设计思路

在后端增加"内容指纹"机制，自动检测相同内容的重复请求：

```
请求 → 计算内容哈希 → 检查缓存 → 命中则直接返回 → 未命中则转发
```

### 实现方案

#### 方案 A: 基于消息内容的哈希缓存（推荐）

```go
// 新文件: relay/content_dedup.go

type ContentDedupCache struct {
    store *pending.Store  // 复用 pending-response 存储
    mu    sync.RWMutex
}

// 计算请求内容的指纹
func computeContentFingerprint(messages []Message, model string, stream bool) string {
    // 仅使用最后 3 条消息 + model 来计算哈希
    // 避免完整历史导致哈希永不重复
    var buf bytes.Buffer
    lastN := 3
    start := len(messages) - lastN
    if start < 0 {
        start = 0
    }
    for _, msg := range messages[start:] {
        buf.WriteString(msg.Role)
        buf.WriteString(":")
        buf.WriteString(msg.Content)
        buf.WriteString("|")
    }
    buf.WriteString(model)
    buf.WriteString("|stream=")
    buf.WriteString(strconv.FormatBool(stream))
    
    hash := sha256.Sum256(buf.Bytes())
    return hex.EncodeToString(hash[:])
}

// 检查并返回缓存的响应
func (c *ContentDedupCache) CheckAndReplay(
    ctx context.Context,
    sessionID string,
    contentHash string,
    w http.ResponseWriter,
) (replayed bool, err error) {
    if c == nil || c.store == nil {
        return false, nil
    }
    
    // 构造缓存 key: session:hash
    cacheKey := fmt.Sprintf("%s:%s", sessionID, contentHash)
    
    // 查询 pending store
    entry, err := c.store.Get(ctx, cacheKey)
    if err != nil || entry == nil || entry.Status != "completed" {
        return false, err
    }
    
    // 设置响应头
    w.Header().Set("X-Gw-Content-Replay", "true")
    w.Header().Set("X-Gw-Cache-Hit", "content-hash")
    w.Header().Set("Content-Type", entry.ContentType)
    w.WriteHeader(http.StatusOK)
    
    // 返回缓存的响应体
    _, err = w.Write([]byte(entry.Body))
    return true, err
}
```

#### 集成到 Handler

```go
// relay/handler.go

func (h *ChatHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
    // ... 现有逻辑 ...
    
    // 解析请求
    var req ChatCompletionRequest
    json.Unmarshal(bodyBytes, &req)
    
    // 计算内容指纹
    contentHash := computeContentFingerprint(req.Messages, req.Model, req.Stream)
    
    // 1. 先检查 IdempotentCache（requestID 级别）
    if h.idempotentCache.CheckAndMark(sessionID, requestID) {
        // 返回 202 in_progress
        return
    }
    
    // 2. 再检查 ContentDedupCache（内容级别）
    if h.contentDedup != nil && sessionID != "" {
        replayed, err := h.contentDedup.CheckAndReplay(
            r.Context(), 
            sessionID, 
            contentHash, 
            w,
        )
        if err != nil {
            slog.Warn("content dedup check failed", "error", err)
        }
        if replayed {
            // 记录缓存命中
            logCtx.SetExtra("cache_hit", "content_hash")
            logCtx.EmitSuccess(nil, nil)
            return
        }
    }
    
    // 3. 未命中，正常执行
    // ... 调用 LLM ...
    
    // 4. 响应完成后，存储到缓存
    if success {
        cacheKey := fmt.Sprintf("%s:%s", sessionID, contentHash)
        h.contentDedup.store.Store(ctx, cacheKey, responseBody, "completed")
    }
}
```

### 方案 B: 轻量级 - 仅检测最后一条消息

如果担心性能，可以简化为只比较最后一条用户消息：

```go
func computeSimpleFingerprint(lastUserMessage string, model string) string {
    if len(lastUserMessage) > 1000 {
        lastUserMessage = lastUserMessage[:1000] // 截断长消息
    }
    return fmt.Sprintf("%s:%s:%x", 
        model, 
        lastUserMessage,
        crc32.ChecksumIEEE([]byte(lastUserMessage)),
    )
}
```

### 配置选项

```go
// reconnect/config.go 中添加

type Config struct {
    // ... 现有字段 ...
    
    // ContentDedupEnabled 控制是否启用基于内容的去重
    ContentDedupEnabled bool
    
    // ContentDedupWindow 内容去重的时间窗口
    // 只在此窗口内检查重复（避免返回太旧的缓存）
    ContentDedupWindow time.Duration  // 默认 10 分钟
    
    // ContentDedupDepth 用于指纹计算的消息深度
    // 0 = 仅最后一条, -1 = 全部, N = 最后 N 条
    ContentDedupDepth int  // 默认 3
}
```

---

## 对比分析

### 现有实现 vs 改进方案

| 功能 | 现有实现 | 改进后 |
|------|---------|--------|
| **相同 requestID 重复** | ✅ IdempotentCache (202) | ✅ 保持不变 |
| **不同 requestID，相同内容** | ❌ 需要前端主动查询 | ✅ 后端自动返回 |
| **缓存存储** | ✅ Pending-Response | ✅ 复用现有存储 |
| **缓存命中率** | 低（仅限并发重试） | 高（覆盖网络重试） |
| **延迟** | 前端两次请求 | 后端一次返回 |
| **用户体验** | 可能看到"重试中" | 透明，如同成功 |

### 性能影响

**计算开销:**
- SHA256 哈希: ~1-5μs (微秒级)
- 内存查询: ~0.5μs
- **总计: < 10μs，可忽略**

**存储开销:**
- 每个缓存条目: ~1KB (响应体) + 64 bytes (哈希)
- 假设 1000 并发用户，每用户 10 条历史 = 10MB
- **Redis 内存增加: 可忽略**

---

## 实施建议

### Phase 1: 最小化实现（1-2小时）

1. ✅ 添加 `computeContentFingerprint()` 函数
2. ✅ 在 `ServeHTTP` 中集成检查逻辑
3. ✅ 响应成功后存储到 pending store
4. ✅ 添加配置开关（默认禁用）

### Phase 2: 完善与测试（2-3小时）

1. ✅ 添加单元测试
2. ✅ 添加 metrics（缓存命中率）
3. ✅ 配置时间窗口和消息深度
4. ✅ 边缘情况处理（超长消息、特殊字符）

### Phase 3: 监控与优化（持续）

1. 监控缓存命中率
2. 调整时间窗口和消息深度
3. 根据实际使用情况优化

---

## 推荐行动

**立即执行:**
1. ✅ 实现方案 A（完整内容哈希）
2. ✅ 默认禁用，通过配置启用
3. ✅ 灰度测试 1 周

**预期效果:**
- 🎯 网络重试场景下，缓存命中率 > 60%
- 🎯 用户重复提问，缓存命中率 > 30%
- 🎯 减少 LLM 调用成本 10-20%
- 🎯 减少响应时间 80-95% (缓存命中时)

---

## 总结

**当前状态:** ❌ 不支持自动检测相同内容的重复请求  
**改进方案:** ✅ 添加基于内容哈希的去重缓存  
**工作量:** ~4-5小时（含测试）  
**优先级:** 🔥 高（显著提升用户体验和降低成本）

是否需要我立即实现这个功能？
