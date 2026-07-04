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
import LiveRequestBlock from './LiveRequestBlock.vue'
import LiveStreamLegend from './LiveStreamLegend.vue'

const emit = defineEmits<{
  openDetail: [requestId: string]
}>()

const { t } = useI18n()
const { requests, connection, paused, togglePause } = useLiveStream()

type GroupMode = 'vendor' | 'provider' | 'model'
const groupMode = ref<GroupMode>('vendor')

// 累计统计（从开始显示到现在）
const cumulativeStats = ref({
  vendor: new Map<string, number>(),
  provider: new Map<string, number>(),
  model: new Map<string, number>(),
})

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
  } else {
    if (selectedStatuses.value.has(key)) {
      selectedStatuses.value.delete(key)
    } else {
      selectedStatuses.value.add(key)
    }
  }
}

// 监听新请求，累计统计
watch(requests, (newReqs, oldReqs) => {
  const oldIds = new Set(oldReqs.filter(r => r.request_id).map(r => r.request_id!))
  const newItems = newReqs.filter(r => r.type === 'request' && r.request_id && !oldIds.has(r.request_id))
  
  for (const req of newItems) {
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
  }
}, { deep: true })

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

// 将请求分配到对应泳道
function getLaneKey(req: LiveRequest): string {
  if (req.type === 'idle_marker') return OTHER_VENDOR

  if (groupMode.value === 'vendor') {
    const vendor = identifyVendor(req.model)
    const topVendors = vendorStats.value.slice(0, TOP_N).map(([v]) => v)
    return topVendors.includes(vendor) ? vendor : OTHER_VENDOR
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

// 按泳道分组请求，支持去重和自动移动到末尾
// 优化版：使用 Map 提升性能，从 O(n²) 降至 O(n)
const laneRequests = computed(() => {
  const grouped = new Map<string, LiveRequest[]>()

  // 初始化所有泳道
  for (const lane of lanes.value) {
    grouped.set(lane.key, [])
  }

  // 优化的去重逻辑：使用 Map 跟踪每个 request_id 的最新版本
  const latestRequestMap = new Map<string, LiveRequest>()
  const idleMarkers: LiveRequest[] = []
  
  // 第一遍：找到每个 request_id 的最新版本
  for (const req of requests.value) {
    if (req.type === 'request' && req.request_id) {
      // 同一个 request_id 只保留最后一次出现（自动去重）
      latestRequestMap.set(req.request_id, req)
    } else if (req.type === 'idle_marker') {
      idleMarkers.push(req)
    }
  }
  
  // 第二遍：将最新版本的请求分配到对应泳道
  for (const req of latestRequestMap.values()) {
    const laneKey = getLaneKey(req)
    const lane = grouped.get(laneKey)
    if (lane) {
      lane.push(req)
    }
  }
  
  // idle_marker 分配到 Other 泳道
  for (const req of idleMarkers) {
    const lane = grouped.get(OTHER_VENDOR)
    if (lane) lane.push(req)
  }

  return grouped
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

onMounted(() => {
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
})

// 当分组模式切换时，立即重新排序
watch(groupMode, () => {
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
    <div class="live-stream-lanes__container">
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

/* 泳道滑入动画 */
.lane-slide-enter-active {
  transition:
    transform 0.4s cubic-bezier(0.18, 1.25, 0.32, 1.0),
    opacity 0.3s ease;
}

.lane-slide-enter-from {
  opacity: 0;
  transform: translateX(30px);
}

.lane-slide-leave-active {
  transition: transform 0.25s ease, opacity 0.25s ease;
  position: absolute;
}

.lane-slide-leave-to {
  opacity: 0;
  transform: translateX(-15px);
}
</style>