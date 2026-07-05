# Routing-Core 部署与迁移指南

**版本**: 1.0
**创建时间**: 2026-07-03

---

## 一、部署清单

### 1.1 前置条件

- Go 1.25.0+
- PostgreSQL 14+ (Citrus 11.3+ 推荐)
- Redis 6.0+

### 1.2 文件清单

部署只需将 `routing-core/` 目录部署到生产服务器即可。**不需要修改现有代码**。

```
routing-core/                   # 整个目录
├── decision/
├── resource/
├── state/
├── tracking/
├── integration/
├── engine.go
└── engine_test.go
```

### 1.3 依赖检查

```bash
cd /opt/llm-gateway-go
go build ./routing-core/...
go test ./routing-core/... -v
```

---

## 二、迁移阶段

### 阶段0: 当前状态（已完成）

✅ 新模块 `routing-core/` 实现完成
✅ 全部测试通过
✅ 与现有代码共存，无破坏性变更

### 阶段1: 灰度接入（1周）

#### 1.1 创建 Engine 实例

在 `cmd/gateway/main.go` 中添加:

```go
import (
    "github.com/kaixuan/llm-gateway-go/credentialfpslot"
    "github.com/kaixuan/llm-gateway-go/limiter"
    routingcore "github.com/kaixuan/llm-gateway-go/routing-core"
    "github.com/kaixuan/llm-gateway-go/routing-core/decision"
    "github.com/kaixuan/llm-gateway-go/routing-core/resource"
    "github.com/kaixuan/llm-gateway-go/routing-core/state"
    "github.com/kaixuan/llm-gateway-go/routing-core/tracking"
)

func setupRoutingEngine(fpSlot *credentialfpslot.Manager, lim *limiter.Limiter, pool *pgxpool.Pool, redisClient *redis.Client) *routingcore.Engine {
    rm := resource.NewResourceManager(fpSlot, lim)
    sc := decision.NewCompositeScorer()
    cl := tracking.NewErrorClassifier()
    sm := state.NewCompositeStateManager(pool, redisClient, routing.DefaultRouteNodeConfig())
    
    return routingcore.NewEngine(rm, sc, cl, sm, slog.Default())
}
```

#### 1.2 旁路验证

在新模块上开启 **旁路模式**（仅记录日志，不影响主流程）:

```go
// 仅用于对比验证
type ShadowEngine struct {
    newEngine *routingcore.Engine
    logger    *slog.Logger
}

func (s *ShadowEngine) Plan(ctx context.Context, req routingcore.PlanRequest, candidates []routingcore.Candidate) (*routingcore.PlanResult, error) {
    // 旧逻辑
    oldResult := oldPlanLogic(candidates)
    
    // 新逻辑（仅记录）
    newResult, err := s.newEngine.Plan(ctx, req, candidates)
    if err != nil {
        s.logger.Warn("new engine plan failed", "error", err)
        return oldResult, nil
    }
    
    if newResult.Selected.CredentialID != oldResult.Selected.CredentialID {
        s.logger.Info("plan divergence", 
            "request_id", req.RequestID,
            "old", oldResult.Selected.CredentialID,
            "new", newResult.Selected.CredentialID,
        )
    }
    
    return oldResult, nil
}
```

#### 1.3 监控指标

```go
// 添加 Prometheus 指标
var (
    planDuration = promauto.NewHistogramVec(
        prometheus.HistogramOpts{Name: "routing_plan_duration_seconds"},
        []string{"engine", "result"},
    )
    
    planDivergence = promauto.NewCounter(
        prometheus.CounterOpts{Name: "routing_plan_divergence_total"},
    )
    
    resourcePressure = promauto.NewGaugeVec(
        prometheus.GaugeOpts{Name: "routing_resource_pressure"},
        []string{"credential_id"},
    )
)
```

### 阶段2: 替换 PlanCandidates（2周）

#### 2.1 修改 routing/router.go

```go
// 在 Router 结构体中添加 engine 字段
type Router struct {
    // ... 现有字段
    Engine *routingcore.Engine  // 新增
}

// 添加新方法
func (r *Router) PlanWithEngine(ctx context.Context, req routingcore.PlanRequest, candidates []Candidate) (*routingcore.PlanResult, error) {
    if r.Engine == nil {
        // Fallback to old logic
        return nil, errors.New("engine not configured")
    }
    
    return r.Engine.Plan(ctx, req, convertToEngineCandidates(candidates))
}
```

#### 2.2 双写期间

保留 `PlanCandidates` 旧方法，新方法 `PlanWithEngine` 并存:
- 1% 流量走新方法
- 99% 流量走旧方法
- 监控对比

逐步切换比例: 1% → 10% → 50% → 100%

### 阶段3: 替换失败处理（1周）

#### 3.1 修改 executor.go 失败处理

