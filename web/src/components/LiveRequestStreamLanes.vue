<script setup lang="ts">
/**
 * LiveRequestStreamLanes — 泳道式实时请求流
 *
 * 支持三种分组模式：
 * 1. 按模型原厂分组（动态计算 Top N）
 * 2. 按供应商分组（动态计算 Top N）
 * 3. 按模型分组（动态计算 Top N）
 *
 * 2026-07-05 revision: 新增按模型分组，实现去重更新动画，定时泳道排序
 */
import { computed, ref, watch, onMounted, onBeforeUnmount } from 'vue'
import { useI18n } from 'vue-i18n'
import { useLiveStream, type LiveRequest } from '../composables/useLiveStream'
import { getInitialLiveStreamStats } from '../api/usage'
import LiveRequestBlock from './LiveRequestBlock.vue'
import LiveStreamLegend from './LiveStreamLegend.vue'

const emit = defineEmits<{
  openDetail: [requestId: string]
}>()

const { t } = useI18n()
const { requests, connection, paused, togglePause } = useLiveStream()

type GroupMode = 'vendor' | 'provider' | 'model'
const groupMode = ref<GroupMode>('vendor')

// 初始统计加载状态
const initialStatsLoaded = ref(false)

// 累计统计（从开始显示到现在）
const cumulativeStats = ref({
  vendor: new Map<string, number>(),
  provider: new Map<string, number>(),
  model: new Map<string, number>(),
})

// 从 API 加载初始统计数据
async function loadInitialStats() {
  try {
    const data = await getInitialLiveStreamStats(7)
    console.log('[LiveStreamLanes] loaded initial stats:', data)
    
    // 初始化原厂统计
    for (const [vendor, count] of Object.entries(data.vendors)) {
      cumulativeStats.value.vendor.set(vendor, count)
    }
    
    // 初始化供应商统计
    for (const [provider, count] of Object.entries(data.providers)) {
      cumulativeStats.value.provider.set(provider, count)
    }
    
    // 初始化模型统计
    for (const [model, count] of Object.entries(data.models)) {
      cumulativeStats.value.model.set(model, count)
    }
    
    initialStatsLoaded.value = true  // 标记加载完成
    console.log('[LiveStreamLanes] initial stats loaded, vendor count:', cumulativeStats.value.vendor.size)
    
    console.log('[LiveStreamLanes] initialized cumulative stats:', {
      vendorCount: cumulativeStats.value.vendor.size,
      providerCount: cumulativeStats.value.provider.size,
      modelCount: cumulativeStats.value.model.size,
    })
  } catch (error) {
    console.error('[LiveStreamLanes] failed to load initial stats:', error)
    // 加载失败也标记为已完成，避免永远卡在加载状态
    initialStatsLoaded.value = true
  }
}

// WebSocket 连接地址（仅管理员可见）
const wsUrl = computed(() => {
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:'
  return `${proto}//${location.host}/api/admin/live-stream`
})

const showWsUrl = ref(false)

// 选中的分组项和状态项（用于高亮显示）
const selectedGroups = ref<Set<string>>(new Set())
const selectedStatuses = ref<Set<string>>(new Set())

// 处理图例项选中/反选
function handleLegendToggle(type: 'group' | 'status', key: string) {
  if (type === 'group') {
    if (selectedGroups.value.has(key)) {
      selectedGroups.value.delete(key)
    } else {
      selectedGroups.value.add(key)
    }
    // 触发响应式更新
    selectedGroups.value = new Set(selectedGroups.value)
  } else {
    if (selectedStatuses.value.has(key)) {
      selectedStatuses.value.delete(key)
    } else {
      selectedStatuses.value.add(key)
    }
    // 触发响应式更新
    selectedStatuses.value = new Set(selectedStatuses.value)
  }
}

// 每个泳道的请求队列（独立管理，避免每次重新计算）
// 使用 shallowRef 避免深度响应式开销
const laneQueues = ref<Map<string, LiveRequest[]>>(new Map())

// 请求ID索引：快速查找请求在哪个泳道
const requestLaneIndex = new Map<string, string>()

// 初始化泳道队列
function initializeLaneQueues() {
  const queues = new Map<string, LiveRequest[]>()
  for (const lane of lanes.value) {
    queues.set(lane.key, [])
  }
  laneQueues.value = queues
  // 清空索引
  requestLaneIndex.clear()
  console.log('[LiveStreamLanes] initialized lane queues:', Array.from(queues.keys()))
}

