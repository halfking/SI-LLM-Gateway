// liveStreamDisplay — UI helpers for the swim lane.
//
// Pure data-shaping for the tiles. Lives in its own module so it
// can be unit-tested in isolation and reused by LiveRequestBlock
// (render) and LiveStreamLegend (label).
//
// 2026-07-03 revision: tile now carries 3 lines of text (time,
// model short label, latency) plus a 2px status border. The model
// short label is *usage-aware* — only the top vendors (by real
// production traffic on 71) get a canonical 3-letter code; every
// other family falls back to "???" + a gray background so the
// eye learns to ignore it. The full model name still lives in
// the hover tooltip so the operator can drill in on demand.
//
// Priority is driven by observed request volume on 71, not by
// marketing reach. If a new vendor becomes dominant, add its
// rule here AND bump it in the model_classifier on the Go side
// (admin/websocket.go: classifyModelCategory) so the legend and
// the tile stay in sync.

/**
 * Reduce a model name to a single uppercase letter for the tile's
 * dominant visual cue (the family colour). Kept for callers that
 * only have room for one character. Same top-vendor priority as
 * `modelShortLabel`.
 */
export function modelGlyph(model: string | undefined | null): string {
  if (!model) return '?'
  const m = model.toLowerCase()
  // Usage-driven short-circuit — top vendors only.
  if (m.startsWith('gpt-') || m.startsWith('o1-') || m.startsWith('o3-') || m.startsWith('o4-')) return 'G'
  if (m.startsWith('claude-')) return 'C'
  if (m.startsWith('qwen')) return 'Q'
  if (m.startsWith('glm-')) return 'M'
  if (m.startsWith('deepseek-')) return 'D'
  if (m.startsWith('minimax')) return 'X'
  // Generic fallback: first alphanumeric of the raw name.
  const m2 = (model || '').trim()
  if (!m2) return '?'
  const first = m2[0]
  return /[a-zA-Z0-9]/.test(first) ? first.toUpperCase() : '?'
}

/**
 * Top-vendor family code shown on the second line of every tile.
 *
 * The list is deliberately short. On 71 the production swim lane
 * is ~95% MiniMax + Claude + GPT + Qwen; everything else (Mistral,
 * Llama, Phi, Gemma, Moonshot, Doubao, Ernie…) gets `???` and a
 * gray background so the operator's eye learns to ignore it.
 *
 * Mapping rules (priority order — first match wins):
 *   - GPT / o1 / o3 / o4  → "GPT"     (OpenAI, blue)
 *   - Claude-*            → "CLD"     (Anthropic, purple)
 *   - Qwen* / Qwen2*      → "QWN"     (Alibaba, orange)
 *   - GLM-*               → "GLM"     (Zhipu, orange)
 *   - Deepseek-*          → "DSK"     (Deepseek, orange)
 *   - MiniMax* / minimax* → "MIX"     (Top usage on 71, gray)
 *
 * Everything else returns "???" — the tile shows a gray tile with
 * a question-mark, the full model name still appears in the hover
 * tooltip so debugging is not lost.
 */
export function modelShortLabel(model: string | undefined | null): string {
  if (!model) return '???'
  const m = model.toLowerCase().trim()
  if (!m) return '???'

  if (m.startsWith('gpt-') || m.startsWith('o1-') || m.startsWith('o3-') || m.startsWith('o4-')) return 'GPT'
  if (m.startsWith('claude-')) return 'CLD'
  if (m.startsWith('qwen')) return 'QWN'
  if (m.startsWith('glm-')) return 'GLM'
  if (m.startsWith('deepseek-')) return 'DSK'
  if (m.startsWith('minimax')) return 'MIX'

  // Everything else is intentionally demoted to ??? so the swim
  // lane's visual hierarchy stays clean. The full model name is
  // still surfaced in the hover tooltip.
  return '???'
}

/**
 * Format a date as HH:MM using the active locale. Used on the
 * first line of every tile so the operator can see *when* the
 * request happened without hovering.
 */
export function timeHHMM(ts: string | undefined | null, locale: string = 'en-US'): string {
  if (!ts) return '--:--'
  const d = new Date(ts)
  if (Number.isNaN(d.getTime())) return '--:--'
  try {
    return d.toLocaleTimeString(locale, { hour: '2-digit', minute: '2-digit', hour12: false })
  } catch {
    return '--:--'
  }
}

/**
 * Format a latency in ms as the compact "1.2s" / "320ms" string
 * shown on the third line. Negative / null / NaN inputs render as
 * "—". In-flight requests render as "…".
 */
export function latencyLabel(latencyMs: number | null | undefined, isInProgress: boolean): string {
  if (isInProgress) return '…'
  if (latencyMs == null || !Number.isFinite(latencyMs)) return '—'
  if (latencyMs < 0) return '—'
  if (latencyMs < 1000) return `${Math.round(latencyMs)}ms`
  if (latencyMs < 10_000) return `${(latencyMs / 1000).toFixed(1)}s`
  return `${Math.round(latencyMs / 1000)}s`
}

/**
 * Status → 2px border colour. Sits on the OUTSIDE of the tile so
 * the dark interior stays a calm canvas and the colour reads as
 * a clean status badge.
 *
 *  - success      → muted green (don't shout when 95% are green)
 *  - in_progress  → amber with CSS pulse animation
 *  - failure      → red, slightly brighter to draw the eye
 *  - default      → neutral gray
 */
export function statusBorderColor(status: string | undefined | null): string {
  switch (status) {
    case 'success':
      return 'rgba(34, 197, 94, 0.85)'
    case 'in_progress':
      return 'rgba(245, 158, 11, 0.95)'
    case 'failure':
      return 'rgba(239, 68, 68, 0.95)'
    default:
      return 'rgba(139, 148, 158, 0.4)'
  }
}

/**
 * Error-kind → text colour. Used on the second line (replaces the
 * family short label) when a request failed, so the operator can
 * tell at a glance *why* without hovering. The mapping is
 * intentionally coarse — five buckets cover 90% of the LLM-gateway
 * failure modes, and any unmapped kind falls back to the
 * neutral "other" colour.
 *
 *  - timeout / cancelled / client_disconnect → amber (network)
 *  - 4xx / auth / quota / rate_limit          → orange (client)
 *  - 5xx / upstream / provider                → red (server)
 *  - model_not_found / routing_failed        → purple (config)
 *  - default                                 → red (other)
 */
export function errorKindColor(errorKind: string | undefined | null): string {
  if (!errorKind) return 'inherit'
  const k = errorKind.toLowerCase()
  if (/(timeout|timedout|cancel|disconnect|network|reset|eof)/.test(k)) return '#fcd34d'
  if (/(5xx|server|upstream|provider|overloaded|backend)/.test(k)) return '#fca5a5'
  if (/(4xx|auth|unauthor|forbidden|quota|rate|billing|payment)/.test(k)) return '#fdba74'
  if (/(not_found|model_not|routing|no_route|resolve|policy)/.test(k)) return '#c4b5fd'
  return '#fca5a5'
}