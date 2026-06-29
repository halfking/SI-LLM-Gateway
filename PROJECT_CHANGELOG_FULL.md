# LLM Gateway 项目完整变更日志

> **仓库**: github.com:halfking/SI-LLM-Gateway (分支: github)
> **变更范围**: 自初始提交 `53604482` 至当前 HEAD `b65a7e94`
> **总提交数**: 1027 个提交
> **代码统计**: +277,600 行 / -242 行
> **生成日期**: 2026-06-28

---

## 📊 项目统计

| 指标 | 数值 |
|------|------|
| 总提交数 | 1027 |
| 文件变更 | 1096 个文件 |
| 新增代码 | +277,600 行 |
| 删除代码 | -242 行 |
| 初始提交 | `53604482` (first commit) |
| 最新提交 | `b65a7e94` (perf(providers): optimize page load speed by 97%) |

---

## 🏗️ 项目阶段里程碑

### Phase 0: 项目初始化
- **提交**: `53604482` - first commit
- **内容**: 基础项目结构，SSH配置，部署文档

### Phase 1: Memora Gateway 起步
- **提交**: `4437467e` - memora-gateway v1.0
- **内容**: Go 高性能内存网关 for AI agents
- **后续**: UMB (User Memory Bank) 集成

### Phase 2-3: Go 数据面核心
- **提交**: `719a347a` - Go数据面P0骨架
  - `cmd/gateway` - 网关入口
  - `identity` - 身份认证
  - `middleware/auth` - 认证中间件
  - `relay/chat` - 聊天中继
- **提交**: `c149c729` - Phase2-3
  - 连接池管理
  - 协议转换
  - 流式中继
  - 熔断器
  - 四层并发控制

### Phase 3: Python & Go 集成
- **提交**: `aef6e60b` - Python tool_use adapter + Go Phase 3 core wiring
- **流式处理**: keep-alive, first-byte timeout, StreamCapture

### Phase 4: 路由与解析
- **提交**: `de0e0b1e` - resolve包
  - 模型名解析
  - TTL缓存

### Phase 5: 审计日志
- **提交**: `f77b9555` - audit结构化审计日志管道

### Phase 6: 安全加固
- **提交**: `c2ac9f15` - Phase 2 hardening
  - AES-GCM keyring
  - Redis rate-limit
  - HMAC KeyInfo

---

## 📦 核心功能模块

### 1. 路由系统 (Autoroute)

#### Analytics Phase 2
| 阶段 | 提交 | 功能 |
|------|------|------|
| Phase 1 | `b51850af` | regex pattern layer 启发式分类器 |
| Phase 2 | `db89dad5` | TuningStore 运行时参数覆盖 |
| Phase 2 | `2fb8f7dc` | matrix/flow API + routing-v2 analytics tab |
| Phase 3 | `7fd873d4` | 隐式反馈信号计算 |
| Phase 4 | `bdb14812` | FeedbackAnalyzer 每日 worker |
| Phase 5 | `04a8bf57` | tuning feedback review endpoints |
| Phase 2b | `e55cc9fe` | decision replay, funnel, model-task-index UI |
| Phase 2c | `f1431c1f` | work_type 维度, decision modal, model alias |

#### 质量门控
- 多层质量降级策略
- `loadCandidatesDB` 多层降级包装
- `successRateThreshold` 参数传递

### 2. 凭据管理系统 (Credential)

#### 指纹槽位 (Fingerprint Slot)
| 功能 | 提交 | 描述 |
|------|------|------|
| 基础 | `55ac8bdc` | admin 重置凭据指纹槽 |
| 长期占用 | `98d49b9e` | 长期指纹占用稳定身份 |
| 自动调整 | `4132b8c8` | idle slot reclaim + auto fp_slot sizing |
| 过期机制 | `96832f01` | 30分钟自动过期 + single slot release |
| 可编辑 | `df786a86` | fp_slot_limit 编辑 + audit log |
| LRU | `d01c3b3a` | LRU 预占用 + 30min reclaim |
| 槽位扩容 | `6a6abb18` | DefaultLimit 5 → 20 |

#### 凭据监控
- 4-tab 详情页
- 6 个模型字段
- `manual_disabled` 控制
- Prometheus 指标

### 3. 可观测性 (Observability)

#### SIEM 集成
- **提交**: `914baeb9` - CEF formatter + FileSink (NOW-4, Phase 1)

#### 安全铠甲 (Security Armor)
- **提交**: `ecea00cc` - LLM-as-judge abstraction + Policy (NOW-2)

#### 遥测数据
- 自动请求标识 (`is_auto_request`)
- 每次尝试延迟记录
- 真实 `request_id` 健康追踪

### 4. 流式处理 (Streaming)