// 去重更新：如果请求已存在，移除旧位置，推到队尾
function upsertRequest(laneKey: string, req: LiveRequest) {
  const queue = laneQueues.value.get(laneKey)
  if (!queue) {
    console.warn(`[LiveStreamLanes] lane ${laneKey} not found, available lanes:`, Array.from(laneQueues.value.keys()))
    return
  }

  const requestId = req.request_id
  if (!requestId) {
    // idle_marker 等非请求类型，直接追加
    queue.push(req)
    if (queue.length > MAX_PER_LANE) {
      queue.shift()
    }
    return
  }

  // 检查是否已存在（去重更新）
  const existingIdx = queue.findIndex(r => r.request_id === requestId)
  if (existingIdx >= 0) {
    // 移除旧位置
    queue.splice(existingIdx, 1)
    console.log(`[LiveStreamLanes] removed duplicate ${requestId} from position ${existingIdx}`)
  }

  // 推到队尾
  queue.push(req)
  console.log(`[LiveStreamLanes] pushed request ${requestId} to lane ${laneKey}, queue size: ${queue.length}`)

  // 限制队列长度
  if (queue.length > MAX_PER_LANE) {
    const removed = queue.shift()
    if (removed?.request_id) {
      requestLaneIndex.delete(removed.request_id)
    }
  }

  // 更新索引
  requestLaneIndex.set(requestId, laneKey)
}

// 监听新请求，直接推入对应泳道（使用 RAF 批量处理）
let pendingRequests: LiveRequest[] = []
let rafHandle: number | null = null

function processPendingRequests() {
  rafHandle = null
  const batch = pendingRequests.splice(0)
  if (batch.length === 0) return

  console.log('[LiveStreamLanes] processing batch:', batch.length)

  for (const req of batch) {
    // 累计原厂统计
    const vendor = identifyVendor(req.model)
    cumulativeStats.value.vendor.set(vendor, (cumulativeStats.value.vendor.get(vendor) || 0) + 1)

    // 累计供应商统计
    if (req.provider_code) {
      cumulativeStats.value.provider.set(req.provider_code, (cumulativeStats.value.provider.get(req.provider_code) || 0) + 1)
    }

    // 累计模型统计
    if (req.model) {
      cumulativeStats.value.model.set(req.model, (cumulativeStats.value.model.get(req.model) || 0) + 1)
    }

    // 推入对应泳道（带去重）
    const laneKey = getLaneKey(req)
    upsertRequest(laneKey, req)
  }

  // 触发响应式更新（浅层拷贝）
  laneQueues.value = new Map(laneQueues.value)
}

function scheduleBatchUpdate() {
  if (rafHandle === null) {
    rafHandle = requestAnimationFrame(processPendingRequests)
  }
}

// 🔥 追踪已处理的请求 ID，避免重复处理
const processedRequestIds = new Set<string>()

watch(requests, (newReqs) => {
  // 🔥 只有当组件实际挂载后才处理新请求
  if (!initialStatsLoaded.value) {
    console.log('[LiveStreamLanes] skipping watch: initialStats not loaded yet')
    return
  }

  console.log('[LiveStreamLanes] requests watch triggered:', {
    bufferSize: newReqs.length,
    processedCount: processedRequestIds.size,
    initialStatsLoaded: initialStatsLoaded.value,
    laneQueueKeys: Array.from(laneQueues.value.keys()),
  })

  // 🔥 调试：输出 buffer 中的请求结构
  console.log('[LiveStreamLanes] buffer contents:', newReqs.map(r => ({
    type: r.type,
    request_id: r.request_id,
    model: r.model,
    hasRequestId: !!r.request_id,
    alreadyProcessed: r.request_id ? processedRequestIds.has(r.request_id) : false,
  })))

  // 🔥 找出尚未处理的新请求
  const newItems = newReqs.filter(r => 
    r.type === 'request' && 
    r.request_id && 
    !processedRequestIds.has(r.request_id)
  )

  console.log('[LiveStreamLanes] unprocessed items:', newItems.length, 'of', newReqs.length)
  
  if (newItems.length === 0) {
    console.log('[LiveStreamLanes] no new items detected')
    return
  }

  console.log('[LiveStreamLanes] detected', newItems.length, 'new requests:', newItems.map(r => ({
    id: r.request_id,
    model: r.model,
    provider: r.provider_code,
  })))

  // 🔥 标记为已处理
  for (const item of newItems) {
    if (item.request_id) {
      processedRequestIds.add(item.request_id)
    }
  }

  // 加入待处理队列
  pendingRequests.push(...newItems)
  console.log('[LiveStreamLanes] pendingRequests queue size:', pendingRequests.length)
  scheduleBatchUpdate()
}, { deep: true }) // 🔥 必须监听深层变化，因为 requests.value.push() 修改的是数组内容

