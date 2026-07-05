# Credential+Model状态管理模块 - 实施进度报告

**日期**: 2026-06-30  
**状态**: ✅ Phase 1 进行中

---

## ✅ 已完成的工作

### 1. 数据库Schema ✅
- 文件: `deploy/sql/migrations/100_credential_model_state.sql`
- 创建了 `credential_model_state` 表
- 包含完整的状态字段、统计字段、探测字段、防闪断字段
- 创建了必要的索引和触发器
- 支持回滚的down脚本

### 2. 核心数据结构 ✅
- 文件: `credentialstate/state.go`
- 定义了 `State` 结构体（完整的状态数据）
- 定义了 `StatusEnum` 枚举（5种状态）
- 实现了辅助方法：
  - `IsHealthy()`, `IsDegraded()`, `IsUnavailable()`
  - `ShouldProbe()` - 判断是否需要探测
  - `CalculateSuccessRate()` - 计算成功率
  - `DetermineStatus()` - 根据统计自动判断状态
- 定义了 `Config` 配置结构（包含所有可调参数）
- 实现了 `Key()` 和 `ParseKey()` 工具函数

### 3. 数据库持久化层 ✅
- 文件: `credentialstate/store.go`
- 实现了 `Store` 结构体
- 核心方法：
  - `Get()` - 查询单个状态
  - `Upsert()` - 插入或更新状态
  - `ListAvailable()` - 查询可用的credentials
  - `GetProbeTargets()` - 获取需要探测的targets
  - `Delete()` - 删除状态（测试用）
- 完整的NULL值处理
- 使用pgx v5

---

## 🔄 下一步工作

### Phase 1 剩余任务

#### 4. 缓存层 (cache.go)
```go
type Cache struct {
    mem   *lru.Cache       // L1: 内存LRU缓存
    redis *redis.Client    // L2: Redis缓存
    store *Store           // L3: 数据库
}

// 实现三层缓存策略
func (c *Cache) Get(ctx, credID, model) (*State, error)
func (c *Cache) Set(ctx, state) error
func (c *Cache) Invalidate(ctx, credID, model) error
```

#### 5. 管理器核心 (manager.go)
```go
type Manager struct {
    cache    *Cache
    store    *Store
    prober   *Prober
    notifier *Notifier
    config   *Config
}

// 核心API
func (m *Manager) GetState(ctx, credID, model) (*State, error)
func (m *Manager) RecordSuccess(ctx, credID, model, latencyMs)
func (m *Manager) RecordFailure(ctx, credID, model, errorKind)
func (m *Manager) RecordProbe(ctx, credID, model, result)
func (m *Manager) FilterAvailable(ctx, candidates) []Candidate
func (m *Manager) TriggerProbe(ctx, credID, model) error
```

#### 6. 防闪断逻辑 (anti_flap.go)
```go
type AntiFlap struct {
    config AntiFlapConfig
}

// 防闪断检查
func (a *AntiFlap) ShouldMarkUnavailable(state) bool
func (a *AntiFlap) ScheduleVerification(credID, model)
func (a *AntiFlap) ResetTransientWindow(state)
```

#### 7. 探测器 (prober.go)
```go
type Prober struct {
    manager *Manager
    db      *pgxpool.Pool
}

// 探测逻辑
func (p *Prober) Start(ctx)
func (p *Prober) ProbeOne(ctx, credID, model) ProbeResult
func (p *Prober) UpdateNextProbeTime(ctx, credID, model, success)
```

#### 8. 通知器 (notifier.go)
```go
type Notifier struct {
    subscribers map[string][]chan *State
}

// 状态变更通知
func (n *Notifier) Subscribe(credID, model, callback)
func (n *Notifier) Notify(state)
```

### Phase 2: 探测集成

- 实现探测逻辑
- 集成现有model_probe
- 实现双重验证（2秒、5秒）
- 动态探测间隔

### Phase 3: 路由集成

- 修改 `provider/client.go` 的 `GetCandidates()`
- 修改 `routing/executor.go` 执行逻辑
- 在每次请求后调用 `RecordSuccess/RecordFailure`
- 在路由前查询状态过滤不可用candidates

### Phase 4: HTTP API

- GET `/api/credential-state/:id/:model`
- POST `/api/credential-state/:id/:model/probe`
- GET `/api/credential-state/available/:model`

---

## 📊 当前代码统计

- 数据库Schema: ~150行
- state.go: ~350行
- store.go: ~400行
- **总计**: ~900行代码

---

## 🎯 关键设计决策

### 1. 三层缓存架构
- L1内存：1000条LRU，<1ms
- L2 Redis：5分钟TTL，<5ms
- L3数据库：持久化

### 2. 状态机设计
```
unknown → healthy → degraded → unavailable
   ↑                              ↓
   └──────────── probing ←────────┘
```

### 3. 防闪断机制
- 30秒窗口内累计3次失败
- 触发2秒、5秒双重验证
- 两次都失败才标记不可用

### 4. 探测策略
- 健康：60秒间隔
- 降级：30秒间隔
- 不可用：10秒间隔

---

## 🔧 下次会话的工作

1. **实现缓存层** (cache.go)
   - LRU内存缓存
   - Redis集成
   - 写穿策略

2. **实现Manager核心** (manager.go)
   - 整合所有组件
   - 实现核心API
   - 异步更新逻辑

3. **部署数据库迁移**
   ```bash
   ssh prod-app "psql -h 127.0.0.1 -U llm_gateway -d llm_gateway -f /path/to/100_credential_model_state.sql"
   ```

4. **编写单元测试**
   - state_test.go
   - store_test.go
   - manager_test.go

---

## 📝 注意事项

### 数据库迁移
- 新表独立，不影响现有系统
- 可以先部署表，再部署代码
- 支持回滚

### 兼容性
- 不删除现有的circuit breaker
- 不删除现有的RouteNodeState
- 双写一段时间后再切换

### 性能
- 异步更新，不阻塞请求路径
- 批量写入优化
- 连接池配置

---

## 📚 相关文件

### 已创建
- ✅ `deploy/sql/migrations/100_credential_model_state.sql`
- ✅ `deploy/sql/migrations/100_credential_model_state.down.sql`
- ✅ `credentialstate/state.go`
- ✅ `credentialstate/store.go`

### 待创建
- ⏳ `credentialstate/cache.go`
- ⏳ `credentialstate/manager.go`
- ⏳ `credentialstate/prober.go`
- ⏳ `credentialstate/anti_flap.go`
- ⏳ `credentialstate/notifier.go`
- ⏳ `credentialstate/api.go`

---

**进度**: Phase 1 完成约40%  
**预计剩余时间**: 3-4小时编码 + 2小时测试
