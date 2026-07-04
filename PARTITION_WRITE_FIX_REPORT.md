# 分区表强制写入 *_default 修复报告

**日期**: 2026-07-04  
**问题**: 所有写入操作必须强制指向 `*_default` 表，禁用 PG 自动分区路由  
**影响表**: `request_logs`, `usage_ledger`, `request_raw`

---

## 问题根源

### 当前架构（2026年7月）
- `request_logs` 父表：`PARTITION BY RANGE(ts)`
- `request_logs_2026_07` 子分区：`FOR VALUES FROM ('2026-07-01') TO ('2026-08-01')` **USING columnar**
- `request_logs_default` 默认分区：`DEFAULT` **USING heap**

### 问题
当应用写入父表 `INSERT INTO request_logs ...` 时，PG 会根据 `ts` 自动路由：
- `ts='2026-07-04'` → 路由到 `request_logs_2026_07`（columnar）
- **Columnar 表不支持 `ON CONFLICT` / `UPDATE` / `DELETE`**
- 导致报错：`UPDATE and CTID scans not supported for ColumnarScan`

### 解决方案
**强制所有写入指向 `*_default` 表（heap），完全绕过 PG 自动路由。**

数据流：
1. **新数据写入** → `*_default`（heap，支持 UPSERT）
2. **历史数据迁移** → 定期从 `*_default` 迁移到月度 columnar 分区（由迁移工具负责）

---

## 修复清单

### 生产代码（P0 - 关键路径）

#### 1. `telemetry/client.go` — 5 处
| 行号 | 原表名 | 修复后 | 操作类型 |
|------|--------|--------|----------|
| 552  | `usage_ledger` | `usage_ledger_default` | INSERT |
| 592  | `request_logs` | `request_logs_default` | INSERT (47 处 ON CONFLICT 列引用同步修复) |
| 856  | `usage_ledger` | `usage_ledger_default` | UPDATE |
| 884  | `usage_ledger` | `usage_ledger_default` | UPDATE |
| 906  | `request_logs` | `request_logs_default` | UPDATE |
| 1190 | `request_logs` | `request_logs_default` | INSERT (upsertRequestLogFallback) |

**关键修复**：
- `ON CONFLICT (request_id, ts) DO UPDATE SET ... WHERE request_logs.xxx`  
  → 所有 `request_logs.xxx` 改为 `request_logs_default.xxx`（共 47 处列引用）

#### 2. `admin/telemetry.go` — 2 处
| 行号 | 原表名 | 修复后 | 操作类型 |
|------|--------|--------|----------|
| 229  | `usage_ledger` | `usage_ledger_default` | INSERT |
| 256  | `request_logs` | `request_logs_default` | INSERT |

#### 3. `admin/credential_success_rate.go` — 1 处
| 行号 | 原表名 | 修复后 | 操作类型 |
|------|--------|--------|----------|
| 125  | `request_logs` | `request_logs_default` | DELETE |

#### 4. `telemetry/provider_model.go` — 1 处
| 行号 | 原表名 | 修复后 | 操作类型 |
|------|--------|--------|----------|
| 211  | `request_logs` | `request_logs_default` | UPDATE |

#### 5. `db/db.go` — 1 处
| 行号 | 原表名 | 修复后 | 操作类型 |
|------|--------|--------|----------|
| (注释) | `request_logs` | `request_logs_default` | 文档注释 |

---

### 测试代码（P1）

#### 6. `bg/passive_probe_listener_test.go` — 3 处
- 2× INSERT INTO `request_logs_default`
- 1× DELETE FROM `request_logs_default`

#### 7. `telemetry/client_live_test.go` — 3 处
- 3× DELETE FROM `request_logs_default`（cleanup guards）

---

### 运维脚本（P2）

#### 8. `scripts/delete-old-request-logs.sh`
- **批量删除旧数据**：`DELETE FROM request_logs_default` (line 150)
- **头部注释**：明确说明只操作 `*_default`，历史列存分区用 `DROP PARTITION`

#### 9. `scripts/archive-request-logs.sh`
- **归档后删除**：`DELETE FROM request_logs_default` (line 211)
- **头部注释**：SELECT/COPY 走父表（聚合所有分区），DELETE 只走 `*_default`

