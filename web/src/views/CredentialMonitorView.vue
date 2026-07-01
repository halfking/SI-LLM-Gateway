<script setup lang="ts">
import { ref, onMounted, computed, onUnmounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { getCredentialMonitorSummary, getSlidingWindow, promoteCredential, demoteCredential, setConcurrencyAuto, toggleModelAvailability, getModelHistory, getCredentialFpSlotStats, getCredentialDecisions, clearManualDisabled, setManualDisabled, type CredentialMonitorSummary, type CredentialModelStatus, type CallEntry, type ModelHistoryEvent, type ModelToggleAction, type FpSlotStats, type CredentialRoutingDecision } from '../api'
import { Chart, registerables } from 'chart.js'
import FpSlotVisualizer from '../components/FpSlotVisualizer.vue'
import SlotInfoCard from '../components/SlotInfoCard.vue'
import SegTabs, { type SegTab } from '../components/SegTabs.vue'
import StatusBadge from '../components/StatusBadge.vue'

const { t } = useI18n()
// Short alias for the credentialMonitor locale namespace. Accepts an
// optional params object for templated strings (e.g. cm('key', { n: 5 })).
const cm = (k: string, params?: Record<string, unknown>): string =>
  t(`credentialMonitor.${k}` as never, params as never)

Chart.register(...registerables)

const loading = ref(false)
const credentials = ref<CredentialMonitorSummary[]>([])
const selectedCred = ref<CredentialMonitorSummary | null>(null)
const selectedModel = ref('')
const windowEntries = ref<CallEntry[]>([])
const windowSource = ref<'redis' | 'request_logs'>('redis')
const windowLoading = ref(false)

// ── 2026-06-26: 详情页 3-tab 重构（合并模型+监控为「模型」）─────────────
// 3 tab = 基础信息 / 模型 / 请求数据. 「模型」tab 内部采用左列表+右详情布局.
// 历史 tab 内容（状态变化历史 + 路由决策）整合进「请求数据」tab.
type DetailTab = 'overview' | 'models' | 'requests'
const detailActiveTab = ref<DetailTab>('overview')
const detailTabs: SegTab[] = [
  { value: 'overview',  label: cm('drawer.tab.overview') },
  { value: 'models',    label: cm('drawer.tab.models') },
  { value: 'requests',  label: cm('drawer.tab.requests') },
]
// 打开 detail 时默认到第一个 tab
watch(selectedCred, (newVal) => {
  if (newVal) detailActiveTab.value = 'overview'
})

const providerFilter = ref(0)
const availStateFilter = ref('')
const healthFilter = ref('')
const quickFilter = ref<'none' | 'broken' | 'low-rate'>('none')

const demoteDialogOpen = ref(false)
const demoteReason = ref('')
const demoteHours = ref(2)

const promoteDialogOpen = ref(false)
const promoteReason = ref('')

const concurrencyDialogOpen = ref(false)
const concurrencyValue = ref(5)
const concurrencyReason = ref('')

// ── 2026-06-23: per-model manual online/offline + state-change history ──
const toggleBusy = ref<Record<string, boolean>>({})
const toggleDialogOpen = ref(false)
const toggleTarget = ref<{
  credId: number
  rawModel: string
  action: ModelToggleAction
  prevReason: string | null
} | null>(null)
const toggleReason = ref('')
const historyLoading = ref(false)
const historyEvents = ref<ModelHistoryEvent[]>([])

// Auto refresh (main list)
const autoRefresh = ref(false)
const refreshInterval = ref(30) // seconds
let refreshTimer: number | null = null

// Detail drawer auto-refresh (2026-06-23)
const detailAutoRefresh = ref(false)
const detailRefreshInterval = ref(5) // seconds
let detailRefreshTimer: number | null = null

// Routing decisions for credential (2026-06-23)
const credentialDecisions = ref<CredentialRoutingDecision[]>([])
const credentialDecisionsLoading = ref(false)
async function loadCredentialDecisions() {
  if (!selectedCred.value) return
  credentialDecisionsLoading.value = true
  try {
    const res = await getCredentialDecisions(selectedCred.value.id, 50)
    credentialDecisions.value = res.decisions
  } catch (e) {
    console.error('credential decisions load failed', e)
  } finally {
    credentialDecisionsLoading.value = false
  }
}

// V3.1 SlotInfoCard ref (2026-06-26)
const slotInfoCardRef = ref<InstanceType<typeof import('../components/SlotInfoCard.vue')['default']> | null>(null)
function refreshSlotInfo() {
  slotInfoCardRef.value?.refresh()
}

// Fingerprint slot visualization (2026-06-23)
const fpSlotStats = ref<FpSlotStats | null>(null)
const fpSlotStatsLoading = ref(false)
async function loadFpSlotStats() {
  if (!selectedCred.value) return
  fpSlotStatsLoading.value = true
  try {
    fpSlotStats.value = await getCredentialFpSlotStats(
      selectedCred.value.provider_id,
      selectedCred.value.id,
    )
  } catch (e) {
    console.error('fp slot stats load failed', e)
  } finally {
    fpSlotStatsLoading.value = false
  }
}

// Clear manual_disabled (2026-06-23)
const clearDisabledDialogOpen = ref(false)
const clearDisabledReason = ref('')

// Set manual_disabled (2026-06-23)
const setManualDisabledDialogOpen = ref(false)
const setManualDisabledTargetValue = ref(false)
const setManualDisabledReason = ref('')

function openClearDisabledDialog() {
  clearDisabledDialogOpen.value = true
  clearDisabledReason.value = ''
}

async function submitClearDisabled() {
  if (!selectedCred.value) return
  try {
    await clearManualDisabled(selectedCred.value.id, clearDisabledReason.value)
    clearDisabledDialogOpen.value = false
    await refreshDetailDrawer()
  } catch (e) {
    alert(t('credentialMonitor.error.clearFailed') + (e instanceof Error ? e.message : String(e)))
  }
}

// Set manual_disabled (2026-06-23)
function openSetManualDisabledDialog(targetValue: boolean) {
  setManualDisabledTargetValue.value = targetValue
  setManualDisabledReason.value = ''
  setManualDisabledDialogOpen.value = true
}

async function submitSetManualDisabled() {
  if (!selectedCred.value || !setManualDisabledReason.value.trim()) return
  try {
    await setManualDisabled(selectedCred.value.id, setManualDisabledTargetValue.value, setManualDisabledReason.value)
    setManualDisabledDialogOpen.value = false
    await refreshDetailDrawer()
  } catch (e) {
    alert(t('credentialMonitor.error.setManualDisabledFailed') + (e instanceof Error ? e.message : String(e)))
  }
}

// Refresh detail drawer content (2026-06-23)
async function refreshDetailDrawer() {
  if (!selectedCred.value) return
  // Reload summary to update selectedCred
  await load()
  const updatedCred = credentials.value.find(c => c.id === selectedCred.value?.id)
  if (updatedCred) {
    selectedCred.value = updatedCred
  }
  // Reload all drawer sections
  if (selectedModel.value) {
    await Promise.all([
      loadSlidingWindow(selectedCred.value.id, selectedModel.value),
      loadHistory(),
      loadCredentialDecisions(),
      loadFpSlotStats(),
    ])
  } else {
    await Promise.all([
      loadCredentialDecisions(),
      loadFpSlotStats(),
    ])
  }
}

function startDetailAutoRefresh() {
  if (detailRefreshTimer) return
  detailAutoRefresh.value = true
  detailRefreshTimer = window.setInterval(() => refreshDetailDrawer(), detailRefreshInterval.value * 1000)
}

function stopDetailAutoRefresh() {
  if (detailRefreshTimer) {
    clearInterval(detailRefreshTimer)
    detailRefreshTimer = null
  }
  detailAutoRefresh.value = false
}

function toggleDetailAutoRefresh() {
  detailAutoRefresh.value ? stopDetailAutoRefresh() : startDetailAutoRefresh()
}

// Watch selectedCred changes to stop auto-refresh when drawer closes
watch(selectedCred, (newVal) => {
  if (!newVal) {
    stopDetailAutoRefresh()
  }
})

// Batch operations
const selectedIds = ref<Set<number>>(new Set())
const batchDialogOpen = ref(false)
const batchAction = ref<'promote' | 'demote'>('promote')
const batchReason = ref('')
const batchHours = ref(2)

// Error pie chart
let errorPieChart: Chart | null = null

async function load() {
  loading.value = true
  try {
    const res = await getCredentialMonitorSummary({
      provider_id: providerFilter.value || undefined,
      include_window_stats: true,
    })
    credentials.value = res.credentials
  } catch (e) {
    console.error('load failed', e)
  } finally {
    loading.value = false
  }
}

// ── Derived summary cards ──────────────────────────────────────────────
const summary = computed(() => {
  const all = credentials.value
  const total = all.length
  const ready = all.filter(c => c.availability_state === 'ready').length
  const abnormal = all.filter(c =>
    ['unreachable', 'cooling', 'rate_limited', 'auth_failed', 'suspended'].includes(c.availability_state)
  ).length
  let brokenModels = 0
  for (const c of all) {
    for (const m of c.models || []) {
      if (m.probe_state === 'broken_confirmed') brokenModels++
    }
  }
  return { total, ready, abnormal, brokenModels }
})

const filteredCreds = computed(() => {
  let result = credentials.value
  if (availStateFilter.value) {
    result = result.filter(c => c.availability_state === availStateFilter.value)
  }
  if (healthFilter.value) {
    result = result.filter(c => c.health_status === healthFilter.value)
  }
  if (quickFilter.value === 'broken') {
    result = result.filter(c => (c.models || []).some(m => m.probe_state === 'broken_confirmed'))
  }
  if (quickFilter.value === 'low-rate') {
    result = result.filter(c => c.aggregated_success_rate != null && c.aggregated_success_rate < 0.5)
  }
  return result
})

const allSelected = computed(() => {
  return filteredCreds.value.length > 0 && filteredCreds.value.every(c => selectedIds.value.has(c.id))
})

function toggleSelectAll() {
  if (allSelected.value) {
    selectedIds.value.clear()
  } else {
    filteredCreds.value.forEach(c => selectedIds.value.add(c.id))
  }
}

function toggleSelect(id: number) {
  if (selectedIds.value.has(id)) {
    selectedIds.value.delete(id)
  } else {
    selectedIds.value.add(id)
  }
}

// ── Per-credential model helpers ───────────────────────────────────────
function modelCount(c: CredentialMonitorSummary) {
  const models = c.models || []
  const total = models.length
  const avail = models.filter(m => m.offer_available && m.binding_available).length
  return { avail, total }
}

function brokenModels(c: CredentialMonitorSummary): CredentialModelStatus[] {
  return (c.models || []).filter(m => m.probe_state === 'broken_confirmed')
}

// First 3 broken model names for the table cell (the rest are hidden behind an
// ellipsis to keep the row readable when a credential has many broken models;
// the drawer shows the full list).
function brokenPreview(c: CredentialMonitorSummary): string[] {
  return brokenModels(c).slice(0, 3).map(m => m.raw_model_name)
}

// ── 2026-06-26: 当前选中模型对象（右侧详情用）─────────────────────────────
const currentModel = computed<CredentialModelStatus | null>(() => {
  if (!selectedCred.value || !selectedModel.value) return null
  return (selectedCred.value.models || []).find(m => m.raw_model_name === selectedModel.value) ?? null
})

// ── 2026-06-26: 3 个状态图标点击处理 ──────────────────────────────────────
// 图标 1: 手工禁用 — 对应整凭据 manual_disabled（不是 per-model）
// 图标 2: 手工启动 — 对应 per-model manual_offline
// 图标 3: 自动   — 自动探测控制
//
// 点击语义：
//   1. 手工禁用（非激活态）→ 弹出确认对话框 → set manual_disabled=true
//   1. 手工禁用（已激活态）→ 弹出确认对话框 → clear manual_disabled
//   2. 手工启动（非激活态）→ 弹出确认对话框 → toggle model offline（manual_offline）
//   2. 手工启动（已激活态）→ 弹出确认对话框 → toggle model online
//   3. 自动（非激活态）     → 弹出确认对话框 → 解除 manual_offline（让自动接管）
function handleManualDisableClick() {
  if (!selectedCred.value || !currentModel.value) return
  if (selectedCred.value.manual_disabled) {
    // 当前已禁用 → 询问是否解除
    openClearDisabledDialog()
  } else {
    // 当前未禁用 → 询问是否禁用整凭据
    openSetManualDisabledDialog(true)
  }
}

function handleManualOnlineClick() {
  if (!currentModel.value) return
  if (currentModel.value.binding_unavailable_reason === 'manual_offline') {
    // 当前是 manual_offline → 弹确认切换回 auto
    openToggleDialog(currentModel.value, 'online')
  } else {
    // 当前不是 manual_offline → 弹确认设为 offline
    openToggleDialog(currentModel.value, 'offline')
  }
}

function handleAutoClick() {
  if (!currentModel.value) return
  // 自动状态下点击：如果是 manual_offline 则弹 online 切换回自动
  if (currentModel.value.binding_unavailable_reason === 'manual_offline') {
    openToggleDialog(currentModel.value, 'online')
  }
  // 其他自动场景下按钮实际为禁用态，所以通常不会进入这里
}

function openDetail(cred: CredentialMonitorSummary) {
  selectedCred.value = cred
  // default the window to the first broken model, else the lowest-rate model
  const models = cred.models || []
  const broken = models.find(m => m.probe_state === 'broken_confirmed')
  const pick = broken || models.slice().sort((a, b) => (a.recent_success_rate ?? 1) - (b.recent_success_rate ?? 1))[0]
  selectedModel.value = pick?.raw_model_name || ''
  if (selectedModel.value) {
    loadSlidingWindow(cred.id, selectedModel.value)
    loadHistory()
  } else {
    windowEntries.value = []
    historyEvents.value = []
  }
  // Load additional drawer data (2026-06-23)
  loadCredentialDecisions()
  loadFpSlotStats()
}

async function loadSlidingWindow(credId: number, model: string) {
  if (!model) return
  windowLoading.value = true
  try {
    const res = await getSlidingWindow(credId, model, 60)
    windowEntries.value = res.entries
    windowSource.value = res.source
    setTimeout(() => renderErrorPieChart(res.stats.error_kinds), 100)
  } catch (e) {
    console.error('sliding window failed', e)
  } finally {
    windowLoading.value = false
  }
}

function selectModel(model: string) {
  if (!selectedCred.value || model === selectedModel.value) return
  selectedModel.value = model
  loadSlidingWindow(selectedCred.value.id, model)
  loadHistory()
}

function renderErrorPieChart(errorKinds: Record<string, number>) {
  const canvas = document.getElementById('errorPieChart') as HTMLCanvasElement
  if (!canvas) return

  if (errorPieChart) {
    errorPieChart.destroy()
  }

  const labels = Object.keys(errorKinds)
  const data = Object.values(errorKinds)

  // 🆕 2026-06-26: 无错误时显示绿色单扇形 "全部健康"，避免空白
  if (labels.length === 0) {
    errorPieChart = new Chart(canvas, {
      type: 'pie',
      data: {
        labels: [cm('chart.allHealthy')],
        datasets: [{
          data: [1],
          backgroundColor: ['#10b981'], // var(--success)
          borderColor: ['rgba(16, 185, 129, 0.4)'],
          borderWidth: 2,
        }],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { position: 'right' },
          title: { display: true, text: cm('chart.errorsWhenHealthy') },
        },
      },
    })
    return
  }

  errorPieChart = new Chart(canvas, {
    type: 'pie',
    data: {
      labels: labels,
      datasets: [{
        data: data,
        backgroundColor: [
          '#ef4444', '#f97316', '#f59e0b', '#eab308', '#84cc16',
          '#22c55e', '#10b981', '#14b8a6', '#06b6d4', '#0ea5e9',
        ],
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { position: 'right' },
        title: { display: true, text: cm('chart.errorsTitle') },
      },
    },
  })
}

function startAutoRefresh() {
  if (refreshTimer) return
  autoRefresh.value = true
  refreshTimer = window.setInterval(() => load(), refreshInterval.value * 1000)
}

function stopAutoRefresh() {
  if (refreshTimer) {
    clearInterval(refreshTimer)
    refreshTimer = null
  }
  autoRefresh.value = false
}

function toggleAutoRefresh() {
  autoRefresh.value ? stopAutoRefresh() : startAutoRefresh()
}

function openBatchDialog(action: 'promote' | 'demote') {
  if (selectedIds.value.size === 0) {
    alert(cm('error.selectFirst'))
    return
  }
  batchAction.value = action
  batchReason.value = ''
  batchHours.value = 2
  batchDialogOpen.value = true
}

async function submitBatch() {
  const ids = Array.from(selectedIds.value)
  const promises = ids.map(id =>
    batchAction.value === 'promote'
      ? promoteCredential(id, batchReason.value)
      : demoteCredential(id, batchReason.value, batchHours.value)
  )
  try {
    await Promise.all(promises)
    batchDialogOpen.value = false
    selectedIds.value.clear()
    load()
  } catch (e) {
    alert(cm('error.batchFailed') + (e instanceof Error ? e.message : String(e)))
  }
}

function openDemoteDialog() {
  demoteDialogOpen.value = true
  demoteReason.value = ''
  demoteHours.value = 2
}

async function submitDemote() {
  if (!selectedCred.value) return
  try {
    await demoteCredential(selectedCred.value.id, demoteReason.value, demoteHours.value)
    demoteDialogOpen.value = false
    load()
    selectedCred.value = null
  } catch (e) {
    alert(cm('error.demoteFailed') + (e instanceof Error ? e.message : String(e)))
  }
}

function openPromoteDialog() {
  promoteDialogOpen.value = true
  promoteReason.value = ''
}

async function submitPromote() {
  if (!selectedCred.value) return
  try {
    await promoteCredential(selectedCred.value.id, promoteReason.value)
    promoteDialogOpen.value = false
    load()
    selectedCred.value = null
  } catch (e) {
    alert(cm('error.promoteFailed') + (e instanceof Error ? e.message : String(e)))
  }
}

function openConcurrencyDialog() {
  concurrencyDialogOpen.value = true
  concurrencyValue.value = selectedCred.value?.concurrency_limit_auto || selectedCred.value?.effective_concurrency || 5
  concurrencyReason.value = ''
}

async function submitConcurrency() {
  if (!selectedCred.value) return
  try {
    await setConcurrencyAuto(selectedCred.value.id, concurrencyValue.value, concurrencyReason.value)
    concurrencyDialogOpen.value = false
    load()
  } catch (e) {
    alert(cm('error.concurrencyFailed') + (e instanceof Error ? e.message : String(e)))
  }
}

// ── 2026-06-23: per-model toggle + history helpers ────────────────────────
function openToggleDialog(m: CredentialModelStatus, action: ModelToggleAction) {
  if (!selectedCred.value) return
  toggleTarget.value = {
    credId: selectedCred.value.id,
    rawModel: m.raw_model_name,
    action,
    prevReason: m.binding_unavailable_reason ?? null,
  }
  toggleReason.value = ''
  toggleDialogOpen.value = true
}

async function submitToggle() {
  if (!toggleTarget.value || !toggleReason.value.trim()) return
  const t = toggleTarget.value
  const key = `${t.credId}|${t.rawModel}`
  toggleBusy.value[key] = true
  try {
    await toggleModelAvailability(t.credId, t.rawModel, t.action, toggleReason.value.trim())
    toggleDialogOpen.value = false
    await load() // refresh summary so the row badge updates
    await loadHistory() // refresh history with the new manual event on top
  } catch (e) {
    alert(`${t.action === 'offline' ? cm('error.offlineFailed') : cm('error.onlineFailed')}` + (e instanceof Error ? e.message : String(e)))
  } finally {
    toggleBusy.value[key] = false
  }
}

async function loadHistory() {
  if (!selectedCred.value || !selectedModel.value) {
    historyEvents.value = []
    return
  }
  historyLoading.value = true
  try {
    const res = await getModelHistory(selectedCred.value.id, selectedModel.value, 50)
    historyEvents.value = res.events
  } catch (e) {
    console.error('history failed', e)
    historyEvents.value = []
  } finally {
    historyLoading.value = false
  }
}

function formatTs(ts: string) {
  // '2026-06-23T10:00:00Z' -> '06-23 10:00'
  const d = new Date(ts)
  if (isNaN(d.getTime())) return ts
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  const h = String(d.getHours()).padStart(2, '0')
  const min = String(d.getMinutes()).padStart(2, '0')
  return `${m}-${day} ${h}:${min}`
}

// ── Badge / color helpers ──────────────────────────────────────────────
function statusBadge(state: string) {
  if (state === 'ready') return 'badge-green'
  if (['degraded', 'cooling', 'rate_limited'].includes(state)) return 'badge-amber'
  if (['unreachable', 'auth_failed', 'suspended'].includes(state)) return 'badge-red'
  return 'badge-gray'
}

function healthBadge(h: string) {
  if (h === 'healthy') return 'badge-green'
  if (h === 'warning') return 'badge-amber'
  if (h === 'unreachable') return 'badge-red'
  return 'badge-gray'
}

function probeBadge(state: string) {
  if (state === 'broken_confirmed') return 'badge-red'
  if (state === 'recovering') return 'badge-amber'
  if (state === 'healthy_confirmed') return 'badge-green'
  return 'badge-gray'
}

function rateClass(rate: number | null | undefined) {
  if (rate == null) return 'rate-none'
  if (rate >= 0.9) return 'rate-good'
  if (rate >= 0.5) return 'rate-warn'
  return 'rate-bad'
}

function rateText(rate: number | null | undefined) {
  if (rate == null) return '—'
  return (rate * 100).toFixed(1) + '%'
}

// 🆕 2026-06-23: 延迟 P95 色阶 (用于模型可用性表).
//   <500ms 绿 / 500-1500ms 琥珀 / >1500ms 红 / null 不染色.
// 阈值参考 credentialhealth 默认配置和 llm-gateway-go 实测分布.
function p95Class(ms: number | null | undefined) {
  if (ms == null) return ''
  if (ms < 500) return 'p95-good'
  if (ms < 1500) return 'p95-warn'
  return 'p95-bad'
}

onMounted(() => load())

onUnmounted(() => {
  stopAutoRefresh()
  stopDetailAutoRefresh()
  if (errorPieChart) errorPieChart.destroy()
})
</script>

<template>
  <div class="page-container">
    <div class="top-bar">
      <h1>{{ cm('page.title') }}</h1>
      <div class="refresh-group">
        <label>
          <input type="checkbox" :checked="autoRefresh" @change="toggleAutoRefresh" />
          {{ cm('page.autoRefresh') }}
        </label>
        <select v-model.number="refreshInterval" class="field-input">
          <option :value="10">{{ cm('page.refreshInterval.s10') }}</option>
          <option :value="30">{{ cm('page.refreshInterval.s30') }}</option>
          <option :value="60">{{ cm('page.refreshInterval.s60') }}</option>
        </select>
        <button class="btn btn-primary btn-sm" @click="load">{{ cm('page.manualRefresh') }}</button>
      </div>
      <span class="tb-sep" aria-hidden="true"></span>
      <span class="label">{{ cm('filter.availability') }}</span>
      <select v-model="availStateFilter" class="field-input">
        <option value="">{{ cm('filter.all') }}</option>
        <option value="ready">ready</option>
        <option value="degraded">degraded</option>
        <option value="cooling">cooling</option>
        <option value="unreachable">unreachable</option>
      </select>
      <span class="label">{{ cm('filter.health') }}</span>
      <select v-model="healthFilter" class="field-input">
        <option value="">{{ cm('filter.all') }}</option>
        <option value="healthy">healthy</option>
        <option value="warning">warning</option>
        <option value="unreachable">unreachable</option>
      </select>
      <div class="quick-filter-group">
        <button class="btn btn-sm btn-ghost" :class="quickFilter === 'none' ? 'qf-active' : ''" @click="quickFilter = 'none'">{{ cm('filter.quickNone') }}</button>
        <button class="btn btn-sm btn-ghost" :class="quickFilter === 'broken' ? 'qf-active qf-bad' : ''" @click="quickFilter = 'broken'">{{ cm('filter.quickBroken') }}</button>
        <button class="btn btn-sm btn-ghost" :class="quickFilter === 'low-rate' ? 'qf-active qf-warn' : ''" @click="quickFilter = 'low-rate'">{{ cm('filter.quickLowRate') }}</button>
      </div>
      <span class="spacer"></span>
      <button class="btn btn-sm btn-success" :disabled="selectedIds.size === 0" @click="openBatchDialog('promote')">
        {{ cm('filter.batchRestore', { n: selectedIds.size }) }}
      </button>
      <button class="btn btn-sm btn-danger" :disabled="selectedIds.size === 0" @click="openBatchDialog('demote')">
        {{ cm('filter.batchDemote', { n: selectedIds.size }) }}
      </button>
    </div>

    <!-- Summary cards -->
    <div class="summary-row">
      <div class="summary-card">
        <div class="summary-label">{{ cm('summary.total') }}</div>
        <div class="summary-value">{{ summary.total }}</div>
      </div>
      <div class="summary-card summary-good">
        <div class="summary-label">{{ cm('summary.ready') }}</div>
        <div class="summary-value">{{ summary.ready }}</div>
      </div>
      <div class="summary-card" :class="summary.abnormal > 0 ? 'summary-warn' : ''">
        <div class="summary-label">{{ cm('summary.abnormal') }}</div>
        <div class="summary-value">{{ summary.abnormal }}</div>
        <div class="summary-sub">{{ cm('summary.unreachable') }}</div>
      </div>
      <div class="summary-card" :class="summary.brokenModels > 0 ? 'summary-bad' : ''">
        <div class="summary-label">{{ cm('summary.brokenModels') }}</div>
        <div class="summary-value">{{ summary.brokenModels }}</div>
        <div class="summary-sub">{{ cm('summary.brokenModelsHint') }}</div>
      </div>
    </div>

    <div v-if="loading" style="text-align:center;padding:32px">{{ cm('table.loading') }}</div>
    <div v-else-if="!filteredCreds.length" style="text-align:center;padding:32px">{{ cm('table.empty') }}</div>

    <div v-else class="card" style="overflow-x:auto;padding:0">
      <table class="data-table dense">
        <thead>
          <tr>
            <th style="width:40px">
              <input type="checkbox" :checked="allSelected" @change="toggleSelectAll" />
            </th>
            <th>{{ cm('table.header.credential') }}</th>
            <th>{{ cm('table.header.provider') }}</th>
            <th>{{ cm('table.header.availability') }}</th>
            <th>{{ cm('table.header.health') }}</th>
            <th>{{ cm('table.header.models') }}</th>
            <th>{{ cm('table.header.recentSuccessRate') }}</th>
            <th>{{ cm('table.header.brokenModels') }}</th>
            <th>{{ cm('table.header.concurrency') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="c in filteredCreds" :key="c.id" class="clickable-row" @click="openDetail(c)">
            <td @click.stop>
              <input type="checkbox" :checked="selectedIds.has(c.id)" @change="toggleSelect(c.id)" />
            </td>
            <td>
              <div>{{ c.label || `#${c.id}` }}</div>
              <div class="cell-sub">{{ cm('table.cell.idPrefix') }}{{ c.id }}</div>
            </td>
            <td>{{ c.provider_name }}</td>
            <td>
              <span class="badge" :class="statusBadge(c.availability_state)">{{ c.availability_state }}</span>
              <div v-if="c.state_reason_code" class="cell-sub">{{ c.state_reason_code }}</div>
            </td>
            <td>
              <span class="badge" :class="healthBadge(c.health_status)">{{ c.health_status }}</span>
            </td>
            <td>
              <span :class="modelCount(c).avail < modelCount(c).total ? 'rate-warn' : ''">
                {{ modelCount(c).avail }}/{{ modelCount(c).total }}
              </span>
            </td>
            <td>
              <span class="rate-cell" :class="rateClass(c.aggregated_success_rate)">
                {{ rateText(c.aggregated_success_rate) }}
              </span>
            </td>
            <td>
              <span v-if="brokenModels(c).length === 0" class="cell-muted">—</span>
              <div v-else style="display:flex;flex-wrap:wrap;gap:4px;align-items:center">
                <span v-for="name in brokenPreview(c)" :key="name" class="badge badge-red model-badge">{{ name }}</span>
                <span v-if="brokenModels(c).length > 3" class="badge badge-gray model-badge" :title="brokenModels(c).map(m => m.raw_model_name).join(', ')">
                  +{{ brokenModels(c).length - 3 }}
                </span>
              </div>
            </td>
            <td>
              <div>{{ cm('table.cell.manualPrefix') }}{{ c.concurrency_limit || '—' }}</div>
              <div class="cell-sub">{{ cm('table.cell.effectivePrefix') }}{{ c.effective_concurrency }}</div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Detail Drawer -->
    <div v-if="selectedCred" class="drawer-backdrop" @click="selectedCred = null">
      <div class="drawer-panel card drawer-panel-wide" @click.stop>
        <div class="drawer-header">
          <div>
            <h3 style="margin:0">{{ selectedCred.label || `${cm('drawer.action.clearManualDisabled').replace('🔓 ', '')} #${selectedCred.id}` }}</h3>
            <div class="drawer-sub">{{ selectedCred.provider_name }}</div>
          </div>
          <div style="display:flex;gap:8px;align-items:center">
            <button
              v-if="selectedCred.manual_disabled"
              class="btn btn-xs btn-warning"
              :title="cm('drawer.action.clearManualDisabledTitle')"
              @click="openClearDisabledDialog"
            >{{ cm('drawer.action.clearManualDisabled') }}</button>
            <button
              v-else
              class="btn btn-xs btn-danger"
              :title="cm('drawer.action.setManualDisabledTitle')"
              @click="openSetManualDisabledDialog(true)"
            >{{ cm('drawer.action.setManualDisabled') }}</button>
            <label style="display:flex;align-items:center;gap:4px;font-size:13px;cursor:pointer">
              <input type="checkbox" :checked="detailAutoRefresh" @change="toggleDetailAutoRefresh" />
              {{ cm('page.autoRefresh') }}
            </label>
            <select v-model.number="detailRefreshInterval" class="field-input" style="width:auto;font-size:13px;padding:2px 6px">
              <option :value="5">{{ cm('page.refreshInterval.s5') }}</option>
              <option :value="10">{{ cm('page.refreshInterval.s10') }}</option>
              <option :value="30">{{ cm('page.refreshInterval.s30') }}</option>
            </select>
            <button class="btn btn-sm btn-ghost" @click="refreshDetailDrawer" :title="cm('drawer.refreshTooltip')">
              <span style="font-size:16px">↻</span>
            </button>
            <button class="btn btn-ghost btn-sm" @click="selectedCred = null">{{ cm('drawer.close') }}</button>
          </div>
        </div>

        <div style="padding:8px 16px 0;display:flex;align-items:center;gap:8px">
          <SegTabs v-model="detailActiveTab" :tabs="detailTabs" />
          <span class="cell-sub" style="margin-left:auto">
            {{ cm('drawer.credentialIdPrefix') }}<code class="mono-sm">{{ selectedCred.id }}</code>
          </span>
        </div>

        <div class="drawer-body">
          <!-- Tab 1: Overview -->
          <div v-if="detailActiveTab === 'overview'" style="display:grid;grid-template-columns:1fr 1fr;gap:16px">
            <div class="drawer-section">
              <div class="drawer-section-title">{{ cm('drawer.overview.sectionTitle') }}</div>
              <div style="display:grid;grid-template-columns:repeat(2,1fr);gap:12px">
                <div>
                  <label class="field-label">{{ cm('drawer.overview.fields.availability') }}</label>
                  <span class="badge" :class="statusBadge(selectedCred.availability_state)">{{ selectedCred.availability_state }}</span>
                </div>
                <div>
                  <label class="field-label">{{ cm('drawer.overview.fields.health') }}</label>
                  <span class="badge" :class="healthBadge(selectedCred.health_status)">{{ selectedCred.health_status }}</span>
                </div>
                <div>
                  <label class="field-label">{{ cm('drawer.overview.fields.quota') }}</label>
                  <span>{{ selectedCred.quota_state }}</span>
                </div>
                <div>
                  <label class="field-label">{{ cm('drawer.overview.fields.consecutiveFailures') }}</label>
                  <span>{{ selectedCred.consecutive_failures }}</span>
                </div>
                <div>
                  <label class="field-label">{{ cm('drawer.overview.fields.manualDisabled') }}</label>
                  <span :class="selectedCred.manual_disabled ? 'badge badge-red' : 'badge badge-gray'">
                    {{ selectedCred.manual_disabled ? cm('drawer.overview.fields.yes') : cm('drawer.overview.fields.no') }}
                  </span>
                </div>
                <div>
                  <label class="field-label">{{ cm('drawer.overview.fields.totalRequests') }}</label>
                  <span class="mono-sm">{{ selectedCred.total_requests }}</span>
                </div>
                <div>
                  <label class="field-label">{{ cm('drawer.overview.fields.totalModels') }}</label>
                  <span class="mono-sm">{{ modelCount(selectedCred).total }}</span>
                </div>
                <div>
                  <label class="field-label">{{ cm('drawer.overview.fields.availableModels') }}</label>
                  <span class="mono-sm">{{ modelCount(selectedCred).avail }} / {{ modelCount(selectedCred).total }}</span>
                </div>
                <div>
                  <label class="field-label">{{ cm('drawer.overview.fields.aggregateSuccessRate') }}</label>
                  <span class="rate-cell" :class="rateClass(selectedCred.aggregated_success_rate)">
                    {{ rateText(selectedCred.aggregated_success_rate) }}
                  </span>
                </div>
                <div>
                  <label class="field-label">{{ cm('drawer.overview.fields.brokenModelCount') }}</label>
                  <span :class="brokenModels(selectedCred).length > 0 ? 'badge badge-red' : 'badge badge-gray'">
                    {{ brokenModels(selectedCred).length }}
                  </span>
                </div>
              </div>
              <div v-if="selectedCred.state_reason_detail" class="cell-sub" style="margin-top:8px">
                {{ selectedCred.state_reason_detail }}
              </div>
            </div>

            <div class="drawer-section">
              <div class="drawer-section-title">{{ cm('drawer.concurrency.sectionTitle') }}</div>
              <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:12px">
                <div>
                  <label class="field-label">{{ cm('drawer.concurrency.manual') }}</label>
                  <div>{{ selectedCred.concurrency_limit || cm('drawer.concurrency.notSet') }}</div>
                </div>
                <div>
                  <label class="field-label">{{ cm('drawer.concurrency.auto') }}</label>
                  <div>{{ selectedCred.concurrency_limit_auto || cm('drawer.concurrency.notSet') }}</div>
                </div>
                <div>
                  <label class="field-label">{{ cm('drawer.concurrency.effective') }}</label>
                  <div class="badge badge-blue">{{ selectedCred.effective_concurrency }}</div>
                </div>
              </div>
              <div style="display:flex;gap:8px;margin-top:8px;flex-wrap:wrap">
                <button class="btn btn-sm" @click="openConcurrencyDialog">{{ cm('drawer.concurrency.adjustAuto') }}</button>
                <button class="btn btn-sm btn-danger" @click="openDemoteDialog">{{ cm('drawer.concurrency.tempDemote') }}</button>
                <button class="btn btn-sm btn-success" @click="openPromoteDialog">{{ cm('drawer.concurrency.restore') }}</button>
              </div>
            </div>
          </div>

          <!-- Tab 2: Models -->
          <div v-else-if="detailActiveTab === 'models'" class="models-tab">
            <div class="models-tab-grid">
              <div class="model-list-panel">
                <div class="drawer-section-title">
                  {{ cm('drawer.modelsTab.listTitle', { n: (selectedCred.models || []).length }) }}
                  <span class="cell-sub" style="margin-left:8px;font-weight:400">{{ cm('drawer.modelsTab.clickHint') }}</span>
                </div>
                <div v-if="!(selectedCred.models || []).length" class="cell-muted" style="padding:12px">{{ cm('drawer.modelsTab.empty') }}</div>
                <div v-else class="model-list">
                  <div v-for="m in selectedCred.models" :key="m.raw_model_name"
                      class="model-list-item"
                      :class="{
                        active: m.raw_model_name === selectedModel,
                        declared: m.data_source === 'declared',
                      }"
                      :title="m.model_disabled_reason || m.raw_model_name"
                      @click="selectModel(m.raw_model_name)">
                    <div class="mli-row1">
                      <StatusBadge :state="m.effective_state" :reason="m.model_disabled_reason" />
                      <code class="mli-name">{{ m.raw_model_name }}</code>
                    </div>
                    <div class="mli-row2">
                      <span class="rate-cell" :class="rateClass(m.recent_success_rate)">{{ rateText(m.recent_success_rate) }}</span>
                      <span class="cell-sub">{{ m.recent_samples ?? 0 }}{{ cm('drawer.modelsTab.sampleUnit') }}</span>
                      <span v-if="m.data_source === 'declared'" class="badge badge-gray mli-tag">{{ cm('drawer.modelsTab.neverCalled') }}</span>
                      <span v-else-if="!m.offer_available || !m.binding_available" class="badge badge-yellow mli-tag">{{ cm('drawer.modelsTab.unavail') }}</span>
                    </div>
                  </div>
                </div>
              </div>

              <div v-if="selectedModel && currentModel" class="model-detail-panel">
                <div class="model-header">
                  <div class="model-header-title">
                    <code class="model-name">{{ selectedModel }}</code>
                    <StatusBadge :state="currentModel.effective_state" :reason="currentModel.model_disabled_reason" />
                  </div>
                  <div class="status-icons">
                    <button
                      class="status-icon icon-manual-disable"
                      :class="{ active: currentModel.effective_state === 'manual_disabled' }"
                      :title="currentModel.effective_state === 'manual_disabled' ? cm('drawer.modelsTab.manualDisabledTitle') : cm('drawer.modelsTab.manualDisabledNot')"
                      :disabled="toggleBusy[selectedCred.id + '|' + selectedModel]"
                      @click="handleManualDisableClick"
                    >
                      <span class="status-icon-dot"></span>
                      {{ cm('drawer.modelsTab.manualDisabled') }}
                    </button>
                    <button
                      class="status-icon icon-manual-enable"
                      :class="{ active: currentModel.binding_unavailable_reason === 'manual_offline' && currentModel.effective_state !== 'manual_disabled' }"
                      :title="currentModel.binding_unavailable_reason === 'manual_offline' ? cm('drawer.modelsTab.manualOnlineTitle') : cm('drawer.modelsTab.manualOnlineNot')"
                      :disabled="toggleBusy[selectedCred.id + '|' + selectedModel]"
                      @click="handleManualOnlineClick"
                    >
                      <span class="status-icon-dot"></span>
                      {{ cm('drawer.modelsTab.manualOnline') }}
                    </button>
                    <button
                      class="status-icon icon-auto"
                      :class="{ active: !['manual_disabled', 'manual_offline'].includes(currentModel.binding_unavailable_reason || '') && !currentModel.effective_state.startsWith('manual_') }"
                      :title="cm('drawer.modelsTab.autoTitle')"
                      @click="handleAutoClick"
                    >
                      <span class="status-icon-dot"></span>
                      {{ cm('drawer.modelsTab.auto') }}
                    </button>
                  </div>
                </div>

                <div class="model-stats-grid">
                  <div class="stat-card">
                    <span class="label">{{ cm('drawer.modelsTab.stats.p95') }}</span>
                    <span :class="p95Class(currentModel.p95_latency_ms)">
                      <template v-if="currentModel.p95_latency_ms != null">{{ currentModel.p95_latency_ms }}{{ cm('drawer.modelsTab.stats.msUnit') }}</template>
                      <template v-else>—</template>
                    </span>
                  </div>
                  <div class="stat-card">
                    <span class="label">{{ cm('drawer.modelsTab.stats.recentSuccessRate') }}</span>
                    <span class="rate-cell" :class="rateClass(currentModel.recent_success_rate)">{{ rateText(currentModel.recent_success_rate) }}</span>
                  </div>
                  <div class="stat-card">
                    <span class="label">{{ cm('drawer.modelsTab.stats.sampleCount') }}</span>
                    <span class="mono-sm">{{ currentModel.recent_samples ?? '—' }}</span>
                  </div>
                  <div class="stat-card">
                    <span class="label">{{ cm('drawer.modelsTab.stats.last24hCalls') }}</span>
                    <span class="mono-sm">{{ currentModel.total_calls ?? 0 }}</span>
                  </div>
                </div>

                <div class="drawer-section">
                  <div class="drawer-section-title">
                    {{ cm('drawer.modelsTab.slidingTitle') }}
                    <span class="source-tag" :class="windowSource === 'redis' ? 'src-redis' : 'src-rl'">
                      {{ windowSource === 'redis' ? cm('drawer.modelsTab.redisSource') : cm('drawer.modelsTab.requestLogsSource') }}
                    </span>
                  </div>
                  <div v-if="windowLoading">{{ cm('drawer.modelsTab.loading') }}</div>
                  <div v-else-if="!windowEntries.length" class="cell-muted">{{ cm('drawer.modelsTab.noData') }}</div>
                  <div v-else>
                    <div class="spark-bar-row">
                      <div v-for="(e, i) in windowEntries.slice(0, 100)" :key="i"
                           class="spark-bar"
                           :style="{
                             background: e.ok ? '#10b981' : '#ef4444',
                             opacity: 0.8,
                           }"
                           :title="`${e.ok ? '✓' : '✗'} ${e.lat}${cm('drawer.modelsTab.stats.msUnit')} ${e.err || ''}`"></div>
                    </div>
                    <div class="window-stats">
                      <span>{{ cm('chart.slidingStatsTotal') }}{{ windowEntries.length }}</span>
                      <span style="color:#10b981">{{ cm('chart.slidingStatsSuccess') }}{{ windowEntries.filter(e => e.ok).length }}</span>
                      <span style="color:#ef4444">{{ cm('chart.slidingStatsFailed') }}{{ windowEntries.filter(e => !e.ok).length }}</span>
                      <span>{{ cm('chart.slidingStatsFailureRate') }}{{ ((windowEntries.filter(e => !e.ok).length / windowEntries.length) * 100).toFixed(1) }}%</span>
                    </div>
                  </div>
                </div>

                <div class="drawer-section">
                  <div class="drawer-section-title">{{ cm('drawer.modelsTab.errorsTitle') }}</div>
                  <div style="height:200px;position:relative">
                    <canvas id="errorPieChart"></canvas>
                  </div>
                </div>

                <div class="drawer-section">
                  <div class="drawer-section-title" style="display:flex;justify-content:space-between;align-items:center">
                    <span>{{ cm('drawer.modelsTab.slotInfoTitle') }}</span>
                    <button class="btn btn-xs btn-ghost" @click="refreshSlotInfo" :disabled="fpSlotStatsLoading">
                      {{ fpSlotStatsLoading ? cm('drawer.modelsTab.loading') : cm('drawer.modelsTab.refresh') }}
                    </button>
                  </div>
                  <SlotInfoCard
                    v-if="selectedCred"
                    ref="slotInfoCardRef"
                    :credential-id="selectedCred.id"
                    :key="selectedCred.id"
                  />
                </div>
              </div>
              <div v-else class="model-detail-panel empty">
                <div class="cell-muted">{{ cm('drawer.modelsTab.emptyHint') }}</div>
              </div>
            </div>
          </div>

          <!-- Tab 3: Requests -->
          <div v-else-if="detailActiveTab === 'requests'" style="display:grid;grid-template-columns:1fr 1fr;gap:16px">
            <div class="drawer-section">
              <div class="drawer-section-title" style="display:flex;align-items:center;gap:8px">
                {{ cm('drawer.requestsTab.historySectionTitle') }}
                <span v-if="historyEvents.length" class="cell-sub">({{ historyEvents.length }})</span>
                <button
                  class="btn btn-xs btn-ghost"
                  :disabled="historyLoading || !selectedModel"
                  style="margin-left:auto"
                  @click="loadHistory"
                >{{ cm('drawer.requestsTab.historyRefresh') }}</button>
              </div>
              <div v-if="!selectedModel" class="cell-muted">{{ cm('drawer.requestsTab.historyEmpty') }}</div>
              <div v-else-if="historyLoading">{{ cm('drawer.requestsTab.historyLoading') }}</div>
              <div v-else-if="!historyEvents.length" class="cell-muted">{{ cm('drawer.requestsTab.historyNoEvents') }}</div>
              <table v-else class="history-table">
                <thead>
                  <tr>
                    <th>{{ cm('drawer.requestsTab.historyColTime') }}</th>
                    <th>{{ cm('drawer.requestsTab.historyColSource') }}</th>
                    <th>{{ cm('drawer.requestsTab.historyColEvent') }}</th>
                    <th>{{ cm('drawer.requestsTab.historyColDetail') }}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="(ev, i) in historyEvents" :key="i" :class="`hist-${ev.event}`">
                    <td class="mono-sm">{{ formatTs(ev.ts) }}</td>
                    <td>
                      <span
                        v-if="ev.source === 'auto'"
                        class="badge"
                        :class="ev.event === 'broke' ? 'badge-red' : 'badge-green'"
                      >{{ cm('drawer.requestsTab.autoPrefix') }}{{ ev.triggered_by || 'scheduler' }}</span>
                      <span
                        v-else
                        class="badge"
                        :class="ev.event === 'offline' ? 'badge-red' : 'badge-green'"
                      >{{ cm('drawer.requestsTab.manualPrefix') }}{{ ev.actor || 'admin' }}</span>
                    </td>
                    <td><code class="mono-sm">{{ ev.event }}</code></td>
                    <td class="cell-sub">
                      <template v-if="ev.source === 'auto' && ev.error_code">
                        {{ ev.error_code }}{{ ev.http_status ? ' (' + ev.http_status + ')' : '' }}
                      </template>
                      <template v-else-if="ev.reason">{{ ev.reason }}</template>
                      <template v-else>—</template>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="drawer-section" style="grid-column:1 / -1">
              <div class="drawer-section-title" style="display:flex;justify-content:space-between;align-items:center">
                <span>{{ cm('drawer.requestsTab.routingSectionTitle', { n: 50 }) }}</span>
                <button
                  class="btn btn-xs btn-ghost"
                  :disabled="credentialDecisionsLoading"
                  @click="loadCredentialDecisions"
                >{{ cm('drawer.requestsTab.routingRefresh') }}</button>
              </div>
              <div v-if="credentialDecisionsLoading">{{ cm('drawer.requestsTab.routingLoading') }}</div>
              <div v-else-if="!credentialDecisions.length" class="cell-muted">{{ cm('drawer.requestsTab.routingNoEvents') }}</div>
              <div v-else style="overflow-x:auto">
                <table class="decision-table">
                  <thead>
                    <tr>
                      <th>{{ cm('drawer.requestsTab.routingColTime') }}</th>
                      <th>{{ cm('drawer.requestsTab.routingColRequestId') }}</th>
                      <th>{{ cm('drawer.requestsTab.routingColModel') }}</th>
                      <th>{{ cm('drawer.requestsTab.routingColTier') }}</th>
                      <th>{{ cm('drawer.requestsTab.routingColResult') }}</th>
                      <th>{{ cm('drawer.requestsTab.routingColLatency') }}</th>
                      <th>{{ cm('drawer.requestsTab.routingColError') }}</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr v-for="d in credentialDecisions" :key="d.request_id">
                      <td class="mono-sm">{{ formatTs(d.ts) }}</td>
                      <td class="mono-sm"><code>{{ d.request_id }}</code></td>
                      <td>
                        <span v-if="d.outbound_model && d.outbound_model !== d.canonical_name">
                          {{ d.canonical_name }} → {{ d.outbound_model }}
                        </span>
                        <span v-else>{{ d.canonical_name }}</span>
                      </td>
                      <td class="mono-sm">{{ d.tier ?? '—' }}</td>
                      <td>
                        <span v-if="d.success" class="badge badge-green">✓</span>
                        <span v-else class="badge badge-red">✗</span>
                        <span v-if="d.sticky_hit" class="badge badge-blue" style="margin-left:4px;font-size:9px">sticky</span>
                      </td>
                      <td class="mono-sm">{{ d.latency_ms != null ? d.latency_ms + cm('drawer.requestsTab.msUnit') : '—' }}</td>
                      <td class="cell-sub" style="font-size:10px">{{ d.error_class || '—' }}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Batch Dialog -->
    <div v-if="batchDialogOpen" class="drawer-backdrop" @click="batchDialogOpen = false">
      <div class="card" @click.stop style="max-width:500px;margin:auto;margin-top:100px;padding:24px">
        <h3 style="margin-top:0">{{ batchAction === 'promote' ? cm('dialog.batchTitle.promote') : cm('dialog.batchTitle.demote') }} ({{ selectedIds.size }} {{ cm('dialog.batchTitleSuffix') }}</h3>
        <div style="margin-bottom:16px">
          <label class="field-label">{{ cm('dialog.batchReasonLabel') }}</label>
          <input v-model="batchReason" class="field-input" :placeholder="cm('dialog.batchReasonPlaceholder')" />
        </div>
        <div v-if="batchAction === 'demote'" style="margin-bottom:16px">
          <label class="field-label">{{ cm('dialog.batchHoursLabel') }}</label>
          <input v-model.number="batchHours" type="number" min="0.5" step="0.5" class="field-input" />
        </div>
        <div style="display:flex;gap:8px;justify-content:flex-end">
          <button class="btn btn-ghost" @click="batchDialogOpen = false">{{ cm('dialog.cancel') }}</button>
          <button :class="batchAction === 'promote' ? 'btn btn-success' : 'btn btn-danger'" @click="submitBatch">
            {{ batchAction === 'promote' ? cm('dialog.batchSubmit.promote') : cm('dialog.batchSubmit.demote') }}
          </button>
        </div>
      </div>
    </div>

    <!-- Demote / Promote / Concurrency dialogs -->
    <div v-if="demoteDialogOpen" class="drawer-backdrop" @click="demoteDialogOpen = false">
      <div class="card" @click.stop style="max-width:500px;margin:auto;margin-top:100px;padding:24px">
        <h3 style="margin-top:0">{{ cm('dialog.demoteTitle') }}</h3>
        <div style="margin-bottom:16px">
          <label class="field-label">{{ cm('dialog.demoteReasonLabel') }}</label>
          <input v-model="demoteReason" class="field-input" :placeholder="cm('dialog.demoteReasonPlaceholder')" />
        </div>
        <div style="margin-bottom:16px">
          <label class="field-label">{{ cm('dialog.demoteHoursLabel') }}</label>
          <input v-model.number="demoteHours" type="number" min="0.5" step="0.5" class="field-input" />
        </div>
        <div style="display:flex;gap:8px;justify-content:flex-end">
          <button class="btn btn-ghost" @click="demoteDialogOpen = false">{{ cm('dialog.cancel') }}</button>
          <button class="btn btn-danger" @click="submitDemote">{{ cm('dialog.demoteSubmit') }}</button>
        </div>
      </div>
    </div>

    <div v-if="promoteDialogOpen" class="drawer-backdrop" @click="promoteDialogOpen = false">
      <div class="card" @click.stop style="max-width:500px;margin:auto;margin-top:100px;padding:24px">
        <h3 style="margin-top:0">{{ cm('dialog.promoteTitle') }}</h3>
        <div style="margin-bottom:16px">
          <label class="field-label">{{ cm('dialog.promoteReasonLabel') }}</label>
          <input v-model="promoteReason" class="field-input" :placeholder="cm('dialog.promoteReasonPlaceholder')" />
        </div>
        <div style="display:flex;gap:8px;justify-content:flex-end">
          <button class="btn btn-ghost" @click="promoteDialogOpen = false">{{ cm('dialog.cancel') }}</button>
          <button class="btn btn-success" @click="submitPromote">{{ cm('dialog.promoteSubmit') }}</button>
        </div>
      </div>
    </div>

    <div v-if="concurrencyDialogOpen" class="drawer-backdrop" @click="concurrencyDialogOpen = false">
      <div class="card" @click.stop style="max-width:500px;margin:auto;margin-top:100px;padding:24px">
        <h3 style="margin-top:0">{{ cm('dialog.concurrencyTitle') }}</h3>
        <div style="margin-bottom:16px">
          <label class="field-label">{{ cm('dialog.concurrencyLimitLabel') }}</label>
          <input v-model.number="concurrencyValue" type="number" min="1" class="field-input" />
        </div>
        <div style="margin-bottom:16px">
          <label class="field-label">{{ cm('dialog.concurrencyReasonLabel') }}</label>
          <input v-model="concurrencyReason" class="field-input" :placeholder="cm('dialog.concurrencyReasonPlaceholder')" />
        </div>
        <div style="display:flex;gap:8px;justify-content:flex-end">
          <button class="btn btn-ghost" @click="concurrencyDialogOpen = false">{{ cm('dialog.cancel') }}</button>
          <button class="btn btn-primary" @click="submitConcurrency">{{ cm('dialog.concurrencySubmit') }}</button>
        </div>
      </div>
    </div>

    <!-- per-model toggle dialog -->
    <div v-if="toggleDialogOpen" class="drawer-backdrop" @click="toggleDialogOpen = false">
      <div class="card" @click.stop style="max-width:480px;margin:auto;margin-top:120px;padding:20px">
        <h3 style="margin-top:0">
          {{ toggleTarget?.action === 'offline' ? cm('dialog.toggleTitle.offline') : cm('dialog.toggleTitle.online') }}
        </h3>
        <div class="cell-sub" style="margin-bottom:12px">
          <code class="mono-sm">{{ toggleTarget?.rawModel }}</code> · {{ cm('dialog.toggleCredentialPrefix') }}{{ toggleTarget?.credId }}
        </div>
        <div v-if="toggleTarget?.action === 'offline'" class="cell-sub" style="margin-bottom:12px">
          {{ cm('dialog.toggleOfflineBody', { code: 'manual_offline' }) }}
        </div>
        <div v-else class="cell-sub" style="margin-bottom:12px">
          {{ cm('dialog.toggleOnlineBody') }}
        </div>
        <label class="field-label">{{ cm('dialog.toggleReasonLabel') }}</label>
        <input
          v-model="toggleReason"
          class="field-input"
          :placeholder="cm('dialog.toggleReasonPlaceholder')"
          @keyup.enter="submitToggle"
        />
        <div style="display:flex;gap:8px;justify-content:flex-end;margin-top:16px">
          <button class="btn btn-ghost" @click="toggleDialogOpen = false">{{ cm('dialog.cancel') }}</button>
          <button
            :class="toggleTarget?.action === 'offline' ? 'btn btn-danger' : 'btn btn-success'"
            :disabled="!toggleReason.trim()"
            @click="submitToggle"
          >{{ toggleTarget?.action === 'offline' ? cm('dialog.toggleSubmit.offline') : cm('dialog.toggleSubmit.online') }}</button>
        </div>
      </div>
    </div>

    <!-- Clear manual_disabled dialog -->
    <div v-if="clearDisabledDialogOpen" class="drawer-backdrop" @click="clearDisabledDialogOpen = false">
      <div class="card" @click.stop style="max-width:480px;margin:auto;margin-top:120px;padding:20px">
        <h3 style="margin-top:0">{{ cm('dialog.clearTitle') }}</h3>
        <div class="cell-sub" style="margin-bottom:12px">
          {{ cm('dialog.toggleCredentialPrefix') }}{{ selectedCred?.id }} {{ cm('dialog.toggleCredentialSep') }} {{ selectedCred?.label || cm('dialog.toggleNoLabel') }}
        </div>
        <div style="margin-bottom:12px;padding:12px;background:rgba(251,191,36,0.1);border:1px solid rgba(251,191,36,0.3);border-radius:6px;font-size:13px">
          {{ cm('dialog.clearWarning') }}
        </div>
        <label class="field-label">{{ cm('dialog.clearReasonLabel') }}</label>
        <input
          v-model="clearDisabledReason"
          class="field-input"
          :placeholder="cm('dialog.clearReasonPlaceholder')"
          @keyup.enter="submitClearDisabled"
        />
        <div style="display:flex;gap:8px;justify-content:flex-end;margin-top:16px">
          <button class="btn btn-ghost" @click="clearDisabledDialogOpen = false">{{ cm('dialog.cancel') }}</button>
          <button
            class="btn btn-warning"
            :disabled="!clearDisabledReason.trim()"
            @click="submitClearDisabled"
          >{{ cm('dialog.clearSubmit') }}</button>
        </div>
      </div>
    </div>

    <!-- Set manual_disabled dialog -->
    <div v-if="setManualDisabledDialogOpen" class="drawer-backdrop" @click="setManualDisabledDialogOpen = false">
      <div class="card" @click.stop style="max-width:480px;margin:auto;margin-top:120px;padding:20px">
        <h3 style="margin-top:0">{{ setManualDisabledTargetValue ? cm('dialog.setTitle.disable') : cm('dialog.setTitle.enable') }}</h3>
        <div class="cell-sub" style="margin-bottom:12px">
          {{ cm('dialog.toggleCredentialPrefix') }}{{ selectedCred?.id }} {{ cm('dialog.toggleCredentialSep') }} {{ selectedCred?.label || cm('dialog.toggleNoLabel') }}
        </div>
        <div v-if="setManualDisabledTargetValue" style="margin-bottom:12px;padding:12px;background:rgba(239,68,68,0.1);border:1px solid rgba(239,68,68,0.3);border-radius:6px;font-size:13px">
          {{ cm('dialog.setDisableBody') }}
        </div>
        <div v-else style="margin-bottom:12px;padding:12px;background:rgba(16,185,129,0.1);border:1px solid rgba(16,185,129,0.3);border-radius:6px;font-size:13px">
          {{ cm('dialog.setEnableBody') }}
        </div>
        <label class="field-label">{{ cm('dialog.setReasonLabel') }}</label>
        <input
          v-model="setManualDisabledReason"
          class="field-input"
          :placeholder="setManualDisabledTargetValue ? cm('dialog.setReasonPlaceholderDisable') : cm('dialog.setReasonPlaceholderEnable')"
          @keyup.enter="submitSetManualDisabled"
        />
        <div style="display:flex;gap:8px;justify-content:flex-end;margin-top:16px">
          <button class="btn btn-ghost" @click="setManualDisabledDialogOpen = false">{{ cm('dialog.cancel') }}</button>
          <button
            :class="setManualDisabledTargetValue ? 'btn btn-danger' : 'btn btn-success'"
            :disabled="!setManualDisabledReason.trim()"
            @click="submitSetManualDisabled"
          >{{ setManualDisabledTargetValue ? cm('dialog.setSubmit.disable') : cm('dialog.setSubmit.enable') }}</button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Outer layout — top-left aligned, stretches across the full available
   width (per 2026-06-24 request). The global .main-body already supplies
   24px padding, so we don't add our own, and we don't cap the width with
   max-width + auto margins (which used to center the content and leave
   big gutters on wide screens). */
.page-container {
  display: flex;
  flex-direction: column;
  gap: 8px;
  min-width: 0;
}

/* Unified top bar — title + refresh + ALL filters + batch actions in a
   single horizontal row (per 2026-06-24 request). Previously split into
   two stacked rows (.top-bar-head + .filter-toolbar); now everything
   shares one row with a vertical separator between the "page-level"
   controls (title/refresh) and the "data-level" controls (filters/batch). */
.top-bar {
  padding: 6px 10px;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
  font-size: 11px;
  color: var(--muted);
}
.top-bar h1 {
  margin: 0;
  font-size: 15px;
  font-weight: 600;
  flex-shrink: 0;
  color: var(--text);
}
.top-bar .refresh-group {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: nowrap;
}
.top-bar .refresh-group label {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 11px;
  color: var(--muted);
}
.top-bar .refresh-group .field-input {
  width: auto;
  font-size: 11px;
  padding: 2px 6px;
}
.top-bar .tb-sep {
  width: 1px;
  height: 18px;
  background: var(--border);
  flex-shrink: 0;
  margin: 0 2px;
}
.top-bar > .label {
  font-size: 11px;
}
.top-bar .field-input { font-size: 11px; padding: 2px 6px; width: auto; }
.top-bar .spacer { flex: 1; }
.top-bar .btn-sm { font-size: 11px; padding: 2px 8px; }
.top-bar .quick-filter-group { display: inline-flex; gap: 4px; }

/* Page header kept for backward compat in case anything still references it */
.page-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0;
}
.page-header h1 {
  margin: 0;
  font-size: 15px;
  font-weight: 600;
}

/* Summary cards — compact, matches the density of /routing-v2's hero chips
   and AnalyticsKpiBar. The previous 16px padding + 28px value font + 20px
   section gap was too airy for an operations dashboard. */
.summary-row {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 8px;
}
.summary-card {
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 8px 12px;
}
.summary-label {
  font-size: 11px;
  color: var(--muted);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
.summary-value {
  font-size: 20px;
  font-weight: 700;
  margin-top: 2px;
  line-height: 1.1;
}
.summary-sub {
  font-size: 10px;
  color: var(--muted);
  margin-top: 2px;
}
.summary-good { border-color: rgba(63, 185, 80, 0.4); }
.summary-good .summary-value { color: var(--success); }
.summary-warn { border-color: rgba(210, 153, 34, 0.4); }
.summary-warn .summary-value { color: var(--warning); }
.summary-bad { border-color: rgba(248, 81, 73, 0.4); }
.summary-bad .summary-value { color: var(--danger); }

/* Quick filter pills */
.quick-filter-group {
  display: inline-flex;
  gap: 4px;
}
.qf-active {
  border-color: var(--accent);
  color: var(--accent-h);
}
.qf-active.qf-bad { border-color: var(--danger); color: var(--danger); }
.qf-active.qf-warn { border-color: var(--warning); color: var(--warning); }

/* Rate coloring */
.rate-cell { font-weight: 600; }
.rate-good { color: var(--success); }
.rate-warn { color: var(--warning); }
.rate-bad { color: var(--danger); }
.rate-none { color: var(--muted); }

/* Main credentials data table — denser than the global style.css default
   (which is 13px / 10px 12px). Mirrors the .dense-table pattern from
   /routing-v2's overview tab so the credentials list can show more rows
   without the right edge pushing past the sidebar. */
.data-table.dense thead th {
  padding: 5px 8px;
  font-size: 10px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--muted);
  border-bottom: 1px solid var(--border);
  background: var(--bg-subtle);
}
.data-table.dense tbody td {
  padding: 5px 8px;
  font-size: 12px;
  border-bottom: 1px solid var(--border);
  vertical-align: middle;
}
.data-table.dense tbody tr:last-child td { border-bottom: none; }

.model-badge {
  font-size: 10px;
  padding: 1px 6px;
}

/* Clickable table rows (click opens the detail drawer) */
.clickable-row {
  cursor: pointer;
}
.clickable-row:hover {
  background: rgba(255, 255, 255, 0.04) !important;
}

/* Model table in drawer */
.model-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
}
.model-table th {
  text-align: left;
  font-size: 11px;
  font-weight: 600;
  color: var(--muted);
  padding: 6px 8px;
  border-bottom: 1px solid var(--border);
}
.model-table td {
  padding: 6px 8px;
  border-bottom: 1px solid var(--border);
}
.model-table tbody tr {
  cursor: pointer;
}
.model-table tbody tr:hover {
  background: rgba(255, 255, 255, 0.03);
}
.model-row-selected {
  background: rgba(99, 102, 241, 0.12) !important;
}