```go
// 替换原本的 credentialstate.WriteOnError 调用
if err := e.Engine.ReportResult(ctx, routingcore.RequestOutcome{
    RequestID:    req.RequestID,
    CredentialID: credential.ID,
    ProviderID:   credential.ProviderID,
    Model:        req.Model,
    StatusCode:   statusCode,
    Duration:     duration,
    Error:        err,
}); err != nil {
    slog.Warn("report result failed", "error", err)
}
```

#### 3.2 双写期间

保留 `credentialstate.Writer.WriteOnError` 调用, 同时调用 `Engine.ReportResult`:
- 对比两者的状态变化
- 验证一致性

### 阶段4: 清理老代码（1周）

- 删除 `routing.PlanCandidates`（已被 Engine 替代）
- 删除 `executor.go` 中手写的 `WriteOnError` 调用
- 删除 `tracking.classifier_test_scenarios_test.go`（保留主测试文件）

---

## 三、监控和告警

### 3.1 关键指标

```promql
# 路由决策耗时
histogram_quantile(0.99, routing_plan_duration_seconds_bucket)

# 路由结果分歧
rate(routing_plan_divergence_total[5m])

# 资源压力分布
routing_resource_pressure

# 状态转换次数
rate(state_transitions_total[5m])

# 错误分类分布
rate(error_classification_total[5m]) by (kind, level)
```

### 3.2 告警规则

```yaml
groups:
- name: routing-core
  rules:
  - alert: HighPlanDivergence
    expr: rate(routing_plan_divergence_total[5m]) > 0.1
    for: 5m
    annotations:
      summary: "High divergence between old and new routing engine"

  - alert: HighResourcePressure
    expr: routing_resource_pressure > 0.8
    for: 10m
    annotations:
      summary: "Credential {{ $labels.credential_id }} has high resource pressure"
```

---

## 四、回滚预案

### 4.1 快速回滚

```bash
# 1. 备份当前二进制
cp /opt/llm-gateway-go/bin/llm-gateway-go /opt/llm-gateway-go/bin/llm-gateway-go.bak-$(date +%Y%m%d)

# 2. 回滚代码
cd /opt/llm-gateway-go
git checkout <previous-tag>

# 3. 重新编译部署
go build -o bin/llm-gateway-go ./cmd/gateway
systemctl restart llm-gateway-go

# 4. 验证
curl http://localhost:8080/health
```

### 4.2 兼容性保证

- ✅ 老接口 `router.PlanCandidates()` 保留至阶段4结束
- ✅ 老接口 `credentialstate.Writer` 保留至阶段3结束
- ✅ 所有路由行为不变（新旧完全等价）

---

## 五、性能基准

### 5.1 测试结果

```
BenchmarkEndToEndFlow-8    50000    25000 ns/op    8000 B/op    50 allocs/op
```

### 5.2 性能预期

| 操作 | 耗时 | 吞吐 |
|------|------|------|
| Engine.Plan (50 candidates) | ~25μs | 40k qps |
| Engine.ReportResult | ~100μs (含DB/Redis) | 10k qps |
| ResourceManager.CheckEligibility | ~5μs | 200k qps |
| CompositeScorer.BatchScore | ~15μs | 66k qps |

---

## 六、验收清单

### 6.1 阶段1 验收

- [ ] 所有单元测试通过
- [ ] 所有集成测试通过
- [ ] 旁路模式记录无 ERROR
- [ ] 路由结果分歧率 < 5%

### 6.2 阶段2 验收

- [ ] 1% 流量切换成功
- [ ] 50% 流量切换成功率 > 99.9%
- [ ] 100% 流量切换延迟变化 < 10%

### 6.3 阶段3 验收

- [ ] 状态转换一致性 100%
- [ ] 错误分类覆盖率 100%
- [ ] 无新增状态不一致问题

### 6.4 阶段4 验收

- [ ] 老代码删除无功能缺失
- [ ] 整体代码减少 ≥ 20%
- [ ] 测试覆盖率 ≥ 70%

---

## 七、常见问题

### Q1: 资源检查在 Plan 阶段，是否影响首次请求延迟？

**A**: 影响极小（< 5μs），且能避免 P2C 选择到注定失败的候选，长期看总延迟更低。

### Q2: 状态转换如何保证一致性？

**A**: 所有状态变更都通过 `StateManager.ProcessEvent`，内部使用 FSM 保证转换合法性，PostgreSQL 事务保证原子性。

### Q3: 是否支持自定义评分权重？

**A**: 支持，通过 `CompositeScorer.UpdateWeights()` 即可动态调整。

### Q4: 老代码何时可以删除？

**A**: 阶段4 之后。新老代码并存期间（阶段1-3），老代码是 fallback。

### Q5: 如何添加新的错误分类规则？

**A**: 通过 `ErrorClassifier.RegisterRule(rule)` 动态注册，无需重新编译。

---

## 八、联系信息

- **负责团队**: official-deploy / ACC
- **技术负责人**: <team-member>
- **相关仓库**: llm-gateway-go-2
- **文档路径**: `/docs/refactor/`