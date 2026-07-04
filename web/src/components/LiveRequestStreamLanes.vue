<script setup lang="ts">
/**
 * LiveRequestStreamLanes — 泳道式实时请求流
 *
 * 2026-07-05 最终需求：
 * - 三维度分组：按原厂、按供应商、按模型
 * - 泳道自动创建 + 请求去重更新（移除旧位置 → 追加到末尾，带动画）
 * - 泳道排序：按请求次数倒序（requestAnimationFrame 节流）
 * - 累加统计：从开始显示时累积，不受缓冲区淘汰影响
 * - 每个泳道最多 30 条
 * - 动态字体大小（根据模型名长度）
 * - 三种模式下行2、行3内容自适应
 */
import { computed, ref, watch, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useLiveStream, type LiveRequest } from '../composables/useLiveStream'
import LiveRequestBlock from './LiveRequestBlock.vue'
import { isSuperAdmin } from '../store'

const emit = defineEmits<{
  openDetail: [requestId: string]
}>()

const { t } = useI18n()
const { requests, connection, paused, togglePause } = useLiveStream()

type GroupMode = 'vendor' | 'provider' | 'model'
const groupMode = ref<GroupMode>('vendor')

const MAX_PER_LANE = 30

// 累加统计（从开始显示时开始累积，不受缓冲区淘汰影响）
const totalRequestsSeen = ref(0)
const laneRequestCounts = ref<Map<string, number>>(new Map())
const seenRequestIds = new Set<string>()

// 模型名 → 原厂（vendor/manufacturer）
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

const VENDOR_COLORS = ['#10a37f', '#3b82f6', '#f59e0b', '#8b5cf6', '#ec4899', '#14b8a6', '#f43f5e', '#84cc16']
const OTHER_KEY = '__OTHER__'

/**
 * 从模型名识别原厂（带 LRU 缓存）
 */
const vendorCache = new Map<string, string>()
function identifyVendor(model: string | undefined): string {
  if (!model) return OTHER_KEY
  if (vendorCache.has(model)) return vendorCache.get(model)!
  
  for (const { vendor, patterns } of VENDOR_PATTERNS) {
    for (const p of patterns) {
      if (p.test(model)) {
        vendorCache.set(model, vendor)
        // LRU: 限制缓存大小
        if (vendorCache.size > 200) {
          const firstKey = vendorCache.keys().next().value
          vendorCache.delete(firstKey)
        }
        return vendor
      }
    }
  }
  vendorCache.set(model, OTHER_KEY)
  return OTHER_KEY
}

/**
 * 根据分组模式获取请求的泳道 key
 */
function getLaneKey(req: LiveRequest): string {
  if (req.type === 'idle_marker') return OTHER_KEY
  
  if (groupMode.value === 'vendor') {
    return identifyVendor(req.model)
  } else if (groupMode.value === 'provider') {
    return req.provider_code || OTHER_KEY
  } else {
    return req.model || OTHER_KEY
  }
}

/**
 * 泳道数据结构
 */
interface Lane {
  key: string
  label: string
  color: string
  count: number
  requests: LiveRequest[]
}

const lanes = ref<Lane[]>([])
let sortScheduled = false

/**
 * 核心逻辑：从缓冲区重建泳道 + 累加统计
 * - 自动创建泳道
 * - 请求去重：移除旧位置 → 追加到末尾（带动画）
 * - 每个泳道最多 30 条
 * - 累加统计不受缓冲区淘汰影响
 */
function rebuildLanes() {
  const laneMap = new Map<string, Lane>()
  
  // 遍历缓冲区，按泳道分组
  for (const req of requests.value) {
    const laneKey = getLaneKey(req)
    
    if (!laneMap.has(laneKey)) {
      // 自动创建泳道
      const label = laneKey === OTHER_KEY ? t('dashboard.liveStream.other') : laneKey
      const preset = VENDOR_PATTERNS.find(v => v.vendor === laneKey)
      const color = preset?.color || VENDOR_COLORS[laneMap.size % VENDOR_COLORS.length] || '#6b7280'
      
      laneMap.set(laneKey, {
        key: laneKey,
        label,
        color,
        count: laneRequestCounts.value.get(laneKey) || 0,
        requests: []
      })
    }
    
    const lane = laneMap.get(laneKey)!
    
    // 累加统计（只对新 request_id 计数）
    if (req.type === 'request' && req.request_id && !seenRequestIds.has(req.request_id)) {
      seenRequestIds.add(req.request_id)
      totalRequestsSeen.value++
      const currentCount = laneRequestCounts.value.get(laneKey) || 0
      laneRequestCounts.value.set(laneKey, currentCount + 1)
      lane.count = currentCount + 1
    }
    
    // 请求更新：移除旧位置 → 追加到末尾（Vue TransitionGroup 自动处理动画）
    if (req.type === 'request' && req.request_id) {
      const existingIdx = lane.requests.findIndex(r => r.request_id === req.request_id)
      if (existingIdx >= 0) {
        // 移除旧位置
        lane.requests.splice(existingIdx, 1)
      }
      // 追加到末尾
      lane.requests.push(req)
    } else {
      // idle_marker 直接追加
      lane.requests.push(req)
    }
    
    // 每个泳道最多 30 条
    if (lane.requests.length > MAX_PER_LANE) {
      lane.requests = lane.requests.slice(-MAX_PER_LANE)
    }
  }
  
  // 转换为数组
  lanes.value = Array.from(laneMap.values())
  
  // 调度排序（节流）
  scheduleSortLanes()
}

