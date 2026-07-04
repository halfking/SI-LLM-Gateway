<script setup lang="ts">
// LiveRequestBlock — single tile in the swim lane.
//
// 2026-07-03 v5: 4-row layout (time / model / provider / latency).
//
//   ┌──────────┐
//   │ 14:35    │  ← line 1: HH:MM start time              (9px)
//   │  GPT     │  ← line 2: model-family code           (11px, bold)
//   │  ANTH   │  ← line 3: provider code (NEW)         ( 8px, muted)
//   │ 1.2s     │  ← line 4: latency                     (9px, monospace)
//   └══════════┘
//     ↑ 2-3px border: coloured by STATUS (green/amber/red), NOT
//       family. The body bg is the FAMILY colour at ~22% alpha so
//       a wall of GPT tiles reads as "blue band" while the status
//       border sits clearly on top.
//
// Why a 4-row layout: the operator needs to see WHICH MODEL on
// which VENDOR is taking the load. The model line is the dominant
// signal (largest, boldest); the provider line is secondary
// (smaller, muted). A failure does NOT replace the model line —
// the failure is encoded in the border colour + a corner badge.
//
// Tile is 60px wide × 76px tall. 4 rows of ~14px line-height + 2px
// padding × 2 (top/bottom) + 4px gap between rows = 76px. The
// narrow width keeps the swim lane in one viewport without
// horizontal scroll.
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import type { LiveRequest } from '../composables/useLiveStream'
import { modelShortLabel, providerShortLabel } from '../composables/liveStreamDisplay'
import {
  getModelCategoryColor,
  STATUS_BORDER_COLORS,
  STATUS_BORDER_WIDTHS,
} from '../composables/liveStreamColors'

const props = defineProps<{
  request: LiveRequest
  /** 分组模式：vendor=原厂, provider=供应商, model=模型 */
  groupMode?: 'vendor' | 'provider' | 'model'
  /** 是否高亮显示（当图例被选中时） */
  highlight?: boolean
}>()

const emit = defineEmits<{
  /** Fired when the user clicks a real (non-idle) tile. */
  select: [requestId: string]
}>()

const { locale } = useI18n()

const isIdle = computed(() => props.request.type === 'idle_marker')

const idleLabel = computed(() => {
  if (!isIdle.value) return ''
  const start = Date.parse(props.request.ts)
  if (Number.isNaN(start)) return '—'
  const minutes = Math.max(1, Math.round((Date.now() - start) / 60_000))
  return `空闲 ${minutes}m`
})

// Line 1: HH:MM start time (locale-aware).
const timeLabel = computed(() => {
  if (!props.request.ts) return '--:--'
  const d = new Date(props.request.ts)
  if (Number.isNaN(d.getTime())) return '--:--'
  try {
    return d.toLocaleTimeString(locale.value, { hour: '2-digit', minute: '2-digit', hour12: false })
  } catch {
    return '--:--'
  }
})

// Line 2: model-family code (always the family, even on failure).
const vendorLabel = computed(() => modelShortLabel(props.request.model))

// Line 3: provider code. Smaller font + lower contrast — secondary
// signal, but critical when an incident is on a specific vendor.
const providerLabel = computed(() => providerShortLabel(props.request.provider_code))

// 获取模型家族名称（用于供应商模式第3行）
function getModelFamily(model: string | undefined): string {
  if (!model) return '???'
  const m = model.toLowerCase()
  if (m.startsWith('gpt-') || m.startsWith('o1-') || m.startsWith('o3-') || m.startsWith('o4-')) return 'OpenAI'
  if (m.startsWith('claude-')) return 'Anthropic'
  if (m.startsWith('gemini') || m.startsWith('palm')) return 'Google'
  if (m.startsWith('llama')) return 'Meta'
  if (m.startsWith('qwen')) return 'Alibaba'
  if (m.startsWith('deepseek')) return 'DeepSeek'
  if (m.startsWith('glm')) return 'Zhipu'
  if (m.startsWith('mistral') || m.startsWith('mixtral')) return 'Mistral'
  if (m.startsWith('grok')) return 'xAI'
  return '其他'
}

// 获取状态文本（用于模型模式第2行）
function getStatusText(): string {
  const status = props.request.status
  if (status === 'success') return '成功'
  if (status === 'in_progress') return '进行中'
  if (status === 'failure') {
    const k = (props.request.error_kind || '').toLowerCase()
    if (/(timeout|timedout)/.test(k)) return '超时'
    if (/(5xx|server|upstream)/.test(k)) return '5xx'
    if (/(4xx|auth|quota)/.test(k)) return '认证'
    if (/(not_found|route)/.test(k)) return '未找到'
    return '失败'
  }
  return '—'
}