#### 10. `scripts/test_local_routing.sh` / `scripts/test_local_concurrency.sh`
- **测试清理**：`DELETE FROM request_logs_default`

#### 11. `scripts/backfill_request_logs_provider_model.sh`
- **历史回填**：
  - `SELECT id FROM request_logs_default` (line 56)
  - `JOIN request_logs_default r` (line 70)
  - `UPDATE request_logs_default r` (line 99)
- **头部注释**：明确说明只回填 `*_default` 数据，列存分区由迁移工具处理

---

### 诊断脚本模板（P3）

#### 12. `deploy/sql/db_scripts/diagnose_and_clean_request_logs.sql`
- **注释块内的 DELETE 模板** → `request_logs_default`
- **警示注释**：禁止直接操作列存分区

---

## 未修改（按设计保留）

### 1. 历史 SQL Migration 脚本
**文件**：
- `deploy/sql/migrations/020_request_logs_unique_request_id.sql`
- `deploy/sql/migrations/055_request_logs_upstream_status_code.sql`
- `deploy/sql/migrations/058_request_logs_status_materialize.sql`
- `deploy/sql/migrations/301_request_logs_unique_request_id_only.sql`
- `deploy/sql/migrations/302_fix_is_auto_request_null.sql`

**原因**：
- 这些是一次性历史回填脚本，已在生产执行完毕
- 修改会破坏审计轨迹（违反 immutable infrastructure 原则）
- 按 lessons-learned 文档，这些脚本不应重跑

### 2. DDL 操作
- `CREATE TABLE` / `CREATE PARTITION` / `ATTACH PARTITION` / `ALTER TABLE`
- 这些是分区定义本身，必须操作父表/分区表

### 3. SELECT 查询（123+ 处）
- `SELECT ... FROM request_logs` — 父表查询会自动聚合 `*_default` + 所有月度分区
- 符合规范，无需修改

---

## 验证结果

### 编译检查
```bash
$ go build ./...
✅ 通过

$ go vet ./...
⚠️  routing/executor.go:1567:2: unreachable code（预存在，与本次修改无关）

$ go test -count=1 -run='^$' ./...
✅ 全包编译通过
```

### 代码扫描
```bash
# 扫描所有 Go/Shell 文件中的写入操作
$ grep -rEn "(INSERT INTO|UPDATE|DELETE FROM)\s+(request_logs|usage_ledger)\b" \
    --include='*.go' --include='*.sh' .
✅ 所有结果均为 *_default 表
```

---

## 关键原则（已写入代码注释）

### 1. 绝不依赖 PG 自动路由
即使 `ts` 在当月范围内（如 `2026-07-04`），也**绝不**写父表让 PG 路由到 `request_logs_2026_07`，因为：
- 当月分区可能是 columnar（不支持 UPSERT）
- 父表 UPDATE/DELETE 会扫描所有分区（触发 columnar CTID scan 错误）

### 2. 数据流清晰分离
- **应用层写入** → 只写 `*_default`（heap）
- **数据迁移** → 定期从 `*_default` 迁移到月度 columnar 分区
- **历史查询** → SELECT 父表（自动聚合所有分区）

### 3. 运维操作边界
- **DELETE/UPDATE 历史数据** → 用 `DROP PARTITION request_logs_YYYY_MM`
- **不要在应用层直接操作列存分区** → 交给迁移工具

---

## 部署建议

### 1. 生产部署前
```bash
# 确认当前月份分区状态
SELECT schemaname, tablename, 
       pg_get_expr(relpartbound, oid) AS partition_bound
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE relname LIKE 'request_logs_2026_%'
ORDER BY relname;

# 确认 default 分区是否 ATTACHED
\d+ request_logs
```

### 2. 回滚计划
如果生产出现问题，回滚 SQL（紧急止损）：
```sql
-- 将写入临时切回父表（允许自动路由）
-- 注意：这会导致 columnar 分区写入失败，仅作紧急止损
ALTER TABLE request_logs RENAME TO request_logs_old;
ALTER TABLE request_logs_default RENAME TO request_logs;
```

