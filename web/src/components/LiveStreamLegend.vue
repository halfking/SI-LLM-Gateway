<script setup lang="ts">
/**
 * LiveStreamLegend — 动态图例，支持选中/反选高亮
 *
 * 2026-07-05 重构：
 * - 左侧：根据分组模式显示Top5（原厂/供应商/模型）+ 其它
 * - 右侧：详细状态（成功/进行中/失败细分）
 * - 支持点击选中/反选，高亮对应tile
 */
import { computed, ref } from 'vue'

type GroupMode = 'vendor' | 'provider' | 'model'

interface LegendItem {
  key: string
  label: string
  color: string
}

const props = defineProps<{
  /** 分组模式 */
  groupMode: GroupMode
  /** 分组维度的统计数据（Top5 + Other） */
  groupItems: LegendItem[]
}>()

const emit = defineEmits<{
  /** 图例项被选中/反选 */
  toggleSelection: [type: 'group' | 'status', key: string]
}>()

// 选中的分组项（原厂/供应商/模型）
const selectedGroups = ref<Set<string>>(new Set())

// 选中的状态项
const selectedStatuses = ref<Set<string>>(new Set())

// 详细状态图例（细化错误类型）
const statusLegend = [
  { key: 'success', label: '成功', color: 'rgba(34, 197, 94, 0.85)', borderWidth: '2px' },
  { key: 'in_progress', label: '进行中', color: 'rgba(245, 158, 11, 0.95)', borderWidth: '2px' },
  { key: 'failure_timeout', label: '超时', color: 'rgba(239, 68, 68, 0.95)', borderWidth: '3px' },
  { key: 'failure_5xx', label: '服务端错误', color: 'rgba(220, 38, 38, 0.95)', borderWidth: '3px' },
  { key: 'failure_4xx', label: '客户端错误', color: 'rgba(239, 68, 68, 0.85)', borderWidth: '3px' },
  { key: 'failure_not_found', label: '未找到', color: 'rgba(239, 68, 68, 0.75)', borderWidth: '3px' },
  { key: 'failure_other', label: '其它失败', color: 'rgba(239, 68, 68, 0.65)', borderWidth: '3px' },
]

// 分组标题
const groupTitle = computed(() => {
  if (props.groupMode === 'vendor') return '原厂'
  if (props.groupMode === 'provider') return '供应商'
  return '模型'
})

// 切换分组项选中状态（反转操作）
function toggleGroup(key: string) {
  if (selectedGroups.value.has(key)) {
    selectedGroups.value.delete(key)
  } else {
    selectedGroups.value.add(key)
  }
  // 触发响应式更新
  selectedGroups.value = new Set(selectedGroups.value)
  emit('toggleSelection', 'group', key)
}

// 切换状态项选中状态（反转操作）
function toggleStatus(key: string) {
  if (selectedStatuses.value.has(key)) {
    selectedStatuses.value.delete(key)
  } else {
    selectedStatuses.value.add(key)
  }
  // 触发响应式更新
  selectedStatuses.value = new Set(selectedStatuses.value)
  emit('toggleSelection', 'status', key)
}
</script>

<template>
  <div class="live-legend">
    <!-- 左侧：分组维度图例（原厂/供应商/模型） -->
    <div class="live-legend__section live-legend__section--left">
      <span class="live-legend__heading">{{ groupTitle }}</span>
      <div class="live-legend__items">
        <button
          v-for="item in groupItems"
          :key="item.key"
          type="button"
          class="live-legend__item"
          :class="{ 'live-legend__item--selected': selectedGroups.has(item.key) }"
          @click="toggleGroup(item.key)"
        >
          <span
            class="live-legend__swatch live-legend__swatch--bg"
            :style="{ background: item.color }"
            aria-hidden="true"
          />
          <span class="live-legend__label">{{ item.label }}</span>
        </button>
      </div>
    </div>

    <!-- 右侧：状态图例 -->
    <div class="live-legend__section live-legend__section--right">
      <span class="live-legend__heading">状态</span>
      <div class="live-legend__items">
        <button
          v-for="item in statusLegend"
          :key="item.key"
          type="button"
          class="live-legend__item"
          :class="{ 'live-legend__item--selected': selectedStatuses.has(item.key) }"
          @click="toggleStatus(item.key)"
        >
          <span
            class="live-legend__swatch live-legend__swatch--border"
            :style="{ borderColor: item.color, borderWidth: item.borderWidth }"
            aria-hidden="true"
          />
          <span class="live-legend__label">{{ item.label }}</span>
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* 2026-07-05 图例重构：左右分布，支持点击选中/反选 */
.live-legend {
  display: flex;
  justify-content: space-between;
  gap: 24px;
  font-size: 11px;
  color: var(--muted, #8b949e);
  padding: 10px 8px;
  margin-bottom: 12px;
  border: 1px solid var(--border, #30363d);
  border-radius: 6px;
  background: var(--bg-subtle, #161b22);
}

.live-legend__section {
  display: flex;
  align-items: center;
  gap: 10px;
  flex: 1;
  min-width: 0;
}

.live-legend__section--left {
  justify-content: flex-start;
}

.live-legend__section--right {
  justify-content: flex-end;
}

.live-legend__heading {
  font-weight: 600;
  color: var(--text, #e6edf3);
  font-size: 12px;
  flex-shrink: 0;
  min-width: 40px;
}

.live-legend__items {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px 8px;
  flex: 1;
  min-width: 0;
}

.live-legend__item {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  white-space: nowrap;
  padding: 3px 8px;
  border-radius: 4px;
  border: 1px solid transparent;
  background: transparent;
  cursor: pointer;
  transition: all 0.15s ease;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans SC', 'Microsoft YaHei', sans-serif;
}

.live-legend__item:hover {
  background: var(--bg, #0f1117);
  border-color: var(--border, #30363d);
}

/* 选中状态：醒目的边框和背景，带脉冲动画 */
.live-legend__item--selected {
  background: rgba(99, 102, 241, 0.15);
  border-color: var(--accent, #6366f1);
  box-shadow: 0 0 0 2px rgba(99, 102, 241, 0.3);
  animation: legend-pulse 2s ease-in-out infinite;
}

@keyframes legend-pulse {
  0%, 100% {
    box-shadow: 0 0 0 2px rgba(99, 102, 241, 0.3);
  }
  50% {
    box-shadow: 0 0 0 3px rgba(99, 102, 241, 0.5);
  }
}

.live-legend__item--selected .live-legend__label {
  color: var(--accent, #6366f1);
  font-weight: 700;
}

.live-legend__swatch {
  display: inline-block;
  width: 14px;
  height: 14px;
  border-radius: 3px;
  flex-shrink: 0;
}

/* 背景色色块 */
.live-legend__swatch--bg {
  opacity: 0.5;
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.1);
}

/* 边框色块 */
.live-legend__swatch--border {
  background: transparent;
  border-style: solid;
  box-shadow: inset 0 0 0 1px rgba(139, 148, 158, 0.2);
}

.live-legend__label {
  line-height: 1;
  color: var(--muted, #8b949e);
  font-size: 11px;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans SC', 'Microsoft YaHei', sans-serif;
}
</style>
