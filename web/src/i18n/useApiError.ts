// useApiError.ts — render a thrown API error in the active locale.
//
// Resolution order (matches the plan §V decision "frontend translates by code"):
//   1. errors.code.<code>   — stable backend ApiError.code (best, machine-readable)
//   2. errors.byStatus[n]   — generic message for the HTTP status
//   3. ApiError.message     — backend's literal detail (Chinese/English fallback)
//   4. errors.unknown
//
// Backward compatible: callers that today display `e.message` can swap in
// `resolveApiError(e)` and the Chinese-user experience is unchanged when no
// code mapping exists yet.

import { i18n, localeRef } from './index'
import { ApiError } from '../api/_core'

const TE = i18n.global.t.bind(i18n.global)

/** Return a localized message for any thrown value (API or otherwise). */
export function resolveApiError(err: unknown): string {
  // Network failure: fetch threw before a response.
  if (err instanceof TypeError && /fetch|network/i.test(err.message)) {
    return TE('errors.network')
  }
  if (err instanceof ApiError) {
    // 1. by code
    if (err.code) {
      const key = `errors.code.${err.code}`
      const tr = TE(key)
      if (tr && tr !== key) return tr
    }
    // 2. by status
    const byStatus = TE(`errors.byStatus.${err.status}`)
    if (byStatus && !/^errors\./.test(byStatus)) return byStatus
    // 3. backend detail (fallback)
    if (err.message) return err.message
  }
  if (err instanceof Error && err.message) return err.message
  return TE('errors.unknown')
}

export { localeRef }
