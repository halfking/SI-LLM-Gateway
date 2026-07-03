// liveStreamDisplay.test.ts — pin the model glyph mapping.
//
// Trivial today, but the mapping is the visual contract that makes
// 30+ blocks readable on a 1366px-wide dashboard. A future regression
// ("gpt-5" added with no glyph rule) would render as "?" and silently
// cost a row of context for the operator.
import { describe, it, expect } from 'vitest'
import { modelGlyph } from './liveStreamDisplay'

describe('modelGlyph', () => {
  it('maps known families to a single uppercase letter', () => {
    expect(modelGlyph('gpt-4o')).toBe('G')
    expect(modelGlyph('gpt-4o-mini')).toBe('G')
    expect(modelGlyph('o1-preview')).toBe('G')
    expect(modelGlyph('o3-mini')).toBe('G')

    expect(modelGlyph('claude-3.5-sonnet')).toBe('C')
    expect(modelGlyph('claude-opus-4')).toBe('C')

    expect(modelGlyph('qwen-max')).toBe('Q')
    expect(modelGlyph('qwen2-72b-instruct')).toBe('Q')
    expect(modelGlyph('glm-4')).toBe('M')
    expect(modelGlyph('deepseek-v3')).toBe('D')
    expect(modelGlyph('moonshot-v1-8k')).toBe('K')
    expect(modelGlyph('doubao-pro')).toBe('B')
    expect(modelGlyph('ernie-4.0')).toBe('E')

    expect(modelGlyph('llama-3.1-70b')).toBe('L')
    expect(modelGlyph('mistral-large')).toBe('M')
    expect(modelGlyph('mixtral-8x22b')).toBe('M')
    expect(modelGlyph('phi-3-medium')).toBe('P')
    expect(modelGlyph('gemma-2-27b')).toBe('G')
  })

  it('uses the vendor initial for minimax-style raw names', () => {
    // minimax is intentionally mapped to X (the actual minimax
    // model name starts with "M" which collides with Mistral/GLM;
    // we keep the standalone brand distinct so the swim lane is
    // unambiguous).
    expect(modelGlyph('MiniMax-M3')).toBe('X')
    expect(modelGlyph('minimax-m3')).toBe('X')
    expect(modelGlyph('minimax')).toBe('X')
  })

  it('falls back to the first alphanumeric character of an unknown name', () => {
    expect(modelGlyph('custom-finetune-v1')).toBe('C')
    expect(modelGlyph('foo-bar')).toBe('F')
  })

  it('returns ? for empty / whitespace / null input', () => {
    expect(modelGlyph('')).toBe('?')
    expect(modelGlyph('   ')).toBe('?')
    expect(modelGlyph(undefined)).toBe('?')
    expect(modelGlyph(null)).toBe('?')
  })

  it('is case-insensitive on the input', () => {
    expect(modelGlyph('GPT-4O')).toBe('G')
    expect(modelGlyph('Claude-3')).toBe('C')
    expect(modelGlyph('QWEN-Max')).toBe('Q')
  })

  it('returns a single character (not a stringified number)', () => {
    for (const v of ['', ' ', 'gpt-4', 'unknown', 'MiniMax-M3', null, undefined]) {
      expect(modelGlyph(v as string | null | undefined)).toHaveLength(1)
    }
  })
})
