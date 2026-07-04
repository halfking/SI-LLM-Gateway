// Auto-translated draft (fr-FR) · 2026-07-02 · please review
// landing.ts — Landing page copy for the public (logged-out) home view.
// Mirrors the props that LandingView passes to ServiceLandingPage plus the
// extra "Roadmap" section that lives directly in LandingView's template.
//
// Keys use camelCase nested objects so vue-i18n's `t()` interpolation and
// `t('landing.features.X.title', { ... })` substitution both work.
export default {
  kicker: 'Open Core · Localisation Chine · Enterprise Grade',
  title: 'LLM Gateway — Passerelle IA Open Core pour les marchés mondiaux',
  subtitle: [
    'La seule passerelle IA alliant open core et localisation Chine profonde — pour les entreprises mondiales.',
    'Gouvernance d\'entreprise, accès LLM global, conformité et souveraineté des données — entièrement open core.',
  ],
  featuresTitle: 'Capacités clés',
  featuresSubtitle: 'Couvre toute la chaîne, de l\'accès à l\'exploitation',
  heroPoints: [
    'Open Core · Apache 2.0',
    'Localisation Chine · MLPS 2.0',
    'Routage intelligent',
    'Sécurité des appels',
    'Réduction des coûts par cache',
    'Prêt pour les agents',
  ],
  features: {
    smartRouting: {
      title: 'Routage intelligent & pool d\'identifiants',
      description:
        'Sélection automatique par locataire, modèle et type de tâche. Pool multi-identifiants à empreintes plus sondage adaptatif — basculement en moins d\'une seconde, taux de bannissement proche de zéro.',
    },
    safety: {
      title: 'Bouclier de sécurité des appels',
      description:
        'Détection d\'injection de prompt LLM-as-judge (v1 mode observable) et planification du masquage des données sensibles — défense de conformité de niveau entreprise.',
      badge: 'beta',
    },
    cache: {
      title: 'Alignement du cache & réduction des coûts',
      description:
        'Stabilisation du préfixe du prompt plus mise en cache sémantique pour maximiser le taux de succès du KV-cache et réduire le coût de calcul des tokens.',
    },
    agent: {
      title: 'Passerelle Agent & MCP',
      description:
        'Registre d\'agents, protocole A2A, hébergement d\'outils MCP et conversion de protocole — évoluez d\'un proxy LLM au point d\'entrée d\'orchestration d\'agents.',
      badge: 'Bientôt disponible',
    },
    observability: {
      title: 'Observabilité de bout en bout',
      description:
        'Journaux de requêtes, audit des décisions de routage, traçage OpenTelemetry, export d\'événements SIEM/CEF — prêt pour MLPS 2.0 et RGPD.',
    },
    billing: {
      title: 'Système de facturation MaaS',
      description:
        'Forfaits + crédits + portefeuille à trois pools (abonnement / crédit / recharge) — boucle complète de commercialisation en libre-service pour les locataires.',
    },
    multiProtocol: {
      title: 'Compatibilité multi-protocoles',
      description:
        'OpenAI Chat / Anthropic Messages / Responses — trois formats entrants normalisés, intégration transparente des modèles chinois et mondiaux.',
    },
    multiTenant: {
      title: 'Isolation multi-locataires',
      description:
        'Sécurité au niveau des lignes RLS PostgreSQL + audit de 43 tours L1=0, zéro fuite de données entre locataires, politique et quota par locataire.',
    },
  },
  advantagesTitle: 'Pourquoi LLM Gateway',
  advantagesSubtitle: 'Conçu pour les entreprises mondiales ayant des besoins en Chine',
  advantages: {
    local: {
      title: 'Localisation Chine approfondie',
      description: 'Interface entièrement en chinois, priorité aux LLM open source chinois, Alipay / WeChat Pay, modèles conformes MLPS 2.0, déploiement sur cloud chinois'
    },
    private: {
      title: 'Déploiement privé',
      description: 'Entièrement sur site, les données ne quittent jamais l\'entreprise, double mode k3s + Docker, zéro dépendance externe',
    },
    antiBan: {
      title: 'Système anti-bannissement',
      description: 'Rotation de 50+ UA + pool d\'empreintes TLS utls + 11 profils de navigateur + rotation automatique toutes les 5 minutes',
    },
    perf: {
      title: 'Plan de données Go haute performance',
      description: 'Go natif, image légère de 40 Mo, 200 simultanés P99 < 500 ms, relais de streaming SSE stable',
    },
  },
  footer: 'LLM Gateway · [GATEWAY_DOMAIN] · Open Core · Localisation Chine · Déploiement privé',
  ariaPoints: 'Points forts',
  roadmap: {
    title: 'Feuille de route produit',
    subtitle: 'Du plan de données LLM à la passerelle Agent entreprise — construit en continu',
    v31: {
      phase: 'v3.1 · 2026 Q3',
      title: 'Centre de ressources API Hub + hébergement d\'outils MCP',
      description:
        'Enregistrement unifié des points d\'accès LLM, des services MCP et des agents. Découverte et réutilisation en libre-service pour les développeurs.',
    },
    v32: {
      phase: 'v3.2 · 2026 Q4',
      title: 'Bouclier de sécurité GA + intégration SIEM + SpecBoost',
      description:
        'Blocage des injections de prompt, masquage des données sensibles, enrichissement intelligent des descriptions API pour améliorer la précision du Function Calling.',
    },
    v40: {
      phase: 'v4.0 · 2027 Q1',
      title: 'Registre d\'agents + passerelle protocole A2A',
      description:
        'Délégation et orchestration de tâches inter-agents, point d\'entrée unifié pour OpenClaw et les agents métier.',
    },
    v50: {
      phase: 'v5.0 · 2027 Q3',
      title: 'Solutions sectorielles GA',
      description:
        'Modèles sectoriels pour le service client, les RH, les ventes et la logistique — solutions d\'agents prêtes à l\'emploi.',
    },
  },
}