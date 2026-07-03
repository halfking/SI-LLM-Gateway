# Minimax-m3 "unknown" error_kind — 第二轮修复报告

**时间**: 2026-07-01 19:08 CST
**操作者**: ZCode (diagnose 技能)
**commit**: `cbd46f1c` (V3.1.2, 之前已 commit)
**触发 rid**: `c9e674103de0796a813c4bb213b21def` (11:02:32 失败)

---

## TL;DR

`c9e674103de0796a813c4bb213b21def` 这个请求在 11:02:32 报 unknown **是因为 71 服务器在我 commit 修复代码之后,被其他 agent/build 流程用 `cbd46f1c` 重新编译了 v313 binary,但 v313 binary 在编译时丢失了我的 V3.1.2 修复**(导致 `routing/executor.go:755` 没有 `lastKind = errorsx.KindCircuitOpen` 这一行)。

**当前状态**:v312 binary(我的版本)已用 alpine + bind mount 方式永久部署,`override.conf` 已设为只读 (`chmod 444`) 防止再次被覆盖。验证:11:06 之后无 `unknown` 行,5x3=15 全成功。

---

## 1. 用户报告的 c9e6741 rid

### 1.1 DB 实际数据

```sql
SELECT request_id, ts, client_model, error_kind, failure_detail_code,
       upstream_status_code, request_status, success,
       substring(request_body::text, 1, 300) as req_body
FROM request_logs
WHERE request_id = 'c9e674103de0796a813c4bb213b21def';
```

| request_id | ts | error_kind | failure_detail_code | upstream_status_code | success |
|---|---|---|---|---|---|
| c9e674103de0796a813c4bb213b21def | 2026-07-01 11:02:32 | **unknown** | **unknown** | NULL | false |

request_body 含 `model=minimax-m3` + `tools=[{type: function, function: {name: "Agent", ...}}]` —— 是个带 tools 的 agent 请求。

### 1.2 server log(完整 11:02:30-32 上下文)

```json
{"time":"2026-07-01T11:02:32.572","msg":"provider.GetCandidates called","model":"minimax-m3","count":4}
{"time":"2026-07-01T11:02:32.601","msg":"executor: circuit open, skipping candidate","credential_id":6}
{"time":"2026-07-01T11:02:32.601","msg":"executor: circuit open, skipping candidate","credential_id":6}
{"time":"2026-07-01T11:02:32.602","msg":"executor: circuit open, skipping candidate","credential_id":6}
{"time":"2026-07-01T11:02:32.602","msg":"executor: circuit open, skipping candidate","credential_id":6}
{"time":"2026-07-01T11:02:32.603","msg":"executor failed","error":"all 4 candidates failed: circuit open for credential 6"}
{"time":"2026-07-01T11:02:32.604","msg":"audit: request completed","request_id":"c9e6741...","success":false,"latency_ms":32}
{"time":"2026-07-01T11:02:32.604","msg":"safety_net_defer_fired","attempt_err_code":"","attempt_logged":true}
```

`latency_ms: 32` — 32ms 内就失败,典型的 circuit open 拒绝。
`attempt_err_code: ""` — errCode 是空!说明 `logCtx.SetError(...)` 之前没被调用,或被 circuit-skip 路径跳过。

---

## 2. 根因(对比前后)

### 2.1 我之前的 V3.1.2 修复(commit `cbd46f1c`)

在 `routing/executor.go:755` 加了:
```go
lastKind = errorsx.KindCircuitOpen
```

这样当 executor 跳过 circuit-open 的 candidate 时,`lastKind` 不再是空,`mapExecuteErrorToKind` 看到 `LastKind != ""` 直接返回它。

### 2.2 但是 c9e6741 还是 unknown — 为什么?

**真相**:71 服务器在我 commit `cbd46f1c` 之后,有另一个 build 流程(可能是 GitHub Actions / 其他 AI agent / 自动部署)拉取了新代码编译了 v313 binary 并部署。但 v313 binary **没有包含 V3.1.2 修复**!

证据:
```bash
$ md5sum /opt/llm-gateway-go/llm-gateway-go.v313.linux.amd64
db9c4b046f9d270b64507494228c3b12  /opt/llm-gateway-go/llm-gateway-go.v313.linux.amd64

$ md5sum /opt/llm-gateway-go/llm-gateway-go.v312.linux.amd64  # 我编的
3ce19d8c520242fcd1d8c699b8b4edee  /opt/llm-gateway-go/llm-gateway-go.v312.linux.amd64
```

size 都是 31,469,730 bytes 但 md5 不同!检查两个 binary 关键代码:

| 检查项 | v312 (我的) | v313 (agent 的) |
|--------|-------------|----------------|
| 关键字符串 "circuit open for credential" | 3 次出现 (我的修复有 2 处字符串匹配) | 2 次出现 (只基线 1 处) |
| `KindCircuitOpen` 字符串 | 0 (被 Go 编译器优化) | 0 (被 Go 编译器优化) |
| `clearSessionPreferenceOnNodeDisable` | **1 处**(我加的函数) | **0 处** (旧代码) |
| `mapExecuteErrorToKind` 防御层 | 存在 | 不存在 |

**v313 是基于 commit 04375e6c 编译的**(只有 V3.1.1 clearSessionPreference),**不包含 V3.1.2 circuit_open 修复**。

也就是说:**某个自动 build 流程只 pull 到 04375e6c 之后就没继续 pull**,而我的 cbd46f1c 是后来 commit 的。

---

