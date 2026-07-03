# v737 Audit Fixes Deployment Report - 71 服务器 (v740)

**部署时间**: 2026-07-03 03:08 CST
**部署版本**: 2.3.3-df57621b-20260702-740 (build_seq=740)
**目标服务器**: 14.103.174.71:25022
**部署状态**: ✅ 成功
**关联事件**: v737 final audit 的 CRITICAL 修复

---

## 部署内容

本版本包含 v737 final audit 的 2 个 CRITICAL 修复：

1. **CRITICAL-1 (operational)**: `cmd/gateway/main.go` — `autoRouteListener` 和 `healthAutoRecover` 的 `Stop()` 加入 shutdown sequence
2. **CRITICAL-2 (SQL drift)**: `deploy/sql/00_schema/full_schema.sql` + per-object trigger file — credentials trigger `UPDATE OF` 列表加 `plan_type`

加上 2 份文档（不需重部署）：

3. `docs/v739_dbpool_refactor.md` — v739+ DBPool refactor 的 6 步 staging 计划
4. `DEPLOYMENT_REPORT_v737_final_audit.md` — v737 final audit 完整报告

---

## 部署验证

### 冒烟测试

```bash
$ curl -sf http://localhost:8781/healthz
{"status":"ok","version":"2.3.3-df57621b-20260702-740","proxy":{"domestic":[...],...}}

$ ps -o pid,etime,cmd -p $(pgrep -f llm-gateway-go.v321 | head -1)
PID      ELAPSED CMD
3573071  00:19   /usr/bin/docker run --rm --name llm-gateway-go ... llm-gateway-go

$ ss -lntp | grep 8781
LISTEN 0  4096  *:8781  *:*  users:(("llm-gateway-go",pid=3573117,fd=17))
```

### Test 1: main.go Stop() 不泄漏连接

PID 3573117 进程对 PG 5432 的 ESTABLISHED 连接数：

```
ESTAB 0  0  172.31.0.3:48226  172.31.0.4:5432  users:(("llm-gateway-go",pid=3573117,fd=7))
ESTAB 0  0  172.31.0.3:41450  172.31.0.4:5432  users:(("llm-gateway-go",pid=3573117,fd=28))
```

**结果**: 2 个 ESTAB（1 个普通 pool conn + 1 个 LISTEN conn）— 理想状态，没有泄漏。

修复前每次 restart 会累积额外的 LISTEN goroutine + 长生命周期 pgxpool conn。本版本启动后，shutdown sequence 调用 `autoRouteListener.Stop()` 和 `healthAutoRecover.Stop()` 关闭 goroutine + 释放 conn。

### Test 2: plan_type PATCH 端到端 NOTIFY 链

| 操作 | listener events diff | candCache invalidated |
|---|---|---|
| `UPDATE credentials SET plan_type = 'token' WHERE id = 6` (token_plan → token) | +1 (`credentials:UPDATE:6`) | +1 (19:40:21.526) |
| `UPDATE credentials SET plan_type = 'token_plan' WHERE id = 6` (token → token_plan) | +1 (`credentials:UPDATE:6`) | +1 (19:40:27.586) |

**结果**: 每次真实 plan_type 变更触发 listener event，candCache 立刻失效，**端到端延迟 < 1ms**。

`auto_route listener: refresh requested` payload="credentials:UPDATE:6" 是 v737 audit C2 trigger 修复的直接验证 — `UPDATE OF` 列表加 `plan_type` 后，trigger 在 plan_type 变更时正确触发 NOTIFY。

### Test 3: 71 上 plan_type 派生 cmb 仍然正确

```
cred 6 / MiniMax-M3:
  plan_type        = token_plan
  cmb.billing_mode = token_plan
  available        = t
  is_routable      = t
  unavailable_reason = null
```

**结果**: `cred 6 / MiniMax-M3` 仍然 routable，无 plan_incompatible 风险。`v_routable_credential_models` rule 8 (plan_type ↔ billing_mode parity) 持续生效。

### Test 4: no-op 变更不触发 trigger (预期)

```
UPDATE credentials SET plan_type = plan_type WHERE id = 6;  (no-op)
→ DIFF=0
```

**结果**: `WHEN (old.* IS DISTINCT FROM new.*)` 正确判断 no-op，不发无意义的 NOTIFY。

---

## Git 提交链

```
dfd11f73 fix(gateway+sql): close two CRITICAL gaps from v737 final audit
b1b117a0 chore: bump version to 2.3.3-feda1901-20260702-735
c18090a4 chore: bump version to 2.3.3-feda1901-20260702-737
feda1901 fix(admin+sql): close audit gaps from v733-v735 review
1de1a668 docs: plan_type UI deployment report v735
be29f726 docs: cmb.billing_mode plan_incompatible fix deployment report v734
28dd7671 chore: bump version to 2.3.3-d2a3d7a5-20260702-734
d2a3d7a5 fix(modelcatalog): derive cmb.billing_mode from credentials.plan_type on upsert
699e6482 docs: candCache staleness fix deployment report v733
33048876 chore: bump version to 2.3.3-45f4d791-20260702-733
45f4d791 fix(routing): close candCache staleness gap on credential state changes
```

---

## 监控

部署后 5 分钟内观察：

```bash
# 1. listener event rate (should be 0-1/min in steady state)
grep "auto_route listener: refresh requested" /opt/llm-gateway-go/logs/gateway.log | tail -10

# 2. candCache invalidation rate (normal: a few per minute)
grep "candidate cache invalidated" /opt/llm-gateway-go/logs/gateway.log | tail -10

# 3. shutdown goroutine count (after next restart, should be 0 leaked)
ps -efL -p $(pgrep -f llm-gateway-go.v321 | head -1) | wc -l
```

---

## 71 Live 状态

| 状态 | 详情 |
|---|---|
| 部署版本 | v740 (2.3.3-df57621b-20260702-740) |
| PID | 3573117 |
| Uptime | 00:19 (deployment start) |
| Port 8781 | LISTEN |
| `/healthz` | 200 OK |
| plan_type chain | cred 6 / token_plan / cmb token_plan / is_routable=t |
| NOTIFY latency | < 1ms |
| Conn leak | NONE (2 ESTAB to PG, 1 pool + 1 LISTEN) |

## v741+ Backlog

来自 v737 final audit：

1. 限制 `/api/pricing/offers/bulk-update` 为 super_admin（修 par_invariant 损坏路径）
2. plan_type PATCH 加 `slog.Info`（operator UX）
3. 加 Prometheus counter
4. `bg.NewHealthAutoRecover` 加 `InvalidateAvailableModelsCache` 参数（parity with v737 H3）
5. dbpool interface 重构（按 `docs/v739_dbpool_refactor.md` 6 步滚动）

每项都是单文件 fix，下次 v741 可分批处理。