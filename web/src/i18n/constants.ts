// constants.ts — canonical list of UI locales supported by the console.
// Keep the locale codes in sync with settings.SupportedLocaleCodes() on the
// backend (settings/spec_general.go) and the Options of the
// `general.default_locale` platform Spec.

export type LocaleDir = 'ltr' | 'rtl'

export interface LocaleMeta {
  /** BCP-47 code, also used as the vue-i18n message key and toLocaleString locale. */
  code: string
  /** Short code shown in compact switchers (e.g. "中文"). */
  short: string
  /** Name written in its own language (for the language menu). */
  nativeName: string
  /** English name (for tooling / logs). */
  englishName: string
  /** Text direction; only ar-SA is rtl today. */
  dir: LocaleDir
  /** Flag emoji used in the switcher. */
  flag: string
}

export const SUPPORTED_LOCALES: LocaleMeta[] = [
  { code: 'en-US', short: 'EN',  nativeName: 'English',   englishName: 'English',              dir: 'ltr', flag: '🇺🇸' },
  { code: 'zh-CN', short: '简中', nativeName: '简体中文',  englishName: 'Chinese (Simplified)', dir: 'ltr', flag: '🇨🇳' },
  { code: 'zh-TW', short: '繁中', nativeName: '繁體中文',  englishName: 'Chinese (Traditional)', dir: 'ltr', flag: '🇹🇼' },
  { code: 'ja-JP', short: '日',  nativeName: '日本語',     englishName: 'Japanese',             dir: 'ltr', flag: '🇯🇵' },
  { code: 'de-DE', short: 'DE',  nativeName: 'Deutsch',   englishName: 'German',               dir: 'ltr', flag: '🇩🇪' },
  { code: 'fr-FR', short: 'FR',  nativeName: 'Français',  englishName: 'French',               dir: 'ltr', flag: '🇫🇷' },
  { code: 'es-ES', short: 'ES',  nativeName: 'Español',   englishName: 'Spanish',              dir: 'ltr', flag: '🇪🇸' },
  { code: 'ar-SA', short: 'ع',   nativeName: 'العربية',    englishName: 'Arabic',               dir: 'rtl', flag: '🇸🇦' },
]

/** Default locale — mirrors the `general.default_locale` Spec default. */
export const DEFAULT_LOCALE = 'en-US'

/** Fallback when a key is missing in the active locale. English is always fully populated. */
export const FALLBACK_LOCALE = 'en-US'

export const RTL_LOCALES: string[] = SUPPORTED_LOCALES.filter((l) => l.dir === 'rtl').map((l) => l.code)

export function getLocaleMeta(code: string): LocaleMeta | undefined {
  return SUPPORTED_LOCALES.find((l) => l.code === code)
}

export function isSupportedLocale(code: string): boolean {
  return SUPPORTED_LOCALES.some((l) => l.code === code)
}

export function isRTL(code: string): boolean {
  return RTL_LOCALES.includes(code)
}

/**
 * Best-effort match of an arbitrary language tag (e.g. navigator.language)
 * to a supported locale. Matches on the primary subtag first, then exact.
 */
export function matchLocale(tag: string): string | undefined {
  const lower = tag.toLowerCase()
  const exact = SUPPORTED_LOCALES.find((l) => l.code.toLowerCase() === lower)
  if (exact) return exact.code
  const primary = lower.split('-')[0]
  const partial = SUPPORTED_LOCALES.find((l) => l.code.toLowerCase().split('-')[0] === primary)
  return partial?.code
}
