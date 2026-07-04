<script setup lang="ts">
/**
 * StatsModal — 统计数据详情弹窗
 * 
 * 显示高量APIKey排行和按模型统计的详细数据
 */
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useLocale } from '../i18n/useLocale'
import type { HotApiKeyEntry, ModelUsage } from '../api'

const props = defineProps<{
  visible: boolean
  type: 'hot-keys' | 'models'
  hotKeys: HotApiKeyEntry[]
  models: ModelUsage[]
  days: number
}>()

const emit = defineEmits<{
  close: []
}>()

const { t } = useI18n()
const { locale } = useLocale()

const title = computed(() => {
  if (props.type === 'hot-keys') {
    return t('dashboard.table.hotKeysTitle')
  }
  return t('dashboard.table.byModelTitle')
})

function fmt(n: number | undefined, decimals = 0) {
  if (n === undefined || n === null) return '—'
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M'
  if (n >= 1_000) return (n / 1_000).toFixed(1) + 'K'
  return Number(n).toFixed(decimals)
}

function fmtCost(v: number | undefined) {
  if (v === undefined || v === null) return '—'
  return '$' + Number(v).toFixed(4)
}

function fmtDate(v: string | null | undefined) {
  if (!v) return '—'
  try {
    return new Date(v).toLocaleString(locale.value, { dateStyle: 'short', timeStyle: 'short' })
  } catch {
    return new Date(v).toLocaleString('en-US', { dateStyle: 'short', timeStyle: 'short' })
  }
}

function handleClose() {
  emit('close')
}

function handleBackdropClick(e: MouseEvent) {
  if (e.target === e.currentTarget) {
    handleClose()
  }
}
</script>

<template>
  <Teleport to="body">
    <Transition name="modal">
      <div
        v-if="visible"
        class="stats-modal-backdrop"
        @click="handleBackdropClick"
      >
        <div class="stats-modal">
          <div class="stats-modal__header">
            <h3 class="stats-modal__title">{{ title }}</h3>
            <button
              type="button"
              class="stats-modal__close"
              @click="handleClose"
              :aria-label="t('common.button.close')"
            >
              ✕
            </button>
          </div>

          <div class="stats-modal__body">
            <!-- 高量 API Key 排行 -->
            <table v-if="type === 'hot-keys' && hotKeys.length > 0">
              <thead>
                <tr>
                  <th>{{ t('dashboard.table.colKey') }}</th>
                  <th>{{ t('dashboard.table.colApplication') }}</th>
                  <th>{{ t('dashboard.table.colOwner') }}</th>
                  <th class="text-end">{{ t('dashboard.table.colRequests') }}</th>
                  <th class="text-end">{{ t('dashboard.table.colTokens') }}</th>
                  <th class="text-end">{{ t('dashboard.table.colCost') }}</th>
                  <th>{{ t('dashboard.table.colLastUsed') }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="k in hotKeys" :key="k.api_key_id">
                  <td><code class="mono-sm">{{ k.key_prefix ?? '—' }}***</code></td>
                  <td>{{ k.application_code ?? '—' }}</td>
                  <td>{{ k.owner_user ?? '—' }}</td>
                  <td class="text-end">{{ fmt(k.request_count) }}</td>
                  <td class="text-end">{{ fmt(k.total_tokens) }}</td>
                  <td class="text-end">{{ fmtCost(k.total_cost_usd) }}</td>
                  <td>{{ fmtDate(k.last_used_at) }}</td>
                </tr>
              </tbody>
            </table>

            <!-- 按模型统计 -->
            <table v-if="type === 'models' && models.length > 0">
              <thead>
                <tr>
                  <th>{{ t('dashboard.table.colModel') }}</th>
                  <th>{{ t('dashboard.table.colProvider') }}</th>
                  <th class="text-end">{{ t('dashboard.table.colRequests') }}</th>
                  <th class="text-end">{{ t('dashboard.table.colTokens') }}</th>
                  <th class="text-end">{{ t('dashboard.table.colCost') }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="m in models" :key="m.model">
                  <td><code class="mono-sm">{{ m.model }}</code></td>
                  <td><span class="badge badge-blue">{{ m.provider_code }}</span></td>
                  <td class="text-end">{{ fmt(m.total_requests) }}</td>
                  <td class="text-end">{{ fmt(m.total_tokens) }}</td>
                  <td class="text-end">{{ fmtCost(m.total_cost_usd) }}</td>
                </tr>
              </tbody>
            </table>

            <div v-if="(type === 'hot-keys' && hotKeys.length === 0) || (type === 'models' && models.length === 0)" class="stats-modal__empty">
              {{ t('dashboard.noData') }}
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.stats-modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.6);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  padding: 20px;
}

.stats-modal {
  background: var(--card, #1c2128);
  border: 1px solid var(--border, #30363d);
  border-radius: var(--radius, 8px);
  max-width: 1000px;
  width: 100%;
  max-height: 80vh;
  display: flex;
  flex-direction: column;
  box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.3), 0 10px 10px -5px rgba(0, 0, 0, 0.2);
}

.stats-modal__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 20px;
  border-bottom: 1px solid var(--border, #30363d);
}

.stats-modal__title {
  font-size: 16px;
  font-weight: 600;
  margin: 0;
  color: var(--text, #e6edf3);
}

.stats-modal__close {
  width: 32px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  border: none;
  background: transparent;
  color: var(--muted, #8b949e);
  font-size: 20px;
  cursor: pointer;
  border-radius: 4px;
  transition: all 0.2s;
}

.stats-modal__close:hover {
  background: var(--bg-subtle, #161b22);
  color: var(--text, #e6edf3);
}

.stats-modal__body {
  padding: 20px;
  overflow-y: auto;
  flex: 1;
}

.stats-modal__body table {
  width: 100%;
  border-collapse: collapse;
}

.stats-modal__body th {
  text-align: left;
  padding: 8px 12px;
  font-size: 12px;
  font-weight: 600;
  color: var(--muted, #8b949e);
  border-bottom: 1px solid var(--border, #30363d);
}

.stats-modal__body td {
  padding: 10px 12px;
  font-size: 13px;
  color: var(--text, #e6edf3);
  border-bottom: 1px solid var(--border, #30363d);
}

.stats-modal__body tbody tr:hover {
  background: var(--bg-subtle, #161b22);
}

.stats-modal__empty {
  text-align: center;
  padding: 40px;
  color: var(--muted, #8b949e);
  font-size: 14px;
}

.text-end {
  text-align: end;
}

.mono-sm {
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 12px;
}

.badge {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 4px;
  font-size: 11px;
  font-weight: 500;
}

.badge-blue {
  background: rgba(59, 130, 246, 0.15);
  color: #60a5fa;
}

/* 弹窗动画 */
.modal-enter-active,
.modal-leave-active {
  transition: opacity 0.3s ease;
}

.modal-enter-active .stats-modal,
.modal-leave-active .stats-modal {
  transition: transform 0.3s cubic-bezier(0.18, 0.89, 0.32, 1.28), opacity 0.3s ease;
}

.modal-enter-from,
.modal-leave-to {
  opacity: 0;
}

.modal-enter-from .stats-modal,
.modal-leave-to .stats-modal {
  transform: scale(0.9) translateY(20px);
  opacity: 0;
}
</style>
