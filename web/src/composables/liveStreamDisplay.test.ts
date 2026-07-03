// liveStreamDisplay.test.ts — pin the swim-lane display primitives.
//
// Why this file exists: the dashboard is a visual contract, and
// every mapping here drives a 50-tile-wide wall of information.
// A regression that breaks "gpt-4o" → "GPT" or that promotes an
// obscure vendor to "TOP" would silently confuse every operator;
// pinning it in a unit test means the contract is enforced by
// `vitest run`, not by an eyeball at 03:00.
import { describe, it, expect } from 'vitest'
import {
  modelGlyph,
  modelShortLabel,
  timeHHMM,
  latencyLabel,
  statusBorderColor,
  errorKindColor,
} from './liveStreamDisplay'

describe('modelGlyph (1-char tile accent)', () => {
  it('maps top vendors to a single uppercase letter', () => {
    expect(modelGlyph('gpt-4o')).toBe('G')
    expect(modelGlyph('gpt-4o-mini')).toBe('G')
    expect(modelGlyph('o1-preview')).toBe('G')
    expect(modelGlyph('claude-3.5-sonnet')).toBe('C')
    expect(modelGlyph('qwen-max')).toBe('Q')
    expect(modelGlyph('qwen2-72b-instruct')).toBe('Q')
    expect(modelGlyph('glm-4')).toBe('M')
    expect(modelGlyph('deepseek-v3')).toBe('D')
    expect(modelGlyph('MiniMax-M3')).toBe('X')
    expect(modelGlyph('minimax-m3')).toBe('X')
  })
  it('returns ? for empty / null / undefined', () => {
    expect(modelGlyph('')).toBe('?')
    expect(modelGlyph(undefined)).toBe('?')
    expect(modelGlyph(null)).toBe('?')
  })
})

describe('modelShortLabel (top-vendor family code)', () => {
  it('returns the canonical code for the top vendors seen on 71', () => {
    // The only families with non-trivial traffic. Everything else
    // is intentionally demoted to ??? to keep the swim lane clean.
    expect(modelShortLabel('gpt-4o')).toBe('GPT')
    expect(modelShortLabel('gpt-4o-mini')).toBe('GPT')
    expect(modelShortLabel('o1-preview')).toBe('GPT')
    expect(modelShortLabel('o3-mini')).toBe('GPT')
    expect(modelShortLabel('claude-3.5-sonnet')).toBe('CLD')
    expect(modelShortLabel('claude-fable-5')).toBe('CLD')
    expect(modelShortLabel('claude-sonnet-5')).toBe('CLD')
    expect(modelShortLabel('qwen-max')).toBe('QWN')
    expect(modelShortLabel('qwen2-72b-instruct')).toBe('QWN')
    expect(modelShortLabel('glm-4')).toBe('GLM')
    expect(modelShortLabel('deepseek-v3')).toBe('DSK')
    expect(modelShortLabel('MiniMax-M3')).toBe('MIX')
    expect(modelShortLabel('minimax-m3')).toBe('MIX')
    expect(modelShortLabel('minimax')).toBe('MIX')
  })

  it('demotes every non-top vendor to ??? so the swim lane stays clean', () => {
    // Top vendors get a 3-letter code; everything else gets ???
    // so the eye learns to ignore minor traffic. Full model names
    // are still in the hover tooltip.
    expect(modelShortLabel('mistral-large')).toBe('???')
    expect(modelShortLabel('mixtral-8x22b')).toBe('???')
    expect(modelShortLabel('llama-3.1-70b')).toBe('???')
    expect(modelShortLabel('phi-3-medium')).toBe('???')
    expect(modelShortLabel('gemma-2-27b')).toBe('???')
    expect(modelShortLabel('moonshot-v1-8k')).toBe('???')
    expect(modelShortLabel('doubao-pro')).toBe('???')
    expect(modelShortLabel('ernie-4.0')).toBe('???')
    expect(modelShortLabel('custom-finetune-v1')).toBe('???')
  })

  it('returns ??? for empty / null / undefined / whitespace', () => {
    expect(modelShortLabel('')).toBe('???')
    expect(modelShortLabel(undefined)).toBe('???')
    expect(modelShortLabel(null)).toBe('???')
    expect(modelShortLabel('   ')).toBe('???')
  })

  it('is case-insensitive on the input', () => {
    expect(modelShortLabel('GPT-4O')).toBe('GPT')
    expect(modelShortLabel('CLAUDE-3')).toBe('CLD')
    expect(modelShortLabel('QWEN-Max')).toBe('QWN')
  })
})

