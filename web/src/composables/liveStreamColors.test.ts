// liveStreamColors.test.ts — sanity check the palette module.
//
// Trivial today, but the palette will grow (status icons, dark mode)
// and a single failing assertion will catch palette regressions
// before they ship.
import { describe, it, expect } from 'vitest'
import {
  MODEL_COLORS,
  STATUS_COLORS,
  getModelCategoryColor,
  getStatusColor,
} from './liveStreamColors'

describe('liveStreamColors', () => {
  it('exports a color for every known model family', () => {
    for (const k of ['openai', 'anthropic', 'domestic', 'oss', 'other'] as const) {
      expect(MODEL_COLORS[k]).toMatch(/^#[0-9a-f]{6}$/i)
    }
  })

  it('exports a color for every known status', () => {
    for (const k of ['success', 'in_progress', 'failure'] as const) {
      expect(STATUS_COLORS[k]).toMatch(/^#[0-9a-f]{6}$/i)
    }
  })

  it('falls back to "other" for unknown model categories', () => {
    expect(getModelCategoryColor(undefined)).toBe(MODEL_COLORS.other)
    expect(getModelCategoryColor(null)).toBe(MODEL_COLORS.other)
    expect(getModelCategoryColor('gpt-9000-fake')).toBe(MODEL_COLORS.other)
  })

  it('falls back to in_progress for unknown statuses', () => {
    expect(getStatusColor(undefined)).toBe(STATUS_COLORS.in_progress)
    expect(getStatusColor(null)).toBe(STATUS_COLORS.in_progress)
    expect(getStatusColor('who-knows')).toBe(STATUS_COLORS.in_progress)
  })

  it('uses distinct hues for each model family', () => {
    const colors = new Set(Object.values(MODEL_COLORS))
    expect(colors.size).toBe(Object.keys(MODEL_COLORS).length)
  })
})