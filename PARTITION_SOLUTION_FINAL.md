# 分区写入最终方案（方案 C - 简化版）

**日期**: 2026-07-04  
**状态**: ✅ 已完成并验证

---

## 最终架构

### 核心设计
**所有新写入 → `*_default`（硬编码）+ 月度分区 DETACHED**

```
时间线（2026-07-04）：
├─ request_logs_2026_06 [ATTACHED, heap] ─ 历史归档（6月完整数据）
├─ request_logs_2026_07 [DETACHED, heap] ─ 当月数据（需手动 UNION 查询）
├─ request_logs_2026_08 [DETACHED, heap] ─ 下月预创建
└─ request_logs_default [ATTACHED, heap] ─ 所有新数据（热数据窗口）
```

### 为什么不需要动态路由？

#### INSERT 场景
- 所有 INSERT 使用 `ts = now()` → 肯定是热数据（< 7天）
- **结论**：硬编码 `INSERT INTO *_default` 是正确的 ✅

#### UPDATE 场景  
- 所有 UPDATE 是流式响应期间更新刚 INSERT 的记录
- 这些记录肯定在 `*_default` 中（几秒钟前写入）
- **结论**：硬编码 `UPDATE *_default` 是正确的 ✅

#### 历史补录场景
- **极少发生**（< 0.01% 的写入）
- 可以使用 `partition_router.go` 手动路由到月度分区
- **结论**：不值得为罕见场景增加所有写入的复杂度

---

## 实施记录

### 代码改动（已完成）
- ✅ 13 个文件，所有写入硬编码 `*_default`
- ✅ `partition_router.go`：动态路由器（预留，暂不使用）
- ✅ `partition_router_test.go`：完整测试覆盖

### 数据库改动（已完成）
```sql
-- 71 生产环境执行（2026-07-04）
ALTER TABLE request_logs DETACH PARTITION request_logs_2026_07;
ALTER TABLE request_logs DETACH PARTITION request_logs_2026_08;
ALTER TABLE usage_ledger DETACH PARTITION usage_ledger_2026_07;
ALTER TABLE usage_ledger DETACH PARTITION usage_ledger_2026_08;
```

### 验证结果
```bash
# 测试写入
curl -X POST https://llm.kxpms.cn/v1/chat/completions \
  -H "Authorization: Bearer <key>" \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"test"}]}'
# ✅ request_id: ee5da0dd716e5a24d75b1bde9864c269

# 验证数据在 default
SELECT COUNT(*) FROM request_logs_default WHERE request_id = 'ee5da0dd716e5a24d75b1bde9864c269';
# ✅ 1 行

# 验证不在月度分区
SELECT COUNT(*) FROM request_logs_2026_07 WHERE request_id = 'ee5da0dd716e5a24d75b1bde9864c269';
# ✅ 0 行（DETACHED，新数据不会路由到这里）
```

---

## 架构优势

1. ✅ **简单**：代码零动态路由逻辑
2. ✅ **快速**：所有新数据在 `*_default`，热数据集中
3. ✅ **安全**：所有 UPSERT 在 heap 表
4. ✅ **灵活**：月度分区可以转 columnar（历史归档高压缩）
5. ✅ **可扩展**：`partition_router.go` 预留，将来需要时启用

---

## 待完成任务

### 短期（本周）
1. ⏳ **每日迁移脚本**
   - 将 `*_default` 中 > 7 天的数据迁移到月度分区
   - cron: `0 2 * * *`（每日凌晨 2:00）
   ```bash
   scripts/migrate-default-to-monthly.sh
   ```

2. ⏳ **查询 VIEW**
   - 封装 UNION 逻辑，简化查询
   ```sql
   CREATE OR REPLACE VIEW request_logs_with_current_month AS
   SELECT * FROM request_logs  -- 自动聚合 ATTACHED 分区（2026_06 + default）
   UNION ALL
   SELECT * FROM request_logs_2026_07;  -- 手动添加 DETACHED 的当月分区
   ```

### 中期（8 月 1 日前）
1. ⏳ **月底转 columnar**
   - 将上月分区（2026_07）转为 columnar
   - ATTACH 到父表（作为只读历史归档）
   ```bash
   scripts/convert-last-month-to-columnar.sh
   ```