describe('timeHHMM', () => {
  it('formats ISO timestamps to HH:MM (24h)', () => {
    const out = timeHHMM('2026-07-03T06:35:00Z', 'en-US')
    expect(out).toMatch(/^\d{2}:\d{2}$/)
  })
  it('returns --:-- for empty / null / invalid input', () => {
    expect(timeHHMM('', 'en-US')).toBe('--:--')
    expect(timeHHMM(null, 'en-US')).toBe('--:--')
    expect(timeHHMM(undefined, 'en-US')).toBe('--:--')
    expect(timeHHMM('not-a-date', 'en-US')).toBe('--:--')
  })
})

describe('latencyLabel', () => {
  it('formats sub-second latencies in ms', () => {
    expect(latencyLabel(50, false)).toBe('50ms')
    expect(latencyLabel(999, false)).toBe('999ms')
  })
  it('formats 1-10s with one decimal', () => {
    expect(latencyLabel(1200, false)).toBe('1.2s')
    expect(latencyLabel(9999, false)).toBe('10.0s')
  })
  it('formats >10s as rounded seconds', () => {
    expect(latencyLabel(15_000, false)).toBe('15s')
  })
  it('renders in-flight as ellipsis', () => {
    expect(latencyLabel(null, true)).toBe('…')
    expect(latencyLabel(500, true)).toBe('…')
  })
  it('renders unknown / negative as em-dash', () => {
    expect(latencyLabel(null, false)).toBe('—')
    expect(latencyLabel(-10, false)).toBe('—')
  })
})

describe('statusBorderColor', () => {
  it('returns rgba for each known status', () => {
    expect(statusBorderColor('success')).toMatch(/34,\s*197,\s*94/)
    expect(statusBorderColor('in_progress')).toMatch(/245,\s*158,\s*11/)
    expect(statusBorderColor('failure')).toMatch(/239,\s*68,\s*68/)
  })
  it('falls back to a neutral gray for unknown status', () => {
    expect(statusBorderColor('weird')).toMatch(/139,\s*148,\s*158/)
    expect(statusBorderColor(undefined)).toMatch(/139,\s*148,\s*158/)
  })
})

describe('errorKindColor (failure-second-line colour)', () => {
  // Order matters: network check first (otherwise "client_disconnect"
  // would match the server check on the "disconnect" token).
  it('amber for timeout / network / cancel / disconnect', () => {
    expect(errorKindColor('timeout')).toBe('#fcd34d')
    expect(errorKindColor('client_disconnect')).toBe('#fcd34d')
    expect(errorKindColor('network_reset')).toBe('#fcd34d')
  })
  it('red for 5xx / upstream / server / provider', () => {
    expect(errorKindColor('upstream_5xx')).toBe('#fca5a5')
    expect(errorKindColor('provider_overloaded')).toBe('#fca5a5')
    expect(errorKindColor('server_error')).toBe('#fca5a5')
  })
  it('orange for 4xx / auth / quota / rate_limit', () => {
    expect(errorKindColor('4xx')).toBe('#fdba74')
    expect(errorKindColor('rate_limit_exceeded')).toBe('#fdba74')
    expect(errorKindColor('quota_exceeded')).toBe('#fdba74')
    expect(errorKindColor('unauthorized')).toBe('#fdba74')
  })
  it('purple for routing / model_not_found / policy', () => {
    expect(errorKindColor('model_not_found')).toBe('#c4b5fd')
    expect(errorKindColor('routing_failed')).toBe('#c4b5fd')
    expect(errorKindColor('no_route')).toBe('#c4b5fd')
  })
  it('returns inherit for empty / null', () => {
    expect(errorKindColor('')).toBe('inherit')
    expect(errorKindColor(null)).toBe('inherit')
    expect(errorKindColor(undefined)).toBe('inherit')
  })
})