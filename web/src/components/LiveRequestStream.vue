<script setup lang="ts">
// LiveRequestStream — swim-lane container (v3).
//
// 2026-07-03 revision: dynamic tile counting via ResizeObserver so
// the operator never sees a horizontal scrollbar. The number of
// tiles rendered = floor((track_width - idle_reservation) / tile_pitch).
// When the live buffer grows past the visible count, the oldest
// entry is hidden (display:none) instead of horizontally scrolling.
//
// Tile entrance animation: the new tile slides in from the RIGHT
// of the track with a small overshoot, then settles. The
// `transition-group` keyed on request_id keeps Vue from re-animating
// every tile whenever one is added — only the freshly-appended
// tail tile gets the entrance animation.
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useLiveStream } from '../composables/useLiveStream'
import { useElementSize } from '../composables/useElementSize'
import { statusCategory, type StatusCategory } from '../composables/liveStreamDisplay'
import LiveRequestBlock from './LiveRequestBlock.vue'
import LiveStreamLegend from './LiveStreamLegend.vue'

const emit = defineEmits<{
  /** Bubble a tile click up so DashboardView can open the detail drawer. */
  openDetail: [requestId: string]
}>()

const { t } = useI18n()
const { requests, connection, paused, togglePause } = useLiveStream()

type StatusFilter = 'all' | 'success' | 'in_progress' | StatusCategory
const statusFilter = ref<StatusFilter>('all')

const filteredRequests = computed(() => {
  if (statusFilter.value === 'all') return requests.value
  return requests.value.filter((r) => {
    if (r.type === 'idle_marker') return true
    // 'success' / 'in_progress' match the raw status directly. The
    // failure_* buckets come from statusCategory(), which inspects
    // both `status` and `error_kind` to decide which of the 5
    // coarse failure families the request belongs to.
    if (statusFilter.value === 'success' || statusFilter.value === 'in_progress') {
      return r.status === statusFilter.value
    }
    return statusCategory(r.status, r.error_kind ?? null) === statusFilter.value
  })
})

// --- Dynamic tile counting -------------------------------------------------

// Tile pitch = 52px wide + 4px gap. Reserve ~120px on the right so
// the entrance animation has room to overshoot without escaping the
// track. The idle marker is wider (110px) and counted separately.
// Tile pitch = 60px wide + 4px gap. Reserve ~24px on the right so
// the entrance animation has room to overshoot without escaping
// the track. The idle marker is wider (110px) and counted
// separately.
const TILE_WIDTH = 60
const TILE_GAP = 4
const TILE_PITCH = TILE_WIDTH + TILE_GAP
const IDLE_WIDTH = 110
const ENTRANCE_RESERVE_PX = 24

const trackRef = ref<HTMLElement | null>(null)
const { width: trackWidth } = useElementSize(trackRef)

// Count only real tiles (skip idle markers — they're a separate
// visual element with a fixed width). The track reserves one tile
// of overshoot room so the entrance animation never clips.
const realTileCount = computed(() =>
  filteredRequests.value.filter((r) => r.type !== 'idle_marker').length,
)

const visibleTileCount = computed(() => {
  if (trackWidth.value <= 0) return 0
  const usable = trackWidth.value - ENTRANCE_RESERVE_PX
  return Math.max(0, Math.floor(usable / TILE_PITCH))
})

// Which slice of `filteredRequests` actually renders. The head of
// the array is the OLDEST request; the tail is the NEWEST. We want
// the newest N visible, so we slice from the end. Idle markers
// stay visible regardless of the cap (they're meaningful context).
const visibleRequests = computed(() => {
  const all = filteredRequests.value
  const reals = all.filter((r) => r.type !== 'idle_marker')
  const idles = all.filter((r) => r.type === 'idle_marker')
  if (visibleTileCount.value >= reals.length) {
    return all
  }
  const take = reals.slice(reals.length - visibleTileCount.value)
  return [...idles, ...take]
})

const connectionLabel = computed(() => {
  if (connection.value === 'open') return t('dashboard.liveStream.connected')
  return t('dashboard.liveStream.disconnected')
})

function onSelect(requestId: string) {
  emit('openDetail', requestId)
}
</script>

