# ErrorClassifier 实现报告

## 任务目标
实现 `routing-core/tracking/` 模块的 ErrorClassifier（错误分类器）。

## 创建的文件

```
routing-core/tracking/
├── classifier.go                      # ErrorClassifier 主实现
├── rules.go                           # 内置分类规则
├── classifier_test.go                 # 单元测试
└── classifier_test_scenarios_test.go  # 实战场景测试
```

## 测试结果

```bash
$ go test ./routing-core/tracking/... -v -cover

PASS
coverage: 98.6% of statements
ok      github.com/kaixuan/llm-gateway-go/routing-core/tracking

✅ 所有测试通过
✅ 覆盖率：98.6%（超过 80% 要求）
✅ 37 个测试用例（22 个单元测试 + 15 个场景测试）
```

## 核心实现

### 1. classifier.go - ErrorClassifier

**接口实现**：
- `Classify(input ClassifyInput) (*ClassifiedError, error)` - 分类错误
- `RegisterRule(rule ClassificationRule) error` - 注册自定义规则
- `GetSuggestions(errorKind string) []string` - 获取修复建议

**关键特性**：
- **多维度匹配**：状态码 + 关键词 + 正则表达式
- **优先级排序**：高优先级规则优先匹配
- **置信度评分**：匹配度越高分数越高
- **Upstream 过滤**：支持特定供应商规则
- **并发安全**：使用 RWMutex 保护规则列表

**匹配逻辑**：
```go
score = (匹配项得分 / 最大可能得分) + (优先级 / 100)
```

### 2. rules.go - 内置规则（按优先级排序）

| 规则 | Priority | Status | Cooldown | Level | Retryable |
|------|----------|--------|----------|-------|-----------|
| auth_error | 100 | 401/403 | 5min | Credential | ❌ |
| quota_error | 95 | 402/429 | 0 | Credential | ❌ |
| rate_limit | 90 | 429 | 15min | Model | ✅ |
| timeout | 85 | 408/504 | 30s | Model | ✅ |
| model_not_found | 80 | 404 | 24h | Model | ❌ |
| upstream_down | 75 | 502/503 | 1min | Model | ✅ |
| network_error | 70 | 500/50x | 2min | Model | ✅ |
| content_filter | 65 | 400 | 0 | Request | ❌ |
| invalid_request | 60 | 400 | 0 | Request | ❌ |
| context_length | 55 | 400 | 0 | Request | ❌ |

**关键决策**：
1. **优先级设计**：高优先级（auth > quota > rate_limit）确保关键错误优先识别
2. **Cooldown 策略**：
   - auth 5min：快速重探测
   - quota 0：需人工介入
   - timeout 30s：快速重试
   - model_not_found 24h：长时间避免无效请求

3. **Level 分层**：
   - Credential：影响整个凭据（auth, quota）
   - Model：影响特定模型（rate_limit, timeout, upstream_down）
   - Request：只影响单次请求（content_filter, invalid_request）

### 3. 测试覆盖

**单元测试**（22个）：
- ✅ 每种规则的匹配验证
- ✅ 优先级排序测试
- ✅ 置信度计算测试
- ✅ 自定义规则注册
- ✅ 正则表达式匹配
- ✅ Upstream 过滤
- ✅ 并发安全测试
- ✅ 未知错误降级

**场景测试**（15个）：
- ✅ OpenAI 认证失败
- ✅ Anthropic 配额耗尽
- ✅ Azure 速率限制
- ✅ 超时场景
- ✅ 模型不存在
- ✅ 上游维护
- ✅ 内容过滤
- ✅ 上下文长度超限
- ✅ 多关键词冲突（测试优先级）
- ✅ StateManager 集成场景

## 关键决策与设计

### 决策 1：匹配算法

采用**得分制 + 优先级加成**：
```go
score = (statusMatch + keywordMatch + patternMatch) / maxPossible + priority/100
```

**理由**：
- 支持部分匹配（例如只匹配状态码或只匹配关键词）
- 优先级作为加成确保重要规则优先
- 置信度可用于监控和调试

### 决策 2：规则必须至少匹配一个维度

修复了初版 bug：如果规则定义了条件但都不匹配，返回 0 分而非优先级加成。

**理由**：避免纯优先级高的规则误匹配不相关错误。

### 决策 3：Cooldown 设计

| 错误类型 | Cooldown | 原因 |
|---------|----------|------|
| auth | 5min | 快速重探，可能是临时 key 失效 |
| quota | 0 | 需人工充值，自动重试无意义 |
| rate_limit | 15min | 等待速率窗口重置 |
| timeout | 30s | 网络波动恢复快 |
| model_not_found | 24h | 模型不存在，长时间避免浪费 |

### 决策 4：三层 Level 设计

符合 PHASE1_TASK_CHECKLIST.md 第 2.2 节 StateManager 的状态分层：
- **CredentialLevel** → 触发 `CredentialState` 更新
- **ModelLevel** → 触发 `BindingState` 更新
- **RequestLevel** → 仅记录日志，不影响状态

## 与 StateManager 集成示例

```go
// 在 routing.Executor 中使用
classifier := tracking.NewErrorClassifier()

input := tracking.ClassifyInput{
    StatusCode:   401,
    ErrorMessage: err.Error(),
    ResponseBody: string(body),
    Upstream:     "openai",
}

classified, _ := classifier.Classify(input)

switch classified.Level {
case tracking.CredentialLevel:
    stateManager.ProcessEvent(ctx, state.StateEvent{
        Type:         state.EventFailureAuth,
        CredentialID: credentialID,
        ErrorKind:    classified.Kind,
        RetryAfter:   classified.Cooldown,
    })
case tracking.ModelLevel:
    stateManager.ProcessEvent(ctx, state.StateEvent{
        Type:         state.EventFailureRateLimit,
        CredentialID: credentialID,
        Model:        model,
        ErrorKind:    classified.Kind,
        RetryAfter:   classified.Cooldown,
    })
case tracking.RequestLevel:
    log.Warn("Request error", "kind", classified.Kind)
}

if classified.Retryable && time.Now().After(cooldownEnd) {
    // 重试逻辑
}
```

## 已知限制与 TODO

### 限制
1. **规则静态化**：当前规则硬编码，未来可支持热更新
2. **Confidence 简化**：当前置信度计算简单，未引入机器学习
3. **缺少速率窗口解析**：未解析 `Retry-After` header

### TODO（Phase 2）
- [ ] 支持从配置文件加载自定义规则
- [ ] 集成 Prometheus 指标（错误分类分布）
- [ ] 支持 `Retry-After` header 解析
- [ ] 添加规则热更新机制
- [ ] 错误分类审计日志

## 验证

```bash
# 构建验证
$ go build ./routing-core/tracking/...
✅ 编译通过

# 单元测试
$ go test ./routing-core/tracking/... -v -cover
✅ 37/37 测试通过
✅ 覆盖率：98.6%

# 集成测试（模拟真实场景）
✅ OpenAI/Anthropic/Azure 错误场景全部通过
✅ 并发安全测试通过
✅ 优先级冲突测试通过
```

## 交付清单

- [x] classifier.go（主实现）
- [x] rules.go（10 个内置规则）
- [x] classifier_test.go（22 个单元测试）
- [x] classifier_test_scenarios_test.go（15 个场景测试）
- [x] 测试覆盖率 ≥ 80%（实际 98.6%）
- [x] 无注释（代码自解释）
- [x] 集成示例文档

---

**实现时间**：2026-07-03  
**负责人**：implementer-classifier  
**状态**：✅ 完成
