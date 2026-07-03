<script setup lang="ts">
// LiveRequestBlock — single tile in the swim lane.
//
// 2026-07-03 revision (v3): switched to a 3-line text layout because
// the operator needs to read at-a-glance WHICH model, WHEN it
// arrived, and HOW LONG it took — not just one letter.
//
//   ┌──────────┐
//   │ 14:35    │  ← line 1: HH:MM start time
//   │  GPT     │  ← line 2: top-vendor 3-letter code (GPT/CLD/QWN/
//   │ 1.2s     │     GLM/DSK/MIX), or error_kind if failed, or ??? otherwise
//   └══════════┘  ← 2px border: green=ok, amber=in-progress, red=failed
//
// The status border (2px) replaces the colour-filled bottom strip.
// For failed tiles the second line swaps the vendor code for the
// error_kind colour-coded word (e.g. "TIMEOUT" amber, "5xx" red,
// "MODEL_NOT_FOUND" purple) so the operator can tell at a glance
// WHY a request failed.
//
// Hover carries the full model name + provider + cost + tokens + id.
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import type { LiveRequest } from '../composables/useLiveStream'
import {
  modelShortLabel,
  timeHHMM,
  latencyLabel,
  statusBorderColor,
  errorKindColor,
} from '../composables/liveStreamDisplay'

const props = defineProps<{
  request: LiveRequest
}>()

const emit = defineEmits<{
  /** Fired when the user clicks a real (non-idle) tile. */
  select: [requestId: string]
}>()

const { locale } = useI18n()

const isIdle = computed(() => props.request.type === 'idle_marker')

// Idle label: "Idle 1 min" — kept as a single horizontal pill so a
// 1-minute silence still reads as "gap" rather than "request".
const idleLabel = computed(() => {
  if (!isIdle.value) return ''
  const start = Date.parse(props.request.ts)
  if (Number.isNaN(start)) return '—'
  const minutes = Math.max(1, Math.round((Date.now() - start) / 60_000))
  return `Idle ${minutes}m`
})

// Line 1: HH:MM start time (locale-aware).
const timeLabel = computed(() => timeHHMM(props.request.ts, locale.value))

// Line 2: vendor code (top-7 only) OR error_kind on failure.
// `errorKindLabel` is a short token for failure tiles so we fit in
// 5-6 characters; `vendorLabel` is the canonical 3-letter code.
const errorKindLabel = computed(() => {
  const k = props.request.error_kind
  if (!k) return ''
  // Keep to ≤6 chars so the tile never overflows.
  return k.replace(/[^a-zA-Z0-9_]/g, '').slice(0, 6).toUpperCase()
})

const vendorLabel = computed(() => {
  // Failed tiles show the error_kind (in colour) instead of the
  // vendor — the vendor already lives on the bottom edge of the
  // tile via the family-colour background of the inner panel.
  if (props.request.status === 'failure' && errorKindLabel.value) {
    return errorKindLabel.value
  }
  return modelShortLabel(props.request.model)
})

const secondLineColor = computed(() => {
  if (props.request.status === 'failure' && props.request.error_kind) {
    return errorKindColor(props.request.error_kind)
  }
  return 'inherit' // inherit from .live-block__second
})

// Line 3: latency or in-progress dot.
const latencyText = computed(() =>
  latencyLabel(props.request.latency_ms ?? null, props.request.status === 'in_progress'),
)

// 2px status border. The border sits on the OUTSIDE of the tile so
// the inner text never gets clipped.
const borderColor = computed(() => statusBorderColor(props.request.status))
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
  if (r.latency_ms != null) lines.push(`Latency: ${latencyText.value}`)
  if (r.total_tokens != null) {
    lines.push(`Tokens: ${r.total_tokens}`)
  } else if (r.prompt_tokens != null || r.completion_tokens != null) {
    const p = r.prompt_tokens ?? 0
    const c = r.completion_tokens ?? 0
    lines.push(`Tokens: ${p}+${c}`)
  }
  if (r.cost_usd != null) lines.push(`Cost: $${r.cost_usd.toFixed(4)}`)
  if (r.error_kind) lines.push(`Error: ${r.error_kind}`)
  if (r.request_id) lines.push(`ID: ${r.request_id.slice(0, 8)}`)
  try {
    lines.push(`Time: ${new Date(r.ts).toLocaleString(locale.value)}`)
  } catch {
    /* ignore */
  }
  return lines.join('\n')
})

function onClick() {
  if (!isIdle.value && props.request.request_id) {
    emit('select', props.request.request_id)
  }
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

  <!-- Real tile: 3 lines + 2px status border. -->
  <div
    v-else
    class="live-block"
    :class="{
      'live-block--clickable': !!request.request_id,
      'live-block--in-progress': isPulsing,
    }"
    role="button"
    tabindex="0"
    :aria-label="tooltip"
    :title="tooltip"
    :style="{ borderColor: borderColor }"
    @click="onClick"
    @keyup.enter="onClick"
    @keyup.space.prevent="onClick"
  >
    <span class="live-block__time">{{ timeLabel }}</span>
    <span class="live-block__vendor" :style="{ color: secondLineColor }">
      {{ vendorLabel }}
    </span>
    <span class="live-block__latency">{{ latencyText }}</span>
  </div>
</template>

<style scoped>
/* 2026-07-03 v3 — 3-line text tile.
 *
 *   width  52px   ← fits ~22-23 tiles in a 1280px dashboard track
 *   height 60px   ← 3 lines × ~16px + 4px padding
 *   border 2px    ← status colour sits on the outside, not inside
 *   font   9-10px ← small enough to fit 3 lines without crowding
 */
.live-block {
  box-sizing: border-box;
  width: 52px;
  height: 60px;
  border-radius: 4px;
  border: 2px solid transparent;
  background: var(--bg-subtle, #161b22);
  color: var(--text, #e6edf3);
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: space-around;
  padding: 2px 2px;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  /* `position: relative` so hover-scale doesn't escape the track's
   * overflow:hidden (see below). */
  position: relative;
  transition: transform 0.15s ease, box-shadow 0.15s ease;
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

/* Line 1: time HH:MM. The lightest weight because time is the
 * least identifying info (the swim lane is a ~minute wide). */
.live-block__time {
  font-size: 9px;
  line-height: 1;
  color: var(--muted, #8b949e);
  letter-spacing: 0.3px;
}

/* Line 2: vendor code / error_kind. Largest font — this is what
 * the operator reads to identify the row at a glance. */
.live-block__vendor {
  font-size: 11px;
  font-weight: 700;
  line-height: 1;
  letter-spacing: 0.5px;
  color: var(--text, #e6edf3);
  /* If the vendor label is too wide, ellipsise instead of
   * overflowing the 52px tile. */
  max-width: 100%;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* Line 3: latency. Slightly muted so it doesn't compete with
 * the vendor label. */
.live-block__latency {
  font-size: 10px;
  line-height: 1;
  color: var(--muted, #8b949e);
  font-variant-numeric: tabular-nums;
}

/* Idle marker: 3x wider so a silence reads as a distinct shape. */
.live-block--idle {
  width: 110px;
  height: 60px;
  border: 2px dashed var(--border, #30363d);
  background: transparent;
  color: var(--muted, #8b949e);
  cursor: default;
}
.live-block__idle-text {
  font-size: 11px;
  font-weight: 500;
}
</style>