<template>
  <div class="live-stream">
    <div class="live-stream__header">
      <h3 class="live-stream__title">{{ t('dashboard.liveStream.title') }}</h3>
      <div class="live-stream__controls">
        <span
          class="live-stream__status"
          :class="{
            'live-stream__status--ok': connection === 'open',
            'live-stream__status--warn': connection !== 'open',
          }"
        >
          <span class="live-stream__dot" aria-hidden="true" />
          {{ connectionLabel }}
        </span>
        <button
          type="button"
          class="live-stream__btn"
          @click="togglePause"
        >
          {{ paused ? t('dashboard.liveStream.resume') : t('dashboard.liveStream.pause') }}
        </button>
        <select v-model="statusFilter" class="live-stream__select">
          <option value="all">{{ t('dashboard.liveStream.filterAll') }}</option>
          <option value="success">{{ t('dashboard.liveStream.filterSuccess') }}</option>
          <option value="in_progress">{{ t('dashboard.liveStream.filterInProgress') }}</option>
          <optgroup :label="t('dashboard.liveStream.filterGroupFailures')">
            <option value="failure_5xx">{{ t('dashboard.liveStream.filterFailure5xx') }}</option>
            <option value="failure_4xx">{{ t('dashboard.liveStream.filterFailure4xx') }}</option>
            <option value="failure_timeout">{{ t('dashboard.liveStream.filterFailureTimeout') }}</option>
            <option value="failure_not_found">{{ t('dashboard.liveStream.filterFailureNotFound') }}</option>
            <option value="failure_other">{{ t('dashboard.liveStream.filterFailureOther') }}</option>
          </optgroup>
        </select>
        <span
          class="live-stream__count"
          :title="t('dashboard.liveStream.countTooltip', { buffer: realTileCount, visible: visibleTileCount })"
          :aria-label="t('dashboard.liveStream.countAria', { buffer: realTileCount, visible: visibleTileCount })"
        >
          <span class="live-stream__count-num">{{ realTileCount }}</span>
          <span class="live-stream__count-sep">/</span>
          <span class="live-stream__count-num">{{ visibleTileCount }}</span>
        </span>
      </div>
    </div>

    <!--
      The track is `overflow: hidden` on purpose: when the live
      buffer grows beyond the visible window we hide the oldest
      entries (see visibleRequests computed above) so there is
      never a horizontal scrollbar. `position: relative` is the
      anchor for the empty-state overlay.
    -->
    <div ref="trackRef" class="live-stream__track">
      <TransitionGroup name="live-slide" tag="div" class="live-stream__track-inner">
        <LiveRequestBlock
          v-for="(req, idx) in visibleRequests"
          :key="req.request_id ?? `idle-${idx}-${req.ts}`"
          :request="req"
          @select="onSelect"
        />
      </TransitionGroup>
      <div v-if="realTileCount === 0" class="live-stream__empty">
        {{ t('dashboard.loading') }}
      </div>
    </div>

    <LiveStreamLegend />
  </div>
</template>

<style scoped>
/* 2026-07-03 dark-mode v3 revision:
 *   - track is overflow:hidden (no horizontal scrollbar)
 *   - tile pitch is computed at runtime via useElementSize
 *   - 4px tile gap, 6px top/bottom padding, 80px track height
 *     leaves enough room for hover-scale + pulse glow
 *
 * 2026-07-03 v6: header row NEVER wraps. The status / pause button /
 * filter / count are sized so a 1280px dashboard fits all of them
 * on one line; on a narrower viewport the flex children shrink
 * proportionally (text becomes ellipsised, NOT wrapped).
 */
