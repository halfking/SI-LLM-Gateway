# llm-gateway-go

LLM Gateway Go 数据面 — 高性能身份感知 LLM 请求代理网关。

## 项目概述

企业级 LLM API 网关：身份感知路由、流量控制、请求标准化与全链路审计追踪。
支持多供应商凭据池管理、自动路由选择、流式中继、断线重连与可观测性。

## 本批提交特性总结

本次提交包含两个独立的工程改进，逻辑清晰可分别回滚。

### 数据库资产全面集中

- **184 生产库逐对象 SQL 导出**：从生产 PostgreSQL 拉取 `pg_dump --schema-only` 输出，自动化解析为 **933 个独立 SQL 文件**，每个表/视图/函数/索引/触发器/策略单独成文件
  - 138 表 / 413 索引 / 88 约束 / 65 序列 / 64 默认值 / 64 RLS 策略 / 37 函数 / 17 视图 / 16 触发器 / 8 外键 / 4 扩展 / 2 物化视图
- **完整参考快照**：`deploy/sql/00_schema/184_full_schema.sql`（11,477 行）作为 184 实时结构的权威镜像
- **拆分工具**：`deploy/sql/scripts/split_pg_dump.py` 支持任意时刻重新同步生产 schema
- **统一目录**：所有 SQL 资产（迁移、初始化、运维、文档、临时）集中到 `deploy/sql/` 下按职能分子目录
  - `00_schema/` 初始化结构
  - `01_functions/` 函数与触发器
  - `02_seed_data/` 最小初始化数据
  - `migrations/` 历史迁移（按编号顺序）
  - `objects/` 逐对象导出（来自 184）
  - `db_scripts/` 运维脚本
  - `adhoc/` 临时/诊断脚本
  - `docs/` 文档 SQL

### 文档精简

- **根目录文档精简到 4 个**：`README.md`、`ARCHITECTURE.md`、`CHANGELOG.md`、`DEPLOYMENT.md`
- **删除 ~150 详细过程文档**：所有 `CHANGELOG_*`、`AUDIT_*`、`DEPLOYMENT_*`、`HOTFIX_*`、`DIAGNOSIS_*`、`*_FIX.md`、`*_REPORT.md`、`*_SUMMARY.md`、`*_ANALYSIS.md` 等连同整个 `docs/` 目录与 `memory-bank/`
- **敏感信息脱敏**：移除所有 IP、服务器主机名、个人邮箱、含密钥命令、具体部署 URL
- **内容归并**：将分散的 CHANGELOG 合并为按版本组织的高阶历史

## 技术栈

- **语言**: Go 1.21+
- **HTTP**: 原生 net/http
- **数据库**: PostgreSQL 15（带 `pg_trgm`、`citus_columnar` 扩展）
- **缓存/限流**: Redis
- **前端**: Vue 3 + Vite + TypeScript

## 文档索引

| 文档 | 说明 |
|---|---|
| [README.md](./README.md) | 本文件，项目入口 |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | 架构总览（错误分类、连接池、流式状态机、审计流水线等） |
| [CHANGELOG.md](./CHANGELOG.md) | 高阶业务变更历史 |
| [DEPLOYMENT.md](./DEPLOYMENT.md) | 部署与运维说明 |

数据库 SQL 资产位于 [`deploy/sql/`](./deploy/sql/)，详见该目录的 README。

## 目录结构

```
llm-gateway-go/
├── cmd/                    # 程序入口
├── relay/                  # HTTP 请求中继核心
│   ├── handler.go          # 请求处理与路由解析
│   ├── stream.go           # SSE 流式响应处理
│   └── normalize.go        # 请求/响应标准化
├── routing/                # 路由与执行
│   ├── executor.go         # 候选执行、重试、粘性路由
│   └── executor_chat.go    # 硬超时与上游调用
├── circuit/                # 熔断器
├── limiter/                # 并发限流
├── pool/                   # 连接池管理
├── provider/               # 供应商/策略解析
├── identity/               # 身份管理（身份哈希、虚拟地址推导）
├── transform/              # 请求转换
├── upstream/               # 上游 LLM 客户端
├── telemetry/              # 遥测
├── audit/                  # 审计日志
├── sessions/               # 会话管理
├── credentialstate/        # 凭证状态机
├── disguise/               # 请求伪装
├── secret/                 # 密钥管理（Fernet 对称加密）
├── ratelimit/              # 滑动窗口限流
├── autoroute/              # 自动路由分类与决策
├── bg/                     # 后台任务（凭证轮换、探活等）
├── admin/                  # 管理接口
├── middleware/             # HTTP 中间件
├── modelname/              # 模型名标准化
├── metatools/              # 工具调用聚合
├── maas/                   # MaaS 计费
├── memora/                 # 会话记忆提取
├── identitypool/           # 终端用户身份池
├── modelcatalog/           # 模型目录
├── registry/               # 注册表
├── catalog/                # 业务目录
├── compressor/             # 上下文压缩
├── discovery/              # 服务发现
├── observability/          # 可观测性
├── settings/               # 租户设置
├── hotconfig/              # 热配置
├── reconnect/              # 断线重连
├── sessions/               # 会话
├── sessions/               # 提示注入检测
├── disguise/               # 响应伪装
├── errorsx/                # 错误码体系
├── web/                    # Vue 3 管理后台
├── deploy/                 # 部署资产（k8s manifest、SQL、shell 脚本）
├── tests/                  # 测试
├── audit/                  # 审计
└── bin/                    # 编译产物
```

