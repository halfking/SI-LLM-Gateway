<script setup lang="ts">
// LiveRequestBlock — single tile in the swim lane.
//
// 2026-07-03 v5: 4-row layout (time / model / provider / latency).
//
//   ┌──────────┐
//   │ 14:35    │  ← line 1: HH:MM start time              (9px)
//   │  GPT     │  ← line 2: model-family code           (11px, bold)
//   │  ANTH   │  ← line 3: provider code (NEW)         ( 8px, muted)
//   │ 1.2s     │  ← line 4: latency                     (9px, monospace)
//   └══════════┘
//     ↑ 2-3px border: coloured by STATUS (green/amber/red), NOT
//       family. The body bg is the FAMILY colour at ~22% alpha so
//       a wall of GPT tiles reads as "blue band" while the status
//       border sits clearly on top.
//
// Why a 4-row layout: the operator needs to see WHICH MODEL on
// which VENDOR is taking the load. The model line is the dominant
// signal (largest, boldest); the provider line is secondary
// (smaller, muted). A failure does NOT replace the model line —
// the failure is encoded in the border colour + a corner badge.
//
// Tile is 60px wide × 76px tall. 4 rows of ~14px line-height + 2px
// padding × 2 (top/bottom) + 4px gap between rows = 76px. The
// narrow width keeps the swim lane in one viewport without
// horizontal scroll.
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import type { LiveRequest } from '../composables/useLiveStream'
import { modelShortLabel, providerShortLabel } from '../composables/liveStreamDisplay'
import {
  getModelCategoryColor,
  STATUS_BORDER_COLORS,
  STATUS_BORDER_WIDTHS,
} from '../composables/liveStreamColors'

const props = defineProps<{
  request: LiveRequest
}>()

const emit = defineEmits<{
  /** Fired when the user clicks a real (non-idle) tile. */
  select: [requestId: string]
}>()

const { locale } = useI18n()

const isIdle = computed(() => props.request.type === 'idle_marker')

const idleLabel = computed(() => {
  if (!isIdle.value) return ''
  const start = Date.parse(props.request.ts)
  if (Number.isNaN(start)) return '—'
  const minutes = Math.max(1, Math.round((Date.now() - start) / 60_000))
  return `Idle ${minutes}m`
})

// Line 1: HH:MM start time (locale-aware).
const timeLabel = computed(() => {
  if (!props.request.ts) return '--:--'
  const d = new Date(props.request.ts)
  if (Number.isNaN(d.getTime())) return '--:--'
  try {
    return d.toLocaleTimeString(locale.value, { hour: '2-digit', minute: '2-digit', hour12: false })
  } catch {
    return '--:--'
  }
})

// Line 2: model-family code (always the family, even on failure).
const vendorLabel = computed(() => modelShortLabel(props.request.model))

// Line 3: provider code. Smaller font + lower contrast — secondary
// signal, but critical when an incident is on a specific vendor.
const providerLabel = computed(() => providerShortLabel(props.request.provider_code))

// Line 4: latency OR error message (for failures).
const latencyText = computed(() => {
  if (props.request.status === 'in_progress') return '…'
  const ms = props.request.latency_ms
  if (ms == null) return '—'
  if (ms < 0) return '—'
  if (ms < 1000) return `${Math.round(ms)}ms`
  if (ms < 10_000) return `${(ms / 1000).toFixed(1)}s`
  return `${Math.round(ms / 1000)}s`
})

/**
 * When status=failure, show a brief error message on line 4 instead
 * of latency. The operator scans the swim lane looking for red tiles
 * with readable error labels (e.g. "Timeout", "5xx", "Auth").
 */
const line4Text = computed(() => {
  if (props.request.status !== 'failure' || !props.request.error_kind) {
    return latencyText.value
  }
  const k = props.request.error_kind.toLowerCase()
  if (/(timeout|timedout)/.test(k)) return 'Timeout'
  if (/(5xx|server|upstream|provider|overloaded|backend)/.test(k)) return '5xx'
  if (/(4xx|auth|unauthor|forbidden|quota|rate|billing|payment)/.test(k)) return 'Auth'
  if (/(not_found|model_not|route|no_route|resolve|policy)/.test(k)) return 'NotFound'
  // Fallback: show first 8 chars of error_kind
  return props.request.error_kind.slice(0, 8)
})

/**
 * Dynamic width based on content length. The tile is at least 60px
 * wide (the baseline that fits "14:35" / "4O-MINI" / "anthropic" /
 * "1.2s" in a tight layout). When the model name or provider name
 * is long (e.g. "2-72B-INSTRUCT" / "azure-openai"), the tile grows
 * to ~75-80px so the full label is visible (or at least more of it
 * before the ellipsis kicks in). CSS clamps at 90px so a pathological
 * "custom-provider-east-2-replica-1" doesn't break the layout.
 */
