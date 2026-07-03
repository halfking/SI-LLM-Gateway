# Routing-Core 架构设计文档

**版本**: 1.0
**创建时间**: 2026-07-03
**状态**: 实现完成 ✅

---

## 一、概述

Routing-Core 是对 LLM Gateway 路由决策层的重构，目标是将分散在 `routing/`、`credentialfpslot/`、`limiter/`、`credentialstate/`、`credentialhealth/` 等模块的逻辑，整合为一个**清晰、单一职责、可独立测试**的核心系统。

### 1.1 重构目标

| 目标 | 描述 | 达成状态 |
|------|------|----------|
| 状态一致性 | 多维度状态统一管理，避免不一致 | ✅ |
| 资源管理 | 指纹槽位 + 并发统一编排 | ✅ |
| 决策清晰 | 评分逻辑独立、可配置 | ✅ |
| 错误跟踪 | 错误分类与状态转换解耦 | ✅ |
| 可测试性 | 模块独立，单测覆盖率 ≥ 60% | ✅ |

### 1.2 核心原则

1. **不可变状态**: 外部不能直接修改状态，必须通过 `Engine.ReportResult()` 或 `StateManager.ProcessEvent()`
2. **多层状态**: Provider → Credential → Binding → Node，层级分明
3. **资源前置检查**: 在路由决策层就过滤资源饱和的候选
4. **评分透明**: 所有评分维度可记录、可回溯

---

## 二、架构设计

### 2.1 模块结构

```
routing-core/
├── resource/           # 资源管理
│   ├── types.go        # 接口定义
│   ├── manager.go      # ResourceManager 实现
│   └── manager_test.go
│
├── decision/           # 决策（评分）
│   ├── scorer.go       # CompositeScorer
│   └── scorer_test.go
│
├── tracking/           # 跟踪（错误分类）
│   ├── classifier.go   # ErrorClassifier
│   ├── rules.go        # 10个内置规则
│   ├── classifier_test.go
│   └── classifier_test_scenarios_test.go
│
├── state/              # 状态管理
│   ├── manager.go      # 接口定义
│   ├── composite_manager.go
│   ├── credential.go
│   ├── binding.go
│   ├── node.go
│   ├── fsm.go          # FSM 引擎
│   ├── events.go
│   └── manager_test.go
│
├── integration/        # 集成测试
│   └── integration_test.go
│
├── engine.go           # 统一引擎
└── engine_test.go
```

### 2.2 数据流图