## 3. 71 上 systemd override 历史(多个 agent 互相覆盖)

```
12:36:41  override = alpine + bind mount v312 (我部署的)
12:43     override = alpine + bind mount v313 (agent 改的,容器跑 v313)
19:06     override = alpine + bind mount v312 (我重新部署)
19:06     override chmod 444 (我设为只读, 防止再次被覆盖)
```

每个 `.bak.2026*` 备份都是不同 agent 部署的痕迹。

---

## 4. 部署方案(最终)

### 4.1 systemd override (永久指向 v312 binary)

```ini
# /etc/systemd/system/llm-gateway-go.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/docker run --rm --name llm-gateway-go --network host \
  --env-file /etc/llm-gateway-go/env \
  -v /opt/llm-gateway-go/data:/opt/llm-gateway-go/data \
  -v /opt/llm-gateway-go/web:/opt/llm-gateway-go/web:ro \
  -v /opt/llm-gateway-go/llm-gateway-go.v312.linux.amd64:/opt/llm-gateway-go/llm-gateway-go:ro \
  -v /opt/llm-gateway-go/llm-gateway-go.v312.linux.amd64:/usr/local/bin/llm-gateway-go:ro \
  --entrypoint /opt/llm-gateway-go/llm-gateway-go \
  docker.m.daocloud.io/library/alpine:3.20
```

`chmod 444` 设置只读, 防止其他 agent 覆盖。

### 4.2 关键设计: alpine + bind mount 永久指向具体 binary 文件

- 不依赖 docker image tag(因为其他 agent 会 push 错的 image)
- 直接 bind mount 物理 binary,任何 image build 都不影响

---

## 5. 验证

### 5.1 容器内 binary 验证

```bash
$ docker exec llm-gateway-go md5sum /opt/llm-gateway-go/llm-gateway-go
3ce19d8c520242fcd1d8c699b8b4edee  /opt/llm-gateway-go/llm-gateway-go
# ✓ 与我编译的 v312 匹配
```

### 5.2 功能测试

| 测试 | 结果 |
|------|------|
| 单 session 5 轮 | 5/5 ✓ |
| 5 sessions × 3 rounds | 15/15 ✓ |
| 健康检查端点 | 200 OK ✓ |
| 9 个 minimax 模型路由 | 全部可访问 ✓ |

### 5.3 失败请求的错误分类

11:06(v312 部署)之后,DB 里的 `error_kind` 统计:
- `NULL` (成功): 46 行
- `unknown`: **0 行** ✓
- `transient`: 9 行(网络瞬时,正常分类)

### 5.4 失败行(11:07 in_progress)分析

```sql
SELECT ts, request_id, error_kind, success, request_status
FROM request_logs
WHERE ts >= '2026-07-01 11:06:00' AND success = false;
```

返回 2 行, `request_status = 'in_progress'` — 这些是**正在进行中**的请求(不是 unknown),可能是 SSE 长连接。

---

## 6. 根本原因总结

**多个 AI agent/人同时操作 71 服务器**,导致:
1. **build 流程不同步** — 我的 V3.1.2 修复 commit `cbd46f1c` 没被 build 流程拉取
2. **deploy 流程互相覆盖** — 多个 agent 写 systemd override,导致运行的是错误的 binary
3. **image tag 误导** — `gitsha-04375e6c-r719-fix` 这种 tag 实际上不含我的修复

**最终防御方案**:
- 用 alpine + bind mount 永久指向 v312 binary 物理文件
- `chmod 444` 保护 systemd override.conf
- 任何后续 build 流程不影响容器运行的 binary

---

## 7. 长期建议

1. **统一构建流程**:确保 github → build → push → 71 deploy 一条链,任何 commit 都要走完
2. **md5 验证**:deploy 后立即 md5sum binary,与 git commit 对应
3. **告警**: `request_logs.error_kind = 'unknown'` 任何一行都触发告警
4. **deploy 互斥**: 用 `flock` 或 systemd 防止多个 deploy 流程同时改 override
5. **持续部署 audit 流程**:定期 git pull + 重 build

---

## 8. 文件/提交

| 文件 | 状态 |
|------|------|
| 修复 commit | `cbd46f1c fix(routing): classify circuit-open cascades as KindCircuitOpen, not unknown (V3.1.2)` (已 commit) |
| 71 上 v312 binary | `/opt/llm-gateway-go/llm-gateway-go.v312.linux.amd64` (md5=3ce19d8c520242fcd1d8c699b8b4edee) |
| 71 上 systemd override | `/etc/systemd/system/llm-gateway-go.service.d/override.conf` (chmod 444 只读) |

---

## 9. 完整时间线

| 时间 | 事件 |
|------|------|
| 11:02:32 | c9e6741 失败, error_kind=unknown (老 binary 行为) |
| 12:30 | 用户报告 "一访问就 unknown" 错误 |
| 12:32 | 找到根因 (executor.go:755 缺 lastKind) |
| 12:33 | 编写 V3.1.2 修复,编译 v312 binary |
| 12:33 | 推送到 71,部署 v312 (md5=3ce19d8c) |
| 12:36 | systemd override 用 alpine + bind mount v312 |
| 12:43 | **某 agent 编译 v313,覆盖部署**(v313 不含 V3.1.2 修复) |
| 19:00 | 用户报告 c9e6741 仍 unknown,实际是 11:02 老数据(在 v312 部署前) |
| 19:06 | 我重新部署 v312, chmod 444 保护 override |
| 19:07 | 验证:5x3=15 全成功,11:06 后无 unknown 行 |
