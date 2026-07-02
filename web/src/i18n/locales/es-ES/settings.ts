// Auto-translated draft (es-ES) · 2026-07-02 · please review
// settings.ts — Vista de ajustes.
export default {
  category: {
    all: 'Todos',
    compression: 'Compresión',
    rateLimit: 'Límite de tasa',
    timeout: 'Tiempo agotado',
    routing: 'Enrutamiento',
    session: 'Sesión',
    security: 'Seguridad',
    circuitBreaker: 'Disyuntor',
    general: 'Otros',
  },
  dangerLevel: {
    note: '🟡 Aviso',
    warn: '🟠 Advertencia',
    danger: '🔴 Peligro',
  },
  list: {
    total: '{n} ajustes en total',
    loading: 'Cargando…',
    empty: 'No hay ajustes en esta categoría',
    table: {
      setting: 'Ajuste',
      currentValue: 'Actual',
      source: 'Origen',
      danger: 'Peligro',
    },
  },
  detail: {
    selectPrompt: '← Seleccione un ajuste a la izquierda para ver detalles',
    type: 'Tipo',
    currentValue: 'Valor actual',
    defaultValue: 'Valor por defecto',
    options: 'Opciones',
    dangerLevel: 'Nivel de peligro',
    hotReload: 'Recarga en caliente',
    hotReloadYes: 'Sí',
    hotReloadNo: 'No (requiere reinicio)',
    observability: 'Observabilidad',
    tenantWarningTitle: 'Ajuste a nivel de inquilino',
    tenantWarningBody: 'Este ajuste se aplica a un único inquilino y no se puede configurar a nivel de sistema. Vaya a la página de <strong>Gestión de inquilinos</strong> para configurarlo para un inquilino específico.',
    errors: {
      loadListFailed: 'Error al cargar',
      loadDetailFailed: 'Error al cargar el detalle',
      saveFailed: 'Error al guardar',
      rollbackFailed: 'Error al revertir',
      invalidNumber: 'Introduzca un número válido',
      confirmRollback: '¿Confirmar la reversión de {key} a su valor anterior?',
    },
  },
  editor: {
    newValueLabel: 'Nuevo valor',
    enabledText: 'Activado',
    disabledText: 'Desactivado',
    stringPlaceholder: 'Introduzca un valor de cadena',
    jsonPlaceholder: 'Introduzca un valor JSON',
    jsonHint: 'Use JSON para tipos complejos',
    saving: 'Guardando…',
    save: 'Guardar',
    rollback: 'Revertir',
  },
  compression: {
    selectLabels: {
      off: '0 - Desactivado',
      auto: '1 - Umbral automático',
      on4xx: '2 - En 4xx (recomendado)',
    },
    enumLabels: {
      off: '0 - Desactivado',
      auto: '1 - Umbral automático',
      on4xx: '2 - En 4xx',
    },
    enumDescriptions: {
      off: 'La compresión está completamente desactivada.',
      auto: 'Comprime automáticamente cuando la longitud del mensaje supera el umbral de la ventana de contexto.',
      on4xx: 'Comprime y reintenta al recibir un error 4xx (p. ej. context_length_exceeded).',
    },
    hint: {
      off: 'La compresión está completamente desactivada.',
      auto: 'Comprime automáticamente cuando la longitud del mensaje supera el umbral de la ventana de contexto.',
      on4xx: 'Comprime y reintenta al recibir un error 4xx (p. ej. context_length_exceeded).',
    },
    strategyEnum: {
      naive: 'naive - Compresión ingenua',
      smart: 'smart - Compresión inteligente',
      adaptive: 'adaptive - Compresión adaptativa',
    },
  },
  docs: {
    compressionModeTitle: '📖 Modo de compresión en detalle',
    compressionModeContent: `<p>El <strong>modo de compresión</strong> controla cómo el sistema maneja contextos de conversación demasiado largos:</p>
<ul>
  <li><code>0 (off)</code> - Desactiva la compresión; devuelve un error cuando el contexto excede.</li>
  <li><code>1 (auto_threshold)</code> - Modo predictivo; comprime proactivamente cuando los mensajes se acercan a la ventana de contexto.</li>
  <li><code>2 (on_4xx)</code> - Modo reactivo; comprime y reintenta tras un error 4xx. [Recomendado]</li>
</ul>
<p class="docs-note">💡 <strong>Se recomienda el modo 2</strong>: comprime solo cuando es necesario, evitando sobrecarga de rendimiento innecesaria.</p>`,
    cacheEnabledTitle: '📖 Caché de sesión en detalle',
    cacheEnabledContent: `<p>La <strong>caché de sesión</strong> controla si se activa la caché por niveles L1/L2/L3:</p>
<ul>
  <li><strong>L1</strong> - Caché en memoria (la más rápida)</li>
  <li><strong>L2</strong> - Caché en Redis (media)</li>
  <li><strong>L3</strong> - Caché en base de datos (la más lenta)</li>
</ul>
<p class="docs-note">⚠️ Cuando se desactiva, no se guarda estado de sesión; esto afecta a la continuidad del contexto.</p>`,
    formatConversionTitle: '📖 Conversión de formato en detalle',
    formatConversionContent: `<p>La <strong>conversión de formato</strong> permite la conversión automática del formato de solicitud entre protocolos:</p>
<ul>
  <li><strong>Ruta Q2</strong>: formato Anthropic → modelos OpenAI</li>
  <li><strong>Ruta Q3</strong>: formato OpenAI → modelos Anthropic</li>
</ul>
<p class="docs-note">💡 Se admiten anulaciones a nivel de proveedor; la conversión puede desactivarse para proveedores específicos.</p>`,
    rateLimitRpmTitle: '📖 Límite de tasa RPM en detalle',
    rateLimitRpmContent: `<p><strong>RPM (Requests Per Minute)</strong> limita el número de solicitudes por inquilino por minuto:</p>
<ul>
  <li>Adecuado para control de tráfico de grano grueso</li>
  <li>Usa un algoritmo de ventana deslizante, con precisión de segundos</li>
  <li>Devuelve HTTP 429 cuando se excede</li>
</ul>
<p class="docs-note">⚠️ <strong>A nivel de inquilino</strong>: este ajuste requiere un tenant_id; configúrelo en la página de Gestión de inquilinos.</p>`,
    rateLimitConcurrentTitle: '📖 Límite de tasa concurrente en detalle',
    rateLimitConcurrentContent: `<p>El <strong>límite concurrente</strong> limita el número de solicitudes concurrentes procesadas por inquilino:</p>
<ul>
  <li>Protege los recursos del sistema; evita que un único inquilino monopolice conexiones</li>
  <li>Basado en contador; respuesta rápida</li>
  <li>Devuelve 429 o pone en cola cuando se excede</li>
</ul>
<p class="docs-note">⚠️ <strong>A nivel de inquilino</strong>: este ajuste requiere un tenant_id; configúrelo en la página de Gestión de inquilinos.</p>`,
  },
}