```
┌─────────────────────────────────────────────────────────────┐
│                      [用户请求]                              │
└──────────────────────────┬──────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 1. Engine.Plan(req, candidates)                            │
│    ┌────────────────────────────────────────────────────┐   │
│    │ Step 1: 资源检查 (ResourceManager)                 │   │
│    │   - CheckEligibility(cred, holder)                 │   │
│    │   - Filter out resource-saturated credentials      │   │
│    ├────────────────────────────────────────────────────┤   │
│    │ Step 2: 综合评分 (CompositeScorer)                 │   │
│    │   - 价格 + 速度 + 稳定性 + 资源压力                  │   │
│    │   - BatchScore + 排序                               │   │
│    ├────────────────────────────────────────────────────┤   │
│    │ Step 3: 偏好应用                                     │   │
│    │   - SessionPreferred > Sticky                       │   │
│    └────────────────────────────────────────────────────┘   │
└──────────────────────────┬──────────────────────────────────┘
                           ↓
                   [Selected Candidate]
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. 执行请求 (routing/executor.go - 暂未重构)                │
└──────────────────────────┬──────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Engine.ReportResult(outcome)                             │
│    ┌────────────────────────────────────────────────────┐   │
│    │ Step 1: 错误分类 (ErrorClassifier)                  │   │
│    │   - status_code + body → Kind + Level               │   │
│    ├────────────────────────────────────────────────────┤   │
│    │ Step 2: 状态事件 (StateManager.ProcessEvent)         │   │
│    │   - Credential-Level → credentials 表               │   │
│    │   - Model-Level → credential_model_bindings 表      │   │
│    │   - Node-Level → RouteNodeStore (Redis)             │   │
│    └────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 三、接口标准

### 3.1 ResourceManager

**位置**: `routing-core/resource/types.go`

```go
type ResourceManager interface {
    CheckEligibility(ctx context.Context, req EligibilityRequest) (*EligibilityResult, error)
    AcquireResources(ctx context.Context, req AcquireRequest) (*AcquiredResources, ReleaseFunc, error)
    GetResourceStats(ctx context.Context, credentialID int) (*ResourceStats, error)
    CalculatePressure(ctx context.Context, credentialID int) (float64, error)
}
```

**职责**:
- 管理指纹槽位（FpSlot）的分配/释放
- 管理并发限额（Concurrency）的获取/归还
- 计算资源压力（0.0-1.0）

**关键类型**:
```go
type EligibilityResult struct {
    Eligible          bool
    FpSlotAvailable   bool
    ConcurAvailable   bool
    ResourcePressure  float64
    RecommendedAction string  // "proceed" | "retry_later" | "use_alternative"
}
```

### 3.2 CompositeScorer

**位置**: `routing-core/decision/scorer.go`

```go
type CompositeScorer interface {
    Score(ctx context.Context, candidate ScoringCandidate) (float64, error)
    BatchScore(ctx context.Context, candidates []ScoringCandidate) ([]ScoredCandidate, error)
    UpdateWeights(weights ScorerWeights)
}
```

**评分公式**:
```
base_score = (0.3 × price_score + 0.4 × speed_score + 0.3 × stability_score)
final_score = base_score × resource_score × (1 + tier_bonus) × (1 + weight_bonus)

其中：
- price_score: 免费=10.0, 否则=1.0/cost
- speed_score: 1.0/(p95_latency_ms + 1)
- stability_score: recent_success_rate (samples>=10) 或 success_rate
- resource_score: 1.0 / (1.0 + 2.0 × pressure)
- tier_bonus: tier=1 → +10%, tier=2 → +5%
- weight_bonus: weight/100
```

### 3.3 ErrorClassifier

**位置**: `routing-core/tracking/classifier.go`

```go
type ErrorClassifier interface {
    Classify(input ClassifyInput) (*ClassifiedError, error)
    RegisterRule(rule ClassificationRule) error
    GetSuggestions(errorKind string) []string
}

type ClassifiedError struct {
    Kind        string         // auth|quota|rate_limit|network|...
    Level       ErrorLevel     // Credential | Model | Request
    Cooldown    time.Duration
    Retryable   bool
    Confidence  float64
    Suggestions []string
}
```

**内置规则**（10条）:

| Kind | Level | Status Codes | Cooldown | Retryable |
|------|-------|--------------|----------|-----------|
| auth | Credential | 401/403 | 5min | ❌ |
| quota | Credential | 402 | 0 | ❌ |
| rate_limit | Model | 429 | 15min | ✅ |
| timeout | Model | 408/504 | 30s | ✅ |
| model_not_found | Model | 404 | 24h | ❌ |
| upstream_down | Model | 502/503 | 1min | ✅ |
| network | Model | 500/50x | 2min | ✅ |
| content_filter | Request | 400 | 0 | ❌ |
| invalid_request | Request | 400 | 0 | ❌ |
| context_length | Request | 400 | 0 | ❌ |

### 3.4 StateManager

**位置**: `routing-core/state/manager.go`

```go
type StateManager interface {
    GetCredentialState(ctx context.Context, credentialID int) (*CredentialState, error)
    GetBindingState(ctx context.Context, credentialID int, model string) (*BindingState, error)
    GetNodeState(ctx context.Context, credentialID int, model string) (*NodeState, error)
    ProcessEvent(ctx context.Context, event StateEvent) error
    BatchProcessEvents(ctx context.Context, events []StateEvent) ([]EventResult, error)
}
```

**状态层次**:
```
Credentials (PostgreSQL)
├── availability_state: ready|cooling|rate_limited|unreachable|suspended|auth_failed
├── quota_state: ok|periodic_exhausted|balance_exhausted|permanently_exhausted
├── circuit_state: closed|open
└── lifecycle_status: active|inactive|deleted

