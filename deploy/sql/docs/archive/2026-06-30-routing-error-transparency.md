# 路由错误透明化修复 (2026-06-30)

## 问题描述

在路由操作中，当数据库或 Redis 查询失败时，原代码选择了"伪装错误"的策略：
- 静默降级到 fallback 行为
- 只记录 WARN 级别日志
- 用户和运维人员无法快速识别真实原因（数据库故障 vs 正常降级）

这种做法会误导用户和运维人员，影响故障排查效率。

## 修复原则

**不伪装数据库/Redis错误，直接返回明确的数据处理或路由数据查询错误。**

## 修改文件

### 1. relay/auto_route.go

**位置**: `maybeResolveAuto` 方法，第292-303行

**修改前**:
```go
decision, err := h.decider.Decide(...)
if err != nil {
    slog.Warn("auto-route: decider failed, falling back", ...)
    // 静默降级到默认模型
    reqBody.Model = autoFallbackModel()
    return rewriteBodyWithModel(rawBody, autoFallbackModel()), nil, false
}
```

**修改后**:
```go
decision, err := h.decider.Decide(...)
if err != nil {
    slog.Error("auto-route: decider failed - data access error", ...)
    // 不伪装错误，直接返回路由数据查询错误
    return nil, nil, true // shouldFail=true，调用方返回 502
}
```

**影响**: 
- 当 auto-route 的 Decide 方法因数据库问题失败时，现在会返回 502 错误
- 用户和运维能立即识别这是路由数据查询错误，而非正常的模型选择

---

### 2. autoroute/decision.go

**位置**: `DBProfileStore.Get` 方法，第440-452行

**修改前**:
```go
err := s.pool.QueryRow(ctx, ...).Scan(&profile)
if err != nil {
    // 数据库错误和"未找到"都返回 false，用 Warn 日志
    if !errors.Is(err, pgxNoRows()) {
        slog.Warn("DBProfileStore.Get query failed", ...)
    }
    return "", false
}
```

**修改后**:
```go
err := s.pool.QueryRow(ctx, ...).Scan(&profile)
if err != nil {
    if errors.Is(err, pgxNoRows()) {
        // 正常情况：没有 profile 记录
        return "", false
    }
    // 数据库错误：明确记录为 ERROR
    slog.Error("DBProfileStore.Get: database query error", ...)
    return "", false
}
```

**影响**: 
- 区分"未找到记录"（正常）和"数据库错误"（故障）
- 使用 ERROR 级别日志，运维监控系统能及时告警

---

### 3. routing/route_node_store.go

**位置1**: `Get` 方法，第94-100行

**修改前**:
```go
val, err := s.client.Get(ctx, key).Result()
if err == redis.Nil {
    return nil, false, nil
}
if err != nil {
    return nil, false, err  // 错误未记录日志
}
```

**修改后**:
```go
val, err := s.client.Get(ctx, key).Result()
if err == redis.Nil {
    return nil, false, nil  // 正常：key 不存在
}
if err != nil {
    // Redis 错误明确记录
    slog.Error("RouteNodeStore.Get: Redis access error", ...)
    return nil, false, err
}
```

**位置2**: `IsUsable` 方法，第208-214行

**修改前**:
```go
func (s *RouteNodeStore) IsUsable(...) bool {
    state, found, err := s.Get(...)
    if err != nil || !found {
        return true  // 降级：视作可用（但未明确记录）
    }
    ...
}
```

**修改后**:
```go
func (s *RouteNodeStore) IsUsable(...) bool {
    state, found, err := s.Get(...)
    if err != nil {
        // Redis 错误不伪装，明确记录
        slog.Error("RouteNodeStore.IsUsable: Redis query error, degrading to available", ...)
        return true  // 降级策略：仍返回可用，但已明确记录错误
    }
    if !found {
        return true  // 正常：首次访问，无状态记录
    }
    ...
}
```

**影响**: 
- Redis 错误现在会记录 ERROR 日志
- 运维能快速识别 Redis 故障，而不是误认为所有节点都健康

---

### 4. routing/router.go

**位置**: `filterByRouteNodeHealth` 方法，第139行

**修改前**:
```go
for _, c := range candidates {
    state, found, _ := r.RouteNodeStore.Get(...)  // 忽略错误
    ...
}
```

**修改后**:
```go
for _, c := range candidates {
    state, found, err := r.RouteNodeStore.Get(...)
    if err != nil {
        // 明确记录数据库错误
        slog.Error("router: RouteNodeStore.Get error in lenient mode", ...)
    }
    ...
}
```

**影响**: 
- Lenient mode（宽容模式）中的数据访问错误也会被明确记录
- 便于诊断为何进入 lenient mode

---

### 5. autoroute/index.go

**位置1**: `Refresh` 方法，第211-215行

**修改前**:
```go
rows, err := idx.pool.Query(ctx, refreshIndexSQL)
if err != nil {
    return fmt.Errorf("query credential_model_index: %w", err)
}
```

**修改后**:
```go
rows, err := idx.pool.Query(ctx, refreshIndexSQL)
if err != nil {
    slog.Error("autoroute.Index.Refresh: database query error", ...)
    return fmt.Errorf("routing data query error (credential_model_index): %w", err)
}
```

**位置2**: `Refresh` 方法，第230-233行

**修改前**:
```go
if rows.Err() != nil {
    return fmt.Errorf("iterate credential_model_index: %w", rows.Err())
}
```

**修改后**:
```go
if rows.Err() != nil {
    slog.Error("autoroute.Index.Refresh: database iteration error", ...)
    return fmt.Errorf("routing data processing error (credential_model_index): %w", rows.Err())
}
```

**影响**: 
- 数据库查询和迭代错误都会记录 ERROR 日志
- 错误消息更具描述性（"routing data query error" 而非泛泛的 "query"）

---

## 编译验证

所有修改已通过编译验证：

```bash
✅ go build ./relay
✅ go build ./routing
✅ go build ./autoroute
```

## 日志级别变化

| 场景 | 修改前 | 修改后 |
|------|--------|--------|
| auto-route decider 失败 | WARN + 降级 | ERROR + 502 |
| DBProfileStore 数据库错误 | WARN | ERROR |
| RouteNodeStore Redis 错误 | 无日志 | ERROR |
| Index Refresh 数据库错误 | 返回 error（调用方记录） | ERROR + 返回 error |

## 运维影响

1. **监控告警**: 所有数据库/Redis 错误现在使用 ERROR 级别，监控系统能及时告警
2. **故障排查**: 日志中能明确区分"正常降级"和"数据访问故障"
3. **用户体验**: auto-route 失败时返回 502（明确错误），而非静默使用 fallback 模型

## 向后兼容性

- ✅ 不影响正常路由逻辑
- ✅ 降级策略仍然生效（RouteNodeStore.IsUsable 仍返回 true）
- ⚠️ auto-route 失败现在返回 502 而非静默降级（这是期望行为）

## 测试建议

1. 模拟 PostgreSQL 连接中断，验证 auto-route 返回 502 并记录 ERROR 日志
2. 模拟 Redis 连接中断，验证路由仍能工作但记录 ERROR 日志
3. 检查监控系统能否正确捕获新的 ERROR 日志
