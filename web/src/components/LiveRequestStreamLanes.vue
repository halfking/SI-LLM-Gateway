<script setup lang="ts">
/**
 * LiveRequestStreamLanes — 泳道式实时请求流
 *
 * 支持两种分组模式：
 * 1. 按模型原厂分组（Top 4 热门原厂 + 其他）— 动态计算
 * 2. 按供应商分组（Top 4 热门供应商 + 其他）— 按用量排序
 *
 * 2026-07-04 revision: 移除"国内/domestic"分类，改为按模型原厂
 * (vendor/manufacturer) 进行分组。面向国际市场，不强调地域。
 */
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { useLiveStream, type LiveRequest } from '../composables/useLiveStream'
import LiveRequestBlock from './LiveRequestBlock.vue'

const emit = defineEmits<{
  openDetail: [requestId: string]
}>()

const { t } = useI18n()
const { requests, connection, paused, togglePause } = useLiveStream()

type GroupMode = 'vendor' | 'provider'
const groupMode = ref<GroupMode>('vendor')

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

// 计算原厂统计，按用量降序排列，取 Top 4
const vendorStats = computed(() => {
  const stats = new Map<string, number>()
  for (const req of requests.value) {
    if (req.type !== 'request') continue
    const vendor = identifyVendor(req.model)
    stats.set(vendor, (stats.get(vendor) || 0) + 1)
  }
  return Array.from(stats.entries())
    .sort((a, b) => b[1] - a[1])
})

// 计算供应商统计，按用量降序排列，取 Top 4
const providerStats = computed(() => {
  const stats = new Map<string, number>()
  for (const req of requests.value) {
    if (req.type === 'request' && req.provider_code) {
      stats.set(req.provider_code, (stats.get(req.provider_code) || 0) + 1)
    }
  }
  return Array.from(stats.entries())
    .sort((a, b) => b[1] - a[1])
})

// 颜色池（用于 Top 4 之外的供应商）
const VENDOR_COLORS = ['#10a37f', '#3b82f6', '#f59e0b', '#8b5cf6', '#ec4899', '#14b8a6', '#f43f5e', '#84cc16']

// 动态泳道配置：Top 4 热门原厂/供应商 + Other
const lanes = computed(() => {
  if (groupMode.value === 'vendor') {
    const topVendors = vendorStats.value.slice(0, 4).map(([vendor]) => vendor)
    return [
      ...topVendors.map((vendor, idx) => {
        const preset = VENDOR_PATTERNS.find((v) => v.vendor === vendor)
        return {
          key: vendor,
          label: vendor,
          color: preset?.color || VENDOR_COLORS[idx] || '#6b7280',
        }
      }),
      { key: OTHER_VENDOR, label: t('dashboard.liveStream.other'), color: '#6b7280' },
    ]
  } else {
    // 供应商模式：按用量排序的 Top 4 + Other
    const topProviders = providerStats.value.slice(0, 4).map(([code]) => code)
    return [
      ...topProviders.map((code, idx) => ({
        key: code,
        label: code,
        color: VENDOR_COLORS[idx] || '#6b7280',
      })),
      { key: OTHER_VENDOR, label: t('dashboard.liveStream.other'), color: '#6b7280' },
    ]
  }
})

// 将请求分配到对应泳道
function getLaneKey(req: LiveRequest): string {
  if (req.type === 'idle_marker') return OTHER_VENDOR

  if (groupMode.value === 'vendor') {
    const vendor = identifyVendor(req.model)
    // 只在 Top 4 中的原厂单独显示，其余归入 Other
    const topVendors = vendorStats.value.slice(0, 4).map(([v]) => v)
    return topVendors.includes(vendor) ? vendor : OTHER_VENDOR
  } else {
    if (!req.provider_code) return OTHER_VENDOR
    const topProviders = providerStats.value.slice(0, 4).map(([c]) => c)
    return topProviders.includes(req.provider_code) ? req.provider_code : OTHER_VENDOR
  }
}

// 按泳道分组请求
const laneRequests = computed(() => {
  const grouped = new Map<string, LiveRequest[]>()

  // 初始化所有泳道
  for (const lane of lanes.value) {
    grouped.set(lane.key, [])
  }

  // 分配请求到泳道
  for (const req of requests.value) {
    const laneKey = getLaneKey(req)
    const lane = grouped.get(laneKey)
    if (lane) {
      lane.push(req)
    } else {
      const otherLane = grouped.get(OTHER_VENDOR)
      if (otherLane) otherLane.push(req)
    }
  }

  return grouped
})

