// landing.ts — Landing page copy for the public (logged-out) home view.
// Mirrors the props that LandingView passes to ServiceLandingPage plus the
// extra "Roadmap" section that lives directly in LandingView's template.
//
// Keys use camelCase nested objects so vue-i18n's `t()` interpolation and
// `t('landing.features.X.title', { ... })` substitution both work.
export default {
  kicker: 'Enterprise AI & Agent Gateway',
  title: 'Kaixuan Enterprise AI & Agent Gateway',
  subtitle:
    'The unified gateway from LLM proxy to agent orchestration. One entry point for every LLM — intelligent routing, safety shields, cache-driven cost control, full-chain audit. Every AI call is observable, controllable, and billable.',
  heroPoints: [
    'Smart Routing',
    'Call Safety',
    'Cache Cost-down',
    'Agent Ready',
    'Full-chain Audit',
    'MaaS Billing',
  ],
  features: {
    smartRouting: {
      title: 'Smart Routing & Credential Pool',
      description:
        'Auto-selects by tenant, model, and task type. Multi-credential fingerprint pool plus adaptive probing — sub-second failover, near-zero ban rate.',
    },
    safety: {
      title: 'Call Safety Shield',
      description:
        'LLM-as-judge prompt-injection detection (v1 observable mode) and sensitive-data masking planning — enterprise-grade compliance defense.',
      badge: 'beta',
    },
    cache: {
      title: 'Cache Alignment & Cost-down',
      description:
        'Prompt prefix stabilization plus semantic caching maximize KV-cache hit rate and reduce token compute cost.',
    },
    agent: {
      title: 'Agent & MCP Gateway',
      description:
        'Agent registry, A2A protocol, MCP tool hosting and protocol conversion — evolve from an LLM proxy to the agent orchestration entry point.',
      badge: 'Coming soon',
    },
    observability: {
      title: 'Full-chain Observability',
      description:
        'Request logs, routing-decision audit, OpenTelemetry tracing, SIEM/CEF event export — ready for MLPS 2.0 and GDPR.',
    },
    billing: {
      title: 'MaaS Billing System',
      description:
        'Plans + credits + three-pool wallet (subscription / credit / top-up) — full self-service commercialization loop for tenants.',
    },
    multiProtocol: {
      title: 'Multi-protocol Compatibility',
      description:
        'OpenAI Chat / Anthropic Messages / Responses — three inbound formats normalized, seamless integration of Chinese and global models.',
    },
    multiTenant: {
      title: 'Multi-tenant Isolation',
      description:
        'PostgreSQL RLS row-level security + 43-round audit L1=0, zero cross-tenant data leakage, per-tenant policy and quota.',
    },
  },
  advantagesTitle: 'Differentiated Advantages',
  advantagesSubtitle: 'What global vendors cannot offer',
  advantages: {
    local: {
      title: 'China Localization',
      description: 'Full Chinese UI, domestic-model priority, Alipay / WeChat Pay, MLPS-compliant templates',
    },
    private: {
      title: 'Private Deployment',
      description: 'Fully on-prem, data never leaves the enterprise, k3s + Docker dual modes, zero external dependencies',
    },
    antiBan: {
      title: 'Anti-ban System',
      description: '50+ UA rotation + utls TLS fingerprint pool + 11 browser profiles + 5-minute auto rotation',
    },
    perf: {
      title: 'Go High-performance Dataplane',
      description: 'Native Go, 40MB lightweight image, 200 concurrent P99 < 500ms, stable SSE streaming relay',
    },
  },
  footer: 'Kaixuan LLM Gateway · [GATEWAY_DOMAIN] · Private deployment · China localization',
  ariaPoints: 'Highlight points',
  roadmap: {
    title: 'Product Evolution Roadmap',
    subtitle: 'From LLM dataplane to enterprise Agent gateway — built continuously',
    v31: {
      phase: 'v3.1 · 2026 Q3',
      title: 'API Hub Asset Center + MCP Tool Hosting',
      description:
        'Unified registration of LLM endpoints, MCP services, and Agents. Developer self-service discovery and reuse.',
    },
    v32: {
      phase: 'v3.2 · 2026 Q4',
      title: 'Safety Shield GA + SIEM Integration + SpecBoost',
      description:
        'Prompt-injection blocking, sensitive-data masking, smart API description enrichment to improve Function Calling accuracy.',
    },
    v40: {
      phase: 'v4.0 · 2027 Q1',
      title: 'Agent Registry + A2A Protocol Gateway',
      description:
        'Cross-agent task delegation and orchestration, OpenClaw and business Agents unified entry.',
    },
    v50: {
      phase: 'v5.0 · 2027 Q3',
      title: 'Industry Solutions GA',
      description:
        'Customer service, HR, sales, logistics industry templates — out-of-the-box agent solutions.',
    },
  },
}