| 功能 | 提交 | 描述 |
|------|------|------|
| 基础流 | `79198886` | keep-alive, first-byte timeout, StreamCapture |
| 会话ID | `c353ce5f` | 可配置 session id aliases |
| 工具调用 | `70f6352b` | thinking signature field |
| 工具角色 | `9147dae9` | bidirectional tool role conversion |
| Opus 4 | `068d2a77` | chunk timeout detection |
| 关键修复 | `6f917f0b` | tool call index 一致性 |
| 关键修复 | `98d49b9e` | first chunk arguments field |

### 5. 前端 (Web)

| 功能 | 提交 | 描述 |
|------|------|------|
| 首页改版 | `1c64829c` | 企业 AI + Agent 网关定位 |
| 凭据详情 | `20b7c3ab` | 重构 + 模型tab左右布局 |
| V3.1 双层槽位 | `10f43f28` | 双层槽位信息卡片 |
| FpSlotVisualizer | `101874fc` | 槽位可视化组件 |

---

## 🔧 数据库架构

### Schema 发展
| 阶段 | 提交 | 内容 |
|------|------|------|
| Phase 1 | `2cef3625` | vendor_name, pricing fields |
| 工作类型 | `97a34406` | work_types PG + admin API |
| 路由增强 | `36b7e2f6` | 过滤器同步实际行为 |

### 分区策略
- **提交**: `4deebde9` - 完整分区策略实现

### 归档系统
- `request_logs_archive` 分层存储
- 按月分区
- columnar 存储优化

---

## 🐛 重要 Bug 修复

| 优先级 | 描述 | 提交 |
|--------|------|------|
| P0 | upstream hang hard-timeout | `9c614f44` |
| P0 | `request_logs` 重复记录 | `fc3e8bba` |
| P0 | tool call index 不一致 | `6f917f0b` |
| P0 | first chunk 无 arguments | `98d49b9e` |
| P1 | `model_offers` VIEW ALTER | `48e074df` |
| P1 | hypertable 列解析 | `de69f857` |
| P1 | 探针状态恢复 | `9176eb67` |
| P2 | LEFT JOIN vs CROSS JOIN | `821bc6d0` |
| P2 | 路由过滤器同步 | `36b7e2f6` |
| P2 | 模板 Invalid end tag | `4fe9a152` |

---

## 📈 性能优化

| 提交 | 描述 | 提升 |
|------|------|------|
| `b65a7e94` | providers page load | 97% |
| `6580350c` | Phase 4 stream split lazy | - |
| `545c9b20` | protocol conversion | 优化 |

---

## 🚀 部署改进

### 部署工具
- `deploy_p0_hotfix.sh` - P0 修复脚本
- `verify_p0_hotfix.sh` - 验证脚本
- `init-db.sh` - 数据库初始化

### 部署文档
- DEPLOYMENT_GUIDE.md
- DEPLOYMENT_READY.md
- DEPLOY_CHECKLIST.md

---

## 📁 SQL 文件清单

### Schema (deploy/sql/00_schema/)
```
001_base_tables.sql           - 基础表
002_providers_and_models.sql  - 提供商和模型
003_routing_tables.sql        - 路由表
004_tuning_and_work_types.sql  - 调优和工作类型
005_maas_billing.sql          - 计费
006_request_logs.sql         - 请求日志
007_archive_and_ledger.sql   - 归档和账本
008_tools_registry.sql       - 工具注册表
```

### Functions (deploy/sql/01_functions/)
```
functions.sql                 - 核心业务函数
```

### Seed Data (deploy/sql/02_seed_data/)
```
001_basic.sql                 - 基础数据
002_providers.sql            - 提供商数据
003_work_types.sql           - 工作类型数据
```

---

## 🔐 安全特性

- AES-GCM keyring 加密
- HMAC KeyInfo 签名
- Redis rate-limit 限流
- LLM-as-judge 内容审核
- Policy 抽象层

---

## 🧪 测试覆盖

- 单元测试覆盖核心模块
- E2E 生产测试套件 (`prod_e2e`)
- 150s 超时配置
- 流式捕获验证

---

## 📍 当前版本信息

| 项目 | 值 |
|------|-----|
| 当前分支 | github |
| 最新提交 | `b65a7e94` |
| 构建序列 | 707+ |
| 模块名 | llm-gateway-go-2 |

---

## 🔄 相关仓库

| 仓库 | URL | 分支 |
|------|-----|------|
| GitHub | github.com:halfking/SI-LLM-Gateway | github (主分支) |
| Codeup | codeup.aliyun.com/kaixuan/official-deploy/llm-gateway-go | github |

---

## 📞 支持与文档

- 完整部署指南: `DEPLOYMENT_GUIDE.md`
- 部署就绪检查: `DEPLOYMENT_READY.md`
- Bug 分析: `CRITICAL_BUG_ANALYSIS.md`
- P0 事件总结: `P0_INCIDENT_SUMMARY.md`

---

**文档版本**: V1.0
**生成时间**: 2026-06-28
**维护者**: LLM Gateway Team