// 每个泳道最多显示的请求数
const MAX_PER_LANE = 20

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
        <span
          class="live-stream-lanes__status"
          :class="{
            'live-stream-lanes__status--ok': connection === 'open',
            'live-stream-lanes__status--warn': connection !== 'open',
          }"
        >
          <span class="live-stream-lanes__dot" aria-hidden="true" />
          {{ connectionLabel }}
        </span>
        <button
          type="button"
          class="live-stream-lanes__btn"
          @click="togglePause"
        >
          {{ paused ? t('dashboard.liveStream.resume') : t('dashboard.liveStream.pause') }}
        </button>
        <select v-model="groupMode" class="live-stream-lanes__select">
          <option value="vendor">{{ t('dashboard.liveStream.groupByVendor') }}</option>
          <option value="provider">{{ t('dashboard.liveStream.groupByProvider') }}</option>
        </select>
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
          <span class="live-stream-lane__name">{{ lane.label }}</span>
          <span class="live-stream-lane__count">{{ laneRequests.get(lane.key)?.length || 0 }}</span>
        </div>

        <!-- 泳道轨道 -->
        <div class="live-stream-lane__track">
          <TransitionGroup name="lane-slide" tag="div" class="live-stream-lane__track-inner">
            <LiveRequestBlock
              v-for="(req, idx) in laneRequests.get(lane.key)?.slice(-MAX_PER_LANE) || []"
              :key="req.request_id ?? `idle-${lane.key}-${idx}-${req.ts}`"
              :request="req"
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
  flex-wrap: nowrap;        /* 强制不折行 */
  gap: 10px;
  margin-bottom: 12px;
  min-width: 0;             /* 允许子元素 shrink 到 0 */
}

.live-stream-lanes__title {
  font-size: 14px;
  font-weight: 600;
  margin: 0;
  color: var(--text, #e6edf3);
  flex-shrink: 0;           /* 标题不被压缩 */
  white-space: nowrap;
}

.live-stream-lanes__controls {
  display: flex;
  align-items: center;
  gap: 8px;
  flex: 1 1 auto;
  min-width: 0;             /* 允许子元素 shrink 到 0 */
  flex-wrap: nowrap;        /* 强制不折行 */
  justify-content: flex-end;
  overflow: hidden;
}

.live-stream-lanes__status {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: var(--muted, #8b949e);
  flex-shrink: 0;           /* 状态不被压缩 */
  white-space: nowrap;
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
  flex-shrink: 0;           /* 按钮不被压缩 */
  min-width: 64px;
}

.live-stream-lanes__btn:hover {
  background: var(--bg-subtle, #161b22);
  border-color: var(--accent, #6366f1);
}

.live-stream-lanes__select {
  font-size: 12px;
  padding: 4px 10px;
  border-radius: 4px;
  border: 1px solid var(--border, #30363d);
  background: var(--bg, #0f1117);
  color: var(--text, #e6edf3);
  cursor: pointer;
  flex-shrink: 0;           /* 下拉框不被压缩 */
  white-space: nowrap;
  min-width: 140px;         /* 给"按原厂/按供应商"一个最小显示宽度 */
}

.live-stream-lanes__select option {
  background: var(--card, #1c2128);
  color: var(--text, #e6edf3);
}

/* 泳道容器 */
.live-stream-lanes__container {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

/* 单个泳道 */
.live-stream-lane {
  display: flex;
  align-items: center;
  gap: 12px;
  min-height: 64px;
  flex-wrap: nowrap;        /* 泳道不折行 */
  min-width: 0;
}

/* 泳道标签 — 固定宽度，避免被挤压 */
.live-stream-lane__label {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 2px;
  width: 120px;             /* 固定宽度 */
  min-width: 120px;
  max-width: 120px;
  flex-shrink: 0;           /* 标签不被压缩 */
  padding-left: 8px;
  border-left: 3px solid var(--accent, #6366f1);
  overflow: hidden;         /* 隐藏溢出内容 */
}

.live-stream-lane__name {
  font-size: 13px;
  font-weight: 600;
  color: var(--text, #e6edf3);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;  /* 过长时省略号 */
  max-width: 100%;
  display: block;
}

.live-stream-lane__count {
  font-size: 11px;
  color: var(--muted, #8b949e);
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  white-space: nowrap;
}

/* 泳道轨道 */
.live-stream-lane__track {
  position: relative;
  flex: 1;
  height: 64px;
  overflow: hidden;
  background: var(--bg-subtle, #161b22);
  border: 1px solid var(--border, #30363d);
  border-radius: 6px;
  padding: 4px 6px;
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