// 模型名 → 原厂（vendor/manufacturer）
// 不强调地域，只按模型的实际研发公司分类
const VENDOR_PATTERNS: Array<{ vendor: string; patterns: RegExp[]; color: string }> = [
  { vendor: 'OpenAI',      patterns: [/\bgpt-?\d/i, /\bo[1-4]/i, /\bo\d{2,}-/i, /chatgpt/i], color: '#10a37f' },
  { vendor: 'Anthropic',   patterns: [/claude/i],                                                color: '#d97757' },
  { vendor: 'Google',      patterns: [/gemini/i, /palm/i, /bard/i, /gemma/i],                   color: '#4285f4' },
  { vendor: 'Meta',        patterns: [/llama/i, /codellama/i],                                   color: '#0668e1' },
  { vendor: 'Mistral',     patterns: [/mistral/i, /mixtral/i, /codestral/i],                    color: '#ff7000' },
  { vendor: 'Alibaba',     patterns: [/qwen/i, /qwq/i, /tongyi/i],                              color: '#ff6a00' },
  { vendor: 'DeepSeek',    patterns: [/deepseek/i],                                              color: '#4d6bfe' },
  { vendor: 'xAI',         patterns: [/grok/i],                                                  color: '#000000' },
  { vendor: 'Cohere',      patterns: [/command/i, /cohere/i],                                    color: '#39594d' },
  { vendor: 'Microsoft',   patterns: [/phi-/i, /wizardlm/i],                                      color: '#00a4ef' },
  { vendor: 'NVIDIA',      patterns: [/nemotron/i, /nvidia/i],                                   color: '#76b900' },
  { vendor: '01.AI',       patterns: [/yi-/i, /yi_/i],                                            color: '#7c3aed' },
  { vendor: 'Baichuan',    patterns: [/baichuan/i],                                              color: '#2563eb' },
  { vendor: 'Zhipu',       patterns: [/glm/i, /chatglm/i],                                        color: '#3b82f6' },
  { vendor: 'Moonshot',    patterns: [/moonshot/i, /kimi/i],                                     color: '#6366f1' },
  { vendor: 'ByteDance',   patterns: [/doubao/i],                                                color: '#1e88e5' },
  { vendor: 'Baidu',       patterns: [/ernie/i, /wenxin/i],                                      color: '#2932e1' },
  { vendor: 'Tencent',     patterns: [/hunyuan/i],                                               color: '#00a4ff' },
  { vendor: 'iFlytek',     patterns: [/spark/i, /iflytek/i],                                     color: '#00b6f3' },
]

const OTHER_VENDOR = 'Other'

/**
 * 从模型名识别原厂。
 * 优先匹配精确模式；若都不匹配，返回 'Other'。
 */
function identifyVendor(model: string | undefined): string {
  if (!model) return OTHER_VENDOR
  for (const { vendor, patterns } of VENDOR_PATTERNS) {
    for (const p of patterns) {
      if (p.test(model)) return vendor
    }
  }
  return OTHER_VENDOR
}

// 使用累计统计（而不是当前缓存）来决定 Top N
const vendorStats = computed(() => {
  return Array.from(cumulativeStats.value.vendor.entries())
    .sort((a, b) => b[1] - a[1])
})

const providerStats = computed(() => {
  return Array.from(cumulativeStats.value.provider.entries())
    .sort((a, b) => b[1] - a[1])
})

const modelStats = computed(() => {
  return Array.from(cumulativeStats.value.model.entries())
    .sort((a, b) => b[1] - a[1])
})

// 当前缓存中的请求总数（不含 idle_marker）
const bufferSize = computed(() => requests.value.filter(r => r.type === 'request').length)

// 当前窗口中实际显示的请求数（每泳道最多30，所有泳道合计）
const visibleCount = computed(() => {
  let total = 0
  for (const lane of lanes.value) {
    const items = laneRequests.value.get(lane.key) || []
    total += Math.min(items.length, MAX_PER_LANE)
  }
  return total
})

// 颜色池（用于 Top 4 之外的供应商）
const VENDOR_COLORS = ['#10a37f', '#3b82f6', '#f59e0b', '#8b5cf6', '#ec4899', '#14b8a6', '#f43f5e', '#84cc16']