/* 🆕 2026-06-23: declared 模型行置灰 (从未被路由实际调用) */
.model-row-declared {
  opacity: 0.55;
}
.model-row-declared:hover {
  opacity: 0.85;
}

/* 🆕 2026-06-23: 延迟 P95 色阶 (基于 ms 阈值) */
.p95-good { color: var(--success); font-weight: 600; }
.p95-warn { color: var(--warning); font-weight: 600; }
.p95-bad  { color: var(--danger); font-weight: 600; }

/* 🆕 2026-06-23: 数据来源 chip (live / declared) */
.source-chip {
  display: inline-block;
  padding: 1px 6px;
  border-radius: 4px;
  font-size: 10px;
  font-weight: 600;
  text-transform: lowercase;
  letter-spacing: 0.02em;
}
.source-live {
  background: rgba(63, 185, 80, 0.15);
  color: var(--success);
}
.source-declared {
  background: rgba(139, 148, 158, 0.15);
  color: var(--muted);
}

.mono-sm {
  font-family: 'SF Mono', Menlo, Consolas, monospace;
  font-size: 12px;
}

/* Sliding window source tag */
.source-tag {
  display: inline-block;
  margin-left: 8px;
  padding: 1px 6px;
  border-radius: 4px;
  font-size: 10px;
  font-weight: 600;
  vertical-align: middle;
}
.src-redis { background: rgba(63, 185, 80, 0.15); color: var(--success); }
.src-rl { background: rgba(99, 102, 241, 0.15); color: var(--accent-h); }