.live-stream {
  border: 1px solid var(--border, #30363d);
  border-radius: var(--radius, 8px);
  background: var(--card, #1c2128);
  padding: 12px 16px 10px;
  margin-bottom: 20px;
}

.live-stream__header {
  display: flex;
  align-items: center;
  /* flex-wrap: nowrap is the single most important rule for this
   * header — the user explicitly asked for "no wrapping" so the
   * status/button/select/count always sit on one row. When the
   * viewport is too narrow, each child shrinks via flex-shrink
   * + min-width: 0 below. */
  flex-wrap: nowrap;
  gap: 10px;
  margin-bottom: 10px;
  /* Push everything into a single row no matter what. */
  min-width: 0;
}

.live-stream__title {
  font-size: 14px;
  font-weight: 600;
  margin: 0;
  color: var(--text, #e6edf3);
  /* The title is the only "always-fits" piece. flex-shrink: 0
   * means the title never gives up its space to the controls. */
  flex-shrink: 0;
  white-space: nowrap;
}

.live-stream__controls {
  display: flex;
  align-items: center;
  gap: 8px;
  /* Controls take the remaining space. min-width: 0 lets flex
   * actually shrink the children below their intrinsic width. */
  flex: 1 1 auto;
  min-width: 0;
  justify-content: flex-end;
  /* All children must NOT wrap; long labels become ellipsised
   * via the .live-stream__select override below. */
  flex-wrap: nowrap;
  overflow: hidden;
}

.live-stream__status {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: var(--muted, #8b949e);
  flex-shrink: 0;
  white-space: nowrap;
}
.live-stream__dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--muted, #8b949e);
  flex-shrink: 0;
}
.live-stream__status--ok .live-stream__dot {
  background: var(--success, #3fb950);
  box-shadow: 0 0 0 3px rgba(63, 185, 80, 0.18);
}
.live-stream__status--warn .live-stream__dot {
  background: var(--warning, #d29922);
  animation: live-dot-pulse 1.4s ease-in-out infinite;
}
@keyframes live-dot-pulse {
  0%, 100% { opacity: 1; }
  50%      { opacity: 0.4; }
}

/* Pause/resume button. Fixed width so the row layout is stable
 * across locales (zh-CN 的 "继续" / en-US 的 "Resume" are 2 vs 6
 * chars but both fit in the same column). */
.live-stream__btn {
  font-size: 12px;
  padding: 4px 10px;
  border-radius: 4px;
  border: 1px solid var(--border, #30363d);
  background: var(--bg, #0f1117);
  color: var(--text, #e6edf3);
  cursor: pointer;
  flex-shrink: 0;
  white-space: nowrap;
  min-width: 64px;
}
.live-stream__btn:hover {
  background: var(--bg-subtle, #161b22);
  border-color: var(--accent, #6366f1);
}

/* Filter <select>. This is the longest element in the row and the
 * most likely to overflow — we give it a min-width, a max-width,
 * and let it shrink when the row is narrow. The displayed text
 * comes from i18n, so we set min-width based on the *longest*
 * locale label (~"Routing / model not found" = 30 chars). 30ch
 * keeps the row balanced in English while still letting zh-CN's
 * 14-char label expand into the available space. */
.live-stream__select {
  font-size: 12px;
  padding: 4px 10px;
  border-radius: 4px;
  border: 1px solid var(--border, #30363d);
  background: var(--bg, #0f1117);
  color: var(--text, #e6edf3);
  cursor: pointer;
  /* Width policy:
   *   - min-width 120px so the dropdown always shows the current
   *     selection truncated to "Failure bre…" (the longest stable
   *     prefix)
   *   - max-width 220px so on a 1920px display the filter does not
   *     eat the count badge
   *   - flex 0 1 auto lets the select shrink below intrinsic width
   *     but still honour min-width */
  flex: 0 1 auto;
  min-width: 120px;
  max-width: 220px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.live-stream__select option {
  background: var(--card, #1c2128);
  color: var(--text, #e6edf3);
}

/* Counter badge: fixed width (matches 3 digits + / + 2 digits). */
.live-stream__count {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  white-space: nowrap;
  flex-shrink: 0;
  font-size: 12px;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  color: var(--muted, #8b949e);
  padding: 4px 10px;
  border: 1px solid var(--border, #30363d);
  border-radius: 4px;
  background: var(--bg, #0f1117);
  font-variant-numeric: tabular-nums;
  min-width: 78px;
  justify-content: center;
}
.live-stream__count-num {
  color: var(--text, #e6edf3);
  font-weight: 600;
}
.live-stream__count-sep {
  color: var(--border, #30363d);
}

.live-stream__track {
  position: relative;
  height: 80px;
  /* overflow:hidden — never a scrollbar. The newest N tiles fit
   * the track; older ones are dropped from the rendered slice. */
  overflow: hidden;
  background: var(--bg-subtle, #161b22);
  border: 1px solid var(--border, #30363d);
  border-radius: 6px;
  padding: 6px 8px;
}

.live-stream__track-inner {
  display: flex;
  align-items: center;
  gap: 4px;
  height: 100%;
  min-height: 60px;
  /* Right-aligned so the newest tile (which Vue appends to the end)
   * stays anchored to the right edge — the slide-in animation
   * reads as "新数据从右进入" rather than "from somewhere in the
   * middle". `flex-end` keeps the trailing edge stable. */
  justify-content: flex-end;
}

.live-stream__empty {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--muted, #8b949e);
  font-size: 12px;
  pointer-events: none;
}

/* Slide-in from the right.
 *
 *   enter-from: starts 40px to the right + faded — matches the
 *               overshoot distance of the entrance-reserve space
 *   enter-active: 0.45s cubic-bezier with a tiny overshoot so the
 *               new tile pops in and settles without feeling
 *               mechanical
 *   leave:        absolute position so the leaving tile is removed
 *               from the flex flow and the rest reflow correctly */
.live-slide-enter-active {
  transition:
    transform 0.45s cubic-bezier(0.18, 1.25, 0.32, 1.0),
    opacity 0.35s ease;
}
.live-slide-enter-from {
  opacity: 0;
  transform: translateX(40px);
}
.live-slide-leave-active {
  transition: transform 0.3s ease, opacity 0.3s ease;
  position: absolute;
}
.live-slide-leave-to {
  opacity: 0;
  transform: translateX(-20px);
}
</style>