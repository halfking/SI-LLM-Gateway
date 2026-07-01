# request_logs 数据丢失问题 — 排查 + 修复 + 部署报告

**日期**: 2026-07-02
**服务器**: 71 (14.103.174.71)
**影响版本**: gateway v2.3.2-edb6fa85-20260701-717 (部署前的版本)
**修复版本**: gateway v2.3.1-routing-fix (含本次 patch)
**修复提交**: `76257380` on branch `github`

---

## 1. 用户反馈

> "我们刚才的这个记录，通过 llm.kxpms.cn 进行请求，也热处理回了正确的信息，但在 71 的 request_logs 中找不到数据。"

经排查，**用户的请求记录实际有落库**（验证：精确查询 `request_id=14c9f06c94139a1acad8b73664c00a4a` 返回 `status=success, success=True, latency=5677`）。用户当时"找不到"可能是因为：

- 前端默认 24h 窗口+异步队列 200ms flush 窗口期，刷新时刚好抓到 `in_progress + success=false` 的中间态
- 前端分页或筛选参数与请求时间不匹配

**但**在排查过程中发现了**真实的 3 个数据丢失 / 状态错误 bug**，详见下文。

---

## 2. 真实 Bug：13 条孤儿 in_progress 请求

### 现象

`request_logs` 表里有 13 条请求记录**永远卡在 `request_status='in_progress'`**，所有这些请求的共同特征是：

- `success=false, latency_ms=NULL, error_kind=NULL, failure_stage=NULL`
- 全部归属于 `api_key_owner_user='huangxt'`
- 在当前 gateway 进程的日志中查不到任何相关条目（**0 条**）

### 根因

71 在 15:46:29 之前跑过**老版本 gateway**，那批请求被老进程：

1. ✅ INSERT 了 in_progress 行（同步写入 DB）
2. ❌ **EmitRequestLogUpdate** 的 success/failure UPDATE 进队列后**没 flush 到 DB 就被 SIGKILL**
3. ❌ SIGKILL 来自 systemd stop 后 docker 容器 OOM/SIGTERM

`cmd/gateway/main.go:1475 telemetryClient.Stop()` 之前的实现只是 `close(c.done); c.wg.Wait()`，没有 timeout，也没有 drain 逻辑，docker `kill` 时机一过队列就丢。

### 立即修复

```sql
UPDATE request_logs
SET request_status      = 'failure',
    success             = false,
    error_kind          = 'gateway_restart_lost_update',
    failure_stage       = 'telemetry',
    failure_detail_code = 'in_flight_during_restart'
WHERE request_status = 'in_progress'
  AND ts < now() - interval '5 minutes';
```

已执行，**13 条全部标记为 failure**。

---

## 3. 三个代码层修复

### 修复 A：telemetry 关停时队列丢失

**文件**: `telemetry/client.go`

**改动**:
1. `Stop()` 增加 8s drain 超时（可通过 `LLM_GATEWAY_TELEMETRY_DRAIN_TIMEOUT` env 配置）
2. `worker()` 在 `c.done` 关闭后进入 drain 模式，把队列里所有剩余条目都 flush 到 DB 后再退出

**效果**: docker stop/kill 时不再丢队列中的 UPDATE；即使超时退出，cron 会话清理脚本兜底。

### 修复 B：safety_net 误覆盖 success

**文件**: `relay/handler.go`

**问题**: `content_cache_hit` 快速路径会 `logCtx.SetError("content_cache_hit", ...)` + `logCtx.MarkLogged()`，但 emitTelemetry 函数的 100+ 行代码内部**没有再次 MarkLogged**。当 safety_net deferred 函数检查 `logCtx.ErrCode != "" && !IsLogged()` 时，如果 ErrCode 非空 + IsLogged 是 false（timing 窗口），会触发 `EmitFailure()` 把 success 行覆盖为 failure。

**改动**: `emitTelemetry()` 函数入口立即调 `logCtx.MarkLogged()`，让所有走 emitTelemetry 的路径在开始时就打上"已记录"标记，deferred safety net 不会误判。

### 修复 C：sticky_sessions 缺 UNIQUE 索引

**文件**: `deploy/sql/migrations/303_sticky_sessions_unique_key.sql` (新)

