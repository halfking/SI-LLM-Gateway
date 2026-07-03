<script setup lang="ts">
// LiveRequestStream — swim-lane container.
//
// Lays out LiveRequestBlock tiles horizontally, left-to-right. The
// composable handles all of the WebSocket lifecycle; this component
// is purely presentation + filter state.
//
// Filters (status + model family) apply on the rendered array only;
// the WebSocket buffer keeps the full set so toggling a filter never
// loses data. Clicking a tile opens the request-detail drawer via
// the existing /api/logs/{id} endpoint.
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useLiveStream, type LiveStatus } from '../composables/useLiveStream'
import LiveRequestBlock from './LiveRequestBlock.vue'
import LiveStreamLegend from './LiveStreamLegend.vue'

const emit = defineEmits<{
  /** Bubble a tile click up so DashboardView can open the detail drawer. */
  openDetail: [requestId: string]
}>()

const { t } = useI18n()
const { requests, connection, paused, togglePause } = useLiveStream()

const statusFilter = ref<'all' | LiveStatus>('all')

const filteredRequests = computed(() => {
  if (statusFilter.value === 'all') return requests.value
  return requests.value.filter((r) => {
    if (r.type === 'idle_marker') return true
    return r.status === statusFilter.value
  })
})

const connectionLabel = computed(() => {
  if (connection.value === 'open') return t('dashboard.liveStream.connected')
  if (connection.value === 'reconnecting' || connection.value === 'connecting') {
    return t('dashboard.liveStream.disconnected')
  }
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
          <option value="failure">{{ t('dashboard.liveStream.filterFailure') }}</option>
        </select>
      </div>
    </div>

    <div class="live-stream__track">
      <TransitionGroup name="live-slide" tag="div" class="live-stream__track-inner">
        <LiveRequestBlock
          v-for="(req, idx) in filteredRequests"
          :key="req.request_id ?? `idle-${idx}`"
          :request="req"
          @select="onSelect"
        />
      </TransitionGroup>
      <div v-if="filteredRequests.length === 0" class="live-stream__empty">
        {{ t('dashboard.loading') }}
      </div>
    </div>

    <LiveStreamLegend />
  </div>
</template>

<style scoped>
/* 2026-07-03 dark-mode audit: every fallback swapped from light
 * defaults (--surface, --surface-secondary, #fff) to the project's
 * GitHub-Dark-Dimmed tokens. The container is now indistinguishable
 * in weight from .stat-card next to it; the only visual differentiator
 * is the horizontal track underneath, which uses --bg-subtle so the
 * blocks float against a darker band.
 */
.live-stream {
  border: 1px solid var(--border, #30363d);
  border-radius: var(--radius, 8px);
  background: var(--card, #1c2128);
  padding: 14px 16px 10px;
  margin-bottom: 20px;
}

.live-stream__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 8px 12px;
  margin-bottom: 12px;
}

.live-stream__title {
  font-size: 14px;
  font-weight: 600;
  margin: 0;
  color: var(--text, #e6edf3);
}

.live-stream__controls {
  display: flex;
  align-items: center;
  gap: 8px;
}

.live-stream__status {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: var(--muted, #8b949e);
}
.live-stream__dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--muted, #8b949e);
}
.live-stream__status--ok .live-stream__dot {
  background: var(--success, #3fb950);
  /* Glow tuned for #1c2128 — a transparent halo of the success
   * colour so the dot reads as "alive" without looking neon. */
  box-shadow: 0 0 0 3px rgba(63, 185, 80, 0.18);
}
.live-stream__status--warn .live-stream__dot {
  background: var(--warning, #d29922);
  animation: pulse 1.4s ease-in-out infinite;
}
@keyframes pulse {
  0%, 100% { opacity: 1; }
  50%      { opacity: 0.4; }
}

.live-stream__btn,
.live-stream__select {
  font-size: 12px;
  padding: 4px 10px;
  border-radius: 4px;
  border: 1px solid var(--border, #30363d);
  background: var(--bg, #0f1117);
  color: var(--text, #e6edf3);
  cursor: pointer;
}
.live-stream__btn:hover {
  background: var(--bg-subtle, #161b22);
  border-color: var(--accent, #6366f1);
}
.live-stream__select option {
  background: var(--card, #1c2128);
  color: var(--text, #e6edf3);
}

.live-stream__track {
  position: relative;
  /* 2026-07-03: tiles are now 22x40 so the track height drops to
   * fit 40px tiles + 12px top/bottom padding + a few pixels of
   * breathing room. Was 110px when tiles were 56x80. */
  height: 64px;
  overflow-x: auto;
  overflow-y: hidden;
  /* --bg-subtle (#161b22) is one shade darker than --card, which
   * makes the coloured tiles pop without requiring an outline. */
  background: var(--bg-subtle, #161b22);
  border: 1px solid var(--border, #30363d);
  border-radius: 6px;
  padding: 12px;
  /* Custom dark-mode scrollbar so the horizontal scroll does not
   * flash a bright white bar on hover. */
  scrollbar-color: var(--border, #30363d) transparent;
}
.live-stream__track-inner {
  display: flex;
  align-items: center;
  /* 3px gap so 50 tiles (~22+3 = 25px each) take ~1250px of track.
   * The browser will horizontally scroll any overflow. */
  gap: 3px;
  height: 100%;
  min-height: 40px;
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

/* Slide-in for new tiles appended on the right.
 * 2026-07-03: shifted from 24px to 10px because the new tiles are
 * only 22px wide — 24px translate would make new tiles visibly jump
 * over an empty neighbour. Shadow tuned to match the project's
 * accent glow so the entrance feels native to the dark theme. */
.live-slide-enter-active {
  transition: transform 0.4s cubic-bezier(0.16, 1, 0.3, 1), opacity 0.3s ease;
}
.live-slide-enter-from {
  opacity: 0;
  transform: translateX(10px);
}
.live-slide-leave-active {
  transition: transform 0.3s ease, opacity 0.3s ease;
  position: absolute;
}
.live-slide-leave-to {
  opacity: 0;
  transform: translateX(-10px);
}
</style>