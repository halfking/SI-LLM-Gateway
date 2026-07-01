// index.ts — vue-i18n instance + locale resolution + lazy loading.
//
// Loading strategy: zh-CN and en-US are bundled (full coverage). The other six
// locales (zh-TW, ja-JP, de-DE, fr-FR, es-ES, ar-SA) are fetched on first
// switch via dynamic import so the initial bundle stays small.
//
// Locale resolution priority: localStorage (store.lang) → browser language → DEFAULT_LOCALE.
// The platform-wide default locale is configurable by admins via the
// `general.default_locale` Spec (auto-rendered in the Settings page); the
// DEFAULT_LOCALE constant below mirrors that Spec's default.

import { createI18n } from 'vue-i18n'
import zhCN from './locales/zh-CN'
import enUS from './locales/en-US'
import { DEFAULT_LOCALE, FALLBACK_LOCALE, SUPPORTED_LOCALES, matchLocale } from './constants'
import { getLang } from '../store'

/** Locales bundled into the initial chunk (full coverage). */
const STATIC_LOCALES = {
  'zh-CN': zhCN,
  'en-US': enUS,
}

/** Dynamic-import loaders for the lazily-fetched locales. */
const LAZY_LOADERS: Record<string, () => Promise<{ default: Record<string, unknown> }>> = {
  'zh-TW': () => import('./locales/zh-TW'),
  'ja-JP': () => import('./locales/ja-JP'),
  'de-DE': () => import('./locales/de-DE'),
  'fr-FR': () => import('./locales/fr-FR'),
  'es-ES': () => import('./locales/es-ES'),
  'ar-SA': () => import('./locales/ar-SA'),
}

/** Locales already loaded into vue-i18n messages. */
const loaded = new Set<string>(Object.keys(STATIC_LOCALES))

/**
 * Pick the initial locale: stored preference → browser → default.
 * Runs once at module load (before app mount) so the first paint is correct.
 */
function detectInitialLocale(): string {
  const stored = getLang()
  if (stored) return stored
  if (typeof navigator !== 'undefined' && navigator.language) {
    const matched = matchLocale(navigator.language)
    if (matched) return matched
  }
  return DEFAULT_LOCALE
}

export const i18n = createI18n({
  legacy: false,
  globalInjection: true, // exposes $t / $tc in templates without explicit useI18n
  locale: detectInitialLocale(),
  fallbackLocale: FALLBACK_LOCALE,
  messages: STATIC_LOCALES,
  // Silence noisy console warnings while the other 6 locales are still stubs;
  // re-enable later once translations are complete.
  missingWarn: false,
  fallbackWarn: false,
})

/** Apply <html lang> and <html dir> for the given locale (no-op in non-browser). */
export function applyDocumentLocale(code: string): void {
  if (typeof document === 'undefined') return
  const meta = SUPPORTED_LOCALES.find((l) => l.code === code)
  if (!meta) return
  document.documentElement.lang = meta.code
  document.documentElement.dir = meta.dir
}

/**
 * Switch the active locale, fetching the message chunk on first use.
 * Safe to call with an unknown locale — it is ignored.
 */
export async function setLocale(code: string): Promise<void> {
  const meta = SUPPORTED_LOCALES.find((l) => l.code === code)
  if (!meta) return
  if (!loaded.has(code)) {
    const loader = LAZY_LOADERS[code]
    if (loader) {
      const mod = await loader()
      // Cast: lazy locales (stubs or partial translations) may have a different
      // shape than the bundled zh-CN/en-US used to infer the i18n message type.
      i18n.global.setLocaleMessage(code, mod.default as never)
      loaded.add(code)
    }
  }
  ;(i18n.global.locale as unknown as { value: string }).value = code
  applyDocumentLocale(code)
}

/** The reactive current locale code (ref<string>). */
export const localeRef = i18n.global.locale as unknown as { value: string }

// Apply the detected locale's <html lang/dir> immediately so the very first
// paint (incl. login screen) has the right text direction before mount.
applyDocumentLocale(detectInitialLocale())
