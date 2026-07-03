<script setup lang="ts">
// LiveRequestBlock — single tile in the swim lane.
//
// Two horizontal halves:
//   - top: model family colour + abbreviated model name
//   - bottom: status colour + latency (or spinner for in_progress)
//
// Idle markers render as a wide dashed block with a relative-time
// label instead of the two-half layout, so a long silence is visually
// distinct from a row of real requests.
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import type { LiveRequest } from '../composables/useLiveStream'
import { getModelCategoryColor, getStatusColor } from '../composables/liveStreamColors'

const props = defineProps<{
  request: LiveRequest
}>()

const emit = defineEmits<{
  /** Fired when the user clicks a real (non-idle) tile. */
  select: [requestId: string]
}>()

const { t, locale } = useI18n()

const isIdle = computed(() => props.request.type === 'idle_marker')

// Idle label: "Idle 1 min" / "Idle 2 min" — approximate, computed
// from ts vs now. Backend guarantees one idle_marker per minute of
// silence, so this is purely cosmetic.
const idleLabel = computed(() => {
  if (!isIdle.value) return ''
  const start = Date.parse(props.request.ts)
  if (Number.isNaN(start)) return '—'
  const minutes = Math.max(1, Math.round((Date.now() - start) / 60_000))
  return t('dashboard.liveStream.idleLabel', { duration: `${minutes}m` })
})

const modelShort = computed(() => {
  const m = props.request.model || ''
  if (!m) return '—'
  // Strip leading vendor prefix for readability: gpt-4o-mini → 4o-mini.
  // Common prefixes the classifier already mapped.
  return m
    .replace(/^gpt-/, '')
    .replace(/^claude-/, '')
    .replace(/^qwen-/, '')
    .replace(/^qwen2-/, '')
    .replace(/^glm-/, '')
    .replace(/^deepseek-/, '')
    .replace(/^moonshot-/, '')
    .slice(0, 12)
})

const latencyLabel = computed(() => {
  if (props.request.status === 'in_progress') return '…'
  const ms = props.request.latency_ms
  if (ms == null) return '—'
  if (ms < 1000) return `${ms}ms`
  return `${(ms / 1000).toFixed(1)}s`
})

const tooltip = computed(() => {
  const r = props.request
  const lines: string[] = []
  if (r.model) lines.push(`${t('dashboard.liveStream.tooltip.model')}: ${r.model}`)
  if (r.provider_code) lines.push(`${t('dashboard.liveStream.tooltip.provider')}: ${r.provider_code}`)
  if (r.status) lines.push(`${t('dashboard.liveStream.tooltip.status')}: ${r.status}`)
  if (r.latency_ms != null) lines.push(`${t('dashboard.liveStream.tooltip.latency')}: ${latencyLabel.value}`)
  if (r.total_tokens != null) lines.push(`${t('dashboard.liveStream.tooltip.tokens')}: ${r.total_tokens}`)
  if (r.cost_usd != null) lines.push(`${t('dashboard.liveStream.tooltip.cost')}: $${r.cost_usd.toFixed(4)}`)
  if (r.error_kind) lines.push(`${t('dashboard.liveStream.tooltip.error')}: ${r.error_kind}`)
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
    <div
      class="live-block__top"
      :style="{ background: getModelCategoryColor(request.model_category) }"
    >
      {{ modelShort }}
    </div>
    <div
      class="live-block__bottom"
      :style="{ background: getStatusColor(request.status) }"
    >
      {{ latencyLabel }}
    </div>
  </div>
</template>

<style scoped>
/* 2026-07-03 dark-mode audit:
 * The project skin is GitHub-Dark-Dimmed with --card #1c2128 /
 * --border #30363d. We follow those tokens rather than hand-picking
 * our own pale defaults so the swim lane sits inside the same
 * surface as the rest of the dashboard.
 *
 * The two coloured halves are filled by inline :style bindings
 * from getModelCategoryColor / getStatusColor, which were tuned
 * for #1c2128 (see composables/liveStreamColors.ts).
 */
.live-block {
  width: 56px;
  height: 80px;
  border-radius: 6px;
  overflow: hidden;
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  /* A thin border from the project's palette keeps the tile from
   * melting into the track on dark backgrounds. We omit it when the
   * top half already supplies a saturated fill (the bind below sets
   * the background on .live-block__top/.live-block__bottom). */
  border: 1px solid rgba(255, 255, 255, 0.04);
  transition: transform 0.15s ease, box-shadow 0.15s ease;
  background: transparent;
}

.live-block--clickable {
  cursor: pointer;
}
.live-block--clickable:hover,
.live-block--clickable:focus-visible {
  transform: translateY(-2px) scale(1.04);
  /* Shadow softened for dark theme — pure black on dark is invisible,
   * a slight blue tint matches --accent and keeps the depth cue. */
  box-shadow: 0 4px 14px rgba(99, 102, 241, 0.35);
  outline: none;
}

.live-block__top,
.live-block__bottom {
  flex: 1 1 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  font-size: 11px;
  font-weight: 600;
  padding: 2px 4px;
  text-align: center;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
  /* Slight inner shadow makes the colour readable when blocks sit
   * next to similarly-saturated neighbours (e.g. amber + orange). */
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.45);
}

.live-block--idle {
  width: 110px;
  border: 2px dashed var(--border, #30363d);
  background: transparent;
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