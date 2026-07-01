<script setup lang="ts">
// LanguageSwitcher.vue — dropdown to pick the UI locale.
// Shown in the app header (main + guest layouts). Persists the choice via
// useLocale.changeLocale (which writes store.lang + sets <html lang/dir>).
import { ref } from 'vue'
import { useLocale } from '../i18n/useLocale'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()
const { locale, supportedLocales, changeLocale } = useLocale()

const open = ref(false)

function currentMeta() {
  return supportedLocales.find((l) => l.code === locale.value)
}

// Close on blur, but defer so a click on an option (which blurs the trigger)
// still registers before the menu disappears.
function scheduleClose() {
  setTimeout(() => (open.value = false), 150)
}

async function pick(code: string) {
  open.value = false
  await changeLocale(code)
}
</script>

<template>
  <div class="lang-switcher" :class="{ open }">
    <button
      type="button"
      class="lang-trigger btn btn-ghost btn-sm"
      :title="t('app.lang.switch')"
      :aria-expanded="open"
      @click="open = !open"
      @blur="scheduleClose"
    >
      <span class="lang-flag" aria-hidden="true">{{ currentMeta()?.flag ?? '🌐' }}</span>
      <span class="lang-code">{{ currentMeta()?.short ?? locale }}</span>
    </button>
    <div v-if="open" class="lang-menu" role="menu">
      <button
        v-for="l in supportedLocales"
        :key="l.code"
        type="button"
        class="lang-option"
        :class="{ active: l.code === locale }"
        role="menuitemradio"
        :aria-checked="l.code === locale"
        @mousedown.prevent="pick(l.code)"
      >
        <span class="lang-flag" aria-hidden="true">{{ l.flag }}</span>
        <span class="lang-native">{{ l.nativeName }}</span>
        <span v-if="l.code === locale" class="lang-check" aria-hidden="true">✓</span>
      </button>
    </div>
  </div>
</template>

<style scoped>
.lang-switcher {
  position: relative;
  flex-shrink: 0;
}

.lang-trigger {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  white-space: nowrap;
}

.lang-flag {
  font-size: 14px;
  line-height: 1;
}

.lang-code {
  font-weight: 600;
}

.lang-menu {
  position: absolute;
  top: calc(100% + 4px);
  inset-inline-end: 0;
  min-width: 180px;
  max-height: 320px;
  overflow-y: auto;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 8px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.35);
  padding: 4px;
  z-index: 100;
}

.lang-option {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  padding: 7px 10px;
  border: none;
  border-radius: 6px;
  background: transparent;
  color: var(--text);
  font-size: 13px;
  text-align: start;
  cursor: pointer;
  transition: background 0.15s;
}

.lang-option:hover {
  background: rgba(255, 255, 255, 0.06);
}

.lang-option.active {
  background: rgba(99, 102, 241, 0.15);
  color: var(--accent-h);
}

.lang-native {
  flex: 1;
  min-width: 0;
}

.lang-check {
  color: var(--accent-h);
  font-size: 12px;
}
</style>
