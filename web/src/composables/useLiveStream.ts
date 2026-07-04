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

// ==================== 单例模式 ====================
// 全局唯一的 WebSocket 连接实例，避免多个组件创建多个连接
let globalInstance: ReturnType<typeof createLiveStreamInstance> | null = null
let refCount = 0

export function useLiveStream(options: UseLiveStreamOptions = {}) {
  console.log('[useLiveStream] called, refCount:', refCount)
  
  if (!globalInstance) {
    console.log('[useLiveStream] creating new global instance')
    globalInstance = createLiveStreamInstance(options)
  }
  
  refCount++
  
  onBeforeUnmount(() => {
    refCount--
    console.log('[useLiveStream] component unmounted, refCount:', refCount)
    
    // 当所有组件都卸载时，断开连接
    if (refCount === 0 && globalInstance) {
      console.log('[useLiveStream] all components unmounted, disposing instance')
      globalInstance.dispose()
      globalInstance = null
    }
  })
  
  return globalInstance
}

function createLiveStreamInstance(options: UseLiveStreamOptions = {}) {
  console.log('[createLiveStreamInstance] options:', options)
  const capacity = options.capacity ?? MAX_VISIBLE
  const endpoint = options.endpoint ?? '/api/admin/live-stream'

  const requests = ref<LiveRequest[]>([])
  // Track which IDs have already been counted so callers (e.g. the
  // dashboard stat-card incremental updater) can be notified when an
  // ID leaves the buffer. Keeps memory predictable: even at QPS=200
  // the buffer is bounded by `capacity`.
  const idIndex = new Set<string>()
  // Push-out callback: fired with the request_id that was just evicted
  // by the new arrival. Lets the dashboard reconcile stat-card
  // accumulators without re-counting an evicted entry on the next
  // initial_data replay.
  let onEvict: ((requestId: string) => void) | null = null
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

  /**
   * O(n) trim: when buffer is at capacity, drop the oldest entry,
   * drop its ID from idIndex, and notify any eviction listener.
   * One shift per eviction is fine for capacity ≤ 60.
   */
  function trimOldest() {
    if (requests.value.length < capacity) return
    const dropped = requests.value.shift()
    if (!dropped) return
    if (dropped.type === 'request' && dropped.request_id) {
      idIndex.delete(dropped.request_id)
      if (onEvict) onEvict(dropped.request_id)
    }
  }

  function appendRequest(item: LiveRequest) {
    if (paused.value) {
      pending.push(item)
      // Bound the pending queue too — keeps memory predictable when
      // a tab is backgrounded for hours.
      if (pending.length > capacity * 4) {
        const dropped = pending.splice(0, pending.length - capacity * 4)
        for (const d of dropped) {
          if (d.type === 'request' && d.request_id) {
            idIndex.delete(d.request_id)
            if (onEvict) onEvict(d.request_id)
          }
        }
      }
      return
    }
    // If we have already seen this ID (e.g. WS broadcast + telemetry
    // replay), skip — it would otherwise inflate the buffer and
    // double-count stats downstream.
    if (item.type === 'request' && item.request_id && idIndex.has(item.request_id)) {
      return
    }
    if (item.type === 'request' && item.request_id) {
      idIndex.add(item.request_id)
    }
    requests.value.push(item)
    while (requests.value.length > capacity) {
      trimOldest()
    }
  }

  function flushPending() {
    if (pending.length === 0) return
    const drained = pending.splice(0, pending.length)
    for (const item of drained) {
      appendRequest(item)
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
    console.log('[liveStream] processing envelope:', { type: e.type, ts: e.ts })
    lastEventAt.value = Date.now()
    if (e.type === 'initial_data' && Array.isArray(e.requests)) {
      console.log('[liveStream] initial_data:', e.requests.length, 'requests')
      // Replace buffer with replay — sort ASC so older entries end up
      // on the left as required. We also clear idIndex first so the
      // replay IDs become the new source of truth (the previous IDs
      // are now considered evicted).
      const sorted = [...e.requests].sort((a, b) => a.ts.localeCompare(b.ts))
      const kept = sorted.slice(-capacity)
      // Notify eviction for every ID that was in the OLD buffer but
      // not in the NEW replay. Best-effort: if an old ID is also in
      // the new replay, the caller will treat it as "still present"
      // because the Set membership is preserved for IDs we keep.
      const newIds = new Set<string>()
      for (const r of kept) {
        if (r.type === 'request' && r.request_id) newIds.add(r.request_id)
      }
      if (onEvict) {
        for (const oldId of idIndex) {
          if (!newIds.has(oldId)) onEvict(oldId)
        }
      }
      idIndex.clear()
      for (const r of kept) {
        if (r.type === 'request' && r.request_id) idIndex.add(r.request_id)
      }
      requests.value = kept
      console.log('[liveStream] initial_data processed, buffer size:', requests.value.length)
      return
    }
    if (e.type === 'request' && e.request) {
      console.log('[liveStream] new request:', { request_id: e.request.request_id, model: e.request.model, status: e.request.status })
      appendRequest(e.request)
      return
    }
    if (e.type === 'idle_marker') {
      console.log('[liveStream] idle_marker')
      appendRequest({ type: 'idle_marker', ts: e.ts })
      return
    }
    // 'ping' or unknown: ignore.
    console.log('[liveStream] ignored envelope type:', e.type)
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
    const wsUrl = `${proto}//${location.host}${endpoint}${qs}`
    console.log('[liveStream] connecting to:', wsUrl.replace(/token=[^&]+/, 'token=***'))
    try {
      ws = new WebSocket(wsUrl)
    } catch (err) {
      console.warn('[liveStream] WebSocket construct failed', err)
      scheduleReconnect()
      return
    }
    connection.value = 'connecting'

    ws.onopen = () => {
      console.log('[liveStream] WebSocket connected')
      connection.value = 'open'
      reconnectAttempt = 0
    }
    ws.onmessage = (ev) => {
      console.log('[liveStream] received message:', ev.data.substring(0, 200))
      try {
        const data = JSON.parse(ev.data) as LiveStreamEnvelope
        console.log('[liveStream] parsed envelope:', { type: data.type, hasRequest: !!data.request, requestsCount: data.requests?.length })
        envelope(data)
      } catch (err) {
        console.warn('[liveStream] bad envelope', err)
      }
    }
    ws.onerror = (err) => {
      console.error('[liveStream] WebSocket error:', err)
      // onclose follows; reconnect happens there.
    }
    ws.onclose = (ev) => {
      console.log('[liveStream] WebSocket closed:', { code: ev.code, reason: ev.reason })
      ws = null
      if (disposed) {
        connection.value = 'closed'
        return
      }
      scheduleReconnect()
    }
  }

  function disconnect() {
    console.log('[liveStream] disconnect called')
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

  // 自动连接（在创建实例时调用）
  console.log('[createLiveStreamInstance] auto-connecting...')
  disposed = false
  connect()

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
    /**
     * Register a callback that fires every time a request_id is
     * evicted from the buffer (either because the buffer is at
     * capacity and the oldest was shifted out, or because an
     * initial_data replay replaced the previous IDs).
     *
     * The dashboard uses this to keep its stat-card accumulators
     * honest: when an ID leaves the buffer we know we'll never see
     * it again in a delta, so any per-request stat already baked
     * into the totals does NOT need to be subtracted (the totals
     * are forever cumulative) — but the per-tenant "live in
     * buffer" count CAN be decremented.
     */
    onRequestEvicted: (cb: (id: string) => void) => {
      onEvict = cb
    },
    /**
     * Reset both the visible buffer and the id index. Used by the
     * "Refresh" button so the next delta starts from a clean slate.
     */
    reset: () => {
      requests.value = []
      idIndex.clear()
      pending.length = 0
    },
    dispose: disconnect,
  }
}