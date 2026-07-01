// useFormat.ts — locale-aware date / number formatting.
//
// Replaces the 69 scattered `new Date(x).toLocaleString('zh-CN', …)` and
// `n.toLocaleString('zh-CN')` call sites with a single reactive formatter.
// Because `locale` is a computed wrapping vue-i18n's reactive locale, every
// `fmtX` re-runs when the language changes — no manual wiring needed.
//
// Migration recipe (see plan §IV Stage 0):
//   import { useFormat } from '@/i18n/useFormat'
//   const { fmtDateTime } = useFormat()
//   // before:  new Date(s).toLocaleString('zh-CN', { dateStyle:'short', timeStyle:'short' })
//   // after:   fmtDateTime(s)

import { computed } from 'vue'
import { localeRef } from './index'

export function useFormat() {
  const locale = computed(() => localeRef.value)

  /** "2026/07/02 14:03" style short date+time. */
  function fmtDateTime(input: string | number | Date | null | undefined): string {
    if (!input) return ''
    const d = new Date(input)
    if (isNaN(d.getTime())) return String(input)
    return d.toLocaleString(locale.value, { dateStyle: 'short', timeStyle: 'short' })
  }

  /** Date-only short form. */
  function fmtDate(input: string | number | Date | null | undefined): string {
    if (!input) return ''
    const d = new Date(input)
    if (isNaN(d.getTime())) return String(input)
    return d.toLocaleDateString(locale.value, { dateStyle: 'short' })
  }

  /** Time-only short form. */
  function fmtTime(input: string | number | Date | null | undefined): string {
    if (!input) return ''
    const d = new Date(input)
    if (isNaN(d.getTime())) return String(input)
    return d.toLocaleTimeString(locale.value, { timeStyle: 'short' })
  }

  /** Grouped integer/decimal, e.g. "1,234,567". */
  function fmtNumber(n: number, fractionDigits?: number): string {
    if (typeof n !== 'number' || !isFinite(n)) return String(n)
    const opts: Intl.NumberFormatOptions =
      fractionDigits != null ? { minimumFractionDigits: fractionDigits, maximumFractionDigits: fractionDigits } : {}
    return n.toLocaleString(locale.value, opts)
  }

  return { locale, fmtDateTime, fmtDate, fmtTime, fmtNumber }
}
