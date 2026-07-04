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
 * Reduce a provider code (or vendor name) to a 2-4 letter *typical*
 * short label shown on the third line of the tile. Like
 * `modelShortLabel`, the rules are family-aware so the operator
 * sees consistent 3-4 character codes instead of a wall of mixed
 * casing and dashes.
 *
 * Mapping rationale (priority order — first match wins):
 *   - 4-letter codes for the big four (OpenAI / Anthropic / Azure /
 *     Google) so they don't visually compete with the 3-letter
 *     model codes above them
 *   - everything else collapses to 3 alphanumerics of the raw name
 *
 * Inputs come from `request.provider_code` (lowercase catalog code
 * like "anthropic", "openai", "azure-openai") or, if missing, a
 * human-readable display name from a future source.
 */
/**
 * Reduce a provider code to a label shown on the third line of the
 * tile. 2026-07-03 revision: show the FULL catalog_code instead
 * of a 3-letter abbreviation. Operators scan the swim lane looking
 * for "anthropic" / "azure-openai" / "openrouter" — the full name
 * carries more identifying weight than the abbreviation.
 *
 * Length policy: the CSS layer applies text-overflow: ellipsis,
 * so very long provider names (e.g. "custom-provider-east-2")
 * just get cut at the tile boundary. We do NOT truncate in code
 * because the user explicitly asked for "完整 ... 超长的用...表示".
 */
export function providerShortLabel(provider: string | undefined | null): string {
  if (!provider) return '???'
  const p = provider.trim()
  if (!p) return '???'
  // Show the full lowercase code. CSS handles ellipsis on overflow.
  return p.toLowerCase()
}

/**
 * Reduce a model name to a SHORT label shown on the second line of
 * the tile. 2026-07-03 revision: tail-first — version numbers carry
 * more identifying weight than vendor prefixes, so a name like
 * "gpt-4o-mini" becomes "4o-mini" rather than "GPT". A bare model
 * name with no version (e.g. "foo-bar") falls back to the last 7
 * alphanumeric chars so we still have *something* on screen.
 *
 * Failure / unknown models get "???".
 */
export function modelShortLabel(model: string | undefined | null): string {
  if (!model) return '???'
  const m = model.toLowerCase().trim()
  if (!m) return '???'

  // Tail-first rules — each captures the last "version" segment.
  // Order matters: the first match wins.
  // - gpt / o1 / o3 / o4: take everything AFTER the prefix.
  //   gpt-4o-mini → "4O-MINI", o1-preview → "PREVIEW"
  // - claude-*: "claude-3.5-sonnet" → "3.5-SONNET"
  // - minimax: short brand label "MIX"
  // - others: tail-first 7 chars so the version still shows
  if (m.startsWith('gpt-')) return stripPrefix(model, 'gpt-')
  if (m.startsWith('o1-')) return stripPrefix(model, 'o1-')
  if (m.startsWith('o3-')) return stripPrefix(model, 'o3-')
  if (m.startsWith('o4-')) return stripPrefix(model, 'o4-')
  if (m.startsWith('claude-')) return stripPrefix(model, 'claude-')
// Qwen family. Two cases:
  //   - qwen-<version>        → "qwen-max"            → "MAX"
  //   - qwen<digit>...         → "qwen2-72b-instruct"   → "2-72B-INSTRUCT"
  //                            "qwen2.5-7b"            → "2.5-7B"
  // The digit branch must come first because "qwen-max" should match
  // the "qwen-" branch, not the regex. The regex strips only
  // "qwen" (NOT the digit), so the suffix starts with the version
  // number that the user explicitly asked to keep.
  if (/^qwen\d/.test(m)) return stripPrefix(model, /^qwen/)
  if (m.startsWith('qwen-')) return stripPrefix(model, 'qwen-')
  if (m.startsWith('glm-')) return stripPrefix(model, 'glm-')
  if (m.startsWith('deepseek-')) return stripPrefix(model, 'deepseek-')
  if (m.startsWith('moonshot-')) return stripPrefix(model, 'moonshot-')
  if (m.startsWith('doubao-')) return stripPrefix(model, 'doubao-')
  if (m.startsWith('ernie-')) return stripPrefix(model, 'ernie-')
  if (m.startsWith('llama-')) return stripPrefix(model, 'llama-')
  if (m.startsWith('mistral-') || m.startsWith('mixtral-')) return stripPrefix(model, /^[a-z]+-/)
  if (m.startsWith('phi-')) return stripPrefix(model, 'phi-')
  if (m.startsWith('gemma-')) return stripPrefix(model, 'gemma-')
  if (m.startsWith('minimax')) return 'MIX'

  // No recognised prefix: take the LAST 7 chars of the raw name
  // (keeping the separator so "foo-bar-123" → "AR-123" rather than
  // collapsing to "OBAR123"). The CSS layer adds ellipsis if even
  // this overflows.
  if (m.length <= 7) return (m || '???').toUpperCase()
  return m.slice(-7).toUpperCase()
}

