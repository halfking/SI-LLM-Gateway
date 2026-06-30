# 🚀 部署指南 — /request-logs 性能优化 (2026-06-30 → 2026-07-01)

**目标**：把 `/api/logs` 的 24h 默认查询从"几秒"压到"<200ms"，并让 `?request_status=` / `?success=` 过滤场景从 COALESCE 表达式过滤改为走 partial index。

**目标服务器**：[SERVER] 71（生产 gateway 与数据库同主机）。

**目标数据库**：Docker 容器 `r112_postgres`（PostgreSQL 15.x）— 也在 71 上，gateway 通过本地 docker exec 进入。

**Git 引用（按部署顺序）**：

| Commit | 阶段 | 说明 |
|---|---|---|
| `eb1c4156` + `4da0df16` + `4addb49c` | P0 | 056 索引 + list/detail 投影拆分 + COUNT 合并（已在生产，未回滚） |
| `25437b9b` | P1.1 | 057 SQL 迁移（provider_model 列 + 索引） |
| `ca0e53ae` | P1.2 | Go helper（写入路径解析 provider_model） |
| `9a20359b` | P1.3 | 读路径 LATERAL 移除 |
| `6babecfc` | P2.1 | 058 物化 request_status + 读路径去掉 COALESCE |

**部署脚本**：`scripts/deploy-to-71.sh`（处理 build → SCP → systemd restart 全流程）。

---

## ⚠️ 关键约束：P1 三阶段 + P2.1 一阶段

P1 必须分三阶段部署（SQL → helper → LATERAL 移除），缺一不可。P2.1（058）独立但与 P1.3 有顺序耦合（不能比 P1.3 更晚）。

| 阶段 | 内容 | 风险 | 回滚成本 |
|---|---|---|---|
| P1.1 | 应用 057 SQL 迁移 | 极低（ADD COLUMN + 索引，全部 idempotent） | 单 SQL |
| P1.2 | 上线 helper（写入路径） | 极低（helper 失败时仅写 WARN 日志，不影响 INSERT） | git revert |
| P1.3 | backfill 旧行 | 中（脚本自动限速 100ms/batch，可中断） | 脚本可重新跑 |
| P1.4 | 移除 LATERAL | 低（前提：P1.3 完成 ≥ 99.9%） | git revert |
| P2.1 | 058 backfill + 读路径简化 | 低（无 schema 变更，纯 backfill + Go 重构） | git revert |

---

## 📋 部署前 Pre-flight（71 上执行）

```bash
# 在 71 主机上，验证当前 schema 状态
ssh <PROD_HOST> "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
SELECT column_name FROM information_schema.columns
WHERE table_name = '\''request_logs'\'' AND column_name IN ('\''provider_model'\'', '\''request_status'\'');
'"

# 期望输出：每列 1 行（provider_model + request_status 列已存在）
# 若 057 还未部署：provider_model 不会列出
# 若 058 还未部署：request_status 列已存在，但部分行可能 NULL/''（无影响，058 会 backfill）
```

---

## 🚦 P1 阶段 1 — 应用 057 SQL 迁移（71 上执行）

### 1.1 应用迁移

```bash
ssh <PROD_HOST> "docker exec -i r112_postgres psql -U <DB_USER> -d llm_gateway" \
  < deploy/sql/migrations/057_request_logs_provider_model_column.sql
```

**幂等保证**：使用 `ADD COLUMN IF NOT EXISTS` 与 `CREATE INDEX IF NOT EXISTS`，重复执行不会报错。

### 1.2 镜像校验（服务重启时 `EnsureRequestLogSchema` 会自动跑，详见 `db/db.go`）

```bash
ssh <PROD_HOST> "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
SELECT indexname FROM pg_indexes
WHERE schemaname = '\''public'\''
  AND tablename = '\''request_logs'\''
  AND indexname LIKE '\''%provider_model%'\'';
'"

# 期望输出：idx_request_logs_provider_model
```

### 1.3 阶段 1 验证

```bash
ssh <PROD_HOST> "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = '\''request_logs'\'' AND column_name = '\''provider_model'\'';
'"

# 期望：provider_model | text | YES

ssh <PROD_HOST> "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
SELECT indexdef FROM pg_indexes
WHERE indexname = '\''idx_request_logs_provider_model'\'';
'"

# 期望：包含 "WHERE provider_model IS NOT NULL"
```

### 1.4 阶段 1 回滚

```bash
ssh <PROD_HOST> "docker exec -i r112_postgres psql -U <DB_USER> -d llm_gateway" \
  < deploy/sql/migrations/057_request_logs_provider_model_column.down.sql
```

回滚立即生效。ADD COLUMN 的代价是更新 catalog（无表重写），drop 也是元数据级。

---

