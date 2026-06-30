# 🚀 部署指南 — request_logs.provider_model 物化 (2026-06-30)

**目标**：把 `/api/logs` 的 24h 默认查询从"几秒"压到"<100ms"，方法是把 `provider_model` 物化到 `request_logs` 表，并彻底删掉读路径的 `LEFT JOIN LATERAL` on `model_offers`。

**Git 引用**：
- SQL 迁移：`25437b9b feat(sql,db): migration 057 — denormalize provider_model onto request_logs`
- Go helper：`ca0e53ae feat(telemetry): resolve + persist provider_model at insert time`
- 读路径 LATERAL 移除：`9a20359b refactor(admin): drop LATERAL on model_offers in requestLogsJoins`

**生产环境**：`r112_postgres` (PostgreSQL 15.x) 容器。

---

## ⚠️ 关键约束：严格分四阶段部署

每个阶段都需要独立的验证步骤。**绝对不要跳过中间的 backfill 阶段直接合 LATERAL 移除 commit**，否则会出现 `provider_model IS NULL` 的窗口期，列表页对应字段在前端会显示空。

| 阶段 | 内容 | 风险 | 回滚成本 |
|---|---|---|---|
| 1 | 应用 057 SQL 迁移 | 极低（ADD COLUMN + 索引，全部 idempotent） | 单 SQL |
| 2 | 上线 helper（写入路径） | 极低（helper 失败时仅写 WARN 日志，不影响 INSERT） | git revert |
| 3 | backfill 旧行 | 中（脚本自动限速 100ms/batch，可中断） | 脚本可重新跑 |
| 4 | 移除 LATERAL | 低（前提：阶段 3 完成 ≥ 99.9%） | git revert |

---

## 📋 部署前 Pre-flight

```bash
# 在生产容器内验证当前 schema 状态
ssh prod-app "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = '\''request_logs'\'' 
  AND column_name = '\''provider_model'\'';
'"

# 期望输出：0 rows (迁移未跑)
# 若已有 1 row，则说明 057 已经在生产应用过，跳到阶段 2。
```

---

## 🚦 阶段 1 — 应用 057 SQL 迁移

### 1.1 应用迁移

```bash
ssh prod-app "docker exec -i r112_postgres psql -U <DB_USER> -d llm_gateway" \
  < deploy/sql/migrations/057_request_logs_provider_model_column.sql
```

**幂等保证**：使用 `ADD COLUMN IF NOT EXISTS` 与 `CREATE INDEX IF NOT EXISTS`，重复执行不会报错。

### 1.2 镜像校验（服务重启时 `EnsureRequestLogSchema` 会自动跑）

```bash
ssh prod-app "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
SELECT indexname FROM pg_indexes 
WHERE schemaname = '\''public'\'' 
  AND tablename = '\''request_logs'\'' 
  AND indexname LIKE '\''%provider_model%'\'';
'"

# 期望输出：
#   idx_request_logs_provider_model
```

### 1.3 阶段 1 验证

```bash
# 验证列已加
docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c "
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'request_logs' AND column_name = 'provider_model';
"
# 期望：provider_model | text | YES

# 验证 partial index 已建
docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c "
SELECT indexdef FROM pg_indexes 
WHERE indexname = 'idx_request_logs_provider_model';
"
# 期望：包含 "WHERE provider_model IS NOT NULL"
```

### 1.4 阶段 1 回滚

```bash
ssh prod-app "docker exec -i r112_postgres psql -U <DB_USER> -d llm_gateway" \
  < deploy/sql/migrations/057_request_logs_provider_model_column.down.sql
```

回滚立即生效。ADD COLUMN 的代价是更新 catalog（无表重写），drop 也是元数据级。

---

## 🚦 阶段 2 — 上线 Go helper（commit ca0e53ae）

### 2.1 部署

```bash
# 标准发布流程：在生产节点拉取 ca0e53ae 之后的镜像，重启 systemd unit
ssh prod-app "cd /opt/llm-gateway-go && git pull && systemctl restart llm-gateway"
# （或按当前部署脚本的标准流程）
```