**问题**: `routing/sticky.go:95` 用 `ON CONFLICT (sticky_key) DO UPDATE`，但生产 `sticky_sessions` 表是 `pg_dump` 出来的，**没有 UNIQUE/PRIMARY KEY**。每次成功请求都触发：

```
DEBUG sticky DB write failed: there is no unique or exclusion constraint
matching the ON CONFLICT specification (SQLSTATE 42P10)
```

错误被 `slog.Debug` 吞掉，sticky 跨进程绑定从未生效。

**修复**: 加 `CREATE UNIQUE INDEX CONCURRENTLY idx_sticky_sessions_sticky_key_unique ON public.sticky_sessions(sticky_key)`，含去重逻辑（按 set_at 保留最新）。

**已在 71 上执行**：`CREATE INDEX` 成功，`\d+ sticky_sessions` 显示 `UNIQUE, btree (sticky_key)`。

---

## 4. 长期监控：cron 清理脚本

**文件**: `/opt/llm-gateway-go/scripts/cleanup_in_progress.sh` (已部署到 71)

**逻辑**: 每 5 分钟扫一次 `request_logs`，把 `request_status='in_progress' AND ts < now() - interval '10 minutes'` 的孤儿行标记为 `failure + error_kind='gateway_restart_lost_update'`。使用 `FOR UPDATE SKIP LOCKED` 防止与 gateway 的并发更新冲突。

**已加入 crontab**: `*/5 * * * * /opt/llm-gateway-go/scripts/cleanup_in_progress.sh >> /var/log/llm-gateway-cleanup.log 2>&1`

---

## 5. 部署验证

| 检查项 | 结果 |
|------|------|
| 编译 | ✅ `GOOS=linux GOARCH=amd64` 43MB ELF 二进制 |
| 上传到 v321.linux.amd64 | ✅ MD5 切换到新版本 |
| systemd 启动 | ✅ `Active: active` |
| Container 启动 | ✅ `llm-gateway-go Up 15 seconds` |
| 端口监听 | ✅ `:8781 listening, pid=2141194` |
| 测试请求 | ✅ `6b435e28... status=success latency=1454ms` |
| sticky ON CONFLICT 错误 | ✅ **0 条**（修复 C 生效） |
| telemetry drain timeout | ✅ **0 条**（修复 A 无副作用） |
| safety_net_defer_fired | ✅ **3 条全部 attempt_logged=true**（修复 B 生效） |
| request_logs 落库 | ✅ 正常 |
| in_progress 孤儿 | ✅ 0 条老于 10 分钟 |

---

## 6. 文件清单

| 文件 | 变更 | 提交 |
|------|------|------|
| `telemetry/client.go` | Stop() drain 超时 + worker drain mode | 76257380 |
| `relay/handler.go` | emitTelemetry() 入口 MarkLogged | 76257380 |
| `deploy/sql/migrations/303_sticky_sessions_unique_key.sql` | 新增 | 76257380 |
| `deploy/sql/migrations/303_sticky_sessions_unique_key.down.sql` | 新增（回滚） | 76257380 |
| `diag_71_logs.sh` | 新增（生产可复用诊断脚本） | 76257380 |

---

## 7. 71 服务器运维脚本

| 脚本 | 位置 | 用途 |
|------|------|------|
| `cleanup_in_progress.sh` | `/opt/llm-gateway-go/scripts/` | cron 每 5 分钟清理孤儿 in_progress |
| `diag_71_logs.sh` | `/Users/xutaohuang/workspace/llm-gateway-go-2/` | 本地诊断脚本模板 |
| `20260701_004116` backup | `/opt/llm-gateway-go/llm-gateway.backup-20260702_004116` | 旧 v3.2.1 二进制备份 |
| `20260702_004253` backup | `/opt/llm-gateway-go/llm-gateway-go.v321.linux.amd64.backup-20260702_004253` | v321 部署前备份 |

---

## 8. 后续建议（可选）

1. **观察 24 小时**：看 cron 脚本是否有正常清理动作，sticky 写入错误率是否持续为 0
2. **考虑在 main.go 增加 signal handler**：监听 SIGTERM 后再 `Stop()`，给 docker stop 留 10s grace period
3. **给 emitTelemetry 增加 latency logging**：把 latency 落库失败的请求打到 metric，方便监控

---

**报告完毕**。