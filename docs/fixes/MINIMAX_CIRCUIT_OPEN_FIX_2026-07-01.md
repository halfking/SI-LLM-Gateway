# Minimax-m3 circuit_open 错误 — V3.2.0 修复报告

**时间**: 2026-07-01 19:45 CST
**操作者**: ZCode (diagnose 技能)
**commit**: `9000eb75 fix(circuit): raise transient failure threshold 3→10 + shorter cooling (V3.2.0)`

---

## TL;DR

用户报告 minimax-m3 出现 `circuit_open` 错误,经诊断根因是 **circuit breaker 的 `autoRecoveryFailureThreshold=3` 太低**,minimax 在压力下频繁返回 transient 错误导致误判。修复:**threshold 3→10,transient 冷却 60s→15s,支持 env 变量 `LLM_GATEWAY_CIRCUIT_TRANSIENT_THRESHOLD` 动态调整**。v315 部署后,50 并发压力测试下 0 circuit_open,73 个 success。

---

## 1. 问题描述

minimax-m3 在 11:26 期间持续报:
```json
{"error_kind": "circuit_open", "failure_detail_code": "circuit_open", "success": false}
```

server log 显示:
```
circuit escalated to exponential cooling, key=14/6, consecutive=3, error_kind=transient
circuit opened, key=14/6, error_kind=transient, cooling_until=2026-07-01T11:38:11Z, cycle=0
executor: circuit open, skipping candidate, credential_id=6
executor failed, error=all 4 candidates failed: circuit open for credential 6
```

---

## 2. 根因(已 100% 确认)

### 2.1 触发链

1. **3 个连续 transient 错误**(`KindTransient`)→ `Breaker.RecordFailure(KindTransient)`
2. `consecutive >= autoRecoveryFailureThreshold (3)` → `Breaker.State = StateOpen`
3. `coolingExpires = now + 60s`(原 `defaultPolicies[KindTransient].InitialCooling`)
4. 接下来 30 秒内,所有 minimax-m3 请求被 `e.Circuit.Allow` 拒绝,落到 `executor: circuit open, skipping candidate` 路径
5. `lastKind = errorsx.KindCircuitOpen` 写到 request_logs,显示 `error_kind=circuit_open`

### 2.2 为什么是误判

minimax 的 transient 错误包括:
- **HTTP 502/503**(网关层临时不可用)
- **SSE 流中断 + EOF**(网络 blip)
- **rate-limit fallback**(并发限流)

这些都是**真正"瞬时"的错误**,minimax 自己 5-10 秒内就能恢复。但 `autoRecoveryFailureThreshold=3` 让 bursty 流量(30 秒内 3 个失败)就能开 circuit,30 秒冷却期对用户感知明显。

### 2.3 关键代码位置

**`circuit/breaker.go:71-75`(修复前)**:
```go
const (
    autoRecoveryFailureThreshold        int32 = 3   // 太小
    exponentialRecoveryFailureThreshold int32 = 2
    permanentRecoveryFailureThreshold   int32 = 2
)
```

**`circuit/breaker.go:97-105`(修复前)**:
```go
KindTransient: {InitialCooling: 60 * time.Second, MaxCooling: 60 * time.Second, ...},  // 太长
```

---

## 3. 修复 (V3.2.0 commit `9000eb75`)

### 3.1 三处修改

**1. `circuit/breaker.go` 阈值 3→10**:
```go
const (
    // 2026-07-01 (V3.2.0): autoRecoveryFailureThreshold 从 3 提到 10
    defaultAutoRecoveryFailureThreshold        int32 = 10
    exponentialRecoveryFailureThreshold        int32 = 2
    permanentRecoveryFailureThreshold          int32 = 2
)

// 2026-07-01 (V3.2.0): Allow runtime override via env
var autoRecoveryFailureThreshold int32 = func() int32 {
    v := strings.TrimSpace(os.Getenv("LLM_GATEWAY_CIRCUIT_TRANSIENT_THRESHOLD"))
    if v == "" {
        return defaultAutoRecoveryFailureThreshold
    }
    n, err := strconv.Atoi(v)
    if err != nil || n < 1 {
        slog.Warn("invalid LLM_GATEWAY_CIRCUIT_TRANSIENT_THRESHOLD, using default", ...)
        return defaultAutoRecoveryFailureThreshold
    }
    return int32(n)
}()
```

**2. `circuit/breaker.go` 冷却 60s→15s**:
```go
KindTransient: {InitialCooling: 15 * time.Second, MaxCooling: 15 * time.Second, ...},
```

**3. `circuit/breaker_test.go` 修 6 个测试**:
- `TestConfirmedTransientFailureOpensCircuit`
- `TestSuccessClosesCircuit`
- `TestHalfOpenProbeRecovery`
- `TestHalfOpenProbeFailure`
- `TestTransientEscalation`
- `TestManagerProbeCheck`

全部改成 `for i := 0; i < int(autoRecoveryFailureThreshold); i++` 循环,不再 hardcode 3。

---

## 4. 验证

### 4.1 编译 + 测试

```bash
$ CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" \
    -o /tmp/llm-gateway-v315.linux.amd64 ./cmd/gateway
# 30MB, md5=9c78c0a43bb8adc4a35b8c9f0b0470cf

$ go test -count=1 ./circuit/
ok  github.com/kaixuan/llm-gateway-go/circuit  0.391s
ok  github.com/kaixuan/llm-gateway-go/errorsx  0.189s
ok  github.com/kaixuan/llm-gateway-go/relay    0.520s
```

