<script setup lang="ts">
// LiveStreamLegend — colour key for the swim lane.
//
// Two rows of swatches: model family + status. Reused palette from
// composables/liveStreamColors so the legend and the tiles stay
// visually identical without hard-coding hex strings in two places.
//
// i18n keys live under dashboard.liveStream.legend.{model,status}
// plus per-category entries (openai / anthropic / domestic / oss /
// other) and per-status (success / inProgress / failure).
import { useI18n } from 'vue-i18n'
import {
  MODEL_COLORS,
  STATUS_COLORS,
  MODEL_FAMILY_LABELS,
  STATUS_LABELS,
} from '../composables/liveStreamColors'

const { t } = useI18n()

const modelEntries = (['openai', 'anthropic', 'domestic', 'oss', 'other'] as const).map((key) => ({
  key,
  color: MODEL_COLORS[key],
  // Prefer i18n when present; fall back to the English label baked
  // into the colours module so the legend never renders empty.
  label: t(`dashboard.liveStream.legend.${key}`, MODEL_FAMILY_LABELS[key]),
}))

const statusEntries = (['success', 'inProgress', 'failure'] as const).map((key) => ({
  key,
  color: STATUS_COLORS[key === 'inProgress' ? 'in_progress' : key],
  label: t(`dashboard.liveStream.legend.${key}`, STATUS_LABELS[key === 'inProgress' ? 'in_progress' : key]),
}))
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