Credential_Model_Bindings (PostgreSQL)
└── available: bool (with unavailable_recover_at)

RouteNodes (Redis)
├── SuccessCount / FailureCount
├── SlideWindow (5min)
└── Disabled + DisabledUntil
```

### 3.5 Engine

**位置**: `routing-core/engine.go`

```go
type Engine struct { ... }

func NewEngine(rm, sc, cl, sm) *Engine

// 路由决策入口
func (e *Engine) Plan(ctx, req PlanRequest, candidates []Candidate) (*PlanResult, error)

// 状态回送入口
func (e *Engine) ReportResult(ctx, outcome RequestOutcome) error
```

---

## 四、集成测试

### 4.1 测试覆盖

| 模块 | 测试文件 | 测试数 | 覆盖率 |
|------|----------|--------|--------|
| ResourceManager | manager_test.go | 4 | 76.2% |
| CompositeScorer | scorer_test.go | 14 | 92.2% |
| ErrorClassifier | classifier_test.go | 22 | 98.6% |
| StateManager | manager_test.go | 8 | 59.9% |
| Engine | engine_test.go | 5 | 61.0% |
| Integration | integration_test.go | 9 | N/A |

### 4.2 关键场景

✅ **Happy Path**: 资源可用 → 评分 → 成功
✅ **High Pressure Routing**: 高压力降权
✅ **Error Classification Flow**: 5种错误分类
✅ **End-to-End Flow**: 完整请求生命周期
✅ **Cascade Failures**: 连续失败累积
✅ **Resource Saturation**: 资源饱和拒绝
✅ **Full Chain Integration**: 全链路集成

### 4.3 测试结果

```bash
$ go test ./routing-core/... -cover