const tileWidth = computed(() => {
  const modelLen = vendorLabel.value.length
  const providerLen = providerLabel.value.length
  const maxLen = Math.max(modelLen, providerLen)
  // Each char is ~5-6px at 11px/8px font. Base is 60px.
  // For every char beyond 8, add 4px so longer labels get more space.
  const extra = Math.max(0, maxLen - 8) * 4
  return Math.min(90, 60 + extra)
})

/**
 * Background colour: family colour at ~22% alpha. The status
 * border (set via :style below) provides the primary visual
 * signal; the family bg just helps the eye group similar tiles.
 */
const familyBg = computed(() => {
  const c = getModelCategoryColor(props.request.model_category)
  return hexToRgba(c, 0.22)
})

const statusBorder = computed(() =>
  STATUS_BORDER_COLORS[props.request.status ?? 'in_progress'] ||
  STATUS_BORDER_COLORS.in_progress,
)

const statusBorderWidth = computed(() =>
  STATUS_BORDER_WIDTHS[props.request.status ?? 'in_progress'] ||
  STATUS_BORDER_WIDTHS.in_progress,
)

const isPulsing = computed(() => props.request.status === 'in_progress')

/**
 * Multi-line native tooltip. Native `title` is chosen over a custom
 * popover because the swim lane lives inside an overflow:hidden
 * track — a popover would clip at the right viewport edge — and
 * because screen readers already announce native title.
 */
const tooltip = computed(() => {
  const r = props.request
  const lines: string[] = []
  if (r.model) lines.push(`Model: ${r.model}`)
  if (r.provider_code) lines.push(`Provider: ${r.provider_code}`)
  lines.push(`Status: ${r.status ?? '?'}`)
  if (r.error_kind) lines.push(`Error: ${r.error_kind}`)
  if (r.latency_ms != null) lines.push(`Latency: ${latencyText.value}`)
  if (r.total_tokens != null) {
    lines.push(`Tokens: ${r.total_tokens}`)
  } else if (r.prompt_tokens != null || r.completion_tokens != null) {
    const p = r.prompt_tokens ?? 0
    const c = r.completion_tokens ?? 0
    lines.push(`Tokens: ${p}+${c}`)
  }
  if (r.cost_usd != null) lines.push(`Cost: $${r.cost_usd.toFixed(4)}`)
  if (r.request_id) lines.push(`ID: ${r.request_id.slice(0, 8)}`)
  try {
    lines.push(`Time: ${new Date(r.ts).toLocaleString(locale.value)}`)
  } catch {
    /* ignore */
  }
  return lines.join('\n')
})

/**
 * Tiny error badge — top-right corner. Single-char glyph for
 * failure type so the operator can tell "this was a timeout" vs
 * "5xx" without opening the tooltip.
 */
const errorBadge = computed(() => {
  if (props.request.status !== 'failure' || !props.request.error_kind) return ''
  const k = props.request.error_kind.toLowerCase()
  if (/(timeout|timedout)/.test(k)) return 'T'
  if (/(5xx|server|upstream|provider|overloaded|backend)/.test(k)) return '!'
  if (/(4xx|auth|unauthor|forbidden|quota|rate|billing|payment)/.test(k)) return 'X'
  if (/(not_found|model_not|route|no_route|resolve|policy)/.test(k)) return '?'
  return '!'
})

function onClick() {
  if (!isIdle.value && props.request.request_id) {
    emit('select', props.request.request_id)
  }
}

/**
 * Tiny hex → rgba converter so the family colour can sit at low
 * alpha over the dark card.
 */
function hexToRgba(hex: string, alpha: number): string {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim())
  if (!m) return `rgba(139, 148, 158, ${alpha})`
  const n = parseInt(m[1], 16)
  const r = (n >> 16) & 0xff
  const g = (n >> 8) & 0xff
  const b = n & 0xff
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}
</script>

<template>
  <!-- Idle marker: wide dashed pill so 1 minute of silence still
       reads as "gap" rather than as a request. -->
  <div
    v-if="isIdle"
    class="live-block live-block--idle"
    :title="idleLabel"
    aria-hidden="true"
  >
    <span class="live-block__idle-text">{{ idleLabel }}</span>
  </div>

  <!-- Real tile: 4 lines + status border + family background. -->
  <div
    v-else
    class="live-block"
    :class="{
      'live-block--clickable': !!request.request_id,
      'live-block--in-progress': isPulsing,
      'live-block--failure': request.status === 'failure',
    }"
    role="button"
    tabindex="0"
    :aria-label="tooltip"
    :title="tooltip"
    :style="{
      background: familyBg,
      borderColor: statusBorder,
      borderWidth: statusBorderWidth + 'px',
      width: tileWidth + 'px',
    }"
    @click="onClick"
    @keyup.enter="onClick"
    @keyup.space.prevent="onClick"
  >
    <span class="live-block__time">{{ timeLabel }}</span>
    <span class="live-block__vendor">{{ vendorLabel }}</span>
    <span class="live-block__provider">{{ providerLabel }}</span>
    <span 
      class="live-block__latency"
      :class="{ 'live-block__latency--error': request.status === 'failure' }"
    >{{ line4Text }}</span>
    <span
      v-if="errorBadge"
      class="live-block__error-badge"
      :title="request.error_kind || ''"
      aria-hidden="true"
    >{{ errorBadge }}</span>
  </div>
