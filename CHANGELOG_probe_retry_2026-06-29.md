# 探活重试机制 - 变更日志

**日期**: 2026-06-29
**范围**: `internal/probeutil/`（共享重试策略）+ `bg/credential_probe_v2.go`（周期探活）+ `admin/provider_cred_lifecycle.go`（手动探活）
**关联审计**: TASK-AUDIT.md / P0_INCIDENT_SUMMARY.md / CHANGELOG_probe_featured_2026-06-29.md

## 问题

`bg/credential_probe_v2.go::probeCredential`（周期探活）和
`admin/provider_cred_lifecycle.go::doHealthCheck`（admin 手动探活）**单次失败就给
整凭据标 unhealthy**。瞬时网络抖动、provider 临时 5xx、上游 LB 偶发 5xx 都会让
正常凭据被错误屏蔽 → `no_candidates` 路由空集。这与 minimax-m3 06-23 事故根因同构。

`bg/model_probe.go::probeWithRetry` 已有 4 attempts (0/10/15/30s) 长间隔重试，但
**只服务于 Layer 1+2（per-model 恢复）路径，不被 `CredentialProbeV2` 调用**。
两个入口仍是单次定生死。

## 根因

凭据可用性判定与上游瞬时抖动耦合过紧：

1. **V2 周期探活**（每小时 30 分执行，5min timeout）→ 一次 `/v1/models` 或一次
   `mini chat "hi"` 失败即返回 `probeCredential=false` → `classifyProbeFailure`
   标记 `unreachable`/`auth_failed` → 写 `credentials.availability_state` →
   `v_routable_credential_models.is_routable=FALSE` → 路由空集。
2. **admin 手动探活**（`POST /api/providers/{id}/credentials/{cid}/check-health`）
   → 一次 `resolveModelsForCredential`（多 URL 候选）失败即写 `health_status=unreachable`。
3. **历史 4xx 即时判定**：step1 内部 `if 401/403` 立即返回；step2 内部 `if 401/403`
   立即返回；4xx 与 5xx 同样被一票否决。

## 修复

实施 **2s + 5s = 3 次** 短间隔重试，专门用于吸收瞬时抖动（与 `model_probe.go` 的
10/15/30s 长间隔正交——长间隔用于等上游恢复，本机制用于消除瞬时错误）。

### 重试分类（用户最终拍板）

| HTTP 状态 / 错误 | 决策 | 理由 |
|---|---|---|
| 网络错误（连接失败/DNS/超时/timeout） | **重试** | 典型瞬时抖动 |
| 5xx（500-599） | **重试** | 服务端错误，本身即瞬时 |
| 408 Request Timeout | **重试** | 上游显式要求慢一点 |
| 425 Too Early | **重试** | 同上 |
| 429 Too Many Requests | **重试** | 限流，稍等可恢复 |
| 400 Bad Request | **不重试** | 参数错，重试无意义 |
| 401 / 403 | **不重试** | 密钥/权限错，重试无意义 |
| 402 Payment Required | **不重试** | 账户欠费，重试无意义 |
| 404 Not Found | **不重试** | 路径/资源错，重试无意义 |
| 422 Unprocessable Entity | **不重试** | 参数验证错，重试无意义 |
| ctx cancel / deadline exceeded | **不重试** | stop signal，避免覆盖优雅停机 |

### 共享重试原语：`internal/probeutil/retry.go`

新文件，作为两个入口的 SSoT：

```go
// ProbeRetryDelays = []time.Duration{0, 2*time.Second, 5*time.Second}
// IsProbeRetryableStatus(code int) bool
// IsProbeCtxCancel(err error) bool
// SleepWithCtx(ctx, d) bool  // 返回 false 表示 ctx 提前 abort
```

`internal/probeutil/` 已有 `endpoint_id.go`（SSoT for "the provider requires
an endpoint ID"），新加 `retry.go` 是同一 SSoT 模式的延伸。

### 改动文件