## 🚦 P1 阶段 2 — 上线 Go helper（commit ca0e53ae）

### 2.1 部署（71 上执行）

走 `scripts/deploy-to-71.sh`：

```bash
# 在本地仓库根目录
./scripts/deploy-to-71.sh

# 脚本会自动：
#   1. go test ./relay ./sessions ./reconnect
#   2. go build → llm-gateway-<commit-hash>
#   3. scp 到 <PROD_HOST>:/opt/llm-gateway-go/
#   4. systemd stop llm-gateway
#   5. cp + chmod +x
#   6. systemd start llm-gateway
#   7. health check on http://localhost:8080/health
```

`EnsureRequestLogSchema` 启动时自动确认列和索引存在（即使阶段 1 已跑过，这里幂等）。

### 2.2 阶段 2 验证

**实时观察新行写入**：
```bash
ssh <PROD_HOST> "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
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
ssh <PROD_HOST> "journalctl -u llm-gateway --since '5 minutes ago' | grep -iE 'provider_model|ResolveProviderModel|PersistProviderModel' | tail -20"

# 期望：无 ERROR / 仅在 SQLSTATE 42P01 (model_offers 缺失) 或 42703 (列未迁移) 时出现 WARN
# P1.1 已跑过 → 应该是 0 WARN
```

**前端 smoke**（任意浏览器）：
- 打开 https://llm.kxpms.cn/request-logs
- 找一个 1-2 分钟内的新行（顶部）
- 点开详情面板，"Provider Model" 字段应该已填值

### 2.3 阶段 2 回滚

```bash
# helper 失败不会让 INSERT 失败（fire-and-forget 设计），最坏情况是回滚到上一 commit
ssh <PROD_HOST> "cd /opt/llm-gateway-go && git revert ca0e53ae && ./scripts/../deploy-to-71.sh"
# 或者手动：git pull 旧 commit + systemctl restart llm-gateway
```

helper 是纯加法，revert 是纯减法，对生产无残留影响。

---

## 🚦 P1 阶段 3 — Backfill 旧行

### 3.1 前置检查

```bash
ssh <PROD_HOST> "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
SELECT COUNT(*) FILTER (WHERE provider_model IS NULL) AS to_backfill,
       COUNT(*) AS total,
       pg_size_pretty(pg_total_relation_size('\''request_logs'\'')) AS table_size
FROM request_logs;
'"

# 100M+ 行 → 10k/batch × 100ms sleep ≈ 17 分钟
# 加上每个 LATERAL 计算耗时，实际可能 30-60 分钟
```

### 3.2 启动 backfill（后台运行，71 上）

```bash
# 推荐：nohup 启动，避免 SSH 断连导致中断
ssh <PROD_HOST> <<'EOF'
cd /opt/llm-gateway-go

# 后台启动 backfill，输出到日志
nohup docker exec -i r112_postgres psql -U <DB_USER> -d llm_gateway \
  < scripts/backfill_request_logs_provider_model.sh \
  > /var/log/llm-gateway-backfill-057.log 2>&1 &

echo "Backfill PID: $!"
EOF
```

### 3.3 监控进度（71 上）

```bash
# 实时进度（每 50 批次打印一次）
ssh <PROD_HOST> "tail -f /var/log/llm-gateway-backfill-057.log"

# 剩余 NULL 行数（粗略进度）
ssh <PROD_HOST> "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
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
ssh <PROD_HOST> "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
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
ssh <PROD_HOST> "ps aux | grep 'backfill_request_logs' | grep -v grep"

# 安全停止 — 脚本使用 SKIP LOCKED，已完成的批次已 commit
ssh <PROD_HOST> "kill <PID>"
# 中断后可重启从上次 cursor 继续（脚本用 id > last_id 游标）
```

---

## 🚦 P1 阶段 4 — 部署 LATERAL 移除（commit 9a20359b）

### 4.1 前置检查（严格）

```bash
# 再次确认 backfill 完成度
ssh <PROD_HOST> "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
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
# 在本地仓库根目录（git pull 已是最新的）
./scripts/deploy-to-71.sh

# 等同于应用 commit 9a20359b
```

### 4.3 阶段 4 验证

**接口 smoke（最关键）**：
```bash
# 默认 24h 列表（用 admin cookie 或 API key）
time curl -s -H "Cookie: <admin session>" \
  'https://llm.kxpms.cn/api/logs?page=1&page_size=50'

# 期望：< 200ms（之前是 3-5s）
```