</template>

<style scoped>
/* 2026-07-03 v5 — 4-row tile (60-90px × 76px, dynamic width).
 *
 *   width  60-90px  ← dynamic: 60px baseline, grows for long labels
 *   height 76px     ← 4 rows × 14px + 4px padding (top+bottom)
 *   border 2-3px    ← thicker on failure
 *   font   8-11px   ← model is the loudest; provider is the quietest
 */
.live-block {
  box-sizing: border-box;
  width: 60px; /* fallback; overridden by :style */
  min-width: 60px;
  max-width: 90px;
  height: 76px;
  border-radius: 4px;
  border: 2px solid rgba(139, 148, 158, 0.4);
  color: var(--text, #e6edf3);
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: space-around;
  padding: 3px 2px;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  position: relative;
  transition: transform 0.15s ease, box-shadow 0.15s ease, border-color 0.15s ease;
}

.live-block--clickable {
  cursor: pointer;
}
.live-block--clickable:hover,
.live-block--clickable:focus-visible {
  transform: translateY(-2px) scale(1.1);
  z-index: 2;
  box-shadow: 0 4px 14px rgba(99, 102, 241, 0.45);
  outline: none;
}

/* In-flight pulses the border colour so the eye catches it even
 * when scanning a wall of tiles. */
.live-block--in-progress {
  animation: live-block-pulse 1.4s ease-in-out infinite;
}
@keyframes live-block-pulse {
  0%, 100% { box-shadow: 0 0 0 0 rgba(245, 158, 11, 0.0); }
  50%      { box-shadow: 0 0 0 4px rgba(245, 158, 11, 0.25); }
}

/* Failure: an extra slight scale-up hint + a subtle red glow. */
.live-block--failure {
  box-shadow: 0 0 0 1px rgba(239, 68, 68, 0.4) inset;
}

/* Line 1: time HH:MM. */
.live-block__time {
  font-size: 9px;
  line-height: 1.1;
  color: var(--muted, #8b949e);
  letter-spacing: 0.3px;
}

/* Line 2: model-family code. Tail-first so version numbers
 * (e.g. "4O-MINI", "3.5-SONNET") carry more identifying weight
 * than the vendor prefix. The dominant signal on the tile. */
.live-block__vendor {
  font-size: 11px;
  font-weight: 700;
  line-height: 1.1;
  letter-spacing: 0.3px;
  color: var(--text, #e6edf3);
  max-width: 100%;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.5);
}

/* Line 3: provider code. 2026-07-03: shows the FULL catalog_code
 * (e.g. "anthropic" / "azure-openai") instead of a 3-letter abbrev.
 * Long names get ellipsis at the tile edge. No text-transform:
 * the operator reads lowercase catalog codes most naturally. */
.live-block__provider {
  font-size: 8px;
  line-height: 1.1;
  font-weight: 600;
  letter-spacing: 0.2px;
  color: var(--muted, #8b949e);
  max-width: 100%;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  /* Slight tint so it doesn't blend into the family-coloured bg
   * when the family is the same colour as the muted text. */
  opacity: 0.9;
}

/* Line 4: latency OR error message (for failures). */
.live-block__latency {
  font-size: 9px;
  line-height: 1.1;
  font-weight: 500;
  font-variant-numeric: tabular-nums;
  color: var(--muted, #8b949e);
  letter-spacing: 0.2px;
}

/* When status=failure, line 4 shows the error kind (e.g. "Timeout",
 * "5xx", "Auth") in a bright amber/red so the operator's eye can
 * scan the swim lane for red tiles with readable error labels. */
.live-block__latency--error {
  font-size: 8px;
  font-weight: 700;
  color: #fbbf24; /* amber-400 */
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

/* When the tile is a failure (red border), boost the error text
 * to full red so it's impossible to miss. */
.live-block--failure .live-block__latency--error {
  color: #ef4444; /* red-500 */
}

/* Error badge — top-right corner. */
.live-block__error-badge {
  position: absolute;
  top: 1px;
  right: 2px;
  width: 12px;
  height: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 9px;
  font-weight: 700;
  line-height: 1;
  color: #fff;
  background: rgba(239, 68, 68, 0.95);
  border-radius: 2px;
  pointer-events: none;
  text-shadow: none;
}

/* Idle marker: 3x wider so a silence reads as a distinct shape. */
.live-block--idle {
  width: 110px;
  height: 60px;
  border: 2px dashed var(--border, #30363d);
  background: transparent;
  color: var(--muted, #8b949e);
  cursor: default;
  /* Override the 4-row vertical layout — idle is single-line. */
  justify-content: center;
}
.live-block__idle-text {
  font-size: 11px;
  font-weight: 500;
}
</style>