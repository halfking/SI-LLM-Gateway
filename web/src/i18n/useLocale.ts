// useLocale.ts — reactive locale + switching composable.
//
// Components import { useLocale } and read `locale.value` / `isRTL.value`,
// and call `changeLocale(code)` from the language switcher. The actual
// message loading + <html dir/lang> application lives in i18n/index.ts;
// this composable just wires the reactive surface and persists the choice.

import { computed, ref } from 'vue'
import { i18n, setLocale, localeRef } from './index'
import { setLang } from '../store'
import { SUPPORTED_LOCALES, getLocaleMeta, isRTL as checkRTL } from './constants'

// A single shared ref so every useLocale() call observes the same state.
// localeRef is vue-i18n's reactive locale; we mirror it locally so callers
// don't need to touch the i18n instance directly.
const current = ref(localeRef.value)
localeRef.value // touch to ensure reactivity binding

export function useLocale() {
  const locale = computed({
    get: () => localeRef.value,
    set: (v: string) => {
      localeRef.value = v
      current.value = v
    },
  })

  const isRTL = computed(() => checkRTL(localeRef.value))
  const dir = computed(() => (isRTL.value ? 'rtl' : 'ltr'))
  const localeMeta = computed(() => getLocaleMeta(localeRef.value))

  /** Persist the choice and load the locale (lazy if not yet loaded). */
  async function changeLocale(code: string): Promise<void> {
    if (!SUPPORTED_LOCALES.some((l) => l.code === code)) return
    await setLocale(code)
    current.value = code
    setLang(code)
  }

  return { locale, isRTL, dir, localeMeta, changeLocale, supportedLocales: SUPPORTED_LOCALES }
}

export { i18n }