// 动态泳道配置：Top 6 热门原厂/供应商/模型 + Other
const TOP_N = 5  // 改为 Top 5，符合需求
const lanes = computed(() => {
  if (groupMode.value === 'vendor') {
    const topVendors = vendorStats.value.slice(0, TOP_N).map(([vendor]) => vendor)
    return [
      ...topVendors.map((vendor, idx) => {
        const preset = VENDOR_PATTERNS.find((v) => v.vendor === vendor)
        const count = cumulativeStats.value.vendor.get(vendor) || 0
        return {
          key: vendor,
          label: vendor,
          color: preset?.color || VENDOR_COLORS[idx] || '#6b7280',
          count,
        }
      }),
      { 
        key: OTHER_VENDOR, 
        label: t('dashboard.liveStream.other'), 
        color: '#6b7280',
        count: Array.from(cumulativeStats.value.vendor.entries())
          .filter(([v]) => !topVendors.includes(v))
          .reduce((sum, [, cnt]) => sum + cnt, 0),
      },
    ]
  } else if (groupMode.value === 'provider') {
    const topProviders = providerStats.value.slice(0, TOP_N).map(([code]) => code)
    return [
      ...topProviders.map((code, idx) => ({
        key: code,
        label: code,
        color: VENDOR_COLORS[idx] || '#6b7280',
        count: cumulativeStats.value.provider.get(code) || 0,
      })),
      { 
        key: OTHER_VENDOR, 
        label: t('dashboard.liveStream.other'), 
        color: '#6b7280',
        count: Array.from(cumulativeStats.value.provider.entries())
          .filter(([p]) => !topProviders.includes(p))
          .reduce((sum, [, cnt]) => sum + cnt, 0),
      },
    ]
  } else {
    // 按模型分组
    const topModels = modelStats.value.slice(0, TOP_N).map(([model]) => model)
    return [
      ...topModels.map((model, idx) => ({
        key: model,
        label: model,
        color: VENDOR_COLORS[idx] || '#6b7280',
        count: cumulativeStats.value.model.get(model) || 0,
      })),
      { 
        key: OTHER_VENDOR, 
        label: t('dashboard.liveStream.other'), 
        color: '#6b7280',
        count: Array.from(cumulativeStats.value.model.entries())
          .filter(([m]) => !topModels.includes(m))
          .reduce((sum, [, cnt]) => sum + cnt, 0),
      },
    ]
  }
})

// 图例数据：根据分组模式动态生成
const legendItems = computed(() => {
  return lanes.value.map(lane => ({
    key: lane.key,
    label: lane.label,
    color: lane.color,
  }))
})

// 判断某个请求是否应该高亮显示
function shouldHighlight(req: LiveRequest): boolean {
  // 如果没有选中任何图例项，则不高亮
  if (selectedGroups.value.size === 0 && selectedStatuses.value.size === 0) {
    return false
  }
  
  // 检查分组维度是否匹配
  let groupMatch = selectedGroups.value.size === 0
  if (selectedGroups.value.size > 0) {
    const laneKey = getLaneKey(req)
    groupMatch = selectedGroups.value.has(laneKey)
  }
  
  // 检查状态维度是否匹配
  let statusMatch = selectedStatuses.value.size === 0
  if (selectedStatuses.value.size > 0 && req.type === 'request') {
    const status = req.status || 'in_progress'
    if (status === 'success') {
      statusMatch = selectedStatuses.value.has('success')
    } else if (status === 'in_progress') {
      statusMatch = selectedStatuses.value.has('in_progress')
    } else if (status === 'failure') {
      // 根据 error_kind 判断具体的失败类型
      const k = (req.error_kind || '').toLowerCase()
      if (/(timeout|timedout|cancel|disconnect)/.test(k)) {
        statusMatch = selectedStatuses.value.has('failure_timeout')
      } else if (/(5xx|server|upstream|provider|overloaded|backend)/.test(k)) {
        statusMatch = selectedStatuses.value.has('failure_5xx')
      } else if (/(4xx|auth|unauthor|forbidden|quota|rate|billing|payment)/.test(k)) {
        statusMatch = selectedStatuses.value.has('failure_4xx')
      } else if (/(not_found|model_not|route|no_route|resolve|policy)/.test(k)) {
        statusMatch = selectedStatuses.value.has('failure_not_found')
      } else {
        statusMatch = selectedStatuses.value.has('failure_other')
      }
    }
  }
  
  // 同时满足分组和状态的匹配才高亮
  return groupMatch && statusMatch
}

// 固定的知名原厂列表（避免依赖累计统计导致初始化问题）
const KNOWN_VENDORS = ['OpenAI', 'Anthropic', 'Google', 'Meta', 'xAI', 'Mistral', 'Cohere', 'DeepSeek']

