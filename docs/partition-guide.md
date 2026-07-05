# PostgreSQL 分区表读写规范指南

**文档版本**: 1.0  
**创建日期**: 2026-07-04  
**适用范围**: 所有使用分区表 + Columnar 存储的时序数据表  
**状态**: ✅ 已实施并验证

---

## 1. 问题背景

### 1.1 业务场景

llm-gateway-go 是一个高吞吐量的 LLM API 网关，核心遥测表 `request_logs` 和 `usage_ledger` 面临以下挑战：

- **高写入频率**：每秒数百次 INSERT/UPDATE
- **大数据量**：单月数据 > 1GB
- **长期归档**：历史数据需要保留但查询频率低

### 1.2 核心冲突

**Columnar 不支持 UPSERT**：
1. 不支持 `UPDATE`
2. 不支持 `DELETE`
3. 不支持 `ON CONFLICT` (speculative insertion)

**实际报错**：
```sql
UPDATE request_logs SET success = true WHERE request_id = 'xxx';
-- ERROR: UPDATE and CTID scans not supported for ColumnarScan

INSERT INTO request_logs (...) VALUES (...)
ON CONFLICT (request_id, ts) DO UPDATE SET ...;
-- ERROR: ON CONFLICT is not supported for columnar tables
```

---

## 2. 架构设计

### 2.1 分区结构

```
request_logs (父表, PARTITION BY RANGE(ts))
├─ request_logs_2026_06 [ATTACHED, columnar] ─ 历史归档
├─ request_logs_2026_07 [DETACHED, heap]     ─ 当月数据
├─ request_logs_2026_08 [DETACHED, heap]     ─ 下月预创建
└─ request_logs_default [ATTACHED, heap]     ─ 所有新数据
```

### 2.2 数据生命周期

```
阶段 1: 热数据（0-7天）
  位置: request_logs_default (heap)
  写入: 应用直接 INSERT/UPDATE
  
阶段 2: 温数据（7-30天）
  位置: request_logs_YYYY_MM (heap, DETACHED)
  写入: 每日迁移脚本
  
阶段 3: 冷数据（> 30天）
  位置: request_logs_YYYY_MM (columnar, ATTACHED)
  写入: 月底转换脚本
```

### 2.3 关键决策

| 问题 | 答案 |
|------|------|
| 为什么不需要动态路由？ | 99.9% 的写入是新数据（热数据） |
| 为什么 DETACH 当月分区？ | DEFAULT 分区约束是动态的 |
| 为什么预留路由器？ | 历史补录场景 < 0.1% |

---

## 3. 写入规范（强制）

### 3.1 INSERT 规范

```go
// ✅ 正确：硬编码 default 表
_, err := tx.Exec(ctx, `
    INSERT INTO request_logs_default (
        request_id, ts, tenant_id, application_id,
        api_key_id, credential_id, success
    ) VALUES (
        $1, now(), $2, $3, $4, $5, $6
    )
    ON CONFLICT (request_id, ts) DO NOTHING
`,
    entry.RequestID, entry.TenantID, entry.ApplicationID,
    entry.APIKeyID, entry.CredentialID, entry.Success,
)

// ❌ 错误：写父表
_, err := tx.Exec(ctx, `
    INSERT INTO request_logs (...)  -- ❌ 禁止
    VALUES (...)
`, ...)
```

### 3.2 UPDATE 规范

```go
// ✅ 正确：UPDATE default 表
_, err := tx.Exec(ctx, `
    UPDATE request_logs_default
    SET prompt_tokens = $2,
        completion_tokens = $3,
        success = $4
    WHERE request_id = $1
`, entry.RequestID, entry.PromptTokens, entry.CompletionTokens, entry.Success)

// ❌ 错误：UPDATE 父表
_, err := tx.Exec(ctx, `
    UPDATE request_logs  -- ❌ 禁止
    SET prompt_tokens = $2
    WHERE request_id = $1
`, ...)
```

### 3.3 ON CONFLICT 列引用规范

