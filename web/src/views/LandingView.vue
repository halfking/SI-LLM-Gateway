<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import ServiceLandingPage from '../components/ServiceLandingPage.vue';

const { t } = useI18n()

// Feature cards (8) — keys are camelCase ids that match `landing.features.<id>`
// in the i18n bundles. The icon is purely visual and stays in code.
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
    const f = t(`landing.features.${key}`, {}, { returnObjects: true }) as {
      title: string
      description: string
      badge?: string
    }
    return { icon, title: f.title, description: f.description, badge: f.badge }
  }),
)

const ADVANTAGE_META: ReadonlyArray<{ key: string; icon: string }> = [
  { key: 'local', icon: '🇨🇳' },
  { key: 'private', icon: '🔒' },
  { key: 'antiBan', icon: '🛡️' },
  { key: 'perf', icon: '⚡' },
]

const advantages = computed(() =>
  ADVANTAGE_META.map(({ key, icon }) => {
    const a = t(`landing.advantages.${key}`, {}, { returnObjects: true }) as {
      title: string
      description: string
    }
    return { icon, title: a.title, description: a.description }
  }),
)

const ROADMAP_KEYS = ['v31', 'v32', 'v40', 'v50'] as const

const roadmapPhases = computed(() =>
  ROADMAP_KEYS.map((k) => {
    const p = t(`landing.roadmap.${k}`, {}, { returnObjects: true }) as {
      phase: string
      title: string
      description: string
    }
    return { phase: p.phase, title: p.title, description: p.description }
  }),
)
</script>

<template>
  <div class="llmgo-landing">
    <ServiceLandingPage
      :kicker="t('landing.kicker')"
      :title="t('landing.title')"
      :subtitle="t('landing.subtitle')"
      :hero-points="(t('landing.heroPoints', {}, { returnObjects: true }) as string[])"
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
