# 05 · Provider 页加载性能优化（1007ms → 28ms，↓97%）

**Commit**：`b65a7e94` — `perf(providers): optimize page load speed by 97%`
**作者**：halfking <kimmy.huang@gmail.com>
**时间**：2026-06-29 12:51 (+0800)
**优先级**：**P2**（运营端体验优化）
**破坏性变更**：**DB schema DDL**（`ALTER TABLE model_probe_runs SET ACCESS METHOD heap`），需要 PostgreSQL ≥ 14 + 单独维护窗口
**依赖**：无

---

## 一、问题陈述（Why）

运营端 `/providers/:id` 详情页加载缓慢，从用户点击到首屏完整可交互需要 **~1 秒**。期望 < 100ms。

**性能瓶颈分布**：

| 层级 | 现象 | 耗时占比 |
|------|------|----------|
| **DB（P0）** | `model_probe_runs` 表使用 `columnar` 存储，recent-failures 查询全表扫描 | ~1007ms（其中 planning 25ms + execution 982ms） |
| **前端（P1）** | 三个 API 串行 await（`getProviderDetail` → `getProviderCredentials` → `getProviderRecentProbeFailures`） | ~970ms（串行叠加） |
| **后端（P2）** | `listCredentials` 逐条调 Redis 查 fp slot 统计（N+1） | 10 凭据时 ~50ms；属潜在瓶颈 |

## 二、修复方案

### 2.1 P0：DB 层优化（核心，贡献 97% 提升）

**文件**：`PERFORMANCE_OPTIMIZATION_REPORT.md` 中描述的 DDL（commit 中未直接提交 SQL，需手动执行）

```sql
-- 1) 更新统计
ANALYZE model_probe_runs;

-- 2) 列式 → 行式
ALTER TABLE model_probe_runs SET ACCESS METHOD heap;
-- 表大小 154MB → 6.5MB（↓95.8%）

-- 3) 覆盖索引
CREATE INDEX idx_mpr_provider_recent_failures 
ON model_probe_runs (credential_id, created_at DESC)
WHERE status <> 'ok' AND status <> 'skipped';
```

**查询耗时对比**（commit message 数据）：

| 阶段 | 修复前 | 修复后 | 提升 |
|------|--------|--------|------|
| Planning Time | 78ms | 25ms | ↓ 68% |
| Execution Time | 927ms | 3ms | ↓ **99.7%** |
| **总耗时** | **1007ms** | **28ms** | ↓ **97%** |

### 2.2 P1：前端并发

**文件**：`web/src/views/ProviderDetailView.vue:42`

```typescript
// 修复前：串行 await
provider.value = await getProviderDetail(providerId.value)
creds.value = await getProviderCredentials(providerId.value)
const failures = await getProviderRecentProbeFailures(providerId.value)

// 修复后：Promise.all 并发
const [providerData, credsData, failuresData] = await Promise.all([
    getProviderDetail(providerId.value),
    getProviderCredentials(providerId.value),
    getProviderRecentProbeFailures(providerId.value).catch(() => ({ models: [] }))
])
```

> 第三个请求 `.catch(() => ({ models: [] }))` 是关键：probe failures 是 best-effort 徽标数，失败不阻塞主流程。

**效果**：墙钟时间 ~1000ms → ~30ms（与 DB 优化叠加后，主要由 DB 决定）。

### 2.3 P2：后端 Redis N+1

**新增**：`credentialfpslot/slot.go:1253+` 新方法 `BatchStats()`

```go
// credentialfpslot/slot.go:1253
// BatchStats returns slot occupancy for multiple credentials in one Redis round-trip.
func (m *Manager) BatchStats(ctx context.Context, credLimits map[int]*int) map[int]struct {
    SlotLimit int
    Used      int
    Free      int
} {
    // 用 Redis pipeline 一次性发完 N 个查询
}
```

**接入点**：`admin/provider_credential.go` — `listCredentials` 改用 `m.fpSlots.BatchStats(ctx, credLimits)` 替代 N 次单独 `Stats` 调用。

**效果**：10 凭据时 10 次 Redis 往返 → 1 次 pipeline 调用；当前 14 凭据尚不显著，是未来扩展性的提前优化。

## 三、测试覆盖