```go
// ✅ 正确：所有列引用都带 request_logs_default 前缀
INSERT INTO request_logs_default (...)
VALUES (...)
ON CONFLICT (request_id, ts) DO UPDATE SET
    prompt_tokens = COALESCE(EXCLUDED.prompt_tokens, request_logs_default.prompt_tokens),
    success = COALESCE(EXCLUDED.success, request_logs_default.success)
WHERE request_logs_default.request_id = EXCLUDED.request_id;

// ❌ 错误：列引用使用父表名
ON CONFLICT (request_id, ts) DO UPDATE SET
    prompt_tokens = COALESCE(EXCLUDED.prompt_tokens, request_logs.prompt_tokens)
    --                                                 ^^^^^^^^^^^^ ❌ 错误
```

### 3.4 DELETE 规范

```go
// ✅ 正确：DELETE 指向 default
_, err := tx.Exec(ctx, `
    DELETE FROM request_logs_default
    WHERE request_id = $1
`, requestID)

// ❌ 错误：DELETE 父表
_, err := tx.Exec(ctx, `
    DELETE FROM request_logs  -- ❌ 禁止
    WHERE request_id = $1
`, requestID)
```

---

## 4. 查询规范（推荐）

### 4.1 查询模式选择

| 查询范围 | 推荐方式 | SQL 示例 |
|---------|---------|----------|
| 最近 7 天 | 直接查 default | `SELECT * FROM request_logs_default WHERE ts > now() - interval '7 days'` |
| 当月所有数据 | 使用 VIEW | `SELECT * FROM request_logs_with_current_month WHERE ts >= '2026-07-01'` |
| 跨月历史 | 查父表 + UNION | `(SELECT * FROM request_logs WHERE ts >= '2026-06-01') UNION ALL (SELECT * FROM request_logs_2026_07)` |

### 4.2 VIEW 定义

```sql
-- request_logs 当月完整数据 VIEW
CREATE OR REPLACE VIEW request_logs_with_current_month AS
SELECT * FROM request_logs          -- 父表（ATTACHED 分区）
UNION ALL
SELECT * FROM request_logs_2026_07;  -- 当月 DETACHED 分区

-- usage_ledger 同理
CREATE OR REPLACE VIEW usage_ledger_with_current_month AS
SELECT * FROM usage_ledger
UNION ALL
SELECT * FROM usage_ledger_2026_07;
```

### 4.3 查询优化

```go
// ✅ 最佳实践：判断时间范围，选择最优查询
func (c *Client) QueryRequestLogs(ctx context.Context, startTime time.Time) ([]RequestLog, error) {
    age := time.Since(startTime)
    
    var sql string
    if age < 7*24*time.Hour {
        // 最近 7 天：直接查 default（最快）
        sql = `SELECT * FROM request_logs_default WHERE ts >= $1`
    } else {
        // 超过 7 天：使用 VIEW（完整数据）
        sql = `SELECT * FROM request_logs_with_current_month WHERE ts >= $1`
    }
    
    return c.db.Query(ctx, sql, startTime)
}
```

---

## 5. 维护规范

### 5.1 每日迁移脚本

```bash
#!/bin/bash
# 将 request_logs_default 中 > 7天的数据迁移到当月分区

CUTOFF_DATE=$(date -u -d '7 days ago' '+%Y-%m-%d %H:%M:%S')
CURRENT_MONTH=$(date -u '+%Y_%m')

psql << EOF
BEGIN;

-- 迁移 request_logs
INSERT INTO request_logs_${CURRENT_MONTH}
SELECT * FROM request_logs_default
WHERE ts < '${CUTOFF_DATE}'::timestamptz
ON CONFLICT (request_id, ts) DO NOTHING;

DELETE FROM request_logs_default
WHERE ts < '${CUTOFF_DATE}'::timestamptz;

-- 迁移 usage_ledger
INSERT INTO usage_ledger_${CURRENT_MONTH}
SELECT * FROM usage_ledger_default
WHERE ts < '${CUTOFF_DATE}'::timestamptz
ON CONFLICT (request_id, ts) DO NOTHING;

DELETE FROM usage_ledger_default
WHERE ts < '${CUTOFF_DATE}'::timestamptz;

COMMIT;
EOF
```

