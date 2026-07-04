# 分区动态路由最终方案（2026-07-04）

## 架构设计

### 核心原则
**所有新写入（INSERT）→ `*_default`（热数据，7天窗口）**  
**UPDATE → `*_default`（流式更新肯定是热数据）**  
**定时迁移 → 7天前的数据迁移到月度分区**

### 分区状态（全部 ATTACHED）
```
request_logs (父表)
├─ request_logs_2026_06 (ATTACHED, heap/columnar) — 历史归档
├─ request_logs_2026_07 (ATTACHED, heap)          — 当月完整数据
├─ request_logs_2026_08 (ATTACHED, heap)          — 下月预创建
└─ request_logs_default (ATTACHED, heap)          — 最近7天热数据
```

### 数据流
```
1. 新请求 INSERT → request_logs_default
   ↓ (流式响应期间)
2. 多次 UPDATE → request_logs_default
   ↓ (每日凌晨 2:00)
3. 定时迁移 → 7天前数据 → request_logs_2026_07
   ↓ (月底 8月1日)
4. Columnar 转换 → request_logs_2026_07 (heap → columnar) → ATTACH
```

## 为什么不需要动态路由？

### INSERT 场景
- **新请求**：`ts = now()`，肯定是热数据 → 写 `*_default` ✅
- **历史补录**：极少发生，且即使写错表也可以后续迁移

### UPDATE 场景
- **流式更新**：更新几秒钟前 INSERT 的记录 → 肯定在 `*_default` ✅
- **历史补录修正**：极少发生，可以手动处理

### 查询场景
- **查询父表**：自动聚合所有 ATTACHED 分区（包括 default + 月度分区） ✅
- **无需 UNION**：所有分区都 ATTACHED

## 当前实现状态

### 代码层面 ✅
- **INSERT**：硬编码 `*_default`（正确）
- **UPDATE**：硬编码 `*_default`（正确）
- **动态路由器**：已实现（`partition_router.go`），**暂时不使用**

### 数据库层面 ❌（需要修复）
- **71 当前状态**：2026_07/08 已 DETACHED
- **应该是**：2026_07/08 应该 RE-ATTACH

## 需要执行的修复

### 1. RE-ATTACH 月度分区（71 环境）
```sql
BEGIN;

ALTER TABLE request_logs ATTACH PARTITION request_logs_2026_07 
    FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');

ALTER TABLE request_logs ATTACH PARTITION request_logs_2026_08 
    FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');

ALTER TABLE usage_ledger ATTACH PARTITION usage_ledger_2026_07 
    FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');

ALTER TABLE usage_ledger ATTACH PARTITION usage_ledger_2026_08 
    FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');

COMMIT;
```

### 2. 验证分区结构
```sql
SELECT 
    p.relname AS parent_table,
    c.relname AS partition_name,
    pg_get_expr(c.relpartbound, c.oid) AS partition_bound,
    am.amname AS access_method
FROM pg_class c
JOIN pg_inherits i ON i.inhrelid = c.oid
JOIN pg_class p ON p.oid = i.inhparent
JOIN pg_am am ON am.oid = c.relam
WHERE p.relname IN ('request_logs', 'usage_ledger')
ORDER BY p.relname, c.relname;
```

**预期结果**：
- request_logs_2026_06 (ATTACHED)
- request_logs_2026_07 (ATTACHED)
- request_logs_2026_08 (ATTACHED)
- request_logs_default (ATTACHED)

### 3. 迁移 default 中的历史数据到月度分区
```sql
-- 迁移 2026_07 分区中已存在的数据（DETACH 期间写入 default 的）
BEGIN;

INSERT INTO request_logs_2026_07
SELECT * FROM request_logs_default
WHERE ts >= '2026-07-01' AND ts < '2026-08-01'
ON CONFLICT (request_id, ts) DO NOTHING;

DELETE FROM request_logs_default
WHERE ts >= '2026-07-01' AND ts < '2026-08-01';

COMMIT;
```

## 验证写入行为（RE-ATTACH 后）

### 测试 1：新 INSERT 应该写入 default
```bash
# 发送测试请求
curl -X POST https://llm.kxpms.cn/v1/chat/completions \
  -H "Authorization: Bearer <valid-key>" \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"test"}]}'

# 查询验证（应该在 default）
psql -c "SELECT COUNT(*) FROM request_logs_default WHERE ts > now() - interval '1 minute';"
# 预期：1

# 查询月度分区（应该为 0）
psql -c "SELECT COUNT(*) FROM request_logs_2026_07 WHERE ts > now() - interval '1 minute';"
# 预期：0（因为新写入在 default，还没迁移）
```

### 测试 2：查询父表应该聚合所有分区
```sql
-- 查询父表
SELECT COUNT(*) FROM request_logs WHERE ts >= '2026-06-01';

-- 应该等于
SELECT 
    (SELECT COUNT(*) FROM request_logs_2026_06) +
    (SELECT COUNT(*) FROM request_logs_2026_07) +
    (SELECT COUNT(*) FROM request_logs_2026_08) +
    (SELECT COUNT(*) FROM request_logs_default)
AS total;
```

## 关键问题：为什么新数据不会路由到 2026_07？

**PostgreSQL 分区路由规则**：
- 写父表 `INSERT INTO request_logs` → PG 根据 `ts` 自动路由
- 写子表 `INSERT INTO request_logs_default` → 直接写指定分区

**我们的实现**：
- 代码硬编码 `INSERT INTO request_logs_default` → **绕过分区路由** ✅
- 即使 2026_07 ATTACHED，新数据也不会写入 2026_07

**验证**：
```sql
-- 测试：手动插入一条数据到 default
INSERT INTO request_logs_default (request_id, ts, tenant_id, ...)
VALUES ('test-request-id', '2026-07-04 12:00:00+00', 'default', ...);

-- 查询父表
SELECT * FROM request_logs WHERE request_id = 'test-request-id';
-- ✅ 能查到（default 是 ATTACHED 的子分区）

-- 查询 2026_07 分区
SELECT * FROM request_logs_2026_07 WHERE request_id = 'test-request-id';
-- ✅ 查不到（因为我们直接写了 default，没有路由到 2026_07）
```

## 优势

1. ✅ **简单**：代码无需动态路由逻辑
2. ✅ **安全**：所有 UPSERT 在 heap 表（default）
3. ✅ **快速**：default 只有 7 天数据，索引小
4. ✅ **完整查询**：SELECT 父表自动聚合所有分区
5. ✅ **无中断**：所有分区 ATTACHED，无跨月问题

## 劣势与缓解

### 劣势 1：default 需要定期清理
**影响**：7 天后 default 会持续增长

**缓解**：定时任务（每日凌晨）迁移 7 天前数据

### 劣势 2：历史补录会写入 default
**影响**：补录 6 月数据会先写 default，需要手动迁移

**缓解**：
- 补录场景极少
- 可以用 `partition_router.go` 手动迁移

## 总结

**最终方案**：
- ✅ 代码：硬编码 `*_default`（已实现）
- ⏳ 数据库：RE-ATTACH 月度分区（待执行）
- ⏳ 定时任务：每日迁移 7 天前数据（待部署）

**`partition_router.go` 的作用**：
- 当前：**不使用**（预留）
- 未来：如果需要支持历史补录，可以用路由器决定目标分区

---

**下一步**：RE-ATTACH 71 的月度分区
