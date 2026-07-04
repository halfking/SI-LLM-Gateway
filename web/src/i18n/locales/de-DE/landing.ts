// Auto-translated draft (de-DE) · 2026-07-02 · please review
// landing.ts — Landing page copy for the public (logged-out) home view.
// Mirrors the props that LandingView passes to ServiceLandingPage plus the
// extra "Roadmap" section that lives directly in LandingView's template.
//
// Keys use camelCase nested objects so vue-i18n's `t()` interpolation and
// `t('landing.features.X.title', { ... })` substitution both work.
export default {
  kicker: 'Open Core · China-Lokalisierung · Enterprise Grade',
  title: 'LLM Gateway — Open-Core-AI-Gateway für globale Märkte',
  subtitle: [
    'Das einzige AI-Gateway, das Open Core mit umfassender China-Lokalisierung vereint — für globale Unternehmen.',
    'Enterprise-Governance, globaler LLM-Zugang, Compliance und Datensouveränität — vollständig Open Core.',
  ],
  featuresTitle: 'Kernfunktionen',
  featuresSubtitle: 'Deckt die gesamte Kette vom Zugang bis zum Betrieb ab',
  heroPoints: [
    'Open Core · Apache 2.0',
    'China-Lokalisierung · MLPS 2.0',
    'Intelligentes Routing',
    'Aufrufsicherheit',
    'Cache-Kostenreduzierung',
    'Agent-bereit',
  ],
  features: {
    smartRouting: {
      title: 'Intelligentes Routing & Anmeldedaten-Pool',
      description:
        'Automatische Auswahl nach Mandant, Modell und Aufgabentyp. Multi-Anmeldedaten-Fingerprint-Pool plus adaptive Prüfung — Failover unter einer Sekunde, nahezu null Sperrungen.',
    },
    safety: {
      title: 'Aufruf-Sicherheits-Schild',
      description:
        'LLM-as-judge Prompt-Injection-Erkennung (v1 beobachtbarer Modus) und Planung zur Maskierung sensibler Daten — Compliance-Verteidigung auf Unternehmensniveau.',
      badge: 'beta',
    },
    cache: {
      title: 'Cache-Ausrichtung & Kostensenkung',
      description:
        'Stabilisierung des Prompt-Präfixes plus semantisches Caching maximieren die KV-Cache-Trefferrate und reduzieren die Token-Rechenkosten.',
    },
    agent: {
      title: 'Agent- & MCP-Gateway',
      description:
        'Agent-Registry, A2A-Protokoll, MCP-Tool-Hosting und Protokollkonvertierung — entwickeln Sie sich vom LLM-Proxy zum Agent-Orchestrierungs-Einstiegspunkt.',
      badge: 'Demnächst verfügbar',
    },
    observability: {
      title: 'Vollständige Beobachtbarkeit',
      description:
        'Anfrage-Logs, Routing-Entscheidungs-Audit, OpenTelemetry-Tracing, SIEM/CEF-Ereignisexport — bereit für MLPS 2.0 und DSGVO.',
    },
    billing: {
      title: 'MaaS-Abrechnungssystem',
      description:
        'Tarife + Credits + Drei-Pool-Wallet (Abonnement / Guthaben / Aufladung) — kompletter Self-Service-Kommerzialisierungs-Loop für Mandanten.',
    },
    multiProtocol: {
      title: 'Multi-Protokoll-Kompatibilität',
      description:
        'OpenAI Chat / Anthropic Messages / Responses — drei eingehende Formate normalisiert, nahtlose Integration chinesischer und globaler Modelle.',
    },
    multiTenant: {
      title: 'Mandanten-Isolation',
      description:
        'PostgreSQL RLS-Zeilenebene-Sicherheit + 43-Runden-Audit L1=0, null mandantenübergreifender Datenverlust, pro-Mandant-Richtlinie und -Kontingent.',
    },
  },
  advantagesTitle: 'Warum LLM Gateway',
  advantagesSubtitle: 'Entwickelt für globale Unternehmen mit China-Anforderungen',
  advantages: {
    local: {
      title: 'Umfassende China-Lokalisierung',
      description: 'Vollständige chinesische Benutzeroberfläche, Priorität für chinesische Open-Source-LLMs, Alipay / WeChat Pay, MLPS 2.0-konforme Vorlagen, Bereitstellung in chinesischen Clouds'
    },
    private: {
      title: 'Private Bereitstellung',
      description: 'Vollständig On-Premise, Daten verlassen das Unternehmen nicht, k3s + Docker Dual-Modus, null externe Abhängigkeiten',
    },
    antiBan: {
      title: 'Anti-Sperr-System',
      description: '50+ UA-Rotation + utls TLS-Fingerprint-Pool + 11 Browser-Profile + 5-Minuten-Autorotation',
    },
    perf: {
      title: 'Go-Hochleistungs-Datenebene',
      description: 'Natives Go, 40 MB leichtgewichtiges Image, 200 gleichzeitig P99 < 500 ms, stabiles SSE-Streaming-Relais',
    },
  },
  footer: 'LLM Gateway · [GATEWAY_DOMAIN] · Open Core · China-Lokalisierung · Private Bereitstellung',
  ariaPoints: 'Highlights',
  roadmap: {
    title: 'Produktentwicklungs-Roadmap',
    subtitle: 'Von der LLM-Datenebene zum Enterprise-Agent-Gateway — kontinuierlich aufgebaut',
    v31: {
      phase: 'v3.1 · 2026 Q3',
      title: 'API-Hub-Asset-Center + MCP-Tool-Hosting',
      description:
        'Einheitliche Registrierung von LLM-Endpunkten, MCP-Diensten und Agenten. Self-Service-Entdeckung und -Wiederverwendung für Entwickler.',
    },
    v32: {
      phase: 'v3.2 · 2026 Q4',
      title: 'Sicherheits-Schild GA + SIEM-Integration + SpecBoost',
      description:
        'Prompt-Injection-Blockierung, Maskierung sensibler Daten, intelligente API-Beschreibungs-Anreicherung zur Verbesserung der Function-Calling-Genauigkeit.',
    },
    v40: {
      phase: 'v4.0 · 2027 Q1',
      title: 'Agent-Registry + A2A-Protokoll-Gateway',
      description:
        'Mandantenübergreifende Aufgabendelegation und -Orchestrierung, einheitlicher Einstieg für OpenClaw und Geschäfts-Agenten.',
    },
    v50: {
      phase: 'v5.0 · 2027 Q3',
      title: 'Branchenlösungen GA',
      description:
        'Kundenservice-, HR-, Vertriebs- und Logistik-Branchenvorlagen — sofort einsatzbereite Agent-Lösungen.',
    },
  },
}