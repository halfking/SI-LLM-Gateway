# SI-LLM-Gateway（超级智能大模型网关 / AI-Native 组织核心网关）

[简体中文](README.zh-CN.md) | [English](README.en-US.md) | [日本語](README.ja-JP.md) | [繁體中文](README.zh-TW.md) | [Español](README.es-ES.md) | [Français](README.fr-FR.md) | [Deutsch](README.de-DE.md) | [العربية](README.ar-SA.md) | [한국어](README.ko-KR.md)

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



## 🎯 当前能力

| 能力维度 | 实现 |
|----------|------|
| **协议层** | OpenAI / Anthropic / Responses 兼容 + SSE 流式中继 + IR 中间表示 |
| **路由层** | 智能候选路由 + 粘性会话 + 自动路由（cost/quality 策略）+ 任务 × 模型热力图 + Sankey 路由流向 |
| **多租户** | 身份隧道（virtual IP/MAC/ClientID）+ 凭据池 + 38+ 表 RLS + 43 轮审计 L1=0 |
| **流量治理** | Token 限流 + 语义缓存 + 提示词压缩 + 滑窗算法 + Circuit Breaker（7 类错误状态机） |
| **审计** | 🔨 全链路审计 + DLQ + 磁盘回退 + OTel + Prometheus **（即将推出）** |
| **凭据** | 多凭据 + 指纹池（50+ UA × 35 lang × 11 utls）+ 自适应探测 + 手动 disable + 凭据 SLA |
| **会话资产化** | 🔨 会话总结 → Memora L1 → 企业记忆 **（即将推出）** |
| **部署** | 一键部署 + 多机热备（支持 Docker / K8s / 裸机多种部署方式） |

详细架构见 [`ARCHITECTURE.md`](ARCHITECTURE.md)。

---

## 🔀 产品下一步目标

```
[当前]   v2.3 企业级 LLM 网关
           - 智能路由、多凭据池、流量治理、多租户隔离
           ↓
[Step-1] AI Gateway Pro（资产中心）
           - API Hub 资产中心
           - MCP 工具网关托管
           - 凭据 SLA 增强
           - 语义缓存 API
           ↓
[Step-2] AI Gateway Secure（安全增强）
           - Model Armor（提示词注入防护）
           - SDP 敏感数据脱敏
           - SIEM/SOAR 对接
           - SpecBoost 智能富集（初版）
           ↓
[Step-3] Agentic Gateway（编排层）
           - Agent Registry（Agent 注册中心）
           - A2A 跨 Agent 通信协议
           - 编排层 PoC
           ↓
[Step-4] Enterprise Edition（企业完整版）
           - 资产自动发现
           - 合规审计 GA
           - SpecBoost GA
           - 行业解决方案
```

详细路线图见 [`docs/PRODUCT_ROADMAP.md`](docs/PRODUCT_ROADMAP.md)。

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

## 📞 演示地址

**网关示例地址**：https://llm.kxpms.cn

---

## 📄 License

[Apache License 2.0](LICENSE)