// 第2行动态内容：根据分组模式决定
const line2Label = computed(() => {
  const mode = props.groupMode || 'vendor'
  if (mode === 'model') {
    // 模型模式：显示状态或错误信息
    return getStatusText()
  }
  // 原厂/供应商模式：显示模型名称
  return vendorLabel.value
})

// 第3行动态内容：根据分组模式决定
const line3Label = computed(() => {
  const mode = props.groupMode || 'vendor'
  if (mode === 'vendor') {
    // 原厂模式：显示供应商名称
    return providerLabel.value
  } else if (mode === 'provider') {
    // 供应商模式：显示模型家族名称
    return getModelFamily(props.request.model)
  } else {
    // 模型模式：显示供应商名称
    return providerLabel.value
  }
})

// 第2行字体大小：根据内容长度动态调整（需求：尽可能显示完整名称）
const line2FontSize = computed(() => {
  const len = line2Label.value.length
  const mode = props.groupMode || 'vendor'
  
  // 模型模式的状态文本较短，使用固定字体
  if (mode === 'model') {
    return '10px'
  }
  
  // 原厂/供应商模式：根据模型名称长度动态调整
  if (len <= 6) return '11px'
  if (len <= 8) return '10px'
  if (len <= 10) return '9px'
  if (len <= 12) return '8px'
  return '7px'
})

// Line 4: latency OR error message (for failures).
const latencyText = computed(() => {
  if (props.request.status === 'in_progress') return '…'
  const ms = props.request.latency_ms
  if (ms == null) return '—'
  if (ms < 0) return '—'
  if (ms < 1000) return `${Math.round(ms)}ms`
  if (ms < 10_000) return `${(ms / 1000).toFixed(1)}s`
  return `${Math.round(ms / 1000)}s`
})

/**
 * When status=failure, show a brief error message on line 4 instead
 * of latency. The operator scans the swim lane looking for red tiles
 * with readable error labels (e.g. "Timeout", "5xx", "Auth").
 */
const line4Text = computed(() => {
  if (props.request.status !== 'failure' || !props.request.error_kind) {
    return latencyText.value
  }
  const k = props.request.error_kind.toLowerCase()
  if (/(timeout|timedout)/.test(k)) return 'Timeout'
  if (/(5xx|server|upstream|provider|overloaded|backend)/.test(k)) return '5xx'
  if (/(4xx|auth|unauthor|forbidden|quota|rate|billing|payment)/.test(k)) return 'Auth'
  if (/(not_found|model_not|route|no_route|resolve|policy)/.test(k)) return 'NotFound'
  // Fallback: show first 8 chars of error_kind
  return props.request.error_kind.slice(0, 8)
})

/**
 * Dynamic width based on content length. 
 * 需求：泳道宽度80px（但tile需要适应内容）
 */
const tileWidth = computed(() => {
  const line2Len = line2Label.value.length
  const line3Len = line3Label.value.length
  const maxLen = Math.max(line2Len, line3Len)
  // 基础宽度 80px
  const base = 80
  // 内容较长时适当增加宽度
  if (maxLen > 12) return Math.min(90, base + 10)
  return base
})

/**
 * Background colour: family colour at ~22% alpha. The status
 * border (set via :style below) provides the primary visual
 * signal; the family bg just helps the eye group similar tiles.
 */
const familyBg = computed(() => {
  const c = getModelCategoryColor(props.request.model_category)
  return hexToRgba(c, 0.22)
})

const statusBorder = computed(() =>
  STATUS_BORDER_COLORS[props.request.status ?? 'in_progress'] ||
  STATUS_BORDER_COLORS.in_progress,
)

const statusBorderWidth = computed(() =>
  STATUS_BORDER_WIDTHS[props.request.status ?? 'in_progress'] ||
  STATUS_BORDER_WIDTHS.in_progress,
)

const isPulsing = computed(() => props.request.status === 'in_progress')

/**
 * Multi-line native tooltip. Native `title` is chosen over a custom
 * popover because the swim lane lives inside an overflow:hidden
 * track — a popover would clip at the right viewport edge — and
 * because screen readers already announce native title.
 */