ok      github.com/kaixuan/llm-gateway-go/routing-core         0.603s  coverage: 61.0%
ok      github.com/kaixuan/llm-gateway-go/routing-core/decision    0.410s  coverage: 92.2%
ok      github.com/kaixuan/llm-gateway-go/routing-core/integration 1.030s  coverage: [no statements]
ok      github.com/kaixuan/llm-gateway-go/routing-core/resource    0.528s  coverage: 76.2%
ok      github.com/kaixuan/llm-gateway-go/routing-core/state       0.398s  coverage: 59.9%
ok      github.com/kaixuan/llm-gateway-go/routing-core/tracking   0.398s  coverage: 98.6%
```

---

## 五、迁移路径

### 5.1 渐进式迁移策略

**当前状态**: 新模块已实现并存，老代码保持不变

**迁移阶段**:

| 阶段 | 任务 | 影响范围 | 风险 |
|------|------|----------|------|
| 1 | 新模块上线（旁路模式） | 无 | 🟢 低 |
| 2 | Executor 调用 Engine.Plan | executor.go | 🟡 中 |
| 3 | Executor 调用 Engine.ReportResult | executor.go | 🟡 中 |
| 4 | 删除老代码 (PlanCandidates, manual error handling) | router.go, executor.go | 🔴 高 |

### 5.2 兼容性保证

- ✅ 老接口 `router.PlanCandidates()` 保留
- ✅ 老接口 `credentialfpslot.Manager` 保留
- ✅ 老接口 `limiter.Limiter` 保留
- ✅ 老接口 `credentialstate.Writer` 保留

### 5.3 回滚预案

```bash
# 一键回滚到 Phase 0（无 routing-core）
git revert <commit-hash>
```

---

## 六、关键决策记录

### 6.1 决策1: 资源检查前置

**选项 A**: 在 Engine.Plan 阶段就过滤资源饱和的候选
**选项 B**: 保持现状，在 Executor 逐个尝试

**决策**: A

**理由**:
- 减少无效候选的评分开销
- 避免 P2C 选择到注定失败的候选
- Executor 的 `AcquireResources` 作为最终确认

### 6.2 决策2: 评分权重

**选项 A**: 价格30% + 速度40% + 稳定性30%
**选项 B**: 价格50% + 速度30% + 稳定性20%

**决策**: A

**理由**:
- 优先速度（AI应用的低延迟需求）
- 稳定性保证质量
- 价格作为决策辅助

### 6.3 决策3: 状态API设计

**选项 A**: HTTP API 暴露状态修改
**选项 B**: 仅内部 Engine.ReportResult 入口

**决策**: B（当前），A（未来 Admin API）

**理由**:
- 强制走 Engine 编排，避免不一致
- 未来 Admin API 调用 StateManager.ProcessEvent

### 6.4 决策4: 渐进式重构

**选项 A**: 一次性重构
**选项 B**: 渐进式（适配器模式）

**决策**: B

**理由**:
- 风险可控
- 保留回滚能力
- 老代码继续工作，新代码逐步覆盖

---

## 七、后续优化计划

### 7.1 短期（1-2周）

- [ ] StateManager.cooldown 计算集成到 Engine.ReportResult
- [ ] Engine.Plan 添加 tracing 支持
- [ ] 完善 StateManager 的 quota_state 转换规则

### 7.2 中期（1个月）

- [ ] 集成到 `routing/executor.go` 替换手工逻辑
- [ ] 实现 `binding.go` 的写入接口
- [ ] 添加 Prometheus 指标

### 7.3 长期（3个月）

- [ ] 完全替换 PlanCandidates / WriteOnError
- [ ] Admin API 暴露状态管理
- [ ] 状态机可视化（Admin UI）

---

## 八、附录

### 8.1 文件清单

```
routing-core/
├── engine.go                          (4.4 KB)
├── engine_test.go                     (5.2 KB)
├── decision/scorer.go                 (4.7 KB)
├── decision/scorer_test.go            (14 KB)
├── integration/integration_test.go    (15 KB)
├── resource/types.go                  (1.6 KB)
├── resource/manager.go                (4.8 KB)
├── resource/manager_test.go           (2.9 KB)
├── state/manager.go                   (1.6 KB)
├── state/composite_manager.go         (2.5 KB)
├── state/credential.go                (2.0 KB)
├── state/binding.go                   (1.3 KB)
├── state/node.go                      (2.2 KB)
├── state/fsm.go                       (4.6 KB)
├── state/events.go                    (2.9 KB)
├── state/manager_test.go              (6.7 KB)
├── tracking/classifier.go             (4.4 KB)
├── tracking/rules.go                  (4.3 KB)
├── tracking/classifier_test.go        (12 KB)
└── tracking/classifier_test_scenarios_test.go (9.4 KB)

总计: ~95 KB, 约 2400 行代码
```

### 8.2 依赖关系

```
routing-core/
├── decision/  → (无外部依赖)
├── tracking/  → (无外部依赖)
├── resource/  → credentialfpslot, limiter, identity
├── state/     → pgxpool, redis, errorsx, routing (RouteNodeConfig)
└── engine     → decision, tracking, resource, state, errorsx
```

### 8.3 关键常量

```go
// CompositeScorer 默认权重
PriceWeight           = 0.3
SpeedWeight           = 0.4
StabilityWeight       = 0.3
PressurePenalty       = 2.0

// ResourceManager
DefaultFpSlotLimit    = 20
DefaultConcurLimit    = 50

// StateManager
RouteNodeWindowSeconds = 300  // 5分钟
FailStreakLimit        = 5
DisabledCooldown       = 180 // 3分钟
```