.cell-sub { font-size: 11px; color: var(--muted); }
.cell-muted { color: var(--muted); }

.drawer-panel-wide {
  width: min(1000px, 95vw);
}

.drawer-section {
  margin-bottom: 16px;
}
.drawer-section-title {
  font-size: 13px;
  font-weight: 600;
  color: var(--text);
  margin-bottom: 8px;
  padding-bottom: 6px;
  border-bottom: 1px solid var(--border);
}

.field-label {
  display: block;
  font-size: 11px;
  color: var(--muted);
  margin-bottom: 2px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

@media (max-width: 900px) {
  .summary-row {
    grid-template-columns: repeat(2, 1fr);
  }
}

/* 2026-06-23: per-model toggle + state-change history */
.history-table {
  width: 100%;
  font-size: 12px;
  border-collapse: collapse;
}
.history-table th {
  text-align: left;
  font-size: 11px;
  color: var(--muted);
  padding: 4px 6px;
  border-bottom: 1px solid var(--border);
}
.history-table td {
  padding: 4px 6px;
  border-bottom: 1px solid var(--border);
  vertical-align: top;
}
.history-table tr.hist-broke td:nth-child(3),
.history-table tr.hist-offline td:nth-child(3) {
  color: var(--danger);
  font-weight: 600;
}
.history-table tr.hist-recovered td:nth-child(3),
.history-table tr.hist-online td:nth-child(3) {
  color: var(--success);
  font-weight: 600;
}
.btn-xs {
  padding: 2px 6px;
  font-size: 11px;
}

/* Decision table (2026-06-23) */
.decision-table {
  width: 100%;
  font-size: 12px;
  border-collapse: collapse;
  margin-top: 8px;
}
.decision-table th {
  text-align: left;
  font-size: 11px;
  color: var(--muted);
  padding: 6px 8px;
  border-bottom: 1px solid var(--border);
  font-weight: 600;
}
.decision-table td {
  padding: 6px 8px;
  border-bottom: 1px solid var(--border);
  vertical-align: top;
}
.decision-table tbody tr.decision-success {
  background: rgba(16, 185, 129, 0.03);
}
.decision-table tbody tr.decision-fail {
  background: rgba(239, 68, 68, 0.03);
}
.decision-table tbody tr:hover {
  background: rgba(255, 255, 255, 0.05) !important;
}

/* ─────────────────────────────────────────────────────────────────────────
 * 2026-06-26: 凭据详情页重构 — 「模型」tab 左右布局 + 3 个状态图标
 *   - .models-tab-grid: 左右 2 列网格 (280px 列表 + 1fr 详情)
 *   - .model-list / .model-list-panel: 左侧模型列表
 *   - .model-detail-panel: 右侧详情容器
 *   - .status-icon*: 模型名称旁的 3 个状态图标按钮
 *   - .model-stats-grid / .stat-card: 4 个统计卡片
 *   - .spark-bar-row / .spark-bar: 滑动窗口条形
 * ──────────────────────────────────────────────────────────────────────── */
.models-tab {
  /* 自然高度 — 由左右面板内容自适应 */
}
.models-tab-grid {
  display: grid;
  grid-template-columns: 280px 1fr;
  gap: 16px;
  align-items: start;
}

/* 左侧：模型列表 */
.model-list-panel {
  border-right: 1px solid var(--border);
  padding-right: 12px;
}
.model-list {
  display: flex;
  flex-direction: column;
  gap: 4px;
  margin: 0;
  padding: 0;
}
.model-list-item {
  padding: 6px 8px;
  border-radius: 6px;
  cursor: pointer;
  border: 1px solid transparent;
  transition: background 0.12s, border-color 0.12s;
  min-width: 0;
}
.model-list-item:hover {
  background: rgba(255, 255, 255, 0.04);
}
.model-list-item.active {
  background: rgba(99, 102, 241, 0.12);
  border-color: rgba(99, 102, 241, 0.4);
}
.model-list-item.declared {
  opacity: 0.7;
}
.model-list-item.declared:hover {
  opacity: 1;
}
.mli-row1 {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-bottom: 2px;
  min-width: 0;
}
.mli-row2 {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 11px;
  color: var(--muted);
}
.mli-row2 .rate-cell {
  font-weight: 600;
}
.mli-name {
  font-family: 'SF Mono', Menlo, Consolas, monospace;
  font-size: 11px;
  font-weight: 600;
  color: var(--text);
  word-break: break-all;
  flex: 1;
  min-width: 0;
  line-height: 1.4;
}
.mli-tag {
  font-size: 9px;
  padding: 1px 5px;
}

/* 右侧：模型详情容器 */
.model-detail-panel {
  display: flex;
  flex-direction: column;
  gap: 14px;
  padding-right: 4px;
}
.model-detail-panel.empty {
  align-items: center;
  justify-content: center;
  min-height: 300px;
}

/* 模型头部：名称 + 3 个状态图标 */
.model-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 12px;
  padding-bottom: 10px;
  border-bottom: 1px solid var(--border);
  flex-wrap: wrap;
}
.model-header-title {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
  min-width: 0;
  flex: 1 1 auto;
}
.model-name {
  font-family: 'SF Mono', Menlo, Consolas, monospace;
  font-size: 16px;
  font-weight: 700;
  color: var(--text);
  word-break: break-all;
}