**EXPLAIN 验证（LATERAL 消失）**（71 上执行）：
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
ssh <PROD_HOST> "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
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
ssh <PROD_HOST> "cd /opt/llm-gateway-go && git revert 9a20359b && systemctl restart llm-gateway"
# 或本地：./scripts/deploy-to-71.sh（基于上一 commit）
```

回滚后旧 LATERAL 重新启用，会再次慢。但 schema 不动、列还在 → 数据完全兼容。

---

## 🚦 P2.1 — 058 物化 request_status（commit 6babecfc）

### 5.1 部署（71 上执行）

058 是 schema 无关的迁移（仅 backfill + Go 重构），可以与 P1.4 一并部署，**无需独立 backfill 窗口**。

```bash
./scripts/deploy-to-71.sh  # 本地执行，会拉取 commit 6babecfc 并部署
```

启动时 `EnsureRequestLogSchema` 自动跑 UPDATE（idempotent，第一次跑会把 NULL/'' 填上，第二次之后是 no-op）。

### 5.2 P2.1 验证

**backfill 已发生**：
```bash
ssh <PROD_HOST> "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c '
SELECT
  COUNT(*) FILTER (WHERE request_status IS NULL) AS null_status,
  COUNT(*) FILTER (WHERE request_status = '\'\'') AS empty_status,
  COUNT(*) FILTER (WHERE request_status IN ('\''success'\'', '\''failure'\'', '\''in_progress'\'')) AS canonical_status,
  COUNT(*) AS total
FROM request_logs;
'"

# 期望：null_status = 0, empty_status = 0, canonical_status = total
```

**EXPLAIN 验证（request_status 过滤走索引）**：
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT rl.ts, rl.request_id, rl.request_status
FROM request_logs rl
WHERE rl.ts BETWEEN now() - interval '24 hours' AND now()
  AND rl.request_status = 'failure'
ORDER BY rl.ts DESC
LIMIT 100;

-- 期望：plan 包含 "Index Scan using idx_request_logs_status_ts" 或
-- "Bitmap Index Scan on idx_request_logs_status_ts"
-- 不再出现 "Filter: ((COALESCE(NULLIF(...))) = 'failure')"
```

**接口 smoke（带 request_status 过滤）**：
```bash
time curl -s -H "Cookie: <admin session>" \
  'https://llm.kxpms.cn/api/logs?page=1&page_size=50&request_status=failure'

# 期望：< 200ms（之前因为 COALESCE 表达式无法走 index，500ms-1s）
```

### 5.3 P2.1 回滚

```bash
ssh <PROD_HOST> "cd /opt/llm-gateway-go && git revert 6babecfc && systemctl restart llm-gateway"
```

读路径会回到 COALESCE 表达式；backfill 已经写入的 request_status 值仍然正确（COALESCE 仍能识别 success/failure/in_progress），不会有数据问题。

---

## 🆘 应急预案（71 上）

### 场景 A：helper 把新行 provider_model 写成 NULL（bug）

```bash
# 1. 立即查 helper 日志
ssh <PROD_HOST> "journalctl -u llm-gateway --since '10 minutes ago' \
  | grep -iE 'ResolveProviderModel|PersistProviderModel'"

# 2. 若大量 WARN，回滚到上一 commit（阶段 2 的 revert）
ssh <PROD_HOST> "cd /opt/llm-gateway-go && git revert ca0e53ae && systemctl restart llm-gateway"

# 3. 旧 LATERAL 自动恢复（因为阶段 4 还未部署），UI 正常显示
```

### 场景 B：backfill 把生产 IO 打满

```bash
# 在 psql 中紧急停止 backfill
ssh <PROD_HOST> "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c \"
SELECT pg_cancel_backend(pid)
FROM pg_stat_activity
WHERE query LIKE '%backfill_request_logs%'
  AND state = 'active';
\""
```

回滚详见 P1.3 阶段 3.5 节。

### 场景 C：阶段 4 部署后，前端显示 provider_model 全是 NULL

```bash
# 检查 helper 是否在跑（telemetry 日志）
ssh <PROD_HOST> "journalctl -u llm-gateway --since '1 minute ago' | grep -E 'helper|provider_model' | tail -5"

# 若 helper 未运行：先重启服务（阶段 2 的 binary 应该已经在跑）
# 若 helper 在跑但 provider_model 仍 NULL：查 LATERAL subquery 语义是否变了（commit diff 验证）

# 紧急回滚到阶段 3 状态：
ssh <PROD_HOST> "cd /opt/llm-gateway-go && git revert 9a20359b && systemctl restart llm-gateway"
```

### 场景 D：阶段 4 部署后，request_status 过滤场景报错（058 关联）

```bash
# 检查 058 的 SELECT 投影 / WHERE 改动是否破坏了某条 SQL
ssh <PROD_HOST> "docker exec r112_postgres psql -U <DB_USER> -d llm_gateway -c \"
SELECT rl.ts, rl.request_id, rl.request_status, rl.error_kind
FROM request_logs rl
WHERE rl.ts > now() - interval '1 hour'
ORDER BY rl.ts DESC LIMIT 5;
\""

# 期望：request_status 全部为 success/failure/in_progress 之一
# 若有 NULL/''，说明 058 backfill 未完成（journalctl 看日志）
```