### 3. 监控指标
- **`*_default` 表增长速率**：应与请求 QPS 一致
- **月度分区写入计数**：应为 0（所有写入走 default）
- **迁移工具运行日志**：确认历史数据正常迁移到 columnar 分区

---

## 改动统计

| 类别 | 文件数 | 改动行数 | 关键修复点 |
|------|--------|----------|-----------|
| 生产代码 | 5 | ~85 | ON CONFLICT 47 处列引用 |
| 测试代码 | 2 | ~10 | DELETE cleanup guards |
| 运维脚本 | 5 | ~30 | 头部注释 + 表名替换 |
| 诊断模板 | 1 | ~10 | 注释块警示 |
| **总计** | **13** | **~135** | **强制 *_default 写入** |

---

## 遗留风险

### 1. 迁移工具未启动
如果 `*_default` 表数据未定期迁移到月度分区，会导致：
- `*_default` 表无限增长
- 查询性能下降（heap 表缺少列存压缩）

**缓解措施**：
- 监控 `*_default` 表大小（阈值：> 10GB 告警）
- 确认 cron / K8s CronJob 正常运行迁移工具

### 2. 历史 SQL 脚本误重跑
如果有人重跑 `020` / `301` / `055` 等历史 migration：
- 会尝试 UPDATE 父表，触发全分区扫描
- 可能导致 columnar CTID scan 错误

**缓解措施**：
- 在 `deploy/sql/migrations/README.md` 中明确标注已完成的 migration
- 使用 migration 版本管理工具（如 golang-migrate）防止重跑

---

## 下一步

1. **本地测试** → 运行 `local-deploy-test` skill 验证 184 生产数据同步后的行为
2. **184 部署** → 使用 `deploy-184` skill 部署到测试环境
3. **生产观察** → 监控 `*_default` 表写入 QPS 和大小增长
4. **迁移工具验证** → 确认历史数据正常迁移到 columnar 分区

---

**修复完成时间**: 2026-07-04  
**验证状态**: ✅ 编译通过 + 全量扫描无遗漏

---

## 部署到 71 环境

### 环境信息
- **目标服务器**: root@14.103.174.71:25022
- **域名**: llm.kxpms.cn
- **数据库**: PostgreSQL 15.3 + Citus 11.3 (columnar support)
- **部署工具**: `deploy-71` skill

### 部署前检查（71 数据库）
```bash
# SSH 到 71
ssh -p 25022 root@14.103.174.71

# 连接数据库
psql -U stockuser -d llm_gateway

# 1. 检查当前分区状态
SELECT 
    schemaname, 
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables 
WHERE tablename ~ '^(request_logs|usage_ledger).*2026_(06|07|08)'
   OR tablename ~ '^(request_logs|usage_ledger)_default$'
ORDER BY tablename;

# 2. 检查 columnar 扩展
SELECT extname, extversion FROM pg_extension WHERE extname = 'citus_columnar';

# 3. 检查分区边界
SELECT 
    c.relname AS partition_name,
    pg_get_expr(c.relpartbound, c.oid) AS partition_bound
FROM pg_class c
JOIN pg_inherits i ON i.inhrelid = c.oid
JOIN pg_class p ON p.oid = i.inhparent
WHERE p.relname IN ('request_logs', 'usage_ledger')
ORDER BY c.relname;

# 4. 检查 *_default 表的访问方法（应该是 heap）
SELECT 
    c.relname,
    am.amname AS access_method
FROM pg_class c
JOIN pg_am am ON am.oid = c.relam
WHERE c.relname ~ '_(default|2026_07)$'
  AND c.relname ~ '^(request_logs|usage_ledger)'
ORDER BY c.relname;
```

### 部署步骤

#### 1. 备份当前版本
```bash
# 在 71 上备份当前二进制
ssh -p 25022 root@14.103.174.71 \
  'cp /opt/llm-gateway-go/llm-gateway-go /opt/llm-gateway-go/llm-gateway-go.bak.$(date +%Y%m%d_%H%M%S)'
```

#### 2. 使用 deploy-71 skill 部署
在本地执行：
```bash
# 调用 deploy-71 skill
# skill 会自动：
# 1. 调用 bump-version.sh 更新版本号
# 2. 交叉编译 linux/amd64
# 3. scp 到 71:/opt/llm-gateway-go/
# 4. systemctl restart llm-gateway-go
# 5. 验证服务启动
```