/**
 * 泳道排序：按请求次数倒序
 * 使用 requestAnimationFrame 节流，避免闪烁
 */
function scheduleSortLanes() {
  if (sortScheduled) return
  sortScheduled = true
  
  requestAnimationFrame(() => {
    lanes.value.sort((a, b) => {
      // Other 泳道始终在最后
      if (a.key === OTHER_KEY) return 1
      if (b.key === OTHER_KEY) return -1
      // 按请求次数倒序
      return b.count - a.count
    })
    sortScheduled = false
  })
}

// 监听缓冲区变化，重建泳道
watch(requests, rebuildLanes, { deep: true })
watch(groupMode, rebuildLanes)

// 初始化
onMounted(rebuildLanes)

// 连接状态显示
const connectionLabel = computed(() => {
  if (connection.value === 'open') return t('dashboard.liveStream.connected')
  return t('dashboard.liveStream.disconnected')
})

// 缓冲区统计
const bufferCount = computed(() => requests.value.filter(r => r.type === 'request').length)
const visibleCount = computed(() => {
  let total = 0
  for (const lane of lanes.value) {
    total += lane.requests.filter(r => r.type === 'request').length
  }
  return total
})

// WebSocket 地址（仅管理员可见）
const showWsUrl = ref(false)
const wsUrl = computed(() => {
  if (!isSuperAdmin.value) return null
  const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:'
  return `${protocol}//${location.host}/admin/live`
})

function toggleWsUrl() {
  if (!isSuperAdmin.value) return
  showWsUrl.value = !showWsUrl.value
}

function onSelect(requestId: string) {
  emit('openDetail', requestId)
}

// 图例数据
const familyLegend = [
  { name: 'OpenAI', color: 'rgba(16, 163, 127, 0.15)' },
  { name: 'Anthropic', color: 'rgba(217, 119, 87, 0.15)' },
  { name: 'Google', color: 'rgba(66, 133, 244, 0.15)' },
  { name: 'Alibaba', color: 'rgba(255, 106, 0, 0.15)' },
  { name: 'DeepSeek', color: 'rgba(77, 107, 254, 0.15)' },
  { name: 'Meta', color: 'rgba(6, 104, 225, 0.15)' },
  { name: '其他', color: 'rgba(107, 114, 128, 0.1)' },
]

const statusLegend = [
  { name: '成功', color: '#3fb950' },
  { name: '进行中', color: '#d29922' },
  { name: '5xx', color: '#ef4444' },
  { name: '4xx', color: '#f97316' },
  { name: '超时', color: '#a855f7' },
  { name: '其他', color: '#dc2626' },
]
</script>