`EnsureRequestLogSchema` 启动时自动确认列和索引存在（即使阶段 1 已跑过，这里幂等）。

### 2.2 阶段 2 验证

**实时观察新行写入**：
```bash
ssh prod-app "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
SELECT 
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE provider_model IS NOT NULL) AS with_provider_model,
  COUNT(*) FILTER (WHERE provider_model IS NULL) AS without_provider_model
FROM request_logs
WHERE ts > now() - interval '\''5 minutes'\'';
'"

# 期望：with_provider_model ≈ total
# 若 without_provider_model 持续 > 10%，查 helper 日志
```

**查 helper 日志**：
```bash
ssh prod-app "journalctl -u llm-gateway --since '5 minutes ago' | grep -iE 'provider_model|ResolveProviderModel|PersistProviderModel' | tail -20"
# 期望：无 ERROR / 仅在 SQLSTATE 42P01 (model_offers 缺失) 或 42703 (列未迁移) 时出现 WARN
# 注意：阶段 1 已跑过 → 应该是 0 WARN
```

**前端 smoke**：
- 打开 https://llm.kxpms.cn/request-logs
- 找一个 1-2 分钟内的新行（顶部）
- 点开详情面板，"Provider Model" 字段应该已填值

### 2.3 阶段 2 回滚

```bash
# helper 失败不会让 INSERT 失败（fire-and-forget 设计），最坏情况是回滚到上一 commit
ssh prod-app "cd /opt/llm-gateway-go && git revert ca0e53ae && systemctl restart llm-gateway"
```

helper 是纯加法，revert 是纯减法，对生产无残留影响。

---

## 🚦 阶段 3 — Backfill 旧行

### 3.1 前置检查

```bash
# 估算待回填行数（决定 backfill 运行时长）
ssh prod-app "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
SELECT COUNT(*) FILTER (WHERE provider_model IS NULL) AS to_backfill,
       COUNT(*) AS total,
       pg_size_pretty(pg_total_relation_size('\''request_logs'\'')) AS table_size
FROM request_logs;
'"

# 100M+ 行 → 10k/batch × 100ms sleep ≈ 17 分钟
# 加上每个 LATERAL 计算耗时，实际可能 30-60 分钟
```

### 3.2 启动 backfill（后台运行）

```bash
# 推荐：screen/tmux 后台，避免 SSH 断连导致中断
ssh prod-app

# 在 prod-app 上：
cd /opt/llm-gateway-go

# 后台启动 backfill，输出到日志
nohup docker exec -i r112_postgres psql -U <DB_USER> -d llm_gateway \
  < scripts/backfill_request_logs_provider_model.sh \
  > /var/log/llm-gateway-backfill-057.log 2>&1 &

echo "Backfill PID: $!"
```

### 3.3 监控进度

```bash
# 实时进度（每 50 批次打印一次）
ssh prod-app "tail -f /var/log/llm-gateway-backfill-057.log"

# 剩余 NULL 行数（粗略进度）
ssh prod-app "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
SELECT 
  COUNT(*) FILTER (WHERE provider_model IS NULL) AS remaining,
  COUNT(*) AS total,
  ROUND(100.0 * COUNT(*) FILTER (WHERE provider_model IS NULL) / COUNT(*), 2) AS pct_remaining
FROM request_logs;
'"
```

### 3.4 验证完成

```bash
# 当 remaining = 0 时，阶段 3 完成
# 允许 < 100 行残留（这些是 backfill 启动后新增的行，由阶段 2 的 helper 自动填充）
ssh prod-app "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
SELECT COUNT(*) AS remaining_null 
FROM request_logs 
WHERE provider_model IS NULL;
'"

# 期望：remaining_null <= (1 分钟内的新增行数)
```

### 3.5 阶段 3 回滚