/* 3 个状态图标按钮 */
.status-icons {
  display: flex;
  gap: 6px;
  flex-wrap: wrap;
  flex-shrink: 0;
}
.status-icon {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 4px 10px;
  border-radius: 16px;
  font-size: 11px;
  font-weight: 600;
  cursor: pointer;
  border: 1px solid var(--border);
  background: var(--bg-subtle);
  color: var(--muted);
  transition: all 0.12s;
  user-select: none;
  white-space: nowrap;
  font-family: inherit;
}
.status-icon:hover:not(:disabled) {
  color: var(--text);
}
.status-icon:disabled {
  cursor: not-allowed;
  opacity: 0.55;
}
.status-icon-dot {
  display: inline-block;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: currentColor;
  flex-shrink: 0;
}
/* 各状态图标颜色 */
.icon-manual-disable {
  color: var(--danger);
}
.icon-manual-enable {
  color: var(--warning);
}
.icon-auto {
  color: var(--success);
}
/* 激活态 (高亮当前选中状态) */
.status-icon.active {
  background: var(--card);
  box-shadow: 0 0 0 2px currentColor;
}
.icon-manual-disable.active { background: rgba(248, 81, 73, 0.12); }
.icon-manual-enable.active { background: rgba(210, 153, 34, 0.12); }
.icon-auto.active          { background: rgba(63, 185, 80, 0.12); }

/* 4 个统计卡片 */
.model-stats-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 8px;
}
.stat-card {
  padding: 10px 12px;
  background: var(--bg-subtle);
  border: 1px solid var(--border);
  border-radius: 6px;
  display: flex;
  flex-direction: column;
  gap: 4px;
  min-width: 0;
}
.stat-card .label {
  font-size: 10px;
  color: var(--muted);
  text-transform: uppercase;
  letter-spacing: 0.04em;
  font-weight: 600;
}
.stat-card > span:not(.label) {
  font-size: 14px;
  font-weight: 700;
  color: var(--text);
}

/* 滑动窗口 spark bars */
.spark-bar-row {
  display: flex;
  gap: 2px;
  overflow-x: auto;
  padding: 8px 0;
}
.spark-bar {
  width: 4px;
  height: 40px;
  border-radius: 1px;
  flex-shrink: 0;
}
.window-stats {
  display: flex;
  gap: 16px;
  margin-top: 8px;
  font-size: 13px;
  flex-wrap: wrap;
}

@media (max-width: 1100px) {
  .models-tab-grid {
    grid-template-columns: 220px 1fr;
  }
  .model-stats-grid {
    grid-template-columns: repeat(2, 1fr);
  }
}
</style>