| 文件 | 改动 |
|---|---|
| `internal/probeutil/retry.go` | 新建：4 个共享 helper + 详细 doc 注释 |
| `internal/probeutil/retry_test.go` | 新建：12 个测试覆盖所有 status + ctx + sleep 边界 |
| `bg/credential_probe_v2.go` | 改：`probeCredential` 内 step1/step2 各自套 retry loop；新增 `shouldRetryChatErrMsg` + `extractStatusCode` |
| `bg/credential_probe_v2_retry_test.go` | 新建：5 个测试覆盖 chat errMsg 分类 + 与 probeutil 协议一致 |
| `admin/provider_cred_lifecycle.go` | 改：`doHealthCheck` 内 `resolveModelsForCredential` 套 retry loop；新增 `shouldRetryAdminFetchErr` |
| `admin/provider_cred_lifecycle_retry_test.go` | 新建：5 个测试覆盖 admin fetch errMsg 分类 |

## 关键代码示例

### `bg/credential_probe_v2.go::probeCredential` 节选

```go
// 2026-06-29 audit: a single failed probe must not declare a credential
// dead. Each step is wrapped in a short-jitter retry loop (0s/2s/5s, see
// internal/probeutil.ProbeRetryDelays) that only retries on transient
// conditions (network errors, 5xx, 408/425/429). 401/403/404/400/422/402
// fail fast because retrying them is pointless and risks masking real
// configuration errors.

// Step 1: GET /v1/models 加重试
for _, delay := range probeutil.ProbeRetryDelays {
    if !probeutil.SleepWithCtx(ctx, delay) { return false, "ctx canceled" }
    // 遍历所有 candidate URL
    step1OK := false
    nonRetryableHit := ""
    for _, u := range modelsURLs {
        resp, err := httpClient.Do(req)
        if resp.StatusCode == 200 { step1OK = true; break }
        if !probeutil.IsProbeRetryableStatus(resp.StatusCode) {
            nonRetryableHit = ...; break  // 401/403/404/400/422/402 fail fast
        }
    }
    if step1OK { break }
    if nonRetryableHit != "" { return false, ... }
}

// Step 2: mini chat 加重试
for _, delay := range probeutil.ProbeRetryDelays {
    if !probeutil.SleepWithCtx(ctx, delay) { return false, "ctx canceled" }
    ok, errMsg := runChat()  // 含原 max_tokens<2 fallback
    if ok { return true, "" }
    if !shouldRetryChatErrMsg(errMsg) { return false, errMsg }  // 4xx 立即失败
}
```

### `admin/provider_cred_lifecycle.go::doHealthCheck` 节选

```go
var (
    models   []string
    source   string
    fetchErr error
    attempts int
)
fetchStart := time.Now()
for _, delay := range probeutil.ProbeRetryDelays {
    if !probeutil.SleepWithCtx(ctx, delay) {
        fetchErr = ctx.Err(); break
    }
    attempts++
    models, source, fetchErr = h.resolveModelsForCredential(ctx, cred, apiKey, true)
    if fetchErr == nil { break }
    if !shouldRetryAdminFetchErr(fetchErr) { break }  // 4xx 立即失败
}
// 后续 health_status / health_error 写入逻辑完全不变
```

## 兼容性

- **happy path 无变化**：第一次 attempt delay=0s，0ms 额外延迟，行为对健康凭据完全一致。
- **失败 path 慢 2s+5s**：原本瞬时失败的凭据现在多 2s+5s 才最终判定。这对应手动
  探活的 user-perceived latency（30s timeout 内仍能完成）和周期探活的 5min timeout
  （3 次尝试总耗时 < 10s，留充足余量）。
- **不可恢复错误零延迟变化**：401/403/404/400/422/402 仍立即判定。
- **ctx cancel 零影响**：ctx 取消立即 abort，不进入下一轮。
- **`bg/model_probe.go::probeWithRetry` 不动**：长间隔 (10/15/30s) 与短间隔
  (0/2/5s) 服务不同目的，长间隔用于等上游恢复，短间隔用于消除瞬时抖动，两者互补。
- **零停机部署**：纯 Go 变更，无 SQL 迁移。

## 验证结果

