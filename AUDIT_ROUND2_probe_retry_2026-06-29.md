# 第二轮审计报告 — 探活重试机制

**日期**: 2026-06-29（第一轮审计同日，推送后复审）
**审计范围**: `origin/server-71` HEAD `ef91bdae`，包含 `d7f87188`（retry）和 `b77f767d`（featured picker）
**审计方法**: 深度代码审查（逻辑漏洞、边界条件、并发安全、与原代码行为兼容性）

---

## 审计发现

| # | 严重度 | 文件:行 | 问题 | 影响 | 修复建议 |
|---|---|---|---|---|---|
| **1** | 🟡 中 | `bg/shared_pick.go:130-138` | featured query `for rows.Next()` 遍历后直接 `rows.Close()`，**没检查 `rows.Err()`**。如果数据库在遍历过程中发生错误（网络中断、数据损坏），`rows.Next()` 返回 false，但 `rows.Err()` 非 nil —— 当前代码会静默跳到 fallback（priority 3b random pick），而不是返回错误 | 数据库故障被误当作"没有 featured 匹配"，降级到 random pick。语义错误：数据库错误应透传给 caller（admin API / bg repickAll），而不是吞掉 | 在 line 138 `rows.Close()` 后加 `if err := rows.Err(); err != nil { return PickProbeResult{}, err }` |
| **2** | 🟢 低 | `bg/shared_pick.go:180-195` | `bindingAvailableForModel` 在数据库错误时返回 `false`（line 194 `return err == nil && ok`），caller (line 88) 会误认为 binding 不可用，跳过 priority 1 (request_log) | priority 1 在数据库短时故障时被错误跳过。但影响有限：后续 priority 2/3 的 query 也会失败，最终整个 `PickProbeModelForCredential` 会返回错误，所以不会产生"选到错误模型"的后果 | 改为 `if err != nil { return false }; return ok`（显式区分"错误"与"不存在"）。或接受现状（防御性改进，非关键） |
| **3** | 🟢 低 | `bg/credential_probe_v2.go:372-385` | step2 retry loop 声明了 `errMsg` 和 `lastErr` 两个变量，但在 loop 内都被赋值为同一个 `e`（line 384-385），完全冗余。最终只使用 `lastErr` (line 392) | 无功能影响，仅代码可读性。增加理解负担 | 删除 `errMsg` 变量，只保留 `lastErr` |

---

## 审计方法详解

### 1. 深度回读 + 真实路径枚举

- **不只看新增代码**：回读每个改动的上下文（前后 50 行），确认与周边逻辑的交互
- **枚举真实错误路径**：对每个 retry loop，列出所有可能的失败分支（网络错、5xx、4xx、ctx cancel、partial response），验证 classifier 覆盖全部
- **SQL 错误处理**：对所有 `db.Query` / `db.QueryRow`，检查是否正确处理了 `rows.Err()` / `Scan()` 错误

### 2. 并发安全审查

- `probeutil.SleepWithCtx`: 检查 timer leak（已有 `defer t.Stop()`，OK）
- `shared_pick.go`: 无共享状态修改，只读 DB，并发安全
- `credential_probe_v2.go`: `probeCredential` 内部无共享状态，每次调用独立 `httpClient`，并发安全

### 3. 与原代码行为兼容性

- **happy path 延迟**：retry 第一次 delay=0s，健康凭据无额外延迟 ✓
- **不可恢复错误立即失败**：401/403/404/400/422/402 在第一次 attempt 就 fail fast，不进入 retry ✓
- **ctx cancel 立即中止**：`SleepWithCtx` 在 ctx.Done() 时返回 false，loop 立即 return ✓
- **错误信息向后兼容**：admin `health_error` 加了 `after N attempts:` 前缀，但原字段仍存在 ✓

---

## 问题分析

### 问题 #1 详解：`rows.Err()` 缺失的影响

**代码路径**（`bg/shared_pick.go:130-138`）：
```go
for rows.Next() {
    var r featuredRow
    if err := rows.Scan(&r.probeModel, &r.candidateName); err != nil {
        continue  // 跳过单行 scan 错误
    }
    available = append(available, r)
}
rows.Close()
// ❌ 缺失：if err := rows.Err(); err != nil { return PickProbeResult{}, err }
if picked := pickFeaturedModelName(available, featured); picked != "" {
    return PickProbeResult{Model: picked, Source: "auto:featured"}, nil
}
// 继续走 priority 3b (random pick)
```

