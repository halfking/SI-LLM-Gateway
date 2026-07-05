# Architecture

LLM Gateway Go 数据面架构总览。

> 注：本文档为高阶架构说明，不含具体 IP、密钥、文件路径或内部命令。

## 0. 双平面架构

```
┌────────────────────┐         ┌────────────────────┐
│  Python 控制面      │         │  Go 数据面          │
│                    │         │                    │
│  - 供应商/凭据管理  │ ──DB──▶ │  - 身份隧道         │
│  - 模型目录        │         │  - 流式中继         │
│  - 策略配置        │         │  - 并发控制         │
│  - 日志查询        │         │  - 审计             │
│  - 管理后台 API    │         │  - 高性能转发       │
└────────────────────┘         └────────────────────┘
```

- **Python 控制面**：供应商、凭据、模型、策略、日志查询（事实源）
- **Go 数据面**：身份隧道、流式中继、并发控制、审计（高性能数据转发）

### 灰度上线

| 阶段 | 描述 |
|---|---|
| 1 | Python 稳定现状 |
| 2 | Go 旁路验证（独立端口、特定 client_profile） |
| 3 | Go 主，Python 备用（默认走 Go，Python 回退） |
| 4 | Go 全量（Python 数据面入口关闭） |

---

## 1. 错误分类与处理

### 1.1 七类错误

| 类别 | 示例 | 恢复 | 重试 | 客户端响应 |
|---|---|---|---|---|
| **TRANSIENT** | 5xx 无明确错误码 | 临时 | ✓ 退避 | 503 `temporarily_unavailable` |
| **TIMEOUT** | 连接/读取超时 | 临时 | ✓ 退避 | 504 `upstream_timeout` |
| **NETWORK** | DNS/连接拒绝/重置 | 临时 | ✓ 退避 | 502 `upstream_network_error` |
| **RATE_LIMIT** | 429 | 周期性 | ✓ 退避 + 缩并发 | 429 `rate_limit_exceeded` |
| **AUTH** | 401/403 | **永久** | ✗ | 502 `credential_invalid` |
| **QUOTA** | 402 余额不足 | **永久** | ✗ | 402 `quota_exhausted` |
| **UPSTREAM_DOWN** | 502/503/504 | 周期性 | ✓ 退避 | 503 `upstream_down` |

### 1.2 恢复曲线

```
临时 (TRANSIENT / TIMEOUT / NETWORK):
  → 冷却 60s 后自动恢复
  → 3 次连续失败 → 升级为"周期性"

周期性 (RATE_LIMIT / UPSTREAM_DOWN):
  → 指数退避: 30s→60s→120s→240s→480s (cap=1800s)
  → 冷却到期 → half_open → 探测
  → 探测成功 → active，失败 → 重算冷却
  → 5 次连续失败 → 通知管理员

永久 (AUTH / QUOTA):
  → 直接 quarantine
  → 记录详细错误与时间戳
  → 通知管理员介入
  → 不自动恢复
```

### 1.3 硬超时（上游挂起防护）

上游静默接受 TCP 但不响应时，通过 goroutine + `upCtx` 桥接 + watchdog 兜底实现硬超时：

- happy path 行为不变（不引入额外延迟）
- 挂起场景立即返回 503（不再被 `http.Client.Timeout` 失效拖住）
- 5s watchdog 兜底，**绝不**在 happy path 上 `defer cancel callCtx`

---

## 2. 身份绑定连接池

### 2.1 池键

```
pool_key = (identity_hash[:16], provider_id, credential_id)
```

原因：凭据不同则 API Key 不同，不能复用连接。

### 2.2 池参数

| 参数 | 值 |
|---|---|
| 最大空闲连接 | 32 |
| 最大总连接 | 128 |
| 空闲超时 | 90s |
| TCP Keepalive | 30s |
| 健康探针 | 30s 一次 HEAD |

### 2.3 健康探测

- 单次失败 → 重试
- 连续 3 次失败 → 标记 pool 为 degraded → 新请求跳过
- 探测恢复 → 标记 active → 新请求继续

---

## 3. 流式中继状态机

```
┌──────────┐   上游返回200     ┌────────────┐   发送chunk    ┌──────────┐
│  等待    │────────────────▶  │  传输中    │──────────────▶│ 已完成   │
│ upstream │                  │(读chunk→   │               │ [DONE]   │
│  响应    │                  │ transform→ │               │  发送    │
└──────────┘                  │  write+flush)               └──────────┘
       │                      └────────────┘                    │
       │ 上游返回                  │        │                    │
       │ 非200                    │        │ 上游返回           │
       ▼                          ▼        ▼ 错误chunk          │
  ┌──────────┐              ┌──────────┐                       │
  │ 错误     │              │ 错误     │                       │
  │ 处理     │              │ chunk    │                       │
  │ (重试/   │              │ 替换+    │                       │
  │  降级)   │              │  发送    │                       │
  └──────────┘              └──────────┘                       │
                                                               │
      客户端断开 (context cancelled) ──────────────────────────┘
      上游超时 (30s无chunk) ────────────────────────────────────┘
```