const tooltip = computed(() => {
  const r = props.request
  const lines: string[] = []
  if (r.model) lines.push(`Model: ${r.model}`)
  if (r.provider_code) lines.push(`Provider: ${r.provider_code}`)
  lines.push(`Status: ${r.status ?? '?'}`)
  if (r.error_kind) lines.push(`Error: ${r.error_kind}`)
  if (r.latency_ms != null) lines.push(`Latency: ${latencyText.value}`)
  if (r.total_tokens != null) {
    lines.push(`Tokens: ${r.total_tokens}`)
  } else if (r.prompt_tokens != null || r.completion_tokens != null) {
    const p = r.prompt_tokens ?? 0
    const c = r.completion_tokens ?? 0
    lines.push(`Tokens: ${p}+${c}`)
  }
  if (r.cost_usd != null) lines.push(`Cost: $${r.cost_usd.toFixed(4)}`)
  if (r.request_id) lines.push(`ID: ${r.request_id.slice(0, 8)}`)
  try {
    lines.push(`Time: ${new Date(r.ts).toLocaleString(locale.value)}`)
  } catch {
    /* ignore */
  }
  return lines.join('\n')
})

/**
 * Tiny error badge — top-right corner. Single-char glyph for
 * failure type so the operator can tell "this was a timeout" vs
 * "5xx" without opening the tooltip.
 */
const errorBadge = computed(() => {
  if (props.request.status !== 'failure' || !props.request.error_kind) return ''
  const k = props.request.error_kind.toLowerCase()
  if (/(timeout|timedout)/.test(k)) return 'T'
  if (/(5xx|server|upstream|provider|overloaded|backend)/.test(k)) return '!'
  if (/(4xx|auth|unauthor|forbidden|quota|rate|billing|payment)/.test(k)) return 'X'
  if (/(not_found|model_not|route|no_route|resolve|policy)/.test(k)) return '?'
  return '!'
})

function onClick() {
  if (!isIdle.value && props.request.request_id) {
    emit('select', props.request.request_id)
  }
}

/**
 * Tiny hex → rgba converter so the family colour can sit at low
 * alpha over the dark card.
 */
function hexToRgba(hex: string, alpha: number): string {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim())
  if (!m) return `rgba(139, 148, 158, ${alpha})`
  const n = parseInt(m[1], 16)
  const r = (n >> 16) & 0xff
  const g = (n >> 8) & 0xff
  const b = n & 0xff
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}
</script>

<template>
  <!-- Idle marker: wide dashed pill so 1 minute of silence still
       reads as "gap" rather than as a request. -->
  <div
    v-if="isIdle"
    class="live-block live-block--idle"
    :title="idleLabel"
    aria-hidden="true"
  >
    <span class="live-block__idle-text">{{ idleLabel }}</span>
  </div>

  <!-- Real tile: 4 lines + status border + family background. -->
  <div
    v-else
    class="live-block"
    :class="{
      'live-block--clickable': !!request.request_id,
      'live-block--in-progress': isPulsing,
      'live-block--failure': request.status === 'failure',
      'live-block--highlight': highlight,
    }"
    role="button"
    tabindex="0"
    :aria-label="tooltip"
    :title="tooltip"
    :style="{
      background: familyBg,
      borderColor: statusBorder,
      borderWidth: statusBorderWidth + 'px',
      width: tileWidth + 'px',
    }"
    @click="onClick"
    @keyup.enter="onClick"
    @keyup.space.prevent="onClick"
  >
    <span class="live-block__time">{{ timeLabel }}</span>
    <span class="live-block__line2" :style="{ fontSize: line2FontSize }">{{ line2Label }}</span>
    <span class="live-block__line3">{{ line3Label }}</span>
    <span 
      class="live-block__latency"
      :class="{ 'live-block__latency--error': request.status === 'failure' }"
    >{{ line4Text }}</span>
    <span
      v-if="errorBadge"
      class="live-block__error-badge"
      :title="request.error_kind || ''"
      aria-hidden="true"
    >{{ errorBadge }}</span>
  </div>
</template>

<style scoped>
/* 2026-07-05 v6 — 4-row tile (80px × 60px, 紧凑布局).
 * 支持三种分组模式的动态显示
 *
 *   width  80px     ← 固定宽度（需求要求）
 *   height 60px     ← 固定高度（需求要求）
 *   border 2px      ← 边框宽度（需求要求）
 *   font   动态     ← 第2行根据内容长度动态调整
 */