**攻击场景**：
1. DB 开始返回前 10 行 binding，中途网络中断
2. `rows.Next()` 返回 false（EOF），但 `rows.Err()` = "network error"
3. 当前代码：`available` 只收集了前 10 行，`pickFeaturedModelName` 用不完整数据挑选 → 可能挑到非最优 featured model
4. 更糟：如果前 10 行都不在 `featured` 里，`pickFeaturedModelName` 返回 `""`，fallback 到 priority 3b random pick

**正确行为**：应该返回 `PickProbeResult{}, network_error`，让 caller（admin API / bg repickAll）感知到数据库故障，而不是用脏数据做决策。

---

## 未发现的问题（已验证正确）

| 审查点 | 结论 |
|---|---|
| `probeutil.IsProbeRetryableStatus` 边界：code=0, code=600, code=1xx/2xx | ✓ 正确：0 retryable, 1xx/2xx/6xx+ non-retryable, 400-599 按策略分类 |
| `probeutil.SleepWithCtx` 零延迟：d=0 时是否立即返回 | ✓ 正确：line 98-100 `if d <= 0 { return ctx.Err() == nil }` |
| `credential_probe_v2.go` step1 retry：nonRetryableHit 是否会覆盖 lastErr | ✓ 正确：nonRetryableHit 非空时立即 break outer loop，不会被 lastErr 覆盖 |
| `admin doHealthCheck` retry：attempts 计数是否正确 | ✓ 正确：line 183 `attempts++` 在每次循环开始，最终 `attempts == len(ProbeRetryDelays)` |
| `shouldRetryChatErrMsg` 对空 errMsg 的处理 | ✓ 防御性正确：返回 true（retryable），虽然 miniChat 不产出空 errMsg，但作为 fallback 合理 |

---

## 修复优先级建议

| 问题 | 优先级 | 理由 |
|---|---|---|
| #1 `rows.Err()` 缺失 | **P2 中** | 数据库故障时产生脏数据决策，违背"错误应透传"原则。但生产环境数据库故障率低，且后续 query 也会失败（最终整个 pick 失败），所以不是 P0 |
| #2 `bindingAvailableForModel` 错误处理 | P3 低 | 防御性改进，实际影响极小 |
| #3 冗余变量 | P4 低 | 纯代码清理，无功能影响 |

---

## 建议后续行动

1. **立即修复 #1**（rows.Err() 缺失）：在新 feature 分支创建修复 commit，经测试后合并到 main/server-71
2. **择机修复 #2/#3**：可与下次相关模块改动一起 bundle，或单独 chore commit
3. **补充集成测试**：模拟数据库中途错误（`pgxmock` 返回 partial rows + err），验证错误被正确透传

---

## 测试覆盖缺失

当前单元测试（`bg/shared_pick_test.go`）只覆盖 happy path + no-match fallback，**未覆盖**：
- 数据库遍历错误（`rows.Err()` 非 nil）
- `bindingAvailableForModel` 数据库错误路径

建议补充：
```go
func TestPickProbeModelForCredential_RowsErr(t *testing.T) {
    mock := pgxmock.NewConn(t)
    mock.ExpectQuery("SELECT.*credential_model_bindings").
        WillReturnRows(pgxmock.NewRows([]string{"probe_model", "candidate_name"}).
            AddRow("gpt-4o", "gpt-4o").
            RowError(0, errors.New("network interrupted")))
    result, err := PickProbeModelForCredential(ctx, mock, 123)
    if err == nil {
        t.Error("expected network error, got nil")
    }
}
```

---

## 结论

第二轮审计发现 **1 个中等优先级**问题（`rows.Err()` 缺失）和 **2 个低优先级**问题（防御性改进 + 代码清理）。

**不影响已推送代码的核心功能正确性**：
- retry 机制本身逻辑正确（3 attempts, 正确分类 retryable/non-retryable）
- featured picker 在数据库健康时工作正常
- 问题只在**数据库故障**这一罕见场景下触发，且后果是"用脏数据做决策"而非"系统崩溃"

建议在下次维护窗口修复 #1，或在生产环境观察一段时间（监控 `health_status=unreachable` 与数据库告警的相关性）后再决定修复时机。