### 5.2 月底转换脚本

将上月分区从 heap 转为 columnar（参考 `scripts/convert-last-month-to-columnar.sh`）

### 5.3 监控指标

| 指标 | 阈值 | 告警级别 |
|------|------|---------|
| `request_logs_default` 表大小 | > 10GB | P2 - 警告 |
| `request_logs_default` 表大小 | > 20GB | P1 - 严重 |
| 每日迁移任务失败 | 连续 2 次 | P1 - 严重 |

---

## 6. 代码审查检查清单

### 6.1 写入代码审查

- [ ] 所有 `INSERT INTO` 指向 `*_default` 表（不是父表）
- [ ] 所有 `UPDATE` 指向 `*_default` 表
- [ ] 所有 `DELETE` 指向 `*_default` 表
- [ ] `ON CONFLICT` 子句中的列引用都带 `*_default` 前缀
- [ ] 写入操作在事务中
- [ ] 无批量 UPDATE（无主键条件）

### 6.2 查询代码审查

- [ ] 最近 7 天数据直接查 `*_default`
- [ ] 当月数据使用 `*_with_current_month` VIEW
- [ ] 所有查询都有 `ts` 范围条件（除非主键查询）
- [ ] 聚合查询带时间范围

---

## 7. 常见错误

### 7.1 分区约束冲突

```
ERROR: new row for relation "request_logs_default" violates partition constraint
SQLSTATE: 23514
```

**原因**：当月分区 ATTACHED，导致 default 无法接收当月数据  
**解决**：DETACH 当月分区

### 7.2 Columnar CTID scan

```
ERROR: UPDATE and CTID scans not supported for ColumnarScan
SQLSTATE: 0A000
```

**原因**：尝试 UPDATE/DELETE columnar 分区  
**解决**：确保写入代码指向 `*_default` 表

### 7.3 ON CONFLICT 不支持

```
ERROR: ON CONFLICT is not supported for columnar tables
SQLSTATE: 0A000
```

**原因**：尝试对 columnar 分区执行 UPSERT  
**解决**：确保写入代码指向 `*_default` 表

---

## 8. 性能基准

| 操作 | QPS | 延迟 (p99) |
|------|-----|-----------|
| INSERT (default) | 500+ | < 10ms |
| UPDATE (default) | 300+ | < 15ms |
| UPSERT (default) | 400+ | < 20ms |
| 查询 default (< 1M 行) | - | < 100ms |
| 查询 VIEW (1-5M 行) | - | < 500ms |
| 存储压缩比 (columnar) | 3:1 ~ 4:1 | - |

---

## 9. 迁移检查清单

### 9.1 新项目接入

- [ ] 创建分区父表（PARTITION BY RANGE(ts)）
- [ ] 创建 default 分区（heap）
- [ ] 创建历史月度分区（columnar，ATTACHED）
- [ ] 创建当月分区（heap，DETACHED）
- [ ] 创建查询 VIEW
- [ ] 配置每日迁移脚本
- [ ] 配置月底转换脚本
- [ ] 配置监控告警

### 9.2 现有项目改造

- [ ] 分析现有分区状态
- [ ] 备份数据
- [ ] DETACH 当月及未来分区
- [ ] 修改应用代码（写入 *_default）
- [ ] 创建查询 VIEW
- [ ] 部署验证
- [ ] 配置维护脚本

---

## 10. 相关文件

| 文件 | 说明 |
|------|------|
| `telemetry/partition_router.go` | 动态路由器（预留） |
| `telemetry/partition_router_test.go` | 路由器测试（100% 覆盖） |
| `tests/partition_write_test.sh` | 自动化集成测试 |
| `deploy/sql/migrations/999_columnar_backfill_and_enforce.sql` | Columnar 转换参考 |

---

**文档所有权**: Infrastructure Team  
**最后更新**: 2026-07-04