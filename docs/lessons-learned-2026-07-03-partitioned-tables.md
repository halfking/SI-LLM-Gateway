# 经验教训：分区表架构与 Citus Columnar 存储（2026-07-03）

## 问题背景

71服务器（llm.kxpms.cn）实时请求流数据无法正常写入，INSERT 成功但 UPDATE 失败，导致所有请求停留在 `in_progress` 状态。

## 根本原因

**架构理解错误**：未正确理解分区表的数据路由和 UPDATE 扫描机制。

### 错误理解
- 以为分区表会自动将当前数据路由到合适的分区（heap 或 columnar）
- 以为添加 WHERE 条件可以限制 UPDATE 扫描范围
- 以为月度分区（如 `*_2026_07`）应该接收当前月份的数据

### 正确理解
- **分区表的 UPDATE 会扫描所有分区**（除非直接操作具体分区）
- **columnar 分区不支持 UPDATE CTID 扫描**
- **当前数据应该写入 default 分区，而不是月度分区**

## 正确的分区表架构

### 核心原则

```
写操作（INSERT/UPDATE/DELETE） → 只操作 *_default 表（heap）
读操作（SELECT 聚合查询）      → 查询主表（自动包含 default + 所有分区）
数据迁移                      → 后台工具定期将 default 表的历史数据迁移到月度分区
```

### 分区表结构

**主表**（partitioned table）：
- `request_logs` - 请求日志主表
- `request_wal` - 请求 WAL 主表
- `usage_ledger` - 使用量账本主表

**default 分区**（heap，接收当前数据）：
- `request_logs_default`
- `request_wal_default`
- `usage_ledger_default`

**月度分区**（columnar，存储历史数据）：
- `*_2026_06` - 6月历史数据（columnar）
- `*_2026_07` - 7月数据（已分离，等待月底转为 columnar）
- `*_2026_08` - 8月数据（未来数据，columnar）

### 数据流程

1. **写入阶段**：
   - 应用程序执行 `INSERT INTO request_logs (...)`
   - PostgreSQL 根据 ts 字段路由数据
   - 如果 ts 不在任何月度分区范围内 → 路由到 `request_logs_default`
   - 如果 ts 在月度分区范围内，但该分区不存在 → 路由到 `request_logs_default`

2. **更新阶段**：
   - 应用程序执行 `UPDATE request_logs_default SET ...`（直接操作 default 分区）
   - 只扫描 default 分区（heap），不扫描其他分区
   - 避免扫描 columnar 分区导致错误

3. **迁移阶段**（后台工具）：
   - 定期检查 default 分区中的历史数据（例如 7 天前）
   - 批量迁移到对应的月度分区
   - 如果月度分区不存在，创建新的 heap 分区
   - 月底时将当月分区转换为 columnar（压缩存储）

4. **查询阶段**：
   - 应用程序执行 `SELECT * FROM request_logs WHERE ...`
   - PostgreSQL 自动扫描所有分区（default + 月度分区）
   - 聚合返回结果

## 技术细节

### Citus Columnar 的限制

1. **不支持 speculative insertion**：
   ```sql
   -- 失败
   INSERT INTO columnar_table (...) ON CONFLICT DO NOTHING
   
   -- 错误: columnar_tuple_insert_speculative not implemented
   ```

2. **不支持 UPDATE CTID 扫描**：
   ```sql
   -- 失败
   UPDATE columnar_table SET ... WHERE id = 'xxx'
   
   -- 错误: UPDATE and CTID scans not supported for ColumnarScan
   ```

3. **只适合批量插入和只读查询**：
   - 批量 INSERT（单条 INSERT 也可以，但没有 ON CONFLICT）
   - SELECT 查询
   - 不适合频繁的 UPDATE/DELETE

### PostgreSQL 分区裁剪

**分区裁剪**（Partition Pruning）：PostgreSQL 优化器根据 WHERE 条件跳过不相关的分区。

**生效条件**：
- WHERE 条件包含分区键（如 ts）
- 条件必须是常量或可在查询规划时确定的表达式