backfill 是 `UPDATE`，把 NULL 改成计算后的值。**无法"撤销"**——但它的语义与读路径旧 LATERAL 完全一致（脚本里复刻了 LATERAL 的 ORDER BY），所以即使回滚也没有数据不一致。

若 backfill 卡住（OOM / 锁等待）：

```bash
# 找 PID
ssh prod-app "ps aux | grep 'backfill_request_logs' | grep -v grep"

# 安全停止 — 脚本使用 SKIP LOCKED，已完成的批次已 commit
ssh prod-app "kill <PID>"
# 中断后可重启从上次 cursor 继续（脚本用 id > last_id 游标）
```

---

## 🚦 阶段 4 — 部署 LATERAL 移除（commit 9a20359b）

### 4.1 前置检查（严格）

```bash
# 再次确认 backfill 完成度
ssh prod-app "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
SELECT 
  COUNT(*) FILTER (WHERE provider_model IS NULL) AS remaining_null,
  COUNT(*) AS total
FROM request_logs 
WHERE ts < now() - interval '\''10 minutes'\'';  -- 排除 helper 写入的新行
'"

# 期望：remaining_null < 100
# 若 > 10000，**不要部署阶段 4**，等 backfill 跑完
```

### 4.2 部署

```bash
ssh prod-app "cd /opt/llm-gateway-go && git pull && systemctl restart llm-gateway"
# 等同于应用 commit 9a20359b
```

### 4.3 阶段 4 验证

**接口 smoke（最关键）**：
```bash
# 默认 24h 列表
time curl -s -H "Cookie: <admin session>" \
  'https://llm.kxpms.cn/api/logs?page=1&page_size=50'

# 期望：< 200ms（之前是 3-5s）
```

**EXPLAIN 验证（LATERAL 消失）**：
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT rl.ts, rl.request_id, rl.provider_model, p.display_name, c.label,
       mc.canonical_name, ak.key_prefix, app.code
FROM request_logs rl
LEFT JOIN providers p ON p.id = rl.provider_id
LEFT JOIN credentials c ON c.id = rl.credential_id
LEFT JOIN api_keys ak ON ak.id = rl.api_key_id
LEFT JOIN applications app ON app.id = ak.application_id
LEFT JOIN models_canonical mc ON mc.id = rl.canonical_id
WHERE rl.ts BETWEEN now() - interval '24 hours' AND now()
ORDER BY rl.ts DESC
LIMIT 100;
```

**期望 plan**：
- ✅ 不再出现 `Subquery Scan on mo_pick` 节点
- ✅ 主查询走 `Index Scan Backward using idx_request_logs_ts_desc` 或分区索引
- ✅ 总耗时 < 100ms

**provider_model 不为 NULL**：
```bash
ssh prod-app "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
SELECT 
  COUNT(*) FILTER (WHERE provider_model IS NULL) AS null_count,
  COUNT(*) FILTER (WHERE provider_model IS NOT NULL) AS populated_count
FROM request_logs
WHERE ts > now() - interval '\''24 hours'\'';
'"

# 期望：null_count < 1000（极少数边界情况：credential 不在 model_offers 中）
```

### 4.4 阶段 4 回滚

```bash
# LATERAL 移除是纯减法
ssh prod-app "cd /opt/llm-gateway-go && git revert 9a20359b && systemctl restart llm-gateway"
```

回滚后旧 LATERAL 重新启用，会再次慢。但 schema 不动、列还在 → 数据完全兼容。

---

## 🆘 应急预案

### 场景 A：helper 把新行 provider_model 写成 NULL（bug）

```bash
# 1. 立即查 helper 日志
ssh prod-app "journalctl -u llm-gateway --since '10 minutes ago' \
  | grep -iE 'ResolveProviderModel|PersistProviderModel'"

# 2. 若大量 WARN，回滚到上一 commit（阶段 2 的 revert）
ssh prod-app "cd /opt/llm-gateway-go && git revert ca0e53ae && systemctl restart llm-gateway"