### 长期
1. ⏳ **监控告警**
   - `*_default` 表大小 > 10GB → 告警（迁移任务可能失败）
   - 定时任务执行失败 → 告警

2. ⏳ **184 环境同步**
   - 71 稳定运行 1 周后，同步到 184 测试环境

---

## 查询模式

### 查询最近数据（推荐）
```sql
-- 直接查 default（最快）
SELECT * FROM request_logs_default 
WHERE ts > now() - interval '7 days';
```

### 查询当月所有数据
```sql
-- 方式 1：手动 UNION
SELECT * FROM request_logs WHERE ts >= '2026-07-01'  -- 包含 2026_06 + default
UNION ALL
SELECT * FROM request_logs_2026_07 WHERE ts >= '2026-07-01';

-- 方式 2：使用 VIEW（待创建）
SELECT * FROM request_logs_with_current_month WHERE ts >= '2026-07-01';
```

### 查询跨月历史数据
```sql
-- 查 6 月数据（ATTACHED，直接查父表）
SELECT * FROM request_logs WHERE ts >= '2026-06-01' AND ts < '2026-07-01';

-- 查 6-7 月数据（需要 UNION 当月 DETACHED 分区）
SELECT * FROM request_logs WHERE ts >= '2026-06-01'
UNION ALL
SELECT * FROM request_logs_2026_07;
```

---

## 历史补录处理

### 场景：补录 2026-06-25 的数据

#### 方式 1：直接写 default（简单）
```go
// 补录数据会先写入 default
entry := &RequestLogEntry{
    RequestID: "backfill-2026-06-25-001",
    // ... 其他字段
}
client.EmitRequestLogInsert(entry)

// 然后手动迁移到 2026_06 分区
// INSERT INTO request_logs_2026_06 
// SELECT * FROM request_logs_default WHERE ts >= '2026-06-25' AND ts < '2026-06-26';
// DELETE FROM request_logs_default WHERE ts >= '2026-06-25' AND ts < '2026-06-26';
```

#### 方式 2：使用路由器（精确）
```go
// 使用 partition_router.go 判断目标分区
ts := time.Date(2026, 6, 25, 12, 0, 0, 0, time.UTC)
targetTable := defaultRouter.getRequestLogsTable(ts)
// 返回: "request_logs_2026_06"

// 构建动态 SQL
sql := fmt.Sprintf(`INSERT INTO %s (...) VALUES (...)`, targetTable)
```

---

## 经验教训

### 1. PostgreSQL DEFAULT 分区约束是动态的
- DEFAULT 分区会自动排除所有 ATTACHED 分区的范围
- 直接写 `*_default` 会被拒绝（如果数据在其他 ATTACHED 分区范围内）
- **解决**：DETACH 当月及未来月份分区

### 2. 新数据写入模式固定
- INSERT 使用 `ts = now()` → 肯定是热数据
- UPDATE 是流式响应 → 肯定更新热数据
- **结论**：硬编码 `*_default` 已经满足 99.99% 场景

### 3. 过度设计的成本
- 动态路由需要 10+ 小时开发 + 测试
- 但实际只有 < 0.01% 的场景需要它（历史补录）
- **结论**：预留接口（`partition_router.go`），按需启用

---

## 总结

### 当前方案：方案 C 简化版
- ✅ 代码：硬编码 `*_default`
- ✅ 数据库：当月分区 DETACHED
- ✅ 查询：手动 UNION（待优化为 VIEW）
- ✅ 扩展：`partition_router.go` 预留

### 与原始方案 C 的区别
- **原始方案 C**：所有写入都动态路由（复杂）
- **简化版**：新数据硬编码 default，历史补录按需路由（简单）

### 与方案 A 的对比
- **方案 A**：写父表 + 月度分区 ATTACHED（放弃 columnar）
- **方案 C**：写 default + 月度分区 DETACHED（支持 columnar）

---

**修复完成时间**: 2026-07-04 18:55 CST  
**验证状态**: ✅ 生产环境写入正常  
**下次里程碑**: 部署每日迁移脚本