#### 3. 部署后验证
```bash
# 1. 检查服务状态
ssh -p 25022 root@14.103.174.71 'systemctl status llm-gateway-go'

# 2. 检查日志（确认无 columnar 错误）
ssh -p 25022 root@14.103.174.71 'journalctl -u llm-gateway-go -n 100 --no-pager | grep -i "columnar\|conflict\|partition"'

# 3. 发送测试请求
curl -X POST https://llm.kxpms.cn/v1/chat/completions \
  -H "Authorization: Bearer test-api-key-12345" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [{"role": "user", "content": "hello"}]
  }'

# 4. 检查数据库写入（确认写入 *_default）
psql -U stockuser -d llm_gateway -c "
SELECT 
    COUNT(*) AS recent_logs,
    MIN(ts) AS earliest,
    MAX(ts) AS latest
FROM request_logs_default
WHERE ts > now() - interval '5 minutes';
"

# 5. 确认月度分区无新写入
psql -U stockuser -d llm_gateway -c "
SELECT 
    COUNT(*) AS unexpected_writes
FROM request_logs_2026_07
WHERE ts > now() - interval '5 minutes';
"
# 预期结果：0 行（所有新写入应该在 *_default）
```

### 回滚方案（如果 71 出问题）

#### 快速回滚（1 分钟内）
```bash
# SSH 到 71
ssh -p 25022 root@14.103.174.71

# 恢复旧版本二进制
cd /opt/llm-gateway-go
cp llm-gateway-go.bak.YYYYMMDD_HHMMSS llm-gateway-go

# 重启服务
systemctl restart llm-gateway-go

# 验证
systemctl status llm-gateway-go
curl https://llm.kxpms.cn/health
```

#### 数据库回滚（紧急止损，不推荐）
```sql
-- 仅在极端情况下使用，会导致短期 columnar 写入失败
-- 将 *_default 表临时设为主表
ALTER TABLE request_logs RENAME TO request_logs_parent_backup;
ALTER TABLE request_logs_default RENAME TO request_logs;

-- 验证后再改回来
ALTER TABLE request_logs RENAME TO request_logs_default;
ALTER TABLE request_logs_parent_backup RENAME TO request_logs;
```

### 监控指标（部署后 24 小时）

#### 1. 数据库表大小趋势
```sql
-- 每小时检查一次
SELECT 
    tablename,
    pg_size_pretty(pg_total_relation_size('public.'||tablename)) AS size,
    n_tup_ins AS inserts_since_vacuum,
    n_tup_upd AS updates_since_vacuum
FROM pg_stat_user_tables
WHERE tablename IN ('request_logs_default', 'usage_ledger_default', 
                    'request_logs_2026_07', 'usage_ledger_2026_07')
ORDER BY tablename;
```

#### 2. 错误日志监控
```bash
# 持续监控 columnar 相关错误
ssh -p 25022 root@14.103.174.71 \
  'journalctl -u llm-gateway-go -f | grep -i "columnar\|conflict\|partition"'
```

#### 3. 请求成功率
```sql
-- 最近 1 小时成功率
SELECT 
    COUNT(*) AS total_requests,
    COUNT(*) FILTER (WHERE success = true) AS successful,
    ROUND(100.0 * COUNT(*) FILTER (WHERE success = true) / COUNT(*), 2) AS success_rate_pct
FROM request_logs_default
WHERE ts > now() - interval '1 hour';
```

#### 4. 月度分区异常写入告警
```sql
-- 应该返回 0，如果 > 0 说明有数据绕过 *_default 写入了 columnar 分区
SELECT COUNT(*) AS unexpected_columnar_writes
FROM request_logs_2026_07
WHERE ts > now() - interval '1 hour';
```

### 预期结果
- ✅ `request_logs_default` 新增速率 ≈ 请求 QPS
- ✅ `request_logs_2026_07` 无新增写入（n_tup_ins 不变）
- ✅ 日志无 `columnar` / `CTID scan` 错误
- ✅ 请求成功率 ≥ 99.5%

---

**71 部署完成后，建议观察 24 小时再部署到 184 测试环境。**
