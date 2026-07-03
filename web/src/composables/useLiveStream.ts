// useLiveStream — WebSocket subscription to admin.LiveStreamHub.
//
// Wires the dashboard swim lane to the backend hub. Handles:
//   - one-shot initial replay (50 most-recent requests, ASC)
//   - incremental append on each "request" envelope
//   - idle markers ("idle_marker" envelopes) for visual gaps
//   - automatic reconnect with exponential back-off
//   - pause/resume so a frozen tab does not lose state
//
// Cap: the buffer is bounded at MAX_VISIBLE (100). When a new request
// arrives past the cap, the oldest entry is shifted off the front.
//
// All timestamps are ISO-8601 UTC strings. The frontend formats them
// per locale.
import { ref, onMounted, onBeforeUnmount, computed } from 'vue'
import { authBearer } from '../store'

export type LiveStatus = 'in_progress' | 'success' | 'failure'

export type LiveModelCategory = 'openai' | 'anthropic' | 'domestic' | 'oss' | 'other'

export interface LiveRequest {
  type: 'request' | 'idle_marker'
  ts: string
  request_id?: string
  tenant_id?: string
  model?: string
  model_category?: LiveModelCategory
  provider_code?: string
  status?: LiveStatus
  latency_ms?: number | null
  prompt_tokens?: number | null
  completion_tokens?: number | null
  total_tokens?: number | null
  cost_usd?: number | null
  error_kind?: string | null
}

export interface LiveStreamEnvelope {
  type: 'initial_data' | 'request' | 'idle_marker' | 'ping'
  ts: string
  request?: LiveRequest
  requests?: LiveRequest[]
}

export type ConnectionState = 'idle' | 'connecting' | 'open' | 'reconnecting' | 'closed'

// 2026-07-03 revision: dropped from 100 → 60. Each tile is now 22px
// wide and the swim lane shows the latest ~1 minute of traffic by
// default. 60 keeps a full minute of peak traffic on screen while
// staying readable (≈1300px of track for 60 tiles + gaps + legend).
const MAX_VISIBLE = 60
const MAX_RECONNECT_DELAY_MS = 15_000
const BASE_RECONNECT_DELAY_MS = 1_000

export interface UseLiveStreamOptions {
  /** Override the WS endpoint (default: `/api/admin/live-stream`). */
  endpoint?: string
  /**
   * Max requests kept in the rendered buffer (default 60). 30-50 is
   * the sweet spot: enough to see the last ~30 seconds of peak
   * traffic at a glance, small enough to fit on a 1366px display.
   */
  capacity?: number
  /** Disable auto-reconnect (used in unit tests). */
  noAutoReconnect?: boolean
}

export function useLiveStream(options: UseLiveStreamOptions = {}) {
  const capacity = options.capacity ?? MAX_VISIBLE
  const endpoint = options.endpoint ?? '/api/admin/live-stream'

  const requests = ref<LiveRequest[]>([])
  const connection = ref<ConnectionState>('idle')
  const paused = ref(false)
  const lastEventAt = ref<number>(0)
  let ws: WebSocket | null = null
  let reconnectAttempt = 0
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null
  // Pending queue for events that arrive while paused so we do not
  // drop anything; flush() moves them into requests on resume.
  const pending: LiveRequest[] = []
  let disposed = false

  function appendRequest(item: LiveRequest) {
    if (paused.value) {
      pending.push(item)
      // Bound the pending queue too — keeps memory predictable when
      // a tab is backgrounded for hours.
      if (pending.length > capacity * 4) {
        pending.splice(0, pending.length - capacity * 4)
      }
      return
    }
    requests.value.push(item)
    while (requests.value.length > capacity) {
      requests.value.shift()
    }
  }

  function flushPending() {
    if (pending.length === 0) return
    const drained = pending.splice(0, pending.length)
    requests.value.push(...drained)
    while (requests.value.length > capacity) {
      requests.value.shift()
    }
  }

  function pause() {
    paused.value = true
  }
  function resume() {
    if (!paused.value) return
    paused.value = false
    flushPending()
  }
  function togglePause() {
    if (paused.value) resume()
    else pause()
  }

  function envelope(e: LiveStreamEnvelope) {
    lastEventAt.value = Date.now()
    if (e.type === 'initial_data' && Array.isArray(e.requests)) {
      // Replace buffer with replay — sort ASC so older entries end up
      // on the left as required.
      const sorted = [...e.requests].sort((a, b) => a.ts.localeCompare(b.ts))
      requests.value = sorted.slice(-capacity)
      return
    }
    if (e.type === 'request' && e.request) {
      appendRequest(e.request)
      return
    }
    if (e.type === 'idle_marker') {
      appendRequest({ type: 'idle_marker', ts: e.ts })
      return
    }
    // 'ping' or unknown: ignore.
  }

  function clearReconnect() {
    if (reconnectTimer) {
      clearTimeout(reconnectTimer)
      reconnectTimer = null
    }
  }

  function scheduleReconnect() {
    if (disposed || options.noAutoReconnect) return
    if (reconnectTimer) return
    reconnectAttempt += 1
    const delay = Math.min(
      BASE_RECONNECT_DELAY_MS * Math.pow(2, reconnectAttempt - 1),
      MAX_RECONNECT_DELAY_MS,
    )
    connection.value = 'reconnecting'
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null
      connect()
    }, delay)
  }

  function connect() {
    if (disposed) return
    if (typeof WebSocket === 'undefined') {
      // SSR / non-browser guard — do nothing. The component will
      // render an empty stream.
      connection.value = 'closed'
      return
    }
    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:'
    const bearer = authBearer()
    // Browsers cannot set arbitrary headers on the WebSocket
    // constructor, so we ride the bearer in the query string. The
    // server-side AdminMiddleware allows `?token=...` (and
    // `?api_key=...`) as a fallback specifically for the live-stream
    // upgrade path. Tokens never appear in browser history because
    // the upgrade response is 101 and the URL is replaced.
    const qs = bearer ? `?token=${encodeURIComponent(bearer)}` : ''
    try {
      ws = new WebSocket(`${proto}//${location.host}${endpoint}${qs}`)
    } catch (err) {
      console.warn('[liveStream] WebSocket construct failed', err)
      scheduleReconnect()
      return
    }
    connection.value = 'connecting'

    ws.onopen = () => {
      connection.value = 'open'
      reconnectAttempt = 0
    }
    ws.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data) as LiveStreamEnvelope
        envelope(data)
      } catch (err) {
        console.warn('[liveStream] bad envelope', err)
      }
    }
    ws.onerror = () => {
      // onclose follows; reconnect happens there.
    }
    ws.onclose = () => {
      ws = null
      if (disposed) {
        connection.value = 'closed'
        return
      }
      scheduleReconnect()
    }
  }

  function disconnect() {
    disposed = true
    clearReconnect()
    if (ws) {
      try {
        ws.close()
      } catch {
        /* ignore */
      }
      ws = null
    }
    connection.value = 'closed'
  }

  onMounted(() => {
    disposed = false
    connect()
  })
  onBeforeUnmount(() => {
    disconnect()
  })

  const isConnected = computed(() => connection.value === 'open')

  return {
    requests,
    connection,
    isConnected,
    paused,
    lastEventAt,
    pause,
    resume,
    togglePause,
    reconnect: () => {
      reconnectAttempt = 0
      clearReconnect()
      connect()
    },
  }
}