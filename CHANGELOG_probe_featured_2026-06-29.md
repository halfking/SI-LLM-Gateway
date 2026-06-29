# 凭据探活：featured-models 优先匹配 - 变更日志

**日期**: 2026-06-29
**范围**: bg 包（`PickProbeModelForCredential`）
**关联审计**: TASK-AUDIT.md / P0_INCIDENT_SUMMARY.md（minimax-m3 06-23 no_candidates 雪崩）

## 问题

`bg/shared_pick.go` 的 `PickProbeModelForCredential` 在国内 provider fallback 阶段
用 `time.Now().UnixNano() % len(candidates)` 在该凭据**所有可用模型**里**随机**挑一个
作为探活目标：

```go
// 旧逻辑 (bg/shared_pick.go:79-103, 修复前)
if domestic {
    var candidates []string
    rows, qerr := db.Query(ctx, `
        SELECT COALESCE(NULLIF(pm.outbound_model_name, ''), pm.raw_model_name) AS probe_model
        FROM credential_model_bindings cmb
        JOIN provider_models pm ON pm.id = cmb.provider_model_id
        WHERE cmb.credential_id = $1
          AND cmb.available = TRUE
          ...
    `, credID)
    ...
    if len(candidates) > 0 {
        pick := candidates[time.Now().UnixNano()%int64(len(candidates))]
        return PickProbeResult{Model: pick, Source: "auto:domestic_random"}, nil
    }
}
```

**风险**：凭据上可能有 30+ 个模型，其中"主流"（featured）模型只占少量。冷门模型
一旦偶发 5xx / 429 / 限流 / 临时维护，探活失败 → 整个凭据被标 `unreachable` 或
`auth_failed` → 凭据上所有其他健康模型被 `v_routable_credential_models.is_routable=FALSE`
一起屏蔽 → **`no_candidates` 路由空集雪崩**。这与 minimax-m3 06-23 事故根因同构。

## 根因

冷门模型的单点抖动**不应该**成为整凭据 unhealthy 的判定依据。探活目标应优先选择
业务定义的"主流模型白名单" `routing_policy.featured_models`，因其：

1. 经过管理员显式维护，与生产流量分布对齐
2. 通常是上游 SLO 最好的模型，抖动概率最低
3. 一旦 featured 探活失败，往往意味着**真**的 provider 故障（不是某个冷门模型偶发）

## 修复

将 4 级 fallback 升级为 **5 级**：

| 优先级 | 来源 | Source 标签 |
|---|---|---|
| 1 | 管理员手动 pin | `manual` |
| 2 | request_logs 7d 最常用 client_model | `auto:request_log` |
| **3a（新）** | **featured_models 列表匹配** | **`auto:featured`** |
| 3b | 该凭据可用模型中随机 | `auto:domestic_random` |
| 4 | 国外 provider | 留空 |

**匹配字段**：`featured_models` 存的是标准模型名（standardized_name / canonical_name），
匹配顺序为 `pm.standardized_name → mc.canonical_name → pm.raw_model_name`，由 SQL 的
`COALESCE` 表达。命中排序按 featured_models 数组下标（业务方在数组里靠前的 = 优先级更高）。

**兜底保留**：featured 命中失败时仍走原随机逻辑（`auto:domestic_random`），向后兼容
未维护 featured_models 的旧凭据。

## 关键代码改动

### `bg/shared_pick.go`

```go
// 顶部 doc 更新: 4-level → 5-level
// PickProbeModelForCredential implements the 5-level fallback algorithm
// (manual > request_logs > featured > domestic_random > empty).

// 新增包级类型
type featuredRow struct {
    probeModel    string  // upstream 实际调用名
    candidateName string  // 标准化名（用于 featured 匹配）
}

// 新增包级纯函数（可单元测试）
func pickFeaturedModelName(available []featuredRow, featured []string) string
func pickRandomCandidate(candidates []string, salt int64) string

// Priority 3a: featured 优先
//   - SQL 把 (probe_model, candidate_name) 拉回 Go
//   - 排序逻辑在 Go 端做（pickFeaturedModelName），
//     保持算法可单测、不依赖 DB
// Priority 3b: featured 没命中 → 原随机兜底
```

### `bg/default_probe_picker.go`

注释同步：4-level → 5-level。

### `bg/shared_pick_test.go`（新增，11 个用例）