```
$ go test ./internal/probeutil/... -v -count=1
=== RUN   TestIsProbeRetryableStatus_NonRetryable              --- PASS
=== RUN   TestIsProbeRetryableStatus_Retryable                 --- PASS
=== RUN   TestIsProbeRetryableStatus_OutOfRange                --- PASS
=== RUN   TestIsProbeCtxCancel_Nil                             --- PASS
=== RUN   TestIsProbeCtxCancel_Canceled                        --- PASS
=== RUN   TestIsProbeCtxCancel_DeadlineExceeded                --- PASS
=== RUN   TestIsProbeCtxCancel_Wrapped                         --- PASS
=== RUN   TestIsProbeCtxCancel_UnrelatedError                  --- PASS
=== RUN   TestProbeRetryDelays_Schedule                        --- PASS
=== RUN   TestSleepWithCtx_Completes                           --- PASS
=== RUN   TestSleepWithCtx_ZeroReturnsImmediately              --- PASS
=== RUN   TestSleepWithCtx_CanceledContext                     --- PASS
=== RUN   TestSleepWithCtx_DeadlineExceeded                    --- PASS
PASS

$ go test ./bg/ -v -count=1 -run "TestShouldRetryChatErrMsg|TestExtractStatusCode"
=== RUN   TestShouldRetryChatErrMsg_FailFast                   --- PASS
=== RUN   TestShouldRetryChatErrMsg_Retryable                  --- PASS
=== RUN   TestShouldRetryChatErrMsg_Empty                      --- PASS
=== RUN   TestExtractStatusCode                                --- PASS
=== RUN   TestShouldRetryChatErrMsg_AgreesWithClassifier       --- PASS
PASS

$ go test ./admin/ -v -count=1 -run "TestShouldRetryAdminFetchErr"
=== RUN   TestShouldRetryAdminFetchErr_Retryable              --- PASS
=== RUN   TestShouldRetryAdminFetchErr_FailFast                --- PASS
=== RUN   TestShouldRetryAdminFetchErr_Nil                     --- PASS
=== RUN   TestShouldRetryAdminFetchErr_CtxCancel               --- PASS
=== RUN   TestShouldRetryAdminFetchErr_NoStatusCode_...        --- PASS
PASS

$ go test ./bg/... ./admin/... ./internal/probeutil/...       # 全量
ok      github.com/kaixuan/llm-gateway-go/bg
ok      github.com/kaixuan/llm-gateway-go/admin
ok      github.com/kaixuan/llm-gateway-go/internal/probeutil

$ go vet ./...                                                # 干净
$ go build ./...                                              # 通过
```

总计 **22 个新单元测试**（probeutil 12 + bg 5 + admin 5），全部通过。

## 部署后观察

1. `SELECT credential_id, health_error, health_checked_at FROM credentials
    WHERE health_status IN ('unreachable', 'auth_failed')
      AND health_checked_at > now() - interval '24 hours'
    ORDER BY health_checked_at DESC LIMIT 50;`
   期望：单凭据短时间内**同一类** unhealthy 标记的连续出现次数显著下降。
2. `SELECT credential_id, COUNT(*) FROM model_probe_runs
    WHERE triggered_by = 'scheduler'
      AND last_attempt_at > now() - interval '24 hours'
    GROUP BY credential_id HAVING COUNT(*) > 5;`
   期望：被反复拉黑-恢复-拉黑的"振荡"凭据数下降。
3. 失败次数中，重试后才最终失败的占比：
   - 在 `provider_cred_lifecycle.go::doHealthCheck` 中，`fetchErr` 已 annotate 为
     `after N attempts:`，可直接 grep 观察。

## 不动的部分（明确范围）

- `bg/model_probe.go::probeWithRetry` —— 已有重试，服务于 per-model 恢复路径，与本
  修复正交。**不**改成短间隔——会破坏它"等上游恢复"的设计意图。
- admin `/check-health` 的 user-facing 响应字段结构 —— 仅在 `fetchErr` 上加
  `after N attempts:` 前缀，向后兼容。
- `bg/credential_probe_v2.go::writeHealth` / `classifyProbeFailure` —— 它们只关心
  `ok/errMsg`，对重试透明。
- 任何 SQL 迁移 —— 无 schema 变更。

## 关联文件

