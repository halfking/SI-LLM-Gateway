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
  providerShortLabel,
  timeHHMM,
  latencyLabel,
  statusBorderColor,
  errorKindColor,
  statusCategory,
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

describe('modelShortLabel (tail-first version extractor)', () => {
  it('strips the GPT prefix and uppercases the rest', () => {
    // 2026-07-03: the operator scans the swim lane looking for the
    // VERSION, not the vendor prefix, so "gpt-4o-mini" → "4O-MINI".
    expect(modelShortLabel('gpt-4o')).toBe('4O')
    expect(modelShortLabel('gpt-4o-mini')).toBe('4O-MINI')
    expect(modelShortLabel('GPT-4O')).toBe('4O')
    expect(modelShortLabel('o1-preview')).toBe('PREVIEW')
    expect(modelShortLabel('o3-mini')).toBe('MINI')
    expect(modelShortLabel('o4-preview')).toBe('PREVIEW')
  })

  it('strips the Claude / qwen / glm / deepseek / moonshot / doubao / ernie prefixes', () => {
    expect(modelShortLabel('claude-3.5-sonnet')).toBe('3.5-SONNET')
    expect(modelShortLabel('claude-fable-5')).toBe('FABLE-5')
    expect(modelShortLabel('claude-sonnet-5')).toBe('SONNET-5')
    expect(modelShortLabel('claude-opus-4')).toBe('OPUS-4')
    expect(modelShortLabel('Claude-3')).toBe('3')
    expect(modelShortLabel('qwen-max')).toBe('MAX')
    expect(modelShortLabel('qwen2-72b-instruct')).toBe('2-72B-INSTRUCT')
    expect(modelShortLabel('qwen2.5-7b')).toBe('2.5-7B')
    expect(modelShortLabel('glm-4')).toBe('4')
    expect(modelShortLabel('deepseek-v3')).toBe('V3')
    expect(modelShortLabel('moonshot-v1-8k')).toBe('V1-8K')
    expect(modelShortLabel('doubao-pro')).toBe('PRO')
    expect(modelShortLabel('ernie-4.0')).toBe('4.0')
    expect(modelShortLabel('llama-3.1-70b')).toBe('3.1-70B')
    expect(modelShortLabel('mistral-large')).toBe('LARGE')
    expect(modelShortLabel('mixtral-8x22b')).toBe('8X22B')
    expect(modelShortLabel('phi-3-medium')).toBe('3-MEDIUM')
    expect(modelShortLabel('gemma-2-27b')).toBe('2-27B')
  })

  it('returns MIX for any minimax variant', () => {
    expect(modelShortLabel('MiniMax-M3')).toBe('MIX')
    expect(modelShortLabel('minimax-m3')).toBe('MIX')
    expect(modelShortLabel('minimax')).toBe('MIX')
  })

  it('falls back to the LAST 7 chars of the raw name for unknown prefixes', () => {
    // Tail-first keeps the separator visible so "foo-bar-123" →
    // "BAR-123" (last 7 chars of the raw name, uppercased). The
    // CSS layer adds ellipsis if even this overflows the 60px tile.
    expect(modelShortLabel('foo-bar-123')).toBe('BAR-123')
    expect(modelShortLabel('custom-finetune-v1')).toBe('TUNE-V1')
    expect(modelShortLabel('my-model')).toBe('Y-MODEL')
    expect(modelShortLabel('a-b-c-d-e-f-g-h')).toBe('E-F-G-H')
    // Short names (<= 7 chars) get the full label uppercased.
    expect(modelShortLabel('foo')).toBe('FOO')
    expect(modelShortLabel('gpt')).toBe('GPT')
  })

  it('returns ??? for empty / null / undefined / whitespace', () => {
    expect(modelShortLabel('')).toBe('???')
    expect(modelShortLabel(undefined)).toBe('???')
    expect(modelShortLabel(null)).toBe('???')
    expect(modelShortLabel('   ')).toBe('???')
  })

  it('is case-insensitive on the input', () => {
    expect(modelShortLabel('GPT-4O')).toBe('4O')
    expect(modelShortLabel('CLAUDE-3')).toBe('3')
    expect(modelShortLabel('QWEN-Max')).toBe('MAX')
  })
})