// 将请求分配到对应泳道
function getLaneKey(req: LiveRequest): string {
  if (req.type === 'idle_marker') return OTHER_VENDOR

  if (groupMode.value === 'vendor') {
    const vendor = identifyVendor(req.model)
    // 🔥 修复：使用固定的知名原厂列表，不依赖 vendorStats
    // 这样即使在 loadInitialStats 完成前，新请求也能正确分配到对应泳道
    return KNOWN_VENDORS.includes(vendor) ? vendor : OTHER_VENDOR
  } else if (groupMode.value === 'provider') {
    if (!req.provider_code) return OTHER_VENDOR
    const topProviders = providerStats.value.slice(0, TOP_N).map(([c]) => c)
    return topProviders.includes(req.provider_code) ? req.provider_code : OTHER_VENDOR
  } else {
    // 按模型分组
    if (!req.model) return OTHER_VENDOR
    const topModels = modelStats.value.slice(0, TOP_N).map(([m]) => m)
    return topModels.includes(req.model) ? req.model : OTHER_VENDOR
  }
}

// 🔥 新方案：直接从泳道队列获取请求，不再计算
// 使用 computed 包裹，确保响应式更新
const laneRequests = computed(() => {
  // 返回当前泳道队列的快照
  return laneQueues.value
})

// 每个泳道最多显示的请求数
const MAX_PER_LANE = 30

// 定时排序泳道（每5秒按累计请求数重新排序，避免UI闪烁）
// 使用 requestAnimationFrame 批量更新，减少重渲染
const sortedLanes = ref(lanes.value)
let sortTimer: ReturnType<typeof setInterval> | null = null
let rafId: number | null = null

// 使用 RAF 批量更新排序，避免频繁触发重渲染
function scheduleSort() {
  if (rafId !== null) return
  
  rafId = requestAnimationFrame(() => {
    rafId = null
    const current = lanes.value
    const sorted = [...current].sort((a, b) => {
      // 先按请求数降序
      if (b.count !== a.count) return b.count - a.count
      // 请求数相同时按 key 字母序（稳定排序，避免闪烁）
      return a.key.localeCompare(b.key)
    })
    
    // 只有顺序真正改变时才更新
    const orderChanged = sorted.some((lane, idx) => lane.key !== sortedLanes.value[idx]?.key)
    if (orderChanged) {
      sortedLanes.value = sorted
    }
  })
}

onMounted(async () => {
  console.log('[LiveStreamLanes] onMounted called')
  
  // 加载初始统计数据
  await loadInitialStats()
  
  console.log('[LiveStreamLanes] after loadInitialStats, lanes:', lanes.value.map(l => ({ key: l.key, count: l.count })))
  
  // 🔥 初始化泳道队列
  initializeLaneQueues()
  
  console.log('[LiveStreamLanes] after initializeLaneQueues, queues:', Array.from(laneQueues.value.keys()))
  
  // 🔥 将 useLiveStream 缓冲区中已有的请求推入泳道
  const existingRequests = requests.value.filter(r => r.type === 'request')
  console.log('[LiveStreamLanes] found', existingRequests.length, 'existing requests in buffer')
  
  if (existingRequests.length > 0) {
    // 🔥 标记缓冲区中的已有请求为已处理
    for (const req of existingRequests) {
      if (req.request_id) {
        processedRequestIds.add(req.request_id)
      }
    }
    pendingRequests.push(...existingRequests)
    processPendingRequests()
  }
  
  // 初始化排序
  sortedLanes.value = [...lanes.value].sort((a, b) => {
    if (b.count !== a.count) return b.count - a.count
    return a.key.localeCompare(b.key)
  })
  
  // 每5秒重新排序一次（使用 RAF 批量更新）
  sortTimer = setInterval(() => {
    scheduleSort()
  }, 5000)
})

onBeforeUnmount(() => {
  if (sortTimer) {
    clearInterval(sortTimer)
    sortTimer = null
  }
  if (rafId !== null) {
    cancelAnimationFrame(rafId)
    rafId = null
  }
  if (rafHandle !== null) {
    cancelAnimationFrame(rafHandle)
    rafHandle = null
  }
})

