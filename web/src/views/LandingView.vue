<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import ServiceLandingPage from '../components/ServiceLandingPage.vue';

const { t } = useI18n()

// Feature cards (8) — keys are camelCase ids that match `landing.features.<id>`
// in the i18n bundles. The icon is purely visual and stays in code.
//
// Note: vue-i18n v9's `t('a.b.c', {}, { returnObjects: true })` does NOT
// auto-traverse a nested message object — it only returns the raw key
// string when the full key isn't found verbatim in `messages`. We therefore
// look up each leaf string via `t('landing.features.<id>.title')` etc.,
// which works correctly under any locale.
const FEATURE_META: ReadonlyArray<{ key: string; icon: string }> = [
  { key: 'smartRouting', icon: '🧭' },
  { key: 'safety', icon: '🔐' },
  { key: 'cache', icon: '⚡' },
  { key: 'agent', icon: '🤖' },
  { key: 'observability', icon: '📊' },
  { key: 'billing', icon: '💳' },
  { key: 'multiProtocol', icon: '🌐' },
  { key: 'multiTenant', icon: '🏗️' },
]

const features = computed(() =>
  FEATURE_META.map(({ key, icon }) => {
    // vue-i18n returns the raw key (e.g. "landing.features.smartRouting.badge") when
    // a leaf string is missing. Filter those out so optional badges don't render
    // as visible fallback text.
    const rawBadge = t(`landing.features.${key}.badge`)
    const badge = rawBadge.startsWith(`landing.features.${key}.badge`)
      ? undefined
      : (rawBadge || undefined)
    return {
      icon,
      title: t(`landing.features.${key}.title`),
      description: t(`landing.features.${key}.description`),
      badge,
    }
  }),
)

const ADVANTAGE_META: ReadonlyArray<{ key: string; icon: string }> = [
  { key: 'local', icon: '🇨🇳' },
  { key: 'private', icon: '🔒' },
  { key: 'antiBan', icon: '🛡️' },
  { key: 'perf', icon: '⚡' },
]

const advantages = computed(() =>
  ADVANTAGE_META.map(({ key, icon }) => ({
    icon,
    title: t(`landing.advantages.${key}.title`),
    description: t(`landing.advantages.${key}.description`),
  })),
)

const ROADMAP_KEYS = ['v31', 'v32', 'v40', 'v50'] as const

const roadmapPhases = computed(() =>
  ROADMAP_KEYS.map((k) => ({
    phase: t(`landing.roadmap.${k}.phase`),
    title: t(`landing.roadmap.${k}.title`),
    description: t(`landing.roadmap.${k}.description`),
  })),
)

// heroPoints is a 6-element string array. Vue-i18n v9's `t('a.b', { returnObjects: true })`
// cannot auto-traverse a nested message object, so we look up each element via its
// full dot path (which IS how vue-i18n resolves leaf keys in nested trees).
const heroPoints = computed(() =>
  [0, 1, 2, 3, 4, 5].map((i) => t(`landing.heroPoints.${i}`)),
)
</script>

<template>
  <div class="llmgo-landing">
    <ServiceLandingPage
      :kicker="t('landing.kicker')"
      :title="t('landing.title')"
      :subtitle="t('landing.subtitle')"
      :hero-points="heroPoints"
      :features="features"
      :advantages="advantages"
      :advantages-title="t('landing.advantagesTitle')"
      :advantages-subtitle="t('landing.advantagesSubtitle')"
      :footer-text="t('landing.footer')"
      accent="#6366f1"
      :hide-cta="true"
    />

    <!-- 路线图预告区块 -->
    <section class="llmgo-roadmap">
      <div class="llmgo-roadmap__inner">
        <h2 class="llmgo-roadmap__title">{{ t('landing.roadmap.title') }}</h2>
        <p class="llmgo-roadmap__sub">{{ t('landing.roadmap.subtitle') }}</p>
        <ol class="llmgo-roadmap__list">
          <li v-for="p in roadmapPhases" :key="p.phase">
            <span class="llmgo-roadmap__phase">{{ p.phase }}</span>
            <strong>{{ p.title }}</strong>
            <span>{{ p.description }}</span>
          </li>
        </ol>
      </div>
    </section>
  </div>
</template>

<style scoped>
.llmgo-landing {
  min-height: 100vh;
  overflow-y: auto;
  background: var(--kx-bg-page, #0f1117);
}

.llmgo-landing :deep(.kx-landing) {
  background: var(--page-bg, #0f1117);
  color: var(--text, #e8eaed);
}

.llmgo-landing :deep(.kx-landing__card),
.llmgo-landing :deep(.kx-landing__adv-flow li) {
  background: var(--panel, #1a1d27);
  border-color: var(--border, #2a2d3a);
}

.llmgo-landing :deep(.kx-landing__points li) {
  background: var(--panel, #1a1d27);
  border-color: var(--border, #2a2d3a);
}

/* 路线图预告区块 */
.llmgo-roadmap {
  padding: 32px 16px 48px;
  max-width: 960px;
  margin: 0 auto;
  width: 100%;
}

.llmgo-roadmap__inner {
  padding: 24px;
  border: 1px solid var(--border, #2a2d3a);
  border-radius: 14px;
  background: var(--panel, #1a1d27);
}

.llmgo-roadmap__title {
  margin: 0 0 4px;
  font-size: 20px;
  font-weight: 600;
  color: #e8eaed;
}

.llmgo-roadmap__sub {
  margin: 0 0 20px;
  font-size: 14px;
  color: #6b7280;
}

.llmgo-roadmap__list {
  display: grid;
  gap: 14px;
  margin: 0;
  padding: 0;
  list-style: none;
}

.llmgo-roadmap__list li {
  display: grid;
  grid-template-columns: 140px 1fr;
  gap: 4px 16px;
  padding: 12px 0;
  border-top: 1px solid var(--border, #2a2d3a);
}

.llmgo-roadmap__list li:first-child {
  border-top: none;
}

.llmgo-roadmap__phase {
  grid-row: span 2;
  align-self: start;
  padding: 4px 10px;
  border-radius: 6px;
  font-size: 12px;
  font-weight: 600;
  color: #a5b4fc;
  background: rgba(99, 102, 241, 0.12);
  white-space: nowrap;
}

.llmgo-roadmap__list strong {
  font-size: 14px;
  font-weight: 600;
  color: #e8eaed;
}

.llmgo-roadmap__list span {
  font-size: 13px;
  line-height: 1.55;
  color: #9aa0a6;
}

@media (max-width: 600px) {
  .llmgo-roadmap__list li {
    grid-template-columns: 1fr;
    gap: 4px;
  }

  .llmgo-roadmap__phase {
    grid-row: auto;
    display: inline-block;
    width: fit-content;
  }
}
</style>
