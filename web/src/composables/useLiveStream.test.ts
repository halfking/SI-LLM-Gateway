// useLiveStream.test.ts — drive the composable with a fake WebSocket.
//
// We install a controllable FakeWebSocket on globalThis before each
// test, then mount a tiny harness component so Vue's onMounted hook
// fires (composables that use lifecycle hooks need a component
// instance to attach to).
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { defineComponent, h, nextTick } from 'vue'
import { mount } from '@vue/test-utils'
import { useLiveStream } from './useLiveStream'

class FakeWebSocket {
  static instances: FakeWebSocket[] = []

  url: string
  readyState: 'CONNECTING' | 'OPEN' | 'CLOSING' | 'CLOSED' = 'CONNECTING'
  onopen: ((ev?: unknown) => void) | null = null
  onmessage: ((ev: { data: string }) => void) | null = null
  onerror: ((ev?: unknown) => void) | null = null
  onclose: ((ev?: unknown) => void) | null = null

  constructor(url: string) {
    this.url = url
    FakeWebSocket.instances.push(this)
  }
  send(): void {}
  close(): void {
    this.readyState = 'CLOSED'
    this.onclose?.()
  }
  fakeOpen() {
    this.readyState = 'OPEN'
    this.onopen?.()
  }
  fakeMessage(data: unknown) {
    this.onmessage?.({ data: JSON.stringify(data) })
  }
}

// Harness: returns the composable handle from setup so the test can
// read it via wrapper.vm. Renders an empty div — the composable's
// own onMounted hook is what we care about.
function harness(opts: Parameters<typeof useLiveStream>[0]) {
  return defineComponent({
    setup() {
      const api = useLiveStream(opts)
      return { api }
    },
    render() {
      return h('div')
    },
  })
}

beforeEach(() => {
  FakeWebSocket.instances = []
  // @ts-expect-error — swapping global for tests
  globalThis.WebSocket = FakeWebSocket
})

afterEach(() => {
  // @ts-expect-error
  delete globalThis.WebSocket
  vi.useRealTimers()
})

