<script setup lang="ts">
// LiveRequestBlock — single tile in the swim lane.
//
// 2026-07-03 revision: shrunk the tile from 56x80 to 22x40 so 30-50
// requests fit in one viewport, and replaced the model-abbrev label
// with a single uppercase family letter. The full model name and
// every other request detail (latency / tokens / cost / error / time
// / provider) is now surfaced only in the hover tooltip — the tile
// itself shows the family + status at a glance.
//
// Why: the dashboard's first impression is the silhouette of the
// last minute. A wall of 100 wide tiles was unreadable; 50 narrow
// tiles each carry one glyph + status colour, and the tooltip
// carries the rest on demand.
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import type { LiveRequest } from '../composables/useLiveStream'
import { getModelCategoryColor, getStatusColor } from '../composables/liveStreamColors'
import { modelGlyph } from '../composables/liveStreamDisplay'

const props = defineProps<{
  request: LiveRequest
}>()

const emit = defineEmits<{
  /** Fired when the user clicks a real (non-idle) tile. */
  select: [requestId: string]
}>()

const { t, locale } = useI18n()

const isIdle = computed(() => props.request.type === 'idle_marker')

// Idle label: "Idle 1 min" / "Idle 2 min" — cosmetic, derived from
// the timestamp vs now. The backend emits one idle_marker per minute
// of silence, so this stays accurate enough.
const idleLabel = computed(() => {
  if (!isIdle.value) return ''
  const start = Date.parse(props.request.ts)
  if (Number.isNaN(start)) return '—'
  const minutes = Math.max(1, Math.round((Date.now() - start) / 60_000))
  return t('dashboard.liveStream.idleLabel', { duration: `${minutes}m` })
})

const modelLabel = computed(() => modelGlyph(props.request.model))

const latencyLabel = computed(() => {
  if (props.request.status === 'in_progress') return '…'
  const ms = props.request.latency_ms
  if (ms == null) return '—'
  if (ms < 1000) return `${ms}ms`
  return `${(ms / 1000).toFixed(1)}s`
})

/**
 * Multi-line tooltip rendered on hover. Built once per request so
 * `request_id`, `model`, `status`, `latency_ms`, `total_tokens`,
 * `cost_usd`, `error_kind` and a localised time are all reachable
 * without leaving the swim lane.
 *
 * Native `title` is used on purpose (vs a custom popover):
 *   - the swim lane lives inside an overflow:auto track; a popover
 *     would clip on the right edge of the viewport
 *   - the track is already keyboard-navigable; native title bubbles
 *     to screen readers
 *   - the operator reads ~50 tiles in a sweep, native title is the
 *     lowest-friction way to surface detail on demand
 */
const tooltip = computed(() => {
  const r = props.request
  const lines: string[] = []
  if (r.model) lines.push(`${t('dashboard.liveStream.tooltip.model')}: ${r.model}`)
  if (r.provider_code) lines.push(`${t('dashboard.liveStream.tooltip.provider')}: ${r.provider_code}`)
  lines.push(`${t('dashboard.liveStream.tooltip.status')}: ${r.status ?? '?'}`)
  if (r.latency_ms != null) lines.push(`${t('dashboard.liveStream.tooltip.latency')}: ${latencyLabel.value}`)
  if (r.total_tokens != null) {
    lines.push(`${t('dashboard.liveStream.tooltip.tokens')}: ${r.total_tokens}`)
  } else if (r.prompt_tokens != null || r.completion_tokens != null) {
    const p = r.prompt_tokens ?? 0
    const c = r.completion_tokens ?? 0
    lines.push(`${t('dashboard.liveStream.tooltip.tokens')}: ${p}+${c}`)
  }
  if (r.cost_usd != null) lines.push(`${t('dashboard.liveStream.tooltip.cost')}: $${r.cost_usd.toFixed(4)}`)
  if (r.error_kind) lines.push(`${t('dashboard.liveStream.tooltip.error')}: ${r.error_kind}`)
  if (r.request_id) lines.push(`ID: ${r.request_id.slice(0, 8)}`)
  try {
    lines.push(`${t('dashboard.liveStream.tooltip.time')}: ${new Date(r.ts).toLocaleTimeString(locale.value)}`)
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
  <div
    v-if="isIdle"
    class="live-block live-block--idle"
    :title="idleLabel"
    aria-hidden="true"
  >
    <span class="live-block__idle-text">{{ idleLabel }}</span>
  </div>
  <div
    v-else
    class="live-block"
    :class="{ 'live-block--clickable': !!request.request_id }"
    role="button"
    tabindex="0"
    :aria-label="tooltip"
    :title="tooltip"
    @click="onClick"
    @keyup.enter="onClick"
    @keyup.space.prevent="onClick"
  >
    <!--
      Single-letter family glyph + a thin status stripe at the
      bottom. Background of the top half is the model-family colour
      so the swim lane is still a heatmap of model usage.
    -->
    <div
      class="live-block__top"
      :style="{ background: getModelCategoryColor(request.model_category) }"
    >
      {{ modelLabel }}
    </div>
    <div
      class="live-block__bottom"
      :style="{ background: getStatusColor(request.status) }"
    />
  </div>
</template>

<style scoped>
/* 2026-07-03 dark-mode + narrow-tile revision.
 *
 * The tile is 22x40px so 50 of them line up in ~1100px of track.
 * The model's first letter sits in the top half; the status
 * colour shows up only as a 4px stripe at the bottom so the family
 * colour still dominates the visual weight of the swim lane. */
.live-block {
  width: 22px;
  height: 40px;
  border-radius: 3px;
  overflow: hidden;
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  border: 1px solid rgba(255, 255, 255, 0.04);
  transition: transform 0.12s ease, box-shadow 0.12s ease;
  background: transparent;
  position: relative;
}

.live-block--clickable {
  cursor: pointer;
}
.live-block--clickable:hover,
.live-block--clickable:focus-visible {
  transform: translateY(-2px) scale(1.18);
  /* z-index lifts the tile above the track's overflow:hidden so the
   * scale doesn't get clipped at the track edges. */
  z-index: 2;
  box-shadow: 0 4px 14px rgba(99, 102, 241, 0.45);
  outline: none;
}

.live-block__top {
  flex: 1 1 auto;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.5px;
  /* Top half is the model-family colour (the dominant signal). */
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.45);
}

.live-block__bottom {
  /* Status stripe: only 4px so the family colour still carries the
   * visual weight. The full block stays <= 40px tall. */
  flex: 0 0 4px;
  width: 100%;
}

/* Idle marker stays a wide dashed block so 1 minute of silence
 * reads as a different shape from a real request. */
.live-block--idle {
  width: 90px;
  height: 40px;
  border: 2px dashed var(--border, #30363d);
  background: transparent;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--muted, #8b949e);
  font-size: 11px;
  cursor: default;
}
.live-block__idle-text {
  text-align: center;
  font-weight: 500;
}
</style>
