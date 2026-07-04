<script setup lang="ts">
// LiveStreamLegend — colour key for the swim lane.
//
// Two rows of swatches: model family + status. Reused palette from
// composables/liveStreamColors so the legend and the tiles stay
// visually identical without hard-coding hex strings in two places.
//
// 2026-07-04: Updated to support dynamic provider list from top providers API
// instead of hardcoded openai/anthropic/domestic/oss/other categories.
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import {
  MODEL_COLORS,
  STATUS_COLORS,
  MODEL_FAMILY_LABELS,
  STATUS_LABELS,
  loadTopProviders,
} from '../composables/liveStreamColors'

const { t } = useI18n()

// Track if providers are loaded
const providersLoaded = ref(false)

// Computed property for model entries that updates when MODEL_COLORS changes
const modelEntries = computed(() => {
  const keys = Object.keys(MODEL_COLORS).filter(k => k !== 'other')
  const entries = keys.map((key) => ({
    key,
    color: MODEL_COLORS[key],
    label: MODEL_FAMILY_LABELS[key] || key,
  }))
  
  // Add "other" at the end
  entries.push({
    key: 'other',
    color: MODEL_COLORS.other,
    label: MODEL_FAMILY_LABELS.other || 'Other',
  })
  
  return entries
})

const statusEntries = (['success', 'inProgress', 'failure'] as const).map((key) => ({
  key,
  color: STATUS_COLORS[key === 'inProgress' ? 'in_progress' : key],
  label: t(`dashboard.liveStream.legend.${key}`, STATUS_LABELS[key === 'inProgress' ? 'in_progress' : key]),
}))

// Load top providers on mount
onMounted(async () => {
  await loadTopProviders(6, 7) // Top 6 providers from last 7 days
  providersLoaded.value = true
})
</script>

<template>
  <div class="live-legend">
    <div class="live-legend__row">
      <span class="live-legend__heading">{{ t('dashboard.liveStream.legend.model') }}</span>
      <span
        v-for="m in modelEntries"
        :key="m.key"
        class="live-legend__item"
      >
        <span
          class="live-legend__swatch"
          :style="{ background: m.color }"
          aria-hidden="true"
        />
        <span class="live-legend__label">{{ m.label }}</span>
      </span>
    </div>
    <div class="live-legend__row">
      <span class="live-legend__heading">{{ t('dashboard.liveStream.legend.status') }}</span>
      <span
        v-for="s in statusEntries"
        :key="s.key"
        class="live-legend__item"
      >
        <span
          class="live-legend__swatch"
          :style="{ background: s.color }"
          aria-hidden="true"
        />
        <span class="live-legend__label">{{ s.label }}</span>
      </span>
    </div>
  </div>
</template>

<style scoped>
/* 2026-07-03 dark-mode audit: pull every fallback to the project's
 * --muted / --text / --border tokens so the legend blends with the
 * surrounding dashboard chrome instead of rendering as a bright bar.
 */
.live-legend {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 18px;
  font-size: 12px;
  color: var(--muted, #8b949e);
  padding: 8px 4px 2px;
  margin-top: 4px;
  border-top: 1px solid var(--border, #30363d);
}

.live-legend__row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px 12px;
}

.live-legend__heading {
  font-weight: 600;
  color: var(--text, #e6edf3);
  margin-inline-end: 4px;
}

.live-legend__item {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}

.live-legend__swatch {
  display: inline-block;
  width: 12px;
  height: 12px;
  border-radius: 3px;
  /* Subtle 1px inner highlight keeps the swatch from looking like
   * a hole punched in the dark card. */
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.08);
}

.live-legend__label {
  line-height: 1;
  color: var(--muted, #8b949e);
}
</style>
