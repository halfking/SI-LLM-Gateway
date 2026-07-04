// landing.ts — 落地页文案（未登录首页）。对应 LandingView 传给 ServiceLandingPage 的 props，
// 以及 LandingView 模板内自带的"路线图"区块。
//
// 使用 camelCase 嵌套对象，便于 vue-i18n 的 t() 插值与 t('landing.features.X.title', {...}) 替换。
export default {
  kicker: 'AI-Native · 企业治理',
  title: 'AI-Native 组织核心网关',
  subtitle: [
    '让 AI 成为组织的原生能力。',
    '核心开源 + 企业增强 + Vibe Coding 治理 + 会话资产化。',
  ],
  featuresTitle: '核心能力',
  featuresSubtitle: '覆盖从接入到运营的关键环节',
  heroPoints: [
    '企业级 AI 入口',
    'Vibe Coding 治理',
    'AI 会话资产化',
    '企业知识沉淀',
    '数据安全护盾',
    '完全私有部署',
  ],
  features: {
    smartRouting: {
      title: '企业级 AI 入口',
      description:
        '1045 Offer / 410 模型 / 100% 覆盖。统一接入全球各类大模型与 AI 工具，智能路由 + 粘性绑定，让企业的每一次 AI 调用可控、可观测、可计费、可治理。',
    },
    safety: {
      title: 'Vibe Coding 治理',
      description:
        '代码质量 +35% · 安全漏洞 -78% · 技术债 -60%。AI 辅助编码全流程治理，从提示词到代码输出的完整质量保障体系。',
    },
    cache: {
      title: 'AI 会话资产化',
      description: '13,000+ 会话已沉淀 · 新人上手 -40%。将每一次 AI 对话转化为可检索、可复用的企业知识资产，跨团队共享智慧。',
    },
    agent: {
      title: '企业知识沉淀',
      description: '知识自动生长 · 跨代传承。大模型会变，Agent 会变，但企业记忆不变。构建不依赖于特定工具的知识底座。',
    },
    observability: {
      title: '数据安全护盾',
      description: '注入拦截 98% · 合规风险 0。LLM-as-judge 提示词注入检测、敏感数据脱敏、SIEM/SOAR 对接，等保 2.0 与 GDPR 就绪。',
    },
    billing: {
      title: '多凭据指纹池 + 抗封号',
      description: '50+ UA · 35 lang · 11 utls · 5min rotation。自适应探测 + 故障秒级切换，封号率趋零，保障服务连续性。',
    },
    multiProtocol: {
      title: '完全私有部署',
      description: '184 k3s + 71 docker · 10 分钟安装。数据不出企业，零外部依赖，开源架构与等保合规要求。',
    },
    multiTenant: {
      title: '企业级管理 + MaaS',
      description: '套餐 + 积分 + 加油包 · 比 SaaS 便宜 60%+。完整的商业化闭环，多租户隔离，PostgreSQL RLS 行级安全 L1=0。',
    },
  },
  advantagesTitle: '差异化优势',
  advantagesSubtitle: '海外厂商给不了的能力',
  advantages: {
    openSource: {
      title: '核心开源',
      description: 'Open Core 开源核心 · Apache 2.0 友好许可 · 全球开发者共建 · 透明可审计',
    },
    private: { title: '私有化部署', description: '完全私有部署，数据不出企业，k3s + Docker 双形态，零外部依赖' },
    antiBan: { title: '抗封号体系', description: '50+ UA 轮换 + utls TLS 指纹池 + 11 浏览器 profile + 5 分钟自动轮换' },
    perf: { title: 'Go 高性能数据面', description: '原生 Go 实现，40MB 轻量镜像，200 并发 P99 < 500ms，SSE 流式稳定中继' },
  },
  footer: '开轩 LLM Gateway · [GATEWAY_DOMAIN] · 私有部署 · 核心开源',
  ariaPoints: '核心亮点',
  roadmap: {
    title: '产品演进路线',
    subtitle: '从 LLM 数据面到企业 Agent 网关，持续构建',
    v31: {
      phase: 'Step 1',
      title: 'API Hub 资产中心 + MCP 工具托管',
      description: '统一登记 LLM 端点、MCP 服务与 Agent，开发者自助发现与复用。凭据 SLA 保障 + 语义缓存 API。',
    },
    v32: {
      phase: 'Step 2',
      title: 'Model Armor 安全护盾 + SIEM 对接',
      description: '提示词注入拦截 GA、敏感数据脱敏 (SDP)、SIEM/SOAR 对接，SpecBoost 智能富集提升 Function Calling 准确率。',
    },
    v40: {
      phase: 'Step 3',
      title: 'Agent Registry + A2A 协议网关',
      description: '跨智能体任务委派与编排，OpenClaw 与业务 Agent 统一接入。资产自动发现 + 合规 GA + SpecBoost GA。',
    },
    v50: {
      phase: 'Step 4',
      title: '行业方案 GA + 外部客户',
      description: '客服、HR、销售、物流四大行业模板，开箱即用的智能体方案。外部 2 客户 + 文档体系 + 计费收费上线。',
    },
  },
}