describe('useLiveStream', () => {
  it('connects on mount and replaces buffer with initial_data in ASC order', async () => {
    const wrapper = mount(harness({ noAutoReconnect: true }))
    await nextTick()
    const api = wrapper.vm.api as ReturnType<typeof useLiveStream>

    expect(FakeWebSocket.instances).toHaveLength(1)
    const ws = FakeWebSocket.instances[0]
    ws.fakeOpen()
    await nextTick()
    expect(api.connection.value).toBe('open')

    ws.fakeMessage({
      type: 'initial_data',
      ts: '2026-07-03T10:00:00Z',
      requests: [
        { type: 'request', ts: '2026-07-03T10:00:30Z', request_id: 'r3', model: 'gpt-4o', model_category: 'openai', status: 'success', latency_ms: 200 },
        { type: 'request', ts: '2026-07-03T10:00:00Z', request_id: 'r1', model: 'gpt-4o', model_category: 'openai', status: 'success', latency_ms: 100 },
        { type: 'request', ts: '2026-07-03T10:00:15Z', request_id: 'r2', model: 'gpt-4o', model_category: 'openai', status: 'failure', latency_ms: 50 },
      ],
    })
    await nextTick()

    expect(api.requests.value.map((r) => r.request_id)).toEqual(['r1', 'r2', 'r3'])
    wrapper.unmount()
  })

  it('appends new requests and caps the buffer at the requested capacity', async () => {
    const wrapper = mount(harness({ capacity: 3, noAutoReconnect: true }))
    await nextTick()
    const api = wrapper.vm.api as ReturnType<typeof useLiveStream>

    const ws = FakeWebSocket.instances[0]
    ws.fakeOpen()
    await nextTick()
    for (let i = 0; i < 5; i++) {
      ws.fakeMessage({
        type: 'request',
        ts: `2026-07-03T10:00:0${i}Z`,
        request: { type: 'request', ts: `2026-07-03T10:00:0${i}Z`, request_id: `r${i}`, status: 'success' },
      })
    }
    await nextTick()
    expect(api.requests.value).toHaveLength(3)
    expect(api.requests.value[0].request_id).toBe('r2')
    expect(api.requests.value[2].request_id).toBe('r4')
    wrapper.unmount()
  })

  it('queues events while paused and flushes them on resume', async () => {
    const wrapper = mount(harness({ noAutoReconnect: true }))
    await nextTick()
    const api = wrapper.vm.api as ReturnType<typeof useLiveStream>

    const ws = FakeWebSocket.instances[0]
    ws.fakeOpen()
    await nextTick()
    ws.fakeMessage({
      type: 'request',
      ts: '2026-07-03T10:00:00Z',
      request: { type: 'request', ts: '2026-07-03T10:00:00Z', request_id: 'a', status: 'success' },
    })
    await nextTick()
    expect(api.requests.value).toHaveLength(1)

    api.togglePause()
    ws.fakeMessage({
      type: 'request',
      ts: '2026-07-03T10:00:01Z',
      request: { type: 'request', ts: '2026-07-03T10:00:01Z', request_id: 'b', status: 'success' },
    })
    ws.fakeMessage({ type: 'idle_marker', ts: '2026-07-03T10:00:02Z' })
    await nextTick()
    expect(api.requests.value).toHaveLength(1)
    expect(api.paused.value).toBe(true)

    api.togglePause()
    await nextTick()
    expect(api.paused.value).toBe(false)
    expect(api.requests.value.map((r) => r.request_id ?? r.type)).toEqual(['a', 'b', 'idle_marker'])
    wrapper.unmount()
  })

  it('schedules a reconnect on close', async () => {
    vi.useFakeTimers()
    const wrapper = mount(harness({ noAutoReconnect: false }))
    await nextTick()
    const api = wrapper.vm.api as ReturnType<typeof useLiveStream>

    const ws = FakeWebSocket.instances[0]
    ws.fakeOpen()
    await nextTick()
    ws.close()
    expect(api.connection.value).toBe('reconnecting')
    await vi.advanceTimersByTimeAsync(1_100)
    expect(FakeWebSocket.instances.length).toBeGreaterThanOrEqual(2)
    wrapper.unmount()
  })

  it('fires onRequestEvicted when the buffer rolls over', async () => {
    const evicted: string[] = []
    const wrapper = mount(harness({ capacity: 3, noAutoReconnect: true }))
    await nextTick()
    const api = wrapper.vm.api as ReturnType<typeof useLiveStream>
    api.onRequestEvicted((id) => evicted.push(id))

    const ws = FakeWebSocket.instances[0]
    ws.fakeOpen()
    await nextTick()
    // Push 5 requests with a buffer cap of 3. The first 2 should be
    // evicted; the last 3 should remain.
    for (let i = 0; i < 5; i++) {
      ws.fakeMessage({
        type: 'request',
        ts: `2026-07-03T10:00:0${i}Z`,
        request: { type: 'request', ts: `2026-07-03T10:00:0${i}Z`, request_id: `r${i}`, status: 'success' },
      })
    }
    await nextTick()
    expect(api.requests.value.map((r) => r.request_id)).toEqual(['r2', 'r3', 'r4'])
    expect(evicted).toEqual(['r0', 'r1'])
    wrapper.unmount()
  })

  it('rejects duplicate request_ids without growing the buffer', async () => {
    const wrapper = mount(harness({ capacity: 5, noAutoReconnect: true }))
    await nextTick()
    const api = wrapper.vm.api as ReturnType<typeof useLiveStream>

    const ws = FakeWebSocket.instances[0]
    ws.fakeOpen()
    await nextTick()
    ws.fakeMessage({
      type: 'request',
      ts: '2026-07-03T10:00:00Z',
      request: { type: 'request', ts: '2026-07-03T10:00:00Z', request_id: 'dup-1', status: 'success' },
    })
    ws.fakeMessage({
      type: 'request',
      ts: '2026-07-03T10:00:01Z',
      request: { type: 'request', ts: '2026-07-03T10:00:01Z', request_id: 'dup-1', status: 'success' },
    })
    await nextTick()
    expect(api.requests.value).toHaveLength(1)
    wrapper.unmount()
  })

  it('reset() clears the buffer AND the id index so the next replay is treated as fresh', async () => {
    const evicted: string[] = []
    const wrapper = mount(harness({ capacity: 5, noAutoReconnect: true }))
    await nextTick()
    const api = wrapper.vm.api as ReturnType<typeof useLiveStream>
    api.onRequestEvicted((id) => evicted.push(id))

    const ws = FakeWebSocket.instances[0]
    ws.fakeOpen()
    await nextTick()
    ws.fakeMessage({
      type: 'request',
      ts: '2026-07-03T10:00:00Z',
      request: { type: 'request', ts: '2026-07-03T10:00:00Z', request_id: 'r1', status: 'success' },
    })
    await nextTick()
    api.reset()
    expect(api.requests.value).toHaveLength(0)
    // Replay the same ID — should be accepted (idIndex is cleared).
    ws.fakeMessage({
      type: 'request',
      ts: '2026-07-03T10:00:01Z',
      request: { type: 'request', ts: '2026-07-03T10:00:01Z', request_id: 'r1', status: 'success' },
    })
    await nextTick()
    expect(api.requests.value).toHaveLength(1)
    expect(api.requests.value[0].request_id).toBe('r1')
    expect(evicted).toEqual([]) // nothing evicted
    wrapper.unmount()
  })
})