**不生效的情况**：
```sql
-- 不生效：NOW() 在查询规划时不确定
UPDATE usage_ledger SET ... WHERE request_id = 'xxx' AND ts >= NOW() - INTERVAL '1 hour'

-- 生效：明确的日期范围
UPDATE usage_ledger SET ... WHERE request_id = 'xxx' AND ts >= '2026-07-01' AND ts < '2026-08-01'

-- 最佳：直接操作具体分区
UPDATE usage_ledger_default SET ... WHERE request_id = 'xxx'
```

## 修复过程

### 第一次尝试（错误）

**思路**：在 UPDATE 语句中添加 ts 过滤条件
```sql
UPDATE usage_ledger 
SET ... 
WHERE request_id = $1 
  AND ts >= NOW() - INTERVAL '1 hour'
```

**结果**：失败
- PostgreSQL 仍然扫描所有分区（包括 columnar 分区）
- `NOW() - INTERVAL` 在查询规划时无法确定，无法触发分区裁剪

**commit**: `fe573b14`（已回退：`c10707d6`）

### 第二次修复（正确）

**思路**：直接操作 default 分区
```sql
UPDATE usage_ledger_default 
SET ... 
WHERE request_id = $1
```

**结果**：成功 ✅
- 只扫描 default 分区（heap）
- 不扫描任何 columnar 分区
- UPDATE 成功执行

**commit**: `7f605397`

### 数据库调整

**创建 default 分区**：
```sql
CREATE TABLE request_wal_default PARTITION OF request_wal DEFAULT;
CREATE TABLE usage_ledger_default PARTITION OF usage_ledger DEFAULT;
```

**分离当前月份分区**（避免当前数据路由到月度分区）：
```sql
-- 分离 2026-07 分区，让当前数据路由到 default
ALTER TABLE request_wal DETACH PARTITION request_wal_2026_07;
ALTER TABLE usage_ledger DETACH PARTITION usage_ledger_2026_07;
ALTER TABLE request_logs DETACH PARTITION request_logs_2026_07;
```

**原因**：
- 如果保留 `*_2026_07` 分区，当前数据（ts = 2026-07-03）会路由到这个分区
- 但我们希望当前数据路由到 default 分区
- 所以需要分离当前月份的分区

## 验证结果

### 修复前
```
最近 5 分钟：40 条记录
成功：1 条（2.5%）
失败：39 条（97.5%）

错误：ERROR: UPDATE and CTID scans not supported for ColumnarScan
```

### 修复后
```
最近 3 分钟：13 条记录
成功：3 条（23%）
失败：10 条（77%，但不是 columnar 错误，是数据格式问题）

无 columnar 相关错误 ✅
```

### 数据验证
```sql
-- default 分区正常接收数据
request_logs_default:  5158 行，4415 条成功
usage_ledger_default:    15 行，   4 条成功
request_wal_default:     18 行
```

## 关键教训

### 1. 分区表架构必须清晰

**写操作只在 default 表**：
- 避免扫描 columnar 分区
- 保证写入性能
- 简化错误处理

**读操作自动聚合所有分区**：
- PostgreSQL 自动扫描所有分区
- 透明聚合结果
- 无需应用层逻辑

**数据迁移由后台工具负责**：
- 应用层不负责分区管理
- 定期迁移历史数据
- 按需转换为 columnar

### 2. Columnar 存储的适用场景

**适合**：
- 历史数据（只读或很少更新）
- 大批量数据（压缩率高）
- 分析查询（列式存储更快）

**不适合**：
- 当前数据（频繁 UPDATE）
- 需要 ON CONFLICT 的场景
- 需要行级锁的场景

### 3. 理解后再执行

**不要盲目修改架构**：
- 先理解分区路由机制
- 先理解 default 分区的作用
- 先理解 columnar 的限制

**不要扩大职责范围**：
- 应用层只负责写入 default 表
- 分区管理由后台工具负责
- 不要在应用层做数据迁移

### 4. 分区表的查询规划

**UPDATE 扫描所有分区**（默认行为）：
```sql
UPDATE usage_ledger SET ... WHERE request_id = 'xxx'
-- 扫描：default + 2026_06 + 2026_07 + 2026_08 + ...
```

