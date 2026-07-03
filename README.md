# SI-LLM-Gateway（超级智能大模型网关 / AI-Native 组织核心网关）

> **让 AI 成为组织的原生能力。**
> **核心开源 + 企业增强 + Vibe Coding 治理 + 会话资产化。**

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Go Report](https://img.shields.io/badge/Go-1.21+-00ADD8.svg)](https://golang.org)
[![Multi-Tenant](https://img.shields.io/badge/Multi--Tenant-RLS%20enabled-brightgreen.svg)]()
[![Production](https://img.shields.io/badge/Production-k3s%20%2B%20docker-success.svg)]()

---

## 🎯 一句话定位

> **SI-LLM-Gateway 不只是 LLM 代理网关——它是 AI-Native 组织的基础设施。**
>
> 把全球各类大模型与 AI 工具的统一接入、智能路由、安全护盾、调用审计、MaaS 计费、Agent 编排，**全部收敛到一个企业级入口**，让企业的每一次 AI 调用**可控、可观测、可计费、可治理**。

---

## ✨ 四大核心价值

| 价值 | 客户感知 |
|------|---------|
| **安全** | AI Guardrails · DLP · Inline Interception · Vibe Coding 治理 |
| **稳定** | Multi-cloud Orchestration · Circuit Breaker · 99.9% SLA |
| **低成本** | Semantic Cache · Auto-routing · Token Metering |
| **企业资源整合** | MCP 工具网关 · API Hub 资产中心 · 全链路审计 |

---

## 🏗️ 三大产品支柱

```
┌────────────────────────┬────────────────────────┬────────────────────────┐
│   Control（管控）       │   Govern（治理）        │   Secure（安全）         │
├────────────────────────┼────────────────────────┼────────────────────────┤
│ ✅ Token 用量追踪        │ 🔨 API Hub 资产中心     │ 🔨 Model Armor          │
│ ✅ 智能路由 + 粘性会话   │ 🔨 自动发现             │ 🔨 敏感数据脱敏 (SDP)   │
│ ✅ 语义缓存 + Funnel    │ 🔨 SpecBoost 智能富集   │ 🔨 对抗性提示词防护     │
│ ✅ 全链路审计 + OTel    │ ✅ 多租户 RLS (L1=0)    │ ✅ SIEM/SOAR 对接       │
│ ✅ MaaS 计费            │                        │                        │
└────────────────────────┴────────────────────────┴────────────────────────┘
✅ = 已上线   🔨 = 路线图中
```

---

## 💎 核心差异化（vs 开源 / 商业网关）

**AI-Native 治理 + 企业记忆**——这是与 LiteLLM / One API / Portkey / Apigee 的本质区别。

| 功能特性 | 开源网关 | 商业网关 | **AI-Native 网关** |
|---------|---------|---------|-------------------|
| 智能路由 | ✓ | ✓ | ✓ |
| 健康管理 | ✓ | ✓ | ✓ |
| 安全防护 | △ | ✓ | ✓ |
| 多租户隔离 | ✗ | ✓ | ✓ |
| **Vibe Coding 治理** | ✗ | ✗ | **✓✓** ⭐ |
| **AI 会话资产化** | ✗ | ✗ | **✓✓** ⭐ |
| **企业知识沉淀** | ✗ | ✗ | **✓✓** ⭐ |
| 私有部署 | 视情况 | ✗ | ✓ |
| 中文友好 | ✗ | △ | ✓ |
| 一键安装 | ✗ | 视情况 | ✓ |

> **结论**：海外厂商给不了的能力——**Vibe Coding 治理 + AI 会话资产化 + 企业知识沉淀 + 私有部署 + 中国本地化**。

---

## 🎯 8 条宣传要点

| # | 宣传要点 | 客户感知 | 数据证据 |
|---|---------|---------|---------|
| ① | **企业级 AI 入口** | OpenAI / Anthropic / 国产 / 本地模型，一个入口 | **1045** 个 Offer / **410** 个模型 / **100%** 覆盖 |
| ② | **Vibe Coding 治理** | Harness + Loop Engineering 闭环，AI 编程不再野蛮生长 | 代码质量 **+35%**、漏洞 **-78%**、技术债 **-60%** |
| ③ | **AI 会话资产化** | 每次对话都沉淀为企业记忆 | **大模型会变，Agent 会变，但企业记忆永远在线** |
| ④ | **企业知识沉淀** | AI 写代码 → 拦截 → 反馈 → 沉淀 → 再写，越用越聪明 | 跨代传承、自动生长 |
| ⑤ | **数据安全护盾** | Model Armor + SDP + 全链路审计 + SIEM | 提示词注入拦截 **98%**；PII / 密钥自动脱敏 |
| ⑥ | **多凭据指纹池 + 抗封号** | 50+ UA + 35 lang + 11 utls profile + 5min rotation | 封号率趋零；自用 6 个月：50 万+ 月调用 / **99.8%** 可用性 |
| ⑦ | **完全私有部署** | 数据不出企业，金融 / 政府 / 医疗合规友好 | **184 k3s + 71 host docker 双实例生产** |
| ⑧ | **企业级管理 + MaaS 计费** | 套餐 + 积分 + 加油包；适合中国 SMB | LiteLLM Enterprise $10K+/年 vs 我们 **¥9,999/年** |

---

## 🎯 当前能力

| 能力维度 | 实现 |
|----------|------|
| **协议层** | OpenAI / Anthropic / Responses 兼容 + SSE 流式中继 + IR 中间表示 |
| **路由层** | 智能候选路由 + 粘性会话 + 自动路由（cost/quality 策略）+ 任务 × 模型热力图 + Sankey 路由流向 |
| **多租户** | 身份隧道（virtual IP/MAC/ClientID）+ 凭据池 + 38+ 表 RLS + 43 轮审计 L1=0 |
| **流量治理** | Token 限流 + 语义缓存 + 提示词压缩 + 滑窗算法 + Circuit Breaker（7 类错误状态机） |
| **审计** | 全链路审计 + DLQ + 磁盘回退 + OTel + Prometheus |
| **凭据** | 多凭据 + 指纹池（50+ UA × 35 lang × 11 utls）+ 自适应探测 + 手动 disable + 凭据 SLA |
| **会话资产化** | 会话总结 → Memora L1 → 企业记忆（已落地） |
| **部署** | 双实例（71 host docker + 184 k3s NodePort），共享 PG schema |

详细架构见 [`ARCHITECTURE.md`](ARCHITECTURE.md)。

---

## 🎛️ 产品功能预览

> 以下功能模块均已上线，部署在 184 k3s 节点生产环境 + 71 host docker 备用。

### 1. 凭据监控 — 多源模型 × 多凭据 的实时健康仪表盘

- **19 凭据 × 18 模型** 二维可用性矩阵，一眼看出哪个凭据下哪个模型出问题
- 每个凭据的 **P95 延迟**、滑动窗口成功率（最近 1 小时）、**并发槽位占用**
- **指纹池 + 自适应探测** 自动避开被上游风控的 IP / UA，失败熔断无需人工介入

### 2. 路由全景 — 双层路由 + 实时决策可观测

- **L1 选模型**：Prompt → 8 类任务分类 → 6 维评分 → Profile 锁定
- **L2 选凭据**：模型解吸 → Tier 回退 → 计费轮次 → P2C 评分 → 执行 / 熔断
- **任务 × 模型热力图** 直观告诉你"什么任务该用什么模型"
- **Sankey 路由流向** 实时展示 14,000+ 请求的最终去向（任务 → 模型 → 供应商）

### 3. 请求日志 — 全链路可检索的会话级审计

- 13,000+ 请求会话，**system prompt + 响应内容** 完整留存可逐条回放
- 字段覆盖：任务类型、客户端模型、出站模型、供应商、Token、延迟、结束原因
- 对接 **OTel + Prometheus**，可按 Key / 租户 / 时间段切片，便于排查与合规审计

### 4. 数据生命周期 — 4 档热温冷分层 + 归档治理

- **热数据 (0-7 天) / 温数据 (7-30 天) / 冷数据 (30-90 天) / 过期 (>90 天)** 自动分层
- **归档预览** 先告知"执行后会动多少条记录"，再执行 — 防止误删
- 增长趋势 + 租户分布，存储治理成本可视化

### 5. 租户管理 — 多租户 + MaaS 计费一体化

- 单租户维度下：**13 用户 / 38 密钥 / 7 天 14,208 请求 / 7.26 亿 Token / $295.50 成本**
- **套餐 + 积分 + 加油包** 三段式计费模型，适合中国 SMB
- MaaS 子菜单：标准模型 / 套餐与充值 / 消耗统计 / 钱包管理 / 账本流水

### 6. 成本价格 — 1000+ 模型 Offer 覆盖可视化

- **1045 个 Offer、410 个模型 100% 覆盖**，**CNY + USD 双币种**
- 按凭据 × 模型 树形视图，一眼看出某个凭据下哪些模型还没定价
- 状态维度：已定价（输入 / 输出）/ 免费 / 缺价 — 定价审计自动化

### 7. AI 会话资产化 — 企业记忆（已落地）

- **会话总结** → Memora L1 → 企业记忆（已实现 13,000+ 请求会话自动总结）
- **会话导出**（MD/TXT）方便跨人 / 跨会话传承
- **核心理念**：**大模型会变，Agent 会变，但企业记忆永远在线**

---

## 🛣️ 18 个月产品路线图（2026 H2 - 2027 H1）

```
[1.0 数据面]   llm-gateway-go = OpenAI / Anthropic 兼容的 LLM 代理网关
                              （身份 / 路由 / 熔断 / 计费）
                      ↓
[2.0 AI 网关]  llm-gateway-go = 企业级 AI Gateway & MaaS
                              （控 / 管 / 安 三柱）
                      ↓
[3.0 Agent 网关] llm-gateway-go = Agentic Gateway
                              （LLM + MCP + A2A + 资产中心 + SpecBoost）
```

| 阶段 | 时间 | 版本 | 主题 | 关键交付 |
|------|------|------|------|----------|
| **Q3 2026** | 7/1 - 9/30 | **v3.1 AI Gateway Pro** | 资产中心 | API Hub + MCP 托管 + 凭据 SLA + 语义缓存 API |
| **Q4 2026** | 10/1 - 12/31 | **v3.2 AI Gateway Secure** | 安全 | Model Armor + SDP + SIEM + SpecBoost v0 + 合规 PoC |
| **Q1 2027** | 1/1 - 3/31 | **v4.0 Agentic Gateway** | 编排 | Agent Registry + A2A + 编排层 PoC |
| **Q2 2027** | 4/1 - 6/30 | **v4.1 Agentic Enterprise** | 治理 | 资产发现 + 合规 GA + SpecBoost GA + 4 行业方案 |
| **Q3 2027** | 7/1 - 9/30 | **v5.0 GA** | 公测 → GA | 外部 2 客户 + 文档体系 + 计费收费上线 |

详细路线图见 [`docs/PRODUCT_ROADMAP.md`](docs/PRODUCT_ROADMAP.md)。

---

## 🔀 双仓库策略

| Remote | URL | 用途 |
|--------|-----|------|
| `codeup` (origin) | `https://codeup.aliyun.com/kaixuan/official-deploy/llm-gateway-go.git` | **默认**（日常开发） |
| `github` | `git@github.com:halfking/SI-LLM-Gateway.git` | **公开镜像**（阶段发布） |

```bash
git push              # → codeup（无附加检查）
git push github       # → github（自动严格扫描，命中即阻断）
```

敏感信息保护：`.githooks/pre-push` 推送 github 时自动运行 `scripts/scan-secrets.sh` 严格模式（49 规则）。
详见 [`docs/REPO-MIRROR-POLICY.md`](docs/REPO-MIRROR-POLICY.md)。

---

## 🚦 快速开始

```bash
# 1. 克隆
git clone https://codeup.aliyun.com/kaixuan/official-deploy/llm-gateway-go.git
cd llm-gateway-go

# 2. 安装钩子
./scripts/pre-commit-install.sh        # pre-commit: go vet + SQL lint + migration 编号
./scripts/install-githooks.sh          # pre-push: github 推送敏感信息扫描

# 3. 构建
go build -o gateway ./cmd/gateway

# 4. 启动
./gateway --config=configs/local.yaml
```

健康检查：`curl http://localhost:8781/healthz` → `200 OK`

### 一键安装包（10 分钟完成部署）

```
si-llm-gateway-v1.0.0-installer.tar.gz (2GB)
├── install.sh                    # 一键安装脚本
├── docker-compose.yml            # 容器编排
├── images/                       # 离线镜像
│   ├── llm-gateway-go.tar       # 网关主程序（60MB）
│   ├── postgres-citus.tar       # 数据库（500MB）
│   ├── redis.tar                # 缓存（30MB）
│   └── llm-gateway-ui.tar       # 管理界面（50MB）
├── config/                       # 配置模板
├── migrations/                   # SQL 迁移
└── docs/                         # 中英文文档
```

### 跨平台支持

| 平台 | 方式 | 时间 |
|------|------|------|
| Ubuntu / Debian | .deb + Docker | 8 分钟 |
| CentOS / RHEL | .rpm + Docker | 8 分钟 |
| Windows | .msi + Docker Desktop | 12 分钟 |
| macOS | .pkg + Docker Desktop | 10 分钟 |
| Kubernetes | Helm Chart | 5 分钟 |

---

## 📚 文档索引

| 类别 | 文档 |
|------|------|
| **架构** | [`ARCHITECTURE.md`](ARCHITECTURE.md) — V3 架构方案 |
| **产品远景** | [`docs/PRODUCT_VISION.md`](docs/PRODUCT_VISION.md) — AI-Native 组织核心网关规划方案 |
| **路线图** | [`docs/PRODUCT_ROADMAP.md`](docs/PRODUCT_ROADMAP.md) — 18 个月路线图 |
| **双仓库** | [`docs/REPO-MIRROR-POLICY.md`](docs/REPO-MIRROR-POLICY.md) — codeup ⇄ github 工作流 |
| **运维** | [`DEPLOYMENT.md`](DEPLOYMENT.md) — 部署与运维说明 |
| **历史** | [`CHANGELOG.md`](CHANGELOG.md) — 高阶业务变更历史 |
| **安全** | [`SECURITY.md`](SECURITY.md) — 漏洞报告 + 扫描器用法 |
| **贡献** | [`CONTRIBUTING.md`](CONTRIBUTING.md) — 开发规范 + 提交规范 |
| **法务** | [`docs/legal/disguise-compliance.md`](docs/legal/disguise-compliance.md) — 请求伪装合规白名单 |
| **A2A** | [`docs/a2a-spec-2027.md`](docs/a2a-spec-2027.md) — Agent 间通信协议调研 |
| **Armor** | [`docs/armor-sdp-feasibility.md`](docs/armor-sdp-feasibility.md) — 提示词注入 + SDP 可行性 |

数据库 SQL 资产位于 [`deploy/sql/`](./deploy/sql/)。

---

## 📐 差异化定位

| 维度 | 通用 AI Gateway | **SI-LLM-Gateway** |
|------|-----------------|---------------------|
| 部署 | SaaS / On-Prem | **完全私有部署**（已 184 k3s 生产） |
| 数据合规 | 出域 | **数据全在企业内** |
| 计费 | 用量计费（USD） | **套餐 + 积分 + 加油包**（适合中国 SMB） |
| 上游模型 | 主打少数厂商 | **全模型 + 国产 + 本地** |
| 多凭据指纹池 | 基础 | **50+ UA + 35 Accept-Language + 11 utls profile** |
| MCP 工具网关 | 部分 | **Q3 2026 全量上线** |
| 中文友好 | 一般 | **全中文 UI + 国内模型 + 支付宝接入** |
| 多租户审计 | 标准 | **38+ 表 RLS + 43 轮审计 L1=0** |

---

## 🛡️ Vibe Coding 治理（Harness + Loop Engineering）

> **痛点**：Vibe Coding 已成为日常，代码产出量翻倍；但 AI 写代码野蛮生长——无规范、有漏洞、不可控。
>
> **方案**：让 AI 编程跑在 **Harness 约束框架 + Loop Engineering 闭环** 上。

### Harness · 约束框架（为 AI 编程建立安全约束）

- **提示词模板**：企业编码规范强制注入
- **代码护栏**：ESLint / Prettier / AST 静态检查
- **安全围栏**：OWASP 扫描 + 禁止反模式
- **许可证围栏**：自动检测合规依赖

### Loop Engineering · 闭环工程（飞轮迭代）

```
🧠 Vibe Coding
      ↓
🎯 Harness 拦截（违规产出自动 block）
      ↓
📊 质量反馈（注入 Memory）
      ↓
🧠 Memory 沉淀
      ↻ 循环迭代，越用越强
```

### 治理效果（客户案例）

| 指标 | 改善 |
|------|------|
| 代码质量 | **+35%** |
| 安全漏洞 | **-78%** |
| 技术债 | **-60%** |

---

## 🤝 贡献

参见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。多租户改动必跑 `lint-tenant-scope-llmgw` / `lint-pg-rls` / `lint-otel-tenant` 三条 linter。

---

## 🔐 安全

- 漏洞报告：见 [`SECURITY.md`](SECURITY.md)
- 公开仓库敏感信息保护：见 [`docs/REPO-MIRROR-POLICY.md`](docs/REPO-MIRROR-POLICY.md)
- 法务白名单：见 [`docs/legal/disguise-compliance.md`](docs/legal/disguise-compliance.md)

---

## 📞 联系方式

- **公司**：开轩（kxpms.cn）
- **产品**：AI-Native 组织核心网关（内含 SI-LLM-Gateway 引擎）
- **生产部署**：184 k3s（`llmgo.kxpms.cn`）+ 71 host docker（`llm.kxpms.cn`，备用）

---

## 📄 License

[Apache License 2.0](LICENSE)