<template>
  <div class="live-stream-lanes">
    <!-- 标题栏 -->
    <div class="live-stream-lanes__header">
      <h3 class="live-stream-lanes__title">{{ t('dashboard.liveStream.title') }}</h3>
      
      <div class="live-stream-lanes__controls">
        <!-- 分组按钮组 -->
        <div class="btn-group">
          <button
            type="button"
            class="btn-group__btn"
            :class="{ 'btn-group__btn--active': groupMode === 'vendor' }"
            @click="groupMode = 'vendor'"
          >
            {{ t('dashboard.liveStream.groupByVendor') }}
          </button>
          <button
            type="button"
            class="btn-group__btn"
            :class="{ 'btn-group__btn--active': groupMode === 'provider' }"
            @click="groupMode = 'provider'"
          >
            {{ t('dashboard.liveStream.groupByProvider') }}
          </button>
          <button
            type="button"
            class="btn-group__btn"
            :class="{ 'btn-group__btn--active': groupMode === 'model' }"
            @click="groupMode = 'model'"
          >
            {{ t('dashboard.liveStream.groupByModel') }}
          </button>
        </div>
        
        <!-- 连接状态 -->
        <span
          class="live-stream-lanes__status"
          :class="{
            'live-stream-lanes__status--ok': connection === 'open',
            'live-stream-lanes__status--warn': connection !== 'open',
          }"
          :title="isSuperAdmin ? 'Click to view WebSocket URL' : ''"
          @click="toggleWsUrl"
        >
          <span class="live-stream-lanes__dot" aria-hidden="true" />
          {{ connectionLabel }}
        </span>
        
        <!-- 暂停按钮 -->
        <button
          type="button"
          class="live-stream-lanes__btn"
          @click="togglePause"
        >
          {{ paused ? t('dashboard.liveStream.resume') : t('dashboard.liveStream.pause') }}
        </button>
        
        <!-- 计数 -->
        <span class="live-stream-lanes__count">
          {{ bufferCount }}(缓存) / {{ visibleCount }}(窗口)
        </span>
      </div>
    </div>
    
    <!-- WebSocket URL（仅管理员） -->
    <div v-if="showWsUrl && wsUrl" class="live-stream-lanes__ws-url">
      <code>{{ wsUrl }}</code>
      <button type="button" class="live-stream-lanes__btn-copy" @click="navigator.clipboard.writeText(wsUrl)">
        Copy
      </button>
    </div>

    <!-- 图例行 -->
    <div class="live-stream-lanes__legend">
      <!-- 左侧：模型家族背景色图例 -->
      <div class="legend-group">
        <span class="legend-title">背景色:</span>
        <div class="legend-items">
          <div v-for="item in familyLegend" :key="item.name" class="legend-item">
            <span class="legend-box" :style="{ background: item.color }" />
            <span class="legend-label">{{ item.name }}</span>
          </div>
        </div>
      </div>
      
      <!-- 右侧：边框颜色图例 -->
      <div class="legend-group">
        <span class="legend-title">边框色:</span>
        <div class="legend-items">
          <div v-for="item in statusLegend" :key="item.name" class="legend-item">
            <span class="legend-box" :style="{ border: `2px solid ${item.color}`, background: 'transparent' }" />
            <span class="legend-label">{{ item.name }}</span>
          </div>
        </div>
      </div>
    </div>

    <!-- 泳道容器 -->
    <div class="live-stream-lanes__container">
      <div
        v-for="lane in lanes"
        :key="lane.key"
        class="live-stream-lane"
      >
        <!-- 泳道标签 -->
        <div class="live-stream-lane__label" :style="{ borderLeftColor: lane.color }">
          <span class="live-stream-lane__name" :title="lane.label">{{ lane.label }}</span>
          <span class="live-stream-lane__count">({{ lane.count }})</span>
        </div>

        <!-- 泳道轨道 -->
        <div class="live-stream-lane__track">
          <TransitionGroup name="lane-slide" tag="div" class="live-stream-lane__track-inner">
            <LiveRequestBlock
              v-for="(req, idx) in lane.requests"
              :key="req.request_id ?? `${lane.key}-${idx}-${req.ts}`"
              :request="req"
              :group-mode="groupMode"
              @select="onSelect"
            />
          </TransitionGroup>
          <div
            v-if="lane.requests.length === 0"
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
  padding: 10px 14px;
  margin-bottom: 20px;
}

/* ====== Header：紧凑布局，不折行 ====== */
.live-stream-lanes__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: nowrap;
  gap: 10px;
  margin-bottom: 10px;
  min-width: 0;
}