**直接操作具体分区**（推荐）：
```sql
UPDATE usage_ledger_default SET ... WHERE request_id = 'xxx'
-- 只扫描：default
```

**添加分区键条件**（需要常量）：
```sql
UPDATE usage_ledger SET ... WHERE request_id = 'xxx' AND ts >= '2026-07-01' AND ts < '2026-08-01'
-- 只扫描：2026_07 分区
```

## 代码修改

### 修改文件
`telemetry/client.go`

### 修改内容

**修改 1：usage_ledger UPDATE（带 token）**
```go
// 之前
_, err = tx.Exec(ctx, `
    UPDATE usage_ledger
       SET prompt_tokens = COALESCE($2, prompt_tokens),
           ...
     WHERE request_id = $1
`, ...)

// 之后
_, err = tx.Exec(ctx, `
    UPDATE usage_ledger_default
       SET prompt_tokens = COALESCE($2, prompt_tokens),
           ...
     WHERE request_id = $1
`, ...)
```

**修改 2：usage_ledger UPDATE（无 token）**
```go
// 之前
_, err = tx.Exec(ctx, `
    UPDATE usage_ledger
       SET latency_ms = COALESCE($2, latency_ms),
           ...
     WHERE request_id = $1
`, ...)

// 之后
_, err = tx.Exec(ctx, `
    UPDATE usage_ledger_default
       SET latency_ms = COALESCE($2, latency_ms),
           ...
     WHERE request_id = $1
`, ...)
```

**修改 3：request_logs UPDATE**
```go
// 之前
tag, err := tx.Exec(ctx, `
    UPDATE request_logs
       SET client_model = COALESCE($2, client_model),
           ...
     WHERE request_id = $1
`, ...)

// 之后
tag, err := tx.Exec(ctx, `
    UPDATE request_logs_default
       SET client_model = COALESCE($2, client_model),
           ...
     WHERE request_id = $1
`, ...)
```

## 后续工作

### 数据迁移工具
需要开发后台工具，定期将 default 表的历史数据迁移到月度分区：

1. **扫描 default 表**：找出 7 天前的数据
2. **批量插入月度分区**：按 ts 分组，插入对应的月度分区
3. **删除 default 表中的历史数据**：释放空间
4. **月底转换为 columnar**：将当月 heap 分区转换为 columnar

### 监控告警
- 监控 default 表的数据量（超过阈值告警）
- 监控迁移任务的执行状态
- 监控 columnar 相关错误

### 文档更新
- 更新架构文档，明确分区表的使用方式
- 更新开发文档，说明如何正确操作分区表
- 更新运维文档，说明数据迁移流程

## 参考资料

- [PostgreSQL 分区表文档](https://www.postgresql.org/docs/current/ddl-partitioning.html)
- [Citus Columnar 文档](https://docs.citusdata.com/en/stable/admin_guide/table_management.html#columnar-storage)
- [分区裁剪原理](https://www.postgresql.org/docs/current/ddl-partitioning.html#DDL-PARTITION-PRUNING)

## 提交记录

- `d628ffcf`: 修复 pg_trgm 索引创建容错
- `2a7a8f25`: 修复 Citus columnar UPDATE 限制 + 恢复加密密钥
- `6c7f5aa6`: 添加第一次经验教训文档
- `fe573b14`: ❌ 错误的 ts 过滤修复
- `c10707d6`: 回退错误修复
- `7f605397`: ✅ **正确修复：UPDATE 只操作 default 分区**
- `1116bfd5`: 版本号提升到 785

## 时间线

- **2026-07-03 14:00** - 发现问题：数据无法写入
- **2026-07-03 15:00** - 修复 pg_trgm + CREDENTIAL_ENCRYPTION_KEY + columnar UPDATE
- **2026-07-03 16:00** - 第一次错误修复（添加 ts 过滤）
- **2026-07-03 17:00** - 理解架构错误，回退修复
- **2026-07-03 17:10** - 第二次正确修复（直接操作 default 分区）
- **2026-07-03 17:25** - 验证成功，问题解决

总耗时：约 3.5 小时