- `internal/probeutil/retry.go` — 新增共享重试原语
- `internal/probeutil/retry_test.go` — 新增 12 个测试
- `bg/credential_probe_v2.go` — `probeCredential` 加 retry loop
- `bg/credential_probe_v2_retry_test.go` — 新增 5 个 chat errMsg 分类测试
- `admin/provider_cred_lifecycle.go` — `doHealthCheck` 加 retry loop
- `admin/provider_cred_lifecycle_retry_test.go` — 新增 5 个 admin fetch errMsg 测试
- `deploy/sql/00_schema/003_routing_tables.sql:258` — 8 个 featured_models 默认值
  （与本次重试正交，但与 `CHANGELOG_probe_featured_2026-06-29.md` 关联）

---

## 审计修正（2026-06-29，同日）

初次实现后对全部 6 个改动文件做了交叉审计，发现并修正 5 个问题：

| # | 严重度 | 位置 | 问题 | 修正 |
|---|---|---|---|---|
| 1 | 🔴 高 | `bg/credential_probe_v2.go:341` | step1 不可重试分支返回 `"401/403/404/400/422/402: " + nonRetryableHit`，前缀硬编码 6 个状态码，与 `nonRetryableHit` 已含的 `status %d:` 信息重复，且未来加新码（如 451）易忘记同步前缀 | 直接返回 `nonRetryableHit`（它已含 `status <code>: <body>`） |
| 2 | 🟡 中 | `internal/probeutil/retry.go:46` | 注释说"errs on the side of retrying for 4xx"，但代码对未列出 4xx（405/409/410/418/428/451…）实际返回 false（不重试）。注释与代码不符，且与用户"4xx 除明确不可恢复外都重试"的决策相悖 | 改代码：除 400/401/402/403/404/422 外的所有 4xx 都重试（`code >= 400 && code <= 599 → true`）。1xx/2xx/3xx/6xx+ 保持 non-retryable（它们不是 probe 失败结果） |
| 3 | 🟡 中 | `bg/credential_probe_v2_retry_test.go` | retryable 测试用例用了 `"chat status 429: rate limited"`，但 miniChat 真实产出是 `"429 rate limited"`（无 `chat status` 前缀，见 credential_probe_v2.go:491）。测试覆盖的不是真实路径 | 补充真实产出格式：`"429 rate limited"`、`"messages unreachable: ..."`、`"build messages request: ..."`；FailFast 测试同理补充 `"402 payment required"`、`"messages status 400/404/422: ..."` |
| 4 | 🟢 低 | `internal/probeutil/retry_test.go:28` | `TestIsProbeRetryableStatus_OutOfRange` 原本只断言"不 panic"，未明确断言 4xx-非-fail-fast 的值 | 改为显式断言：405/409/410/418/428/451 等 17 个 4xx 必须 retryable；100/200/204/301/304/600/999 必须 non-retryable |
| 5 | 🟢 低 | `bg/credential_probe_v2.go:408` | `shouldRetryChatErrMsg("")` 返回 true（"defensive retry"），但空 errMsg 在 `runChat` 返回 `ok=false` 时不可能出现（miniChat 总返回非空 errMsg） | 保留该分支（防御性，未来 miniChat 改动可能产出空 errMsg），但在注释里明确"unreachable in current miniChat/miniAnthropic, kept defensive" |

### 审计方法

1. 回读每个改动文件的完整 diff 上下文（不只看新增部分）
2. 对每个 retry loop，枚举 miniChat / miniAnthropic / fetchVendorModels 的**所有真实 errMsg 产出格式**，逐一验证 classifier 处理正确
3. 对每个测试用例，核对它声称覆盖的 errMsg 格式与生产代码实际产出的格式是否一致
4. 对每条注释，核对它与代码的实际行为是否一致

### 验证

```
$ go test ./... -count=1       # 整个模块，0 个 FAIL
$ go vet ./...                 # 干净
$ go build ./...               # 通过
```

修正后 `TestIsProbeRetryableStatus_OutOfRange` 从 4 个隐式断言扩展到 24 个显式断言（17 retryable + 7 non-retryable），`TestShouldRetryChatErrMsg_Retryable` 从 12 个用例扩展到 14 个（全部是真实产出格式）。