.live-stream-lanes__title {
  font-size: 13px;
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

/* 分组按钮组 */
.btn-group {
  display: inline-flex;
  border: 1px solid var(--border, #30363d);
  border-radius: 4px;
  overflow: hidden;
  flex-shrink: 0;
}

.btn-group__btn {
  font-size: 11px;
  padding: 3px 8px;
  border: none;
  background: var(--bg, #0f1117);
  color: var(--muted, #8b949e);
  cursor: pointer;
  white-space: nowrap;
  transition: all 0.15s;
  border-right: 1px solid var(--border, #30363d);
}

.btn-group__btn:last-child {
  border-right: none;
}

.btn-group__btn:hover {
  background: var(--bg-subtle, #161b22);
  color: var(--text, #e6edf3);
}

.btn-group__btn--active {
  background: var(--accent, #6366f1);
  color: #fff;
  font-weight: 600;
}

/* 连接状态 */
.live-stream-lanes__status {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 11px;
  color: var(--muted, #8b949e);
  flex-shrink: 0;
  white-space: nowrap;
  cursor: pointer;
}

.live-stream-lanes__dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--muted, #8b949e);
  flex-shrink: 0;
}

.live-stream-lanes__status--ok .live-stream-lanes__dot {
  background: var(--success, #3fb950);
  box-shadow: 0 0 0 2px rgba(63, 185, 80, 0.18);
}

.live-stream-lanes__status--warn .live-stream-lanes__dot {
  background: var(--warning, #d29922);
  animation: lane-dot-pulse 1.4s ease-in-out infinite;
}

@keyframes lane-dot-pulse {
  0%, 100% { opacity: 1; }
  50%      { opacity: 0.4; }
}

/* 按钮 */
.live-stream-lanes__btn {
  font-size: 11px;
  padding: 3px 10px;
  border-radius: 4px;
  border: 1px solid var(--border, #30363d);
  background: var(--bg, #0f1117);
  color: var(--text, #e6edf3);
  cursor: pointer;
  white-space: nowrap;
  flex-shrink: 0;
  transition: all 0.15s;
}

.live-stream-lanes__btn:hover {
  background: var(--bg-subtle, #161b22);
  border-color: var(--accent, #6366f1);
}

/* 计数 */
.live-stream-lanes__count {
  font-size: 11px;
  color: var(--muted, #8b949e);
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  flex-shrink: 0;
  white-space: nowrap;
}

/* WebSocket URL */
.live-stream-lanes__ws-url {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 10px;
  background: var(--bg-subtle, #161b22);
  border: 1px solid var(--border, #30363d);
  border-radius: 4px;
  margin-bottom: 8px;
  font-size: 11px;
}

.live-stream-lanes__ws-url code {
  flex: 1;
  color: var(--text, #e6edf3);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.live-stream-lanes__btn-copy {
  font-size: 10px;
  padding: 2px 8px;
  border-radius: 3px;
  border: 1px solid var(--border, #30363d);
  background: var(--bg, #0f1117);
  color: var(--text, #e6edf3);
  cursor: pointer;
  white-space: nowrap;
  flex-shrink: 0;
}

/* 图例行 */
.live-stream-lanes__legend {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 6px 10px;
  background: var(--bg-subtle, #161b22);
  border: 1px solid var(--border, #30363d);
  border-radius: 4px;
  margin-bottom: 10px;
  font-size: 10px;
  flex-wrap: wrap;
}

.legend-group {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
}

.legend-title {
  font-weight: 600;
  color: var(--muted, #8b949e);
  white-space: nowrap;
  margin-right: 4px;
}

.legend-items {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}

.legend-item {
  display: flex;
  align-items: center;
  gap: 3px;
}

.legend-box {
  width: 14px;
  height: 14px;
  border-radius: 2px;
  flex-shrink: 0;
}

.legend-label {
  font-size: 9px;
  color: var(--text, #e6edf3);
  white-space: nowrap;
}

/* 泳道容器 */
.live-stream-lanes__container {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

/* 单个泳道 */
.live-stream-lane {
  display: flex;
  align-items: center;
  gap: 10px;
  min-height: 60px;
  flex-wrap: nowrap;
  min-width: 0;
}

/* 泳道标签 */
.live-stream-lane__label {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 2px;
  width: 80px;
  min-width: 80px;
  max-width: 80px;
  flex-shrink: 0;
  padding-left: 6px;
  border-left: 3px solid var(--accent, #6366f1);
  overflow: hidden;
}

.live-stream-lane__name {
  font-size: 11px;
  font-weight: 600;
  color: var(--text, #e6edf3);
  text-align: right;
  word-wrap: break-word;
  overflow-wrap: break-word;
  max-width: 100%;
  line-height: 1.2;
  display: block;
}

.live-stream-lane__count {
  font-size: 10px;
  color: var(--muted, #8b949e);
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  white-space: nowrap;
}

/* 泳道轨道 */
.live-stream-lane__track {
  position: relative;
  flex: 1;
  height: 60px;
  overflow: hidden;
  background: var(--bg-subtle, #161b22);
  border: 1px solid var(--border, #30363d);
  border-radius: 5px;
  padding: 3px 5px;
}

.live-stream-lane__track-inner {
  display: flex;
  align-items: center;
  gap: 3px;
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
  font-size: 11px;
  pointer-events: none;
}

/* 泳道滑入动画（高大上，但轻量）*/
.lane-slide-enter-active {
  transition:
    transform 0.4s cubic-bezier(0.34, 1.56, 0.64, 1),
    opacity 0.3s ease;
}

.lane-slide-enter-from {
  opacity: 0;
  transform: translateX(30px) scale(0.95);
}

.lane-slide-leave-active {
  transition: 
    transform 0.3s cubic-bezier(0.4, 0, 1, 1),
    opacity 0.3s ease;
  position: absolute;
}

.lane-slide-leave-to {
  opacity: 0;
  transform: translateX(-20px) scale(0.9);
}

/* 移动动画（更新时移除旧位置 → 追加到末尾）*/
.lane-slide-move {
  transition: transform 0.4s cubic-bezier(0.25, 0.8, 0.25, 1);
}
</style>