## 主要模块

| 模块 | 职责 |
|---|---|
| `relay/handler.go` | HTTP 请求生命周期、错误码统一、降级路由 |
| `routing/executor.go` | 候选规划、重试、状态写入、粘性路由 |
| `routing/executor_chat.go` | 硬超时上下文桥接上游调用 |
| `relay/stream.go` | SSE 流式代理、超时、保活 |
| `circuit/breaker.go` | 凭证级熔断状态机 |
| `pool/` | 身份绑定连接池 |
| `identity/identity.go` | 身份哈希与虚拟地址推导 |
| `transform/transform.go` | 请求转换与出站模型渲染 |
| `limiter/limiter.go` | 并发限制 |
| `ratelimit/sliding.go` | 滑动窗口限流 |
| `autoroute/` | 模型自动选择与 work_type 分类 |
| `audit/` | 审计事件管道（批写+死信回退） |
| `telemetry/` | 请求日志批写、分区路由 |

### 核心处理流程

```
请求入口 → relay/handler.go → routing/executor.go → circuit/breaker.go
   → upstream/client.go → 响应
        ↓                ↓                ↓
   路由解析         候选执行          熔断/限流
```

## 运行时端点

| 端点 | 方法 | 说明 |
|---|---|---|
| `/healthz` | GET | 进程存活 |
| `/readyz` | GET | 依赖就绪 |
| `/v1/chat/completions` | POST | Chat Completion API |
| `/v1/completions` | POST | Completion API |
| `/v1/messages` | POST | Anthropic Messages API |
| `/v1/responses` | POST | OpenAI Responses API |
| `/v1/models` | GET | 模型列表 |
| `/v1/keys/*` | POST | API Key 申请与管理 |
| `/api/admin/*` | GET/POST | 管理后台接口 |

请求格式同时支持 OpenAI-compatible 与 Anthropic-compatible。

## 错误处理

七类错误处理：

| 类别 | 示例 | 恢复策略 |
|---|---|---|
| TRANSIENT | 5xx (无明确错误码) | 临时 60s 冷却 |
| TIMEOUT | 连接/读取超时 | 退避重试 |
| NETWORK | DNS/连接拒绝/重置 | 退避重试 |
| RATE_LIMIT | 429 | 指数退避 30s→60s→120s... |
| AUTH | 401/403 | 永久 quarantine |
| QUOTA | 402 余额不足 | 永久 quarantine |
| UPSTREAM_DOWN | 502/503/504 | 指数退避 |

详见 [ARCHITECTURE.md](./ARCHITECTURE.md)。

## 验证

```bash
go test ./...
gofmt -w .
go vet ./...
```

## 依赖

- PostgreSQL 15
- Redis
- Go 1.21+

## 更新历史

| 时间 | 内容 |
|---|---|
| 2026-06-29 | 数据库资产全面集中：184 生产库逐对象 SQL 导出（933 个独立文件），统一迁移到 `deploy/sql/` 目录；新增 `split_pg_dump.py` 自动同步工具 |
| 2026-06-29 | 文档精简：根目录精简到 4 个文档（README / ARCHITECTURE / CHANGELOG / DEPLOYMENT），删除 ~150 详细过程文档，敏感信息脱敏 |
| 2026-06-29 | 在 README 中加入本批提交特性总结与更新历史 |

详细变更见 [CHANGELOG.md](./CHANGELOG.md)；架构说明见 [ARCHITECTURE.md](./ARCHITECTURE.md)。