describe('providerShortLabel (full label, CSS does the ellipsis)', () => {
  it('returns the full lowercase catalog code for every known vendor', () => {
    // 2026-07-03: operator preference is "show the full name" —
    // OPEN/ANTH were too cryptic when scanning a wall of tiles.
    expect(providerShortLabel('openai')).toBe('openai')
    expect(providerShortLabel('OpenAI')).toBe('openai')
    expect(providerShortLabel('OPENAI')).toBe('openai')
    expect(providerShortLabel('openai-prod')).toBe('openai-prod')
    expect(providerShortLabel('anthropic')).toBe('anthropic')
    expect(providerShortLabel('Anthropic')).toBe('anthropic')
    expect(providerShortLabel('azure')).toBe('azure')
    expect(providerShortLabel('azure-openai')).toBe('azure-openai')
    expect(providerShortLabel('Azure-OpenAI-US-East')).toBe('azure-openai-us-east')
    expect(providerShortLabel('google')).toBe('google')
    expect(providerShortLabel('vertex-ai')).toBe('vertex-ai')
  })

  it('returns the full code for Chinese / OSS providers too', () => {
    expect(providerShortLabel('minimax')).toBe('minimax')
    expect(providerShortLabel('qwen')).toBe('qwen')
    expect(providerShortLabel('deepseek')).toBe('deepseek')
    expect(providerShortLabel('zhipu')).toBe('zhipu')
    expect(providerShortLabel('glm')).toBe('glm')
    expect(providerShortLabel('mistral')).toBe('mistral')
    expect(providerShortLabel('cohere')).toBe('cohere')
    expect(providerShortLabel('bedrock')).toBe('bedrock')
  })

  it('returns the full code for unknown / custom providers', () => {
    // CSS adds the ellipsis when the tile is narrower than the
    // label — we do NOT truncate in code.
    expect(providerShortLabel('my-vendor')).toBe('my-vendor')
    expect(providerShortLabel('foo.bar')).toBe('foo.bar')
    expect(providerShortLabel('abc-123')).toBe('abc-123')
    expect(providerShortLabel('custom-provider-east-2')).toBe('custom-provider-east-2')
  })

  it('returns ??? for empty / null / undefined / whitespace', () => {
    expect(providerShortLabel('')).toBe('???')
    expect(providerShortLabel(undefined)).toBe('???')
    expect(providerShortLabel(null)).toBe('???')
    expect(providerShortLabel('   ')).toBe('???')
  })
})

describe('statusCategory (coarse failure taxonomy)', () => {
  it('returns success for status=success regardless of error_kind', () => {
    expect(statusCategory('success', null)).toBe('success')
    expect(statusCategory('success', 'timeout')).toBe('success')
  })

  it('returns in_progress for status=in_progress', () => {
    expect(statusCategory('in_progress', null)).toBe('in_progress')
  })

  it('returns failure_timeout FIRST (must not be caught by 5xx bucket)', () => {
    expect(statusCategory('failure', 'timeout')).toBe('failure_timeout')
    expect(statusCategory('failure', 'client_disconnect')).toBe('failure_timeout')
    expect(statusCategory('failure', 'network_reset')).toBe('failure_timeout')
    expect(statusCategory('failure', 'eof')).toBe('failure_timeout')
  })

  it('returns failure_5xx for server-side errors', () => {
    expect(statusCategory('failure', '5xx')).toBe('failure_5xx')
    expect(statusCategory('failure', 'upstream_5xx')).toBe('failure_5xx')
    expect(statusCategory('failure', 'provider_overloaded')).toBe('failure_5xx')
    expect(statusCategory('failure', 'server_error')).toBe('failure_5xx')
    expect(statusCategory('failure', 'backend_timeout')).toBe('failure_5xx')
  })

  it('returns failure_4xx for client-side / auth errors', () => {
    expect(statusCategory('failure', '4xx')).toBe('failure_4xx')
    expect(statusCategory('failure', 'unauthorized')).toBe('failure_4xx')
    expect(statusCategory('failure', 'rate_limit_exceeded')).toBe('failure_4xx')
    expect(statusCategory('failure', 'quota_exceeded')).toBe('failure_4xx')
    expect(statusCategory('failure', 'payment_required')).toBe('failure_4xx')
  })

  it('returns failure_not_found for routing / config errors', () => {
    expect(statusCategory('failure', 'model_not_found')).toBe('failure_not_found')
    expect(statusCategory('failure', 'routing_failed')).toBe('failure_not_found')
    expect(statusCategory('failure', 'no_route')).toBe('failure_not_found')
    expect(statusCategory('failure', 'policy_denied')).toBe('failure_not_found')
  })

  it('returns failure_other for failure status with unmapped error_kind', () => {
    expect(statusCategory('failure', null)).toBe('failure_other')
    expect(statusCategory('failure', 'transient')).toBe('failure_other')
    expect(statusCategory('failure', 'unknown_error')).toBe('failure_other')
  })

  it('returns failure_other for unmapped non-failure status', () => {
    expect(statusCategory('weird_status', 'timeout')).toBe('failure_other')
    expect(statusCategory(undefined, null)).toBe('failure_other')
  })

  it('is case-insensitive on error_kind', () => {
    expect(statusCategory('failure', 'TIMEOUT')).toBe('failure_timeout')
    expect(statusCategory('failure', 'UPSTREAM_5xx')).toBe('failure_5xx')
    expect(statusCategory('failure', 'Model_Not_Found')).toBe('failure_not_found')
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