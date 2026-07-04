// Auto-translated draft (es-ES) · 2026-07-02 · please review
// landing.ts — Página de aterrizaje pública.
export default {
  kicker: 'Open Core · Localización China · Enterprise Grade',
  title: 'LLM Gateway — Puerta de enlace IA Open Core para mercados globales',
  subtitle: [
    'La única puerta de enlace IA que combina open core con profunda localización china — para empresas globales.',
    'Gobernanza empresarial, acceso LLM global, cumplimiento y soberanía de datos — todo open core.',
  ],
  featuresTitle: 'Capacidades principales',
  featuresSubtitle: 'Cubriendo toda la cadena, desde el acceso hasta las operaciones',
  heroPoints: [
    'Open Core · Apache 2.0',
    'Localización China · MLPS 2.0',
    'Enrutamiento inteligente',
    'Seguridad de llamadas',
    'Reducción de costes por caché',
    'Listo para agentes',
  ],
  features: {
    smartRouting: {
      title: 'Enrutamiento inteligente y pool de credenciales',
      description:
        'Selecciona automáticamente por inquilino, modelo y tipo de tarea. Pool de huellas dactilares multi-credencial más sondeo adaptativo: conmutación en subsegundos, tasa de baneo cercana a cero.',
    },
    safety: {
      title: 'Escudo de seguridad de llamadas',
      description:
        'Detección de inyección de prompt con LLM-as-judge (modo observable v1) y planificación de enmascaramiento de datos sensibles: defensa de cumplimiento de nivel empresarial.',
      badge: 'beta',
    },
    cache: {
      title: 'Alineación de caché y reducción de costes',
      description:
        'Estabilización del prefijo del prompt y caché semántica que maximizan la tasa de acierto de KV-cache y reducen el coste computacional por tokens.',
    },
    agent: {
      title: 'Pasarela de agentes y MCP',
      description:
        'Registro de agentes, protocolo A2A, hosting de herramientas MCP y conversión de protocolos: del proxy LLM al punto de entrada de orquestación de agentes.',
      badge: 'Próximamente',
    },
    observability: {
      title: 'Observabilidad de extremo a extremo',
      description:
        'Registros de solicitudes, auditoría de decisiones de enrutamiento, trazado con OpenTelemetry, exportación de eventos SIEM/CEF — listo para MLPS 2.0 y GDPR.',
    },
    billing: {
      title: 'Sistema de facturación MaaS',
      description:
        'Planes + créditos + monedero de tres pools (suscripción / crédito / recarga): bucle completo de comercialización autoservicio para inquilinos.',
    },
    multiProtocol: {
      title: 'Compatibilidad multiprotocolo',
      description:
        'OpenAI Chat / Anthropic Messages / Responses — tres formatos entrantes normalizados, integración perfecta de modelos chinos y globales.',
    },
    multiTenant: {
      title: 'Aislamiento multi-inquilino',
      description:
        'Seguridad a nivel de fila (RLS) de PostgreSQL + auditoría de 43 rondas L1=0, cero fugas de datos entre inquilinos, política y cuota por inquilino.',
    },
  },
  advantagesTitle: 'Por qué LLM Gateway',
  advantagesSubtitle: 'Diseñado para empresas globales con necesidades en China',
  advantages: {
    local: {
      title: 'Localización china profunda',
      description: 'Interfaz completamente en chino, prioridad a LLM open source chinos, Alipay / WeChat Pay, plantillas compatibles con MLPS 2.0, despliegue en nubes chinas'
    },
    private: {
      title: 'Despliegue privado',
      description: 'Totalmente on-prem, los datos nunca salen de la empresa, modos dual k3s + Docker, cero dependencias externas',
    },
    antiBan: {
      title: 'Sistema anti-baneo',
      description: 'Rotación de 50+ UA + pool de huellas TLS utls + 11 perfiles de navegador + rotación automática cada 5 minutos',
    },
    perf: {
      title: 'Plano de datos de alto rendimiento en Go',
      description: 'Go nativo, imagen ligera de 40 MB, P99 < 500 ms con 200 concurrentes, retransmisión estable de SSE en streaming',
    },
  },
  footer: 'LLM Gateway · [GATEWAY_DOMAIN] · Open Core · Localización China · Despliegue privado',
  ariaPoints: 'Puntos destacados',
  roadmap: {
    title: 'Hoja de ruta de evolución del producto',
    subtitle: 'Del plano de datos LLM a la pasarela de agentes empresariales, en construcción continua',
    v31: {
      phase: 'v3.1 · 2026 Q3',
      title: 'API Hub Asset Center + hosting de herramientas MCP',
      description:
        'Registro unificado de endpoints LLM, servicios MCP y agentes. Autoservicio de descubrimiento y reutilización para desarrolladores.',
    },
    v32: {
      phase: 'v3.2 · 2026 Q4',
      title: 'Escudo de seguridad GA + integración SIEM + SpecBoost',
      description:
        'Bloqueo de inyección de prompt, enmascaramiento de datos sensibles, enriquecimiento inteligente de la descripción de la API para mejorar la precisión del Function Calling.',
    },
    v40: {
      phase: 'v4.0 · 2027 Q1',
      title: 'Registro de agentes + pasarela de protocolo A2A',
      description:
        'Delegación y orquestación de tareas entre agentes, entrada unificada de OpenClaw y agentes de negocio.',
    },
    v50: {
      phase: 'v5.0 · 2027 Q3',
      title: 'Soluciones sectoriales GA',
      description:
        'Plantillas sectoriales para atención al cliente, RR. HH., ventas y logística: soluciones de agentes listas para usar.',
    },
  },
}