// 当分组模式切换时，需要重新分配所有请求到新泳道
watch(groupMode, () => {
  console.log('[LiveStreamLanes] group mode changed to:', groupMode.value)
  
  // 🔥 清空泳道队列，避免残留数据
  laneQueues.value.clear()
  
  // 重新初始化泳道队列（创建空队列）
  initializeLaneQueues()
  
  console.log('[LiveStreamLanes] cleared and reinitialized lanes:', Array.from(laneQueues.value.keys()))
  
  // 🔥 从 requests buffer 中重新处理所有已标记为已处理的请求
  // 这样可以确保切换维度后，泳道数据与当前维度一致
  const allBufferedRequests = requests.value.filter(r => 
    r.type === 'request' && 
    r.request_id && 
    processedRequestIds.has(r.request_id)
  )
  
  console.log('[LiveStreamLanes] re-processing', allBufferedRequests.length, 'buffered requests for new group mode')
  
  // 重新分配到新泳道
  for (const req of allBufferedRequests) {
    const laneKey = getLaneKey(req)
    upsertRequest(laneKey, req)
  }
  
  // 触发响应式更新
  laneQueues.value = new Map(laneQueues.value)
  
  // 立即重新排序
  sortedLanes.value = [...lanes.value].sort((a, b) => {
    if (b.count !== a.count) return b.count - a.count
    return a.key.localeCompare(b.key)
  })
})

// 当泳道定义变化时，触发排序检查（使用 RAF 避免频繁更新）
watch(lanes, () => {
  scheduleSort()
}, { deep: false })

const connectionLabel = computed(() => {
  if (connection.value === 'open') return t('dashboard.liveStream.connected')
  return t('dashboard.liveStream.disconnected')
})

function onSelect(requestId: string) {
  emit('openDetail', requestId)
}
</script>