# 3. 旧 LATERAL 自动恢复（因为阶段 4 还未部署），UI 正常显示
```

### 场景 B：backfill 把生产 IO 打满

```sql
-- 在 psql 中紧急停止 backfill
SELECT pg_cancel_backend(pid) 
FROM pg_stat_activity 
WHERE query LIKE '%backfill_request_logs%' 
  AND state = 'active';
```

回滚详见 3.5 节。

### 场景 C：阶段 4 部署后，前端显示 provider_model 全是 NULL

```bash
# 检查 helper 是否在跑（telemetry 日志）
ssh prod-app "journalctl -u llm-gateway --since '1 minute ago' | grep -E 'helper|provider_model' | tail -5"

# 若 helper 未运行：先重启服务（阶段 2 的 binary 应该已经在跑）
# 若 helper 在跑但 provider_model 仍 NULL：查 LATERAL subquery 语义是否变了（commit diff 验证）

# 紧急回滚到阶段 3 状态：
ssh prod-app "cd /opt/llm-gateway-go && git revert 9a20359b && systemctl restart llm-gateway"
```

---

## 📊 性能对比（部署前后）

| 指标 | 部署前 | 部署后（阶段 4） |
|---|---|---|
| `/api/logs?page=1&page_size=50` 端到端 | 3-5s | < 200ms |
| 主查询耗时 | ~3s | < 50ms |
| LATERAL 子查询次数/页 | 100 | 0 |
| `model_offers` 表读放大 | 每页 100× | 0 |
| `request_logs` 体积影响 | 0 | +1 text 列（典型 < 64 bytes/行） |

---

## 📝 验证清单（部署后填）

- [ ] 阶段 1 — `provider_model` 列存在，`idx_request_logs_provider_model` 索引存在
- [ ] 阶段 1 — `request_logs_archive` 也加了列（archive 数据迁移不丢列）
- [ ] 阶段 2 — 服务启动后新 5 分钟的行 `provider_model` 全部填值（除 credential 不在 model_offers 的边缘情况）
- [ ] 阶段 2 — 前端详情面板显示 `provider_model`
- [ ] 阶段 3 — backfill 跑完后剩余 NULL 行数 < 100
- [ ] 阶段 4 — EXPLAIN 不再包含 `mo_pick` 子查询
- [ ] 阶段 4 — `/api/logs` 接口响应时间 < 200ms
- [ ] 阶段 4 — 前端列表页 24h 默认查询体感 < 1s

---

## 🧹 部署后清理（可选，1 周后）

阶段 4 部署稳定运行 1 周后：

1. 删除 `requestLogsJoins` 注释里的"previously had LATERAL"那段历史注释
2. 把 `db/request_logs_archive_schema.go` 里 `provider_model` 那行的 `-- 2026-06-30: per 057_*.sql` 注释里的日期更新（让 git blame 显示迁移来源）
3. 不需要删列（product 已经读它）
4. 把 `scripts/backfill_request_logs_provider_model.sh` 加到 archive（不要删，万一未来有手动 backfill 需求）
5. 通知 ops：未来 `model_offers` 视图的 schema 变更不再需要协调 `request_logs` 读路径

---

## 🔗 相关文档

- `docs/2026-06-30-routing-error-transparency.md` — 整体 fix 背景
- `docs/FINAL_SOLUTION_REPORT_minimax_20260630.md` — MiniMax-M3 incident 总结（provider_model 在该报告内被提及为加速 request_logs 的关键）
- `deploy/sql/migrations/057_request_logs_provider_model_column.sql` — 迁移 DDL
- `scripts/backfill_request_logs_provider_model.sh` — backfill 脚本（含注释）

---

## 📞 紧急联系

若阶段 4 部署后任何指标下降 > 20%，立即：

```bash
ssh prod-app "cd /opt/llm-gateway-go && git revert 9a20359b && systemctl restart llm-gateway"
```

LATERAL 移除是**纯减法**，revert 不会影响 schema/列/数据，最多回到阶段 3 的慢路径，UI 仍可用。