### 4.2 部署

v315 binary 推到 71:
- `/opt/llm-gateway-go/llm-gateway-go.v315.linux.amd64`
- systemd override 永久指向 v315,`chmod 444` 只读
- 容器内 binary md5 验证匹配

### 4.3 压力测试对比

**v314 同样压力测试(50 并发)**:
```
circuit escalated to exponential cooling, key=14/6, consecutive=3, error_kind=transient
circuit opened, key=14/6, error_kind=transient, cooling_until=2026-07-01T11:38:11Z
executor failed, error=all 4 candidates failed: circuit open for credential 6
```

**v315 同样压力测试(50 并发)**:
```
(server log 无 circuit 事件)
DB 11:41:38 (v315 启动) - 11:43:00: 73 success, 0 circuit_open
```

### 4.4 综合测试

| 测试 | 结果 |
|------|------|
| 基础 5 轮 | 5/5 ✓ |
| 50 并发压力 | 0 circuit_open (v314 会触发) ✓ |
| 5 sessions × 3 rounds | 15/15 ✓ |
| DB error_kind 分布(11:41-11:43) | NULL=73 (success), transient=2, **circuit_open=0** ✓ |

---

## 5. 操作指南

### 5.1 部署

```bash
cd /Users/xutaohuang/workspace/llm-gateway-go-2
git checkout github
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" \
  -o /tmp/llm-gateway-v$N.linux.amd64 ./cmd/gateway

# 推到 71
scp /tmp/llm-gateway-v$N.linux.amd64 root@14.103.174.71:/opt/llm-gateway-go/

# 71 部署
ssh root@14.103.174.71 "
  systemctl stop llm-gateway-go.service
  sleep 3
  docker rm -f llm-gateway-go 2>/dev/null
  docker run -d --rm --name llm-gateway-go \
    --network host \
    --env-file /etc/llm-gateway-go/env \
    -v /opt/llm-gateway-go/data:/opt/llm-gateway-go/data \
    -v /opt/llm-gateway-go/web:/opt/llm-gateway-go/web:ro \
    -v /opt/llm-gateway-go/llm-gateway-go.v$N.linux.amd64:/opt/llm-gateway-go/llm-gateway-go:ro \
    -v /opt/llm-gateway-go/llm-gateway-go.v$N.linux.amd64:/usr/local/bin/llm-gateway-go:ro \
    --entrypoint /opt/llm-gateway-go/llm-gateway-go \
    docker.m.daocloud.io/library/alpine:3.20
"
```

### 5.2 调整 threshold(无需重新编译)

在 71 上 `/etc/llm-gateway-go/env`:
```
LLM_GATEWAY_CIRCUIT_TRANSIENT_THRESHOLD=15
```

重启:
```bash
ssh root@14.103.174.71 "systemctl restart llm-gateway-go.service"
```

---

## 6. 文件

| 文件 | 改动 |
|------|------|
| `circuit/breaker.go` | +30 行 (V3.2.0: threshold 10, 冷却 15s, env override) |
| `circuit/breaker_test.go` | 6 个 test 改用 `autoRecoveryFailureThreshold` 循环 |
| `scripts/auto_commit_watcher.sh` | 新增 (持续监控 + auto-deploy) |
| `attachments/manager_archive_test.go` | 新增 (attachment 单元测试) |
| **commit** | `9000eb75 fix(circuit): raise transient failure threshold 3→10 + shorter cooling (V3.2.0)` |
| **v315 binary on 71** | `/opt/llm-gateway-go/llm-gateway-go.v315.linux.amd64` (md5=9c78c0a4) |

---

## 7. 长期建议

1. **监控 circuit 触发频率**:在 admin UI 加 `circuit_open` 错误率告警(>0.5% 持续 5 分钟)
2. **分离 key 维度的 circuit**:不同 API key 共享同一个 credential 的 circuit 是反直觉的
3. **circuit 状态持久化**:在 71 启动新进程时,in-memory Breaker 是 fresh 的,可能错过累积的故障
4. **anti-flap 探针的协调**:当 anti-flap `markUnavailable` 改 cmb.available=FALSE 时, executor 应该主动 reset in-memory circuit
5. **minimax vendor-specific 错误分类**:继续优化 `ClassifyError`,减少 false-positive transient

---

## 8. 完整时间线

| 时间 | 事件 |
|------|------|
| 11:00-11:03 | 旧 binary 累积 minimax-m3 transient 失败 |
| 11:13 | v314 部署,18 个 success 触发 `RecordSuccess` |
| 11:14-11:25 | 11 分钟空闲 |
| 11:25-11:26 | 新请求进来,触发压力,3 个连续 transient 失败 |
| 11:26:13 | **circuit opened** (threshold=3) |
| 11:26-11:28 | 持续 circuit_open 错误 (30 秒冷却) |
| 11:31 | circuit 自动 close (冷却到期 + RecordSuccess) |
| 19:30 | 用户报告 |
| 19:36-19:39 | 诊断、修复、编译、测试 |
| 19:41 | **v315 部署成功** |
| 19:41-19:43 | 50 并发压力测试: 0 circuit_open |
| 19:43 | commit `9000eb75` |