| 测试文件 | 测试函数 | 验证目标 |
|----------|----------|----------|
| `credentialfpslot/slot_batch_test.go` | `TestBatchStats` | 批量查询基本正确性 |
| `credentialfpslot/slot_batch_test.go` | `TestBatchStats_EmptyInput` | 空输入边界 |
| `credentialfpslot/slot_batch_test.go` | `TestBatchStats_UnlimitedCredentials` | 无限凭据（credLimit=nil） |
| `credentialfpslot/slot_batch_test.go` | `TestBatchStats_Consistency` | 与单条 `Stats` 结果一致性 |

## 四、跨分支同步要点（Sync Notes）

### 4.1 必带文件

```
credentialfpslot/slot.go              # 修改 +123 行（追加 BatchStats）
credentialfpslot/slot_batch_test.go   # 新增 176 行
admin/provider_credential.go          # 修改 +22 行（listCredentials 改用 BatchStats）
web/src/views/ProviderDetailView.vue  # 修改 ~20 行（串行→并发）
PERFORMANCE_OPTIMIZATION_REPORT.md    # 新增 82 行（背景报告）
```

### 4.2 关键 DB 同步点

| 操作 | 时机 | 风险 |
|------|------|------|
| `ALTER TABLE model_probe_runs SET ACCESS METHOD heap` | **必须在维护窗口执行** | 长时间锁表（154MB 表） |
| `CREATE INDEX idx_mpr_provider_recent_failures` | 与 DDL 一起或之后 | 短期锁表 |
| `ANALYZE model_probe_runs` | DDL 后 | 不锁表，建议业务低峰 |

**重要**：commit 中**未提交**迁移 SQL 文件！其他分支需手动从 `PERFORMANCE_OPTIMIZATION_REPORT.md` 复制 DDL 写入 `db/migrations/` 目录，或在 `db/migrations/` 目录下新建 `0XX_*.sql` 文件。

### 4.3 验证步骤

```bash
# 1. 单元测试
go test ./credentialfpslot/... -run TestBatchStats -v

# 2. DB 验证
psql -c "\d model_probe_runs" | grep "Access method"
# 期望：Access method: heap
psql -c "EXPLAIN ANALYZE SELECT ... FROM model_probe_runs WHERE ... ORDER BY created_at DESC LIMIT 50"
# 期望：使用 idx_mpr_provider_recent_failures

# 3. 前端构建
cd web && npm run build

# 4. 端到端
# 浏览器打开 /providers/:id，DevTools Network 面板：3 个请求并行开始；DB 查询 < 50ms
```

### 4.4 兼容性

- ✅ 后端 API 完全兼容
- ✅ 前端 UI 完全兼容
- ⚠️ DB schema 变更（仅 ACCESS METHOD + 新增索引）
- ⚠️ PostgreSQL 版本要求 ≥ 14（`SET ACCESS METHOD` 语法支持）

## 五、风险与回滚（Risk & Rollback）

| 维度 | 评估 |
|------|------|
| 影响面 | 运营端 `/providers/:id`；DB 层影响 `model_probe_runs` 全表 |
| 可逆性 | **DB 难回滚**：`ALTER TABLE ... SET ACCESS METHOD columnar` 在某些版本上不支持；建议保留 DDL 前快照 |
| 降级开关 | 无显式开关；如要回退到串行前端，git revert `ProviderDetailView.vue` 即可 |
| 监控 | `pg_stat_user_tables.seq_scan` / `idx_scan` on `model_probe_runs`；应看到 idx_scan 上升 |

## 六、未来优化（Future Improvements）

1. **提交 DDL 迁移文件**：本 commit 缺 `db/migrations/0XX_model_probe_runs_heap.sql`，建议补齐。
2. **BatchStats 扩展**：可进一步实现 `BatchAcquire` / `BatchRelease`，减少凭据竞争场景的 Redis 往返。
3. **前端流式渲染**：`Promise.all` 是并发，但 3 个响应到达后才是整批渲染；可用 React Suspense / Vue Suspense 进一步提升体感。
4. **DB 连接池**：`admin/provider_credential.go` 的查询未指定 `LIMIT` 优化；凭据数大时仍可能慢。
5. **索引维护**：`idx_mpr_provider_recent_failures` 是部分索引，VACUUM 策略需确认不会失效。