三种中断处理：
- **客户端断开**：`context.Done()` → cancel upstream → 审计标记 `interrupted=true`
- **上游超时**：最后 chunk 后 30s 无新 chunk → 发送 error chunk → 审计
- **上游错误**：错误 chunk → transform → 发送给客户端 → 重试/降级

---

## 4. 审计流水线（含死信）

```
events channel (buf=10000)
        │
        ▼
   ┌─────────┐    批量 (500/批)    ┌──────────┐
   │  batch  │ ──────────────────▶ │  DB 写入  │
   │ buffer  │                     └──────────┘
   └─────────┘                           │ 失败
        ▲                                ▼
        │                          ┌──────────┐
   ticker 5s                       │   DLQ    │  (buf=1000)
        │                          └──────────┘
        │                               │ 满
        │                               ▼
   ctx.Done()                    磁盘回退目录
        │                        (/var/log/llm-gateway/audit-fallback/)
        ▼                               │
   最终刷出                       每 5min 扫描重试
                                 7 天自动清理
```

设计原则：
- 审计**绝不**阻塞请求路径
- DB 不可用 → 磁盘回退
- panic-safe（独立 goroutine + recover）
- 审计事件**绝不**包含明文凭据

---

## 5. 凭据解密安全设计

### 5.1 解密流程

```
masterKey  (env / k8s secret)
    │
    ▼
Fernet 解密  (与 Python cryptography 兼容)
    │
    ▼
明文 cache   (sync.Map, TTL=5min)
    │
    ▼
调用栈使用 + defer 内存覆写
```

### 5.2 安全约束

- 解密后的 key 在 goroutine 栈上传递，**不逃逸**到堆
- 使用后立即覆写内存
- 日志/审计**禁止**输出明文
- cache TTL 到期自动失效

---

## 6. 速率限制（双层）

```
┌──────────────────────────────────────┐
│  全局 token bucket                    │
│  - 5000 req/s, burst=200             │
└──────────────────────────────────────┘
                  ▼
┌──────────────────────────────────────┐
│  Per-API-Key token bucket             │
│  - 100 req/s, burst=50               │
└──────────────────────────────────────┘
```

实现：无锁（仅依赖 `atomic`），CAS 更新 tokens。

---

## 7. 探活与重试

### 7.1 5 级 Fallback（探活目标选择）

| 优先级 | 来源 |
|---|---|
| 1 | 管理员手动 pin |
| 2 | `request_logs` 7d 最常用 client_model |
| 3a | `routing_policy.featured_models` 白名单 |
| 3b | 该凭据可用模型中随机（兜底） |
| 4 | 国外 provider 列表 |

### 7.2 短间隔重试（消除瞬时抖动）

- 延迟序列：0s / 2s / 5s（共 3 次）
- 只重试：网络错误、5xx、408、425、429
- fail-fast：400 / 401 / 402 / 403 / 404 / 422、ctx cancel
- 与 `bg/model_probe.go` 的 10/15/30s 长间隔**正交**（长间隔等上游恢复，短间隔消除瞬时抖动）

---

## 8. 请求日志归档

### 8.1 分层存储

```
热数据:  request_logs          (heap, 月度分区)
                │
                │  archive_request_logs(month)
                ▼
冷数据:  request_logs_archive  (citus_columnar, 月度分区)
```

### 8.2 唯一约束

`request_logs` 表：`UNIQUE (request_id)` —— 一个逻辑用户请求即使跨重试 / fallback / 异步重试也只有一行记录。

### 8.3 自动维护函数

- `archive_request_logs(archive_month)` — 迁移单月数据到列式存储
- `ensure_next_month_archive_partition()` — 预创建下月列式分区（cron 友好）
- `ensure_request_logs_partition(target_ts)` — 预创建下月 heap 分区

---

## 9. MaaS 计费

- `maas_settings` 单行表：单价与汇率
- `model_credit_rates` 按 canonical 模型维护 credits/1M tokens
- `credit_ledger` / `usage_ledger` 按月分区
- `billing_orders` 订单表
- `tenant_credit_wallets` 租户钱包
- 缓存输入/输出单独计费（cache_in / cache_out 字段）

---

## 10. 自动路由

### 10.1 work_type 分类

- 22+ 内置 work_type（通用对话、代码生成、长文档、Agent、采集、多媒体等）
- LLM 任务分类器识别 → 命中候选模型集

### 10.2 决策路径

```
请求 → work_type 分类 → 候选集
   ↓
   success_rate 阈值过滤
   ↓
   权重 + min_score 排序
   ↓
   选 top-1 → 执行
   ↓
   失败 → fallback 下一个候选
```

### 10.3 反馈信号

- 隐式：成功/失败、延迟、用户重试
- 显式：用户评分、admin 调整
- 每日 worker 反馈聚合