/**
 * Strip a known prefix from a model name and return the remainder
 * uppercased. The CSS layer adds ellipsis if even the remainder
 * overflows the tile. Leading separator characters are kept
 * (so "qwen2-72b" → "2-72b" preserves the version number).
 */
function stripPrefix(model: string, prefix: string | RegExp): string {
  const m = model.trim()
  let suffix: string
  if (typeof prefix === 'string') {
    if (!m.toLowerCase().startsWith(prefix)) return m.toUpperCase()
    suffix = m.slice(prefix.length)
  } else {
    const re = new RegExp('^' + prefix.source, 'i')
    const matched = m.match(re)
    if (!matched) return m.toUpperCase()
    suffix = m.slice(matched[0].length)
  }
  // Only collapse leading separators IF the remainder would be a
  // bare letter sequence ("qwen-max" → "MAX", not "-MAX"). When the
  // remainder starts with a digit or has its own separator already,
  // keep the separator so the version number stays readable
  // ("qwen2-72b" → "2-72B", "gpt-3.5" → "3.5").
  const trimmed = suffix.replace(/^[-._ ]+/, (m) => {
    const next = (suffix.replace(/^[-._ ]+/, ''))[0] || ''
    // If next char is a letter, drop the leading separator
    // (we want a clean identifier). If next char is a digit, KEEP
    // the separator so the version number stays intact.
    return /[a-zA-Z]/.test(next) ? '' : m
  })
  return (trimmed || '???').replace(/[ _]/g, '-').toUpperCase()
}

/**
 * Coarse status category. Maps (status, error_kind) to one of:
 *
 *   success         → status === 'success'
 *   in_progress     → status === 'in_progress'
 *   failure_5xx     → status === 'failure' + server-side error (5xx,
 *                      upstream/provider/overloaded)
 *   failure_4xx     → status === 'failure' + client-side error (4xx,
 *                      auth/quota/rate_limit/forbidden/billing)
 *   failure_timeout → status === 'failure' + network/timeout/
 *                      disconnect/reset
 *   failure_not_found → status === 'failure' + routing/model_not_found
 *   failure_other   → status === 'failure' + unmapped
 *
 * The mapping is intentionally coarse: in production the raw
 * `error_kind` strings come from the upstream provider and the
 * error stage in the gateway, so they vary ("5xx", "server_5xx",
 * "upstream_5xx", "upstream_error", "model_error"…). Five buckets
 * cover 90% of the variants; anything unmapped falls into
 * `failure_other` so the operator can still find it via the
 * "All failures" filter.
 *
 * The order of checks matters — "disconnect" should match the
 * timeout bucket, not the 5xx bucket (the server didn't even see
 * the request). Hence the network check is FIRST.
 */
export type StatusCategory =
  | 'success'
  | 'in_progress'
  | 'failure_5xx'
  | 'failure_4xx'
  | 'failure_timeout'
  | 'failure_not_found'
  | 'failure_other'

export function statusCategory(
  status: string | undefined | null,
  errorKind: string | undefined | null,
): StatusCategory {
  if (status === 'success') return 'success'
  if (status === 'in_progress') return 'in_progress'
  if (status !== 'failure') return 'failure_other' // unmapped non-failure status
  if (!errorKind) return 'failure_other'
  const k = errorKind.toLowerCase()
  // Pure network / client-side disconnect FIRST. We use negative
  // lookaheads to make sure upstream / server / backend timeouts
  // do NOT fall into the timeout bucket — they belong to 5xx. The
  // error_kind values use snake_case ("client_disconnect",
  // "network_reset", "upstream_timeout", "backend_timeout") so
  // plain substring matching with these negative-lookahead guards
  // is the cleanest formulation.
  if (/(?<!upstream_)(?<!backend_)(?<!server_)timeout/.test(k)) return 'failure_timeout'
  if (/client_disconnect|\bdisconnect\b|network_reset|network_error|connection_reset|eof|cancelled|canceled/.test(k)) return 'failure_timeout'
  // Server-side / upstream.
  if (/(5xx|server|upstream|provider|overloaded|backend|internal)/.test(k)) return 'failure_5xx'
  // Client-side / auth / quota.
  if (/(4xx|auth|unauthor|forbidden|quota|rate|billing|payment|invalid)/.test(k)) return 'failure_4xx'
  // Routing / config. Use \brout so "routing" / "route" / "no_route"
  // all match (substring "route" misses "routing" because of the 'i').
  if (/(not_found|model_not|\brout|no_route|resolve|policy|missing)/.test(k)) return 'failure_not_found'
  return 'failure_other'
}

/**
 * Tiny hex → rgba converter (used by LiveRequestBlock for the family
 * background). Cached by raw hex; called twice per render (once for
 * border tint, once for background) so we want it cheap.
 */
export function hexToRgba(hex: string, alpha: number): string {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim())
  if (!m) return `rgba(139, 148, 158, ${alpha})`
  const n = parseInt(m[1], 16)
  const r = (n >> 16) & 0xff
  const g = (n >> 8) & 0xff
  const b = n & 0xff
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
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