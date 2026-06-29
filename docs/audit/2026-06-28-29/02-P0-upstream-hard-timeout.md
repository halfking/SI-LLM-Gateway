# 02 · P0 上游挂起硬超时修复

**Commit**：`9c614f44` — `fix(executor): P0 upstream hang hard-timeout + prod_e2e suite`
**作者**：halfking <kimmy.huang@gmail.com>
**时间**：2026-06-29 02:57 (+0800)
**优先级**：**P0**（生产事故级别）
**破坏性变更**：否（向后兼容，默认行为不变）
**依赖**：无

---

## 一、问题陈述（Why）

**生产事故**：2026-06-28 prod_e2e 测试中观察到，部分上游（典型场景：通过公司代理 `172.31.0.2:7890` 转发）**静默接受 TCP 连接但永远不写响应**。具体表现：

| 症状 | 触发模型 / 端点 | 观测值 |
|------|----------------|--------|
| 非流式挂起 | qwen3-235b-a22b / mimo-v2.5-pro / kimi-k2.5 / kimi-k2.6 / mistral-large | > 200s 后超时 |
| 端点挂起 | `/v1/completions` | 无限挂起 |
| 边界挂起 | `/v1/chat/completions` + `messages=[]` | 无限挂起 |

> **核心痛点**：每次请求卡 3-4 分钟，配合 `maxRetries=2` 累加可达 **360s 客户端等待**，期间耗尽 limiter、占用 client connection。

## 二、根因分析（Root Cause）

`http.Client.Timeout` 和 `ResponseHeaderTimeout` 在企业代理环境下**不会触发**：代理接受 SYN-ACK 后不向目标转发，net/http 的 read loop 一直阻塞。原始 `routing/executor_chat.go` 中的 upstream 调用：

```go
// 修复前：直接 e.Upstream.Do(req) — 无 goroutine 桥接 upCtx
resp, uErr = e.Upstream.Do(req)  // 阻塞最长 = upCtx 期限
```

`upCtx` 虽然有截止时间，但 `http.Client.Do` 在代理卡顿时并不感知 ctx 取消。

## 三、修复方案（Solution）

**关键文件**：`routing/executor_chat.go`
**新增函数**：
- `doUpstreamWithHardTimeout(req, upCtx, upstream)` @ L1009
- `doUpstreamRawWithHardTimeout(req, upCtx, httpClient)` @ L1070

**调用点**：
- `executor_chat.go:375` — 替换 `e.Upstream.Do(req)`
- `executor_chat.go:377` — 替换 `httpClient.Do(req)`

### 3.1 核心设计

```go
// doUpstreamWithHardTimeout (routing/executor_chat.go:1009-1110)
func doUpstreamWithHardTimeout(req *http.Request, upCtx context.Context, upstream *upstreampkg.Client) (*http.Response, *upstreampkg.Error) {
    callCtx, cancelCall := context.WithCancel(context.Background())
    // 关键：不要 defer cancelCall() — 详见下面 CRITICAL
    cancelReq := req.WithContext(callCtx)

    type result struct {
        resp *http.Response
        uErr *upstreampkg.Error
    }
    done := make(chan result, 1)
    go func() {
        defer func() {
            if r := recover(); r != nil {
                done <- result{nil, &upstreampkg.Error{...}}
            }
        }()
        resp, uErr := upstream.Do(cancelReq)
        done <- result{resp, uErr}
    }()

    select {
    case r := <-done:
        return r.resp, r.uErr
    case <-upCtx.Done():
        cancelCall()                       // ← 关键：桥接 upCtx 到 callCtx
        watchdog := time.NewTimer(5 * time.Second)
        defer watchdog.Stop()
        select {
        case <-done:
        case <-watchdog.C:
        }
        return nil, &upstreampkg.Error{
            Kind:    errorsx.KindTimeout,
            Message: fmt.Sprintf("upstream hard timeout: %v", upCtx.Err()),
            Err:     upCtx.Err(),
        }
    }
}
```

### 3.2 ⚠️ CRITICAL 设计决策