<template>
  <div class="live-stream-lanes">
    <div class="live-stream-lanes__header">
      <h3 class="live-stream-lanes__title">{{ t('dashboard.liveStream.title') }}</h3>
      <div class="live-stream-lanes__controls">
        <!-- 分组模式切换 -->
        <div class="live-stream-lanes__group-toggle">
          <button
            type="button"
            class="live-stream-lanes__group-btn"
            :class="{ 'live-stream-lanes__group-btn--active': groupMode === 'vendor' }"
            @click="groupMode = 'vendor'"
          >
            {{ t('dashboard.liveStream.groupByVendor') }}
          </button>
          <button
            type="button"
            class="live-stream-lanes__group-btn"
            :class="{ 'live-stream-lanes__group-btn--active': groupMode === 'provider' }"
            @click="groupMode = 'provider'"
          >
            {{ t('dashboard.liveStream.groupByProvider') }}
          </button>
          <button
            type="button"
            class="live-stream-lanes__group-btn"
            :class="{ 'live-stream-lanes__group-btn--active': groupMode === 'model' }"
            @click="groupMode = 'model'"
          >
            {{ t('dashboard.liveStream.groupByModel') }}
          </button>
        </div>

        <!-- 连接状态 -->
        <button
          type="button"
          class="live-stream-lanes__status"
          :class="{
            'live-stream-lanes__status--ok': connection === 'open',
            'live-stream-lanes__status--warn': connection !== 'open',
          }"
          @click="showWsUrl = !showWsUrl"
          :title="showWsUrl ? wsUrl : '点击查看连接地址'"
        >
          <span class="live-stream-lanes__dot" aria-hidden="true" />
          {{ connectionLabel }}
        </button>

        <!-- 暂停/继续按钮 -->
        <button
          type="button"
          class="live-stream-lanes__btn"
          @click="togglePause"
        >
          {{ paused ? t('dashboard.liveStream.resume') : t('dashboard.liveStream.pause') }}
        </button>

        <!-- 缓存/窗口统计 -->
        <span
          class="live-stream-lanes__count"
          :title="`缓存: ${bufferSize} 个请求 / 窗口: ${visibleCount} 个请求`"
        >
          <span class="live-stream-lanes__count-num">{{ bufferSize }}</span>
          <span class="live-stream-lanes__count-sep">/</span>
          <span class="live-stream-lanes__count-num">{{ visibleCount }}</span>
        </span>
      </div>
    </div>

    <!-- WebSocket 连接地址提示 -->
    <div v-if="showWsUrl" class="live-stream-lanes__ws-url">
      <code>{{ wsUrl }}</code>
    </div>

    <!-- 图例：放在标题栏下一行 -->
    <LiveStreamLegend 
      :group-mode="groupMode"
      :group-items="legendItems"
      @toggle-selection="handleLegendToggle"
    />

    <!-- 泳道容器 -->
    <div v-if="!initialStatsLoaded" class="live-stream-lanes__loading">
      <span class="live-stream-lanes__loading-text">{{ t('dashboard.liveStream.loadingStats') }}</span>
    </div>
    <div v-else class="live-stream-lanes__container">
      <div
        v-for="lane in sortedLanes"
        :key="lane.key"
        class="live-stream-lane"
      >
        <!-- 泳道标签 -->
        <div class="live-stream-lane__label" :style="{ borderLeftColor: lane.color }">
          <div class="live-stream-lane__name-wrapper">
            <span class="live-stream-lane__name" :title="lane.label">{{ lane.label }}</span>
          </div>
          <span class="live-stream-lane__count">({{ lane.count }})</span>
        </div>

        <!-- 泳道轨道 -->
        <div class="live-stream-lane__track">
          <TransitionGroup name="lane-slide" tag="div" class="live-stream-lane__track-inner">
            <LiveRequestBlock
              v-for="(req, idx) in laneRequests.get(lane.key)?.slice(-MAX_PER_LANE) || []"
              :key="req.request_id ?? `idle-${lane.key}-${idx}-${req.ts}`"
              :request="req"
              :group-mode="groupMode"
              :highlight="shouldHighlight(req)"
              @select="onSelect"
            />
          </TransitionGroup>
          <div
            v-if="(laneRequests.get(lane.key)?.length || 0) === 0"
            class="live-stream-lane__empty"
          >
            —
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.live-stream-lanes {
  border: 1px solid var(--border, #30363d);
  border-radius: var(--radius, 8px);
  background: var(--card, #1c2128);
  padding: 12px 16px;
  margin-bottom: 20px;
}

/* ====== Header：禁止折行 ====== */
.live-stream-lanes__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: nowrap;
  gap: 10px;
  margin-bottom: 12px;
  min-width: 0;
}

.live-stream-lanes__title {
  font-size: 14px;
  font-weight: 600;
  margin: 0;
  color: var(--text, #e6edf3);
  flex-shrink: 0;
  white-space: nowrap;
}

.live-stream-lanes__controls {
  display: flex;
  align-items: center;
  gap: 8px;
  flex: 1 1 auto;
  min-width: 0;
  flex-wrap: nowrap;
  justify-content: flex-end;
  overflow: hidden;
}

/* 分组模式切换按钮组 */
.live-stream-lanes__group-toggle {
  display: flex;
  gap: 4px;
  border: 1px solid var(--border, #30363d);
  border-radius: 4px;
  background: var(--bg, #0f1117);
  padding: 2px;
  flex-shrink: 0;
}

.live-stream-lanes__group-btn {
  font-size: 11px;
  padding: 3px 8px;
  border-radius: 3px;
  border: none;
  background: transparent;
  color: var(--muted, #8b949e);
  cursor: pointer;
  white-space: nowrap;
  transition: all 0.15s ease;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans SC', 'Microsoft YaHei', sans-serif;
}

.live-stream-lanes__group-btn:hover {
  background: var(--bg-subtle, #161b22);
  color: var(--text, #e6edf3);
}

.live-stream-lanes__group-btn--active {
  background: var(--accent, #6366f1);
  color: #fff;
  font-weight: 600;
}

/* 连接状态按钮 */
.live-stream-lanes__status {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  padding: 4px 10px;
  border-radius: 4px;
  border: 1px solid var(--border, #30363d);
  background: var(--bg, #0f1117);
  color: var(--muted, #8b949e);
  cursor: pointer;
  flex-shrink: 0;
  white-space: nowrap;
  transition: all 0.15s ease;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans SC', 'Microsoft YaHei', sans-serif;
}

.live-stream-lanes__status:hover {
  background: var(--bg-subtle, #161b22);
  border-color: var(--accent, #6366f1);
}

.live-stream-lanes__dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--muted, #8b949e);
  flex-shrink: 0;
}

.live-stream-lanes__status--ok .live-stream-lanes__dot {
  background: var(--success, #3fb950);
  box-shadow: 0 0 0 3px rgba(63, 185, 80, 0.18);
}

.live-stream-lanes__status--warn .live-stream-lanes__dot {
  background: var(--warning, #d29922);
  animation: lane-dot-pulse 1.4s ease-in-out infinite;
}

@keyframes lane-dot-pulse {
  0%, 100% { opacity: 1; }
  50%      { opacity: 0.4; }
}

.live-stream-lanes__btn {
  font-size: 12px;
  padding: 4px 10px;
  border-radius: 4px;
  border: 1px solid var(--border, #30363d);
  background: var(--bg, #0f1117);
  color: var(--text, #e6edf3);
  cursor: pointer;
  white-space: nowrap;
  flex-shrink: 0;
  min-width: 64px;
  transition: all 0.15s ease;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans SC', 'Microsoft YaHei', sans-serif;
}

.live-stream-lanes__btn:hover {
  background: var(--bg-subtle, #161b22);
  border-color: var(--accent, #6366f1);
}

/* 缓存/窗口统计 */
.live-stream-lanes__count {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  white-space: nowrap;
  flex-shrink: 0;
  font-size: 12px;
  font-family: ui-monospace, SFMono-Regular, Menlo, 'Cascadia Code', monospace;
  color: var(--muted, #8b949e);
  padding: 4px 10px;
  border: 1px solid var(--border, #30363d);
  border-radius: 4px;
  background: var(--bg, #0f1117);
  font-variant-numeric: tabular-nums;
  min-width: 78px;
  justify-content: center;
}

.live-stream-lanes__count-num {
  color: var(--text, #e6edf3);
  font-weight: 600;
}

.live-stream-lanes__count-sep {
  color: var(--border, #30363d);
}

/* WebSocket 连接地址 */
.live-stream-lanes__ws-url {
  margin-bottom: 8px;
  padding: 8px 12px;
  background: var(--bg-subtle, #161b22);
  border: 1px solid var(--border, #30363d);
  border-radius: 4px;
  font-size: 11px;
  color: var(--muted, #8b949e);
  overflow-x: auto;
}

.live-stream-lanes__ws-url code {
  font-family: ui-monospace, SFMono-Regular, Menlo, 'Cascadia Code', monospace;
  color: var(--text, #e6edf3);
}

/* 泳道容器 */
.live-stream-lanes__container {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

/* 单个泳道（高度60px，需求要求） */
.live-stream-lane {
  display: flex;
  align-items: center;
  gap: 12px;
  min-height: 60px;
  flex-wrap: nowrap;
  min-width: 0;
}

/* 泳道标签 — 固定宽度（约10个字符），支持折行显示，高度与泳道一致 */
.live-stream-lane__label {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 2px;
  width: 120px;
  min-width: 120px;
  max-width: 120px;
  flex-shrink: 0;
  padding: 4px 0 4px 8px;
  border-left: 3px solid var(--accent, #6366f1);
  overflow: hidden;
  min-height: 60px;
  justify-content: center;
}

.live-stream-lane__name-wrapper {
  width: 100%;
  overflow: hidden;
}

.live-stream-lane__name {
  font-size: 13px;
  font-weight: 600;
  color: var(--text, #e6edf3);
  word-break: break-word;
  line-height: 1.3;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  max-width: 100%;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans SC', 'Microsoft YaHei', sans-serif;
}

.live-stream-lane__count {
  font-size: 11px;
  color: var(--muted, #8b949e);
  font-family: ui-monospace, SFMono-Regular, Menlo, 'Cascadia Code', monospace;
  white-space: nowrap;
  font-variant-numeric: tabular-nums;
}

/* 泳道轨道（高度60px，需求要求） */
.live-stream-lane__track {
  position: relative;
  flex: 1;
  height: 60px;
  overflow: hidden;
  background: var(--bg-subtle, #161b22);
  border: 1px solid var(--border, #30363d);
  border-radius: 6px;
  padding: 2px 4px;
}

.live-stream-lane__track-inner {
  display: flex;
  align-items: center;
  gap: 4px;
  height: 100%;
  justify-content: flex-end;
}

.live-stream-lane__empty {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--muted, #8b949e);
  font-size: 12px;
  pointer-events: none;
}

/* 泳道轨道滑入动画：新请求从右侧滑入 */
.lane-slide-enter-active {
  transition:
    transform 0.45s cubic-bezier(0.18, 1.25, 0.32, 1.0),
    opacity 0.35s ease;
}

.lane-slide-enter-from {
  opacity: 0;
  transform: translateX(40px);
}

/* 移动到队尾动画（去重更新时） */
.lane-slide-move {
  transition: transform 0.4s cubic-bezier(0.25, 0.46, 0.45, 0.94);
}

.lane-slide-leave-active {
  transition: transform 0.3s ease, opacity 0.3s ease;
  position: absolute;
}

.lane-slide-leave-to {
  opacity: 0;
  transform: translateX(-20px);
}

/* 加载状态 */
.live-stream-lanes__loading {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 200px;
  color: var(--muted, #8b949e);
}

.live-stream-lanes__loading-text {
  font-size: 14px;
  animation: pulse 1.5s ease-in-out infinite;
}

@keyframes pulse {
  0%, 100% {
    opacity: 0.6;
  }
  50% {
    opacity: 1;
  }
}
</style>