.live-block {
  box-sizing: border-box;
  width: 80px;
  min-width: 80px;
  max-width: 90px;
  height: 60px;
  border-radius: 4px;
  border: 2px solid rgba(139, 148, 158, 0.4);
  color: var(--text, #e6edf3);
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: space-around;
  padding: 2px;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans SC', 'Microsoft YaHei', sans-serif;
  position: relative;
  transition: transform 0.15s ease, box-shadow 0.15s ease, border-color 0.15s ease;
}

.live-block--clickable {
  cursor: pointer;
}
.live-block--clickable:hover,
.live-block--clickable:focus-visible {
  transform: translateY(-2px) scale(1.1);
  z-index: 2;
  box-shadow: 0 4px 14px rgba(99, 102, 241, 0.45);
  outline: none;
}

/* In-flight pulses the border colour so the eye catches it even
 * when scanning a wall of tiles. */
.live-block--in-progress {
  animation: live-block-pulse 1.4s ease-in-out infinite;
}
@keyframes live-block-pulse {
  0%, 100% { box-shadow: 0 0 0 0 rgba(245, 158, 11, 0.0); }
  50%      { box-shadow: 0 0 0 4px rgba(245, 158, 11, 0.25); }
}

/* Failure: an extra slight scale-up hint + a subtle red glow. */
.live-block--failure {
  box-shadow: 0 0 0 1px rgba(239, 68, 68, 0.4) inset;
}

/* Highlight: 图例选中时的高亮效果 */
.live-block--highlight {
  transform: scale(1.1);
  z-index: 10;
  box-shadow: 0 0 12px 2px rgba(99, 102, 241, 0.6);
  animation: live-block-highlight-pulse 1.5s ease-in-out infinite;
}

@keyframes live-block-highlight-pulse {
  0%, 100% { box-shadow: 0 0 12px 2px rgba(99, 102, 241, 0.6); }
  50%      { box-shadow: 0 0 18px 4px rgba(99, 102, 241, 0.8); }
}

/* Line 1: time HH:MM (居中对齐). */
.live-block__time {
  font-size: 8px;
  line-height: 1.1;
  color: var(--muted, #8b949e);
  letter-spacing: 0.2px;
  font-family: ui-monospace, SFMono-Regular, Menlo, 'Cascadia Code', monospace;
  text-align: center;
}

/* Line 2: 动态内容（模型名或状态），居中显示，字体大小动态调整 */
.live-block__line2 {
  font-size: 11px; /* fallback, 由 :style 覆盖 */
  font-weight: 700;
  line-height: 1.1;
  letter-spacing: 0.2px;
  color: var(--text, #e6edf3);
  max-width: 100%;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.5);
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans SC', 'Microsoft YaHei', sans-serif;
  text-align: center;
  padding: 0 2px;
}

/* Line 3: 动态内容（供应商或模型家族），居中显示 */
.live-block__line3 {
  font-size: 7px;
  line-height: 1.1;
  font-weight: 600;
  letter-spacing: 0.1px;
  color: var(--muted, #8b949e);
  max-width: 100%;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  opacity: 0.9;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans SC', 'Microsoft YaHei', sans-serif;
  text-align: center;
  padding: 0 2px;
}

/* Line 4: latency (xxxs 或 xxxms 两种形式). */
.live-block__latency {
  font-size: 8px;
  line-height: 1.1;
  font-weight: 500;
  font-variant-numeric: tabular-nums;
  color: var(--muted, #8b949e);
  letter-spacing: 0.2px;
  font-family: ui-monospace, SFMono-Regular, Menlo, 'Cascadia Code', monospace;
  text-align: center;
}

/* When status=failure, line 4 shows the error kind in bright amber/red */
.live-block__latency--error {
  font-size: 7px;
  font-weight: 700;
  color: #fbbf24; /* amber-400 */
  letter-spacing: 0.3px;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans SC', 'Microsoft YaHei', sans-serif;
}

/* When the tile is a failure (red border), boost the error text
 * to full red so it's impossible to miss. */
.live-block--failure .live-block__latency--error {
  color: #ef4444; /* red-500 */
}

/* Error badge — top-right corner. */
.live-block__error-badge {
  position: absolute;
  top: 1px;
  right: 2px;
  width: 12px;
  height: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 9px;
  font-weight: 700;
  line-height: 1;
  color: #fff;
  background: rgba(239, 68, 68, 0.95);
  border-radius: 2px;
  pointer-events: none;
  text-shadow: none;
}

/* Idle marker: 3x wider so a silence reads as a distinct shape. */
.live-block--idle {
  width: 110px;
  height: 60px;
  border: 2px dashed var(--border, #30363d);
  background: transparent;
  color: var(--muted, #8b949e);
  cursor: default;
  /* Override the 4-row vertical layout — idle is single-line. */
  justify-content: center;
}
.live-block__idle-text {
  font-size: 10px;
  font-weight: 500;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans SC', 'Microsoft YaHei', sans-serif;
}
</style>