---

## 📊 性能对比（部署前后，71 上）

| 指标 | 部署前（P0 之前） | P0 + P1 + P2.1 部署后 |
|---|---|---|
| `/api/logs?page=1&page_size=50` 端到端 | 3-5s | < 200ms |
| 主查询耗时 | ~3s | < 50ms |
| LATERAL 子查询次数/页 | 100 | 0 |
| `model_offers` 表读放大 | 每页 100× | 0 |
| `?request_status=failure` 过滤 | 1-2s（COALESCE 表达式） | < 200ms（partial index 命中） |
| `request_logs` 体积影响 | 0 | +1 text 列（典型 < 64 bytes/行） |

---

## 📝 验证清单（部署后填）

- [ ] P1.1 — `provider_model` 列存在，`idx_request_logs_provider_model` 索引存在
- [ ] P1.1 — `request_logs_archive` 也加了列（archive 数据迁移不丢列）
- [ ] P1.2 — 服务启动后新 5 分钟的行 `provider_model` 全部填值（除 credential 不在 model_offers 的边缘情况）
- [ ] P1.2 — 前端详情面板显示 `provider_model`
- [ ] P1.3 — backfill 跑完后剩余 NULL 行数 < 100
- [ ] P1.4 — EXPLAIN 不再包含 `mo_pick` 子查询
- [ ] P1.4 — `/api/logs` 接口响应时间 < 200ms
- [ ] P1.4 — 前端列表页 24h 默认查询体感 < 1s
- [ ] P2.1 — `request_status` 列无 NULL/'' 值
- [ ] P2.1 — `?request_status=failure` 过滤走 `idx_request_logs_status_ts` 索引
- [ ] P2.1 — `?request_status=` 接口响应时间 < 200ms

---

## 🧹 部署后清理（可选，1 周后）

所有阶段部署稳定运行 1 周后：

1. 删除 `requestLogsJoins` 注释里的"previously had LATERAL"那段历史注释
2. 把 `db/request_logs_archive_schema.go` 里 `provider_model` 那行的 `-- 2026-06-30: per 057_*.sql` 注释里的日期更新（让 git blame 显示迁移来源）
3. 把 `admin/logs.go` 的 `requestLogStatusExpr` 常量彻底删掉（已无活引用）；同步删除 `admin/session_title_test.go:TestRequestLogStatusExprRequiresRLAlias`
4. 不需要删 `provider_model` 或 `request_status` 列（product 已经读它）
5. 把 `scripts/backfill_request_logs_provider_model.sh` 加到 archive（不要删，万一未来有手动 backfill 需求）
6. 通知 ops：未来 `model_offers` 视图的 schema 变更不再需要协调 `request_logs` 读路径

---

## 🔗 相关文档

- `docs/2026-06-30-routing-error-transparency.md` — 整体 fix 背景
- `docs/FINAL_SOLUTION_REPORT_minimax_20260630.md` — MiniMax-M3 incident 总结（provider_model 在该报告内被提及为加速 request_logs 的关键）
- `deploy/sql/migrations/057_request_logs_provider_model_column.sql` — 迁移 DDL
- `deploy/sql/migrations/058_request_logs_status_materialize.sql` — 058 迁移 DDL
- `scripts/backfill_request_logs_provider_model.sh` — backfill 脚本（含注释）
- `scripts/deploy-to-71.sh` — 71 服务器部署脚本

---

## 📞 紧急联系

若任一阶段部署后任何指标下降 > 20%，立即：

```bash
ssh <PROD_HOST> "cd /opt/llm-gateway-go && git revert <last-deployed-commit-sha> && systemctl restart llm-gateway"
```

各 commit revert 不会影响 schema/列/数据，最多回到上一阶段，UI 仍可用。

---

## 📋 服务器快速参考

| 项目 | 值 |
|---|---|
| 生产主机 | [SERVER] 71 (`<PROD_HOST>` / `<PROD_HOST_IP>` — 占位化，由 deploy-to-71.sh 注入) |
| 数据库容器 | `r112_postgres` (PostgreSQL 15.x，Docker 容器，在 71 上) |
| 数据库 | `llm_gateway` |
| 数据库用户 | `<DB_USER>` （占位化） |
| 部署目录 | `/opt/llm-gateway-go/` |
| 服务名 (systemd) | `llm-gateway` |
| 二进制文件名 | `llm-gateway-<git-short-sha>` |
| 健康检查端口 | `http://localhost:8080/health` |
| 前端域名 | https://llm.kxpms.cn |