> **绝不能在 happy path 上 `defer cancelCall()`**。
> 流式读取器（`relay/stream.go:147`）通过 `resp.Request.Context()` 派生 read loop ctx。
> 如果 callCtx 在 Do 返回后立刻被 cancel，stream reader 的下一次 read 会立刻收到 `context.Canceled`，
> 进而**误报 `first_byte_timeout`**（即使首字节已到达）。

callCtx 与 upCtx 是**单向桥接**：只由 upCtx 监听 goroutine 主动 cancel，**从不**由 defer 路径 cancel。

### 3.3 5 秒 watchdog

upCtx 触发 cancelCall 后，仍需等待内部 goroutine 干净退出（避免 goroutine 泄漏），
最坏等 5s 后强制返回。

## 四、测试覆盖

| 测试文件 | 测试函数 | 验证目标 |
|----------|----------|----------|
| `routing/hard_timeout_test.go:29` | `TestDoUpstreamWithHardTimeout` | 基础硬超时触发 |
| `routing/hard_timeout_test.go:97` | `TestDoUpstreamWithHardTimeout_NormalResponse` | 正常路径不触发 cancelCall |
| `routing/hard_timeout_test.go:132` | `TestDoUpstreamWithHardTimeout_ServerErrorReturnsImmediately` | 5xx 立即返回 |

**集成验证**（生产环境 `https://llm.kxpms.cn`）：
- 91 PASS / 14 FAIL / 12 SKIP（修复前 14 失败全为上游挂起）
- 修复后 qwen3-235b-a22b 首次 130s 返回 503，后续断路器打开 44ms 返回

## 五、跨分支同步要点（Sync Notes）

### 5.1 必带文件

```
routing/executor_chat.go              # 改动 +160 行
routing/hard_timeout_test.go          # 新增 159 行
tests/prod_e2e/                       # 10 个套件 + common.sh + run_all.sh
tests/prod_e2e/REPORT.md              # 背景报告
```

### 5.2 验证步骤（最小重现）

```bash
# 1. 单元测试
go test ./routing/... -run TestDoUpstreamWithHardTimeout -v

# 2. 编译
go build ./...

# 3. 端到端（需生产环境）
cd tests/prod_e2e && bash run_all.sh
# 期望：所有套件返回 0；上游挂起相关 14 个失败应转为通过或被 SKIP
```

### 5.3 兼容性

- ✅ **100% 向后兼容**：仅在原有调用点替换为包装函数
- ✅ 不修改 HTTP 协议、不修改响应格式
- ✅ 不修改数据库 schema
- ✅ 不需要任何环境变量 / config key

### 5.4 已知边界

| 场景 | 行为 |
|------|------|
| 上游已发送部分 chunk 但中途挂起 | 5s watchdog 触发；client 收到 `upstream hard timeout` |
| 流式响应在 cancelCall 触发后才到达 | callCtx 不被 defer cancel，goroutine 仍可写 channel；通过 watchdog 兜底 |
| panic 恢复 | `recover()` 写入 `upstreampkg.Error{Kind: KindTransient}`，不崩溃 |
| 1.5× ResponseHeaderTimeout 长延迟 | 仍由 upCtx 截止控制，wrapper 不引入额外延迟 |

## 六、风险与回滚（Risk & Rollback）

| 维度 | 评估 |
|------|------|
| 影响面 | 所有 `/v1/chat/completions` 路径必经 `executor_chat.go` |
| 可逆性 | 极高（cherry-pick 反向 = 一行回退到 `e.Upstream.Do(req)`） |
| 降级开关 | 无显式开关；如需临时关闭，注释 `executor_chat.go:375-377` 的 wrapper 调用即可 |
| 监控 | 关注 `errorsx.KindTimeout` 错误计数（应大幅下降）；新增 `upstream hard timeout: ...` 日志可观测 |

## 七、未来优化（Future Improvements）

作者 commit message 中**未列**，但根据代码上下文有：

1. **wrapper 抽取到公共包**：当前两个函数 `doUpstreamWithHardTimeout` / `doUpstreamRawWithHardTimeout` 有 80% 重复代码，可考虑抽到 `routing/internal/timeout` 子包供其他 executor（completions / embeddings）复用。
2. **watchdog 时间可配置**：当前硬编码 5s，复杂场景可暴露为 config。
3. **指标暴露**：建议在 `metrics.go` 增加 `upstream_hard_timeout_total{provider,model}` counter。
