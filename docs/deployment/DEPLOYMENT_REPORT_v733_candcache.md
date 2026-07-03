# candCache 状态传播修复部署报告 - 71 服务器

**部署时间**: 2026-07-02 16:30 CST
**部署版本**: 2.3.3-45f4d791-20260702-733 (build_seq=733)
**目标服务器**: 14.103.174.71:25022
**部署状态**: ✅ 成功

---

## 背景

收到用户报告：在请求 `a69a71a05e6610adcf55df32f2618797` 中，minimax 会话下 minimax-prod-1/minimax-m3 在管理界面/DB 已显示可用，但路由层仍返回 `no available provider for model 'minimax-m3'`。

代码审计定位到根因：`provider.Client.candCache`（进程内、30 秒 TTL）持有陈旧空候选列表。三条独立的写入路径都没有让 candCache 失效，导致**最多 30 秒的恢复滞后**。

---

## 核心修复

| 修复点 | 文件 | 行为 |
|---|---|---|
| P1#1: RecoverExpired 失效 candCache | `credentialhealth/checker.go` | 自动恢复 tick 写完 `cmb.available=TRUE` 后**同步**调 `invalidateCache()` |
| P1#2: NOTIFY listener 同步失效 | `bg/auto_route_realtime_listener.go` | PG `LISTEN auto_route_refresh` 触发时**立即**调 `invalidateCandCache()`（不再等 5s debounce） |
| P2: candCache TTL 缩到 5s | `provider/client.go` | 任何忘记接 invalidator 的新代码路径最多滞后 5s |
| P3: 集中 helper | — | 已经是 `provider.InvalidateAllCandidateCache` 包级函数，无需新抽象 |
| main 装配 | `cmd/gateway/main.go` | 把 `provider.InvalidateAllCandidateCache` 注入 `bg.NewHealthAutoRecover` 和 `bg.NewAutoRouteRealtimeListener` |

---

## Git 提交

```
33048876 chore: bump version to 2.3.3-45f4d791-20260702-733
45f4d791 fix(routing): close candCache staleness gap on credential state changes
```

修复 commit `45f4d791`:
- 6 个 .go 文件 +219/-20
- 1 个新测试文件 `bg/auto_route_realtime_listener_test.go`
- 2 个新单元测试（`TestRecoverExpired_InvokesInvalidator`、`TestAutoRouteRealtimeListener_HandleNotification_InvalidatesCandCache`）
- 1 个契约保护测试（`TestRecoverExpired_NoInvalidateWhenZeroRows`）

---

## 测试结果

| 包 | 结果 |
|---|---|
| `go build ./...` | ✅ 0 errors |
| `credentialhealth` | ✅ 5/5（含 2 个新增回归测试）|
| `bg` | ✅ 2/2 新增 listener 测试通过 |
| `provider` / `relay` / `admin` / `cmd/...` | ✅ 全部通过 |
| `routing` | ⚠️ 8 个预存失败（修改前已存在，与本修复无关）|

---

## 部署验证

### 1. 服务状态

```
$ curl -sf http://localhost:8781/healthz
{"status":"ok","version":"2.3.3-45f4d791-20260702-733","proxy":{"healthy":true,...}}

$ systemctl is-active llm-gateway-go.service
active

$ ss -lntp | grep 8781
LISTEN ... *:8781 ... users:(("llm-gateway-go",pid=3455389,fd=19))
```

进程 uptime: 45 秒（新版本确认运行中）。

### 2. 实时 NOTIFY → candCache 端到端验证

**方法**：在 71 上用 `psql` 对一条 active 的 `credential_model_bindings` 行做一次无变化 UPDATE（只触发 trigger），观察 gateway.log 出现 `"candidate cache invalidated"` 的时刻。

**结果**：
```
UPDATE 时刻:               16:31:58.497052279
NOTIFY listener 收到:      16:31:58.531880032  (+34 ms)
candidate cache invalidated: 16:31:58.531918888 (+34 ms)
```

PG UPDATE → 进程内 candCache 清空：**端到端 34 毫秒**。

修复前等效路径延迟：**最长 30 秒**（candCache TTL）。

**提升 ~880 倍**。

### 3. 当前路由实际状态

71 上 `credential_model_bindings` 中：
- `cred=11 / minimax-m3` 当前 `available=FALSE`，`unavailable_reason='manual_disabled_100pct_failure_persistent'`，`availability_state='rate_limited'`，`unavailable_recover_at=NULL`

这是一个**手动禁用**的运维状态——SQL `v_routable_credential_models.is_routable=FALSE`，从源头排除，所以即使 candCache 完全清空也仍然返回 "no available provider"。

要让 minimax-m3 重新可路由，需要运维手动清掉该 cmb 行的 `available=FALSE` / `unavailable_reason`，或等运维工具的恢复逻辑触发。

**本修复并未也不能让一个被运维手动禁用的路由恢复可用——它修复的是：当 DB 状态发生变化时，路由层能立刻感知到变化。**

---

## 监控指标（部署后观察）

```
# 每秒 NOTIFY 触发量
$ tail -f /opt/llm-gateway-go/logs/gateway.log | grep "candidate cache invalidated" | wc -l

# 应保持低值；如果飙到 > 10/s 说明有写入风暴
```

---

## 回滚

如需回滚到上一版（732）：

```bash
export SSHPASS=Kaixuan2025
bash ~/.agents/skills/deploy-71/scripts/rollback.sh
```

脚本会列出 `/opt/llm-gateway-go/llm-gateway-go.v321.linux.amd64.bak.*` 让你选。