| 用例 | 验证点 |
|---|---|
| `TestPickFeaturedModelName_EmptyInputs` | 边界：空切片 |
| `TestPickFeaturedModelName_StandardizedNameMatch` | 标准化名命中基本路径 |
| `TestPickFeaturedModelName_PriorityIsFeaturedOrder` | 排序按 featured 数组下标，**不**按 available 顺序 |
| `TestPickFeaturedModelName_NoMatchReturnsEmpty` | 不命中返回空，触发 3b 兜底 |
| `TestPickFeaturedModelName_FiltersOutNonFeatured` | 冷门模型**绝不**入选 |
| `TestPickFeaturedModelName_DuplicateFeaturedNames_HandledGracefully` | featured_models 重复项不 panic |
| `TestPickRandomCandidate_ReturnsMemberOfInput` | 随机结果必须是候选之一 |
| `TestPickRandomCandidate_DeterministicBySalt` | 同 salt 结果稳定 |
| `TestPickRandomCandidate_FullCoverage` | 模 len 覆盖：salts 0..N-1 → 全候选 |
| `TestPickRandomCandidate_Empty` | 空切片安全 |
| `TestPickFeaturedModelName_RealisticSnapshot` | **30 模型 / 3 featured 场景，100 次试验绝不返回冷门**（审计关键性质） |

## 验证结果

```
$ go test ./bg/ -run "TestPickFeaturedModelName|TestPickRandomCandidate" -v
=== RUN   TestPickFeaturedModelName_EmptyInputs                       --- PASS
=== RUN   TestPickFeaturedModelName_StandardizedNameMatch             --- PASS
=== RUN   TestPickFeaturedModelName_PriorityIsFeaturedOrder           --- PASS
=== RUN   TestPickFeaturedModelName_NoMatchReturnsEmpty               --- PASS
=== RUN   TestPickFeaturedModelName_FiltersOutNonFeatured             --- PASS
=== RUN   TestPickFeaturedModelName_DuplicateFeaturedNames_...        --- PASS
=== RUN   TestPickRandomCandidate_ReturnsMemberOfInput                --- PASS
=== RUN   TestPickRandomCandidate_DeterministicBySalt                 --- PASS
=== RUN   TestPickRandomCandidate_FullCoverage                        --- PASS
=== RUN   TestPickRandomCandidate_Empty                               --- PASS
=== RUN   TestPickFeaturedModelName_RealisticSnapshot                 --- PASS
PASS
ok      github.com/kaixuan/llm-gateway-go/bg  0.547s

$ go test ./bg/...
ok      github.com/kaixuan/llm-gateway-go/bg  0.341s

$ go vet ./...
（无输出）

$ go build ./...
（无输出）
```

## 兼容性

- **新增 source 标签** `auto:featured`：字符串扩展，前向兼容。admin UI 走通用 string 渲染路径。
- **现有 `auto:domestic_random` 凭据行为变化**：仅当 featured 命中时变化；管理员想锁回
  随机可手动 `POST /api/providers/{id}/credentials/{cid}/probe-model` 设置 `manual`。
- **零停机部署**：纯 Go 变更，无 SQL 迁移，无 schema 变更。
- **回滚**：单次 git revert 即可。

## 部署后观察

1. `SELECT source, COUNT(*) FROM credential_probe_model_log
    WHERE picked_at > now() - interval '24 hours'
    GROUP BY source;`
   期望：新增 `auto:featured` 行；`auto:domestic_random` 数量下降。
2. `SELECT credential_id, raw_model_name, state, last_status
    FROM model_probe_state
    WHERE last_status IN ('network', 'auth', 'http_5xx')
      AND last_attempt_at > now() - interval '24 hours';`
   期望：失败集中在冷门模型的次数应显著下降。
3. 如发现某凭据 featured 命中后**真**的 provider 故障仍被准确捕获（应如此），
   即可认为本修复没有引入假阴性增加。

## 不动的部分（明确范围）

- Priority 2（request_logs 最常用模型）— 本次不动
- `bg/model_probe.go` Layer 4 `featuredCycle`（广撒网多模型探活）— 解耦，不动
- `bg/credential_probe_v2.go` 的 `cycleAll` — 它只跑已写好的 `default_probe_model`，不挑模型
- 任何 admin UI 改动 — `auto:featured` 走通用字符串渲染
- 任何 SQL 迁移 — `routing_policy.featured_models` schema 不动

## 关联文件

- `bg/shared_pick.go` — 核心改动
- `bg/default_probe_picker.go` — 注释同步
- `bg/shared_pick_test.go` — 新增 11 个单元测试
- `deploy/sql/00_schema/002_providers_and_models.sql:70` — `standardized_name` 列定义（标准名存储位置）
- `deploy/sql/00_schema/003_routing_tables.sql:258` — `featured_models` 默认值（8 个标准名）
- `admin/routing.go:743` — featured_models 录入语义（COALESCE canonical_name, raw_model_name）
