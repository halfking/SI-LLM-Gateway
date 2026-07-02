<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import {
  getMaasUsageSummary,
  getMaasWallet,
  getRequestLogs,
  type MaasUsageSummary,
  type MaasWallet,
  type RequestLogRow,
} from '../api'
import { getCurrentTenantId } from '../store'
import { useFormat } from '../i18n/useFormat'

const days = ref(7)
const summary = ref<MaasUsageSummary | null>(null)
const wallet = ref<MaasWallet | null>(null)
const loading = ref(false)
const error = ref('')

const selectedModel = ref<string | null>(null)
const selectedDate = ref<string | null>(null)
const detailRows = ref<RequestLogRow[]>([])
const detailLoading = ref(false)
const detailTitle = ref('')

const { t: td } = useI18n()
const tdash = (k: string, params?: Record<string, unknown>): string => td(`tenants.dashboard.${k}` as never, params as never)
const { fmtNumber, fmtDate, fmtDateTime } = useFormat()

const tenantLabel = computed(() => tdash('tenantLabel', { id: getCurrentTenantId() }))

const activeSubscription = computed(() => wallet.value?.subscription ?? null)

function fmtDateHuman(s: string | undefined) {
  if (!s) return '—'
  return fmtDate(s)
}

function subscriptionPeriod(sub: NonNullable<MaasWallet['subscription']>) {
  return `${fmtDateHuman(sub.period_start)} — ${fmtDateHuman(sub.period_end)}`
}

const maxModelRequests = computed(() => {
  const rows = summary.value?.by_model ?? []
  return Math.max(1, ...rows.map((r) => r.requests))
})

const maxTrendCredits = computed(() => {
  const rows = summary.value?.trend ?? []
  return Math.max(1, ...rows.map((r) => r.credits))
})

const maxTrendRequests = computed(() => {
  const rows = summary.value?.trend ?? []
  return Math.max(1, ...rows.map((r) => r.requests))
})

function creditsDisplay(v: number | null | undefined) {
  if (v == null) return '—'
  return fmtNumber(v)
}

async function load() {
  loading.value = true
  error.value = ''
  selectedModel.value = null
  selectedDate.value = null
  detailRows.value = []
  try {
    const [s, w] = await Promise.all([
      getMaasUsageSummary(days.value, 10),
      getMaasWallet(),
    ])
    summary.value = s
    wallet.value = w
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : tdash('loadFailed')
  } finally {
    loading.value = false
  }
}

function dateRangeForDay(day: string): { from: string; to: string } {
  const start = new Date(day + 'T00:00:00Z')
  const end = new Date(start)
  end.setUTCDate(end.getUTCDate() + 1)
  return { from: start.toISOString(), to: end.toISOString() }
}

async function showModelDetail(model: string) {
  if (selectedModel.value === model) {
    selectedModel.value = null
    detailRows.value = []
    return
  }
  selectedModel.value = model
  selectedDate.value = null
  detailTitle.value = tdash('detailTitleModel', { model })
  detailLoading.value = true
  try {
    const since = new Date()
    since.setUTCDate(since.getUTCDate() - days.value)
    const res = await getRequestLogs({
      model,
      from: since.toISOString(),
      page: 1,
      page_size: 50,
    })
    detailRows.value = res.items ?? []
  } catch (e: unknown) {
    detailRows.value = []
    error.value = e instanceof Error ? e.message : tdash('detailLoadFailed')
  } finally {
    detailLoading.value = false
  }
}

async function showDateDetail(day: string) {
  if (selectedDate.value === day) {
    selectedDate.value = null
    detailRows.value = []
    return
  }
  selectedDate.value = day
  selectedModel.value = null
  detailTitle.value = tdash('detailTitleDay', { day })
  detailLoading.value = true
  try {
    const { from, to } = dateRangeForDay(day)
    const res = await getRequestLogs({ from, to, page: 1, page_size: 50 })
    detailRows.value = res.items ?? []
  } catch (e: unknown) {
    detailRows.value = []
    error.value = e instanceof Error ? e.message : tdash('detailLoadFailed')
  } finally {
    detailLoading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div>
    <div class="page-header">
      <div class="page-header-title">
        <h2>{{ tdash('title') }}</h2>
      </div>
      <div class="page-header-actions">
        <span class="tenant-badge">{{ tenantLabel }}</span>
        <select v-model.number="days" class="days-select" @change="load">
          <option :value="1">{{ tdash('range.today') }}</option>
          <option :value="7">{{ tdash('range.last7d') }}</option>
          <option :value="30">{{ tdash('range.last30d') }}</option>
        </select>
        <button class="btn btn-ghost btn-sm" :disabled="loading" @click="load">{{ tdash('refresh') }}</button>
      </div>
    </div>

    <div v-if="error" class="alert alert-danger">{{ error }}</div>

    <div v-if="wallet" class="subscription-card card">
      <div class="subscription-head">
        <div class="subscription-title">{{ tdash('subscriptionTitle') }}</div>
        <RouterLink to="/tenant/pricing" class="link-sm">{{ tdash('goPricing') }}</RouterLink>
      </div>
      <div v-if="activeSubscription" class="subscription-grid">
        <div class="sub-item">
          <span class="sub-label">{{ tdash('labelPlan') }}</span>
          <span class="sub-value">{{ activeSubscription.plan_name }}</span>
        </div>
        <div class="sub-item">
          <span class="sub-label">{{ tdash('labelPeriod') }}</span>
          <span class="sub-value">{{ subscriptionPeriod(activeSubscription) }}</span>
        </div>
        <div class="sub-item">
          <span class="sub-label">{{ tdash('labelQuotaRemaining') }}</span>
          <span class="sub-value highlight">{{ fmtNumber(wallet.quota_remaining) }} {{ tdash('creditsUnit') }}</span>
        </div>
        <div class="sub-item">
          <span class="sub-label">{{ tdash('labelExpiresAt') }}</span>
          <span class="sub-value">{{ fmtDateHuman(activeSubscription.period_end) }}</span>
        </div>
      </div>
      <div v-else class="subscription-empty">
        {{ tdash('noSubscription') }}
        <RouterLink to="/tenant/pricing">{{ tdash('goPricingLink') }}</RouterLink>
        {{ tdash('noSubscriptionHint') }}
      </div>
    </div>

    <div class="stat-grid" v-if="summary && wallet">
      <div class="stat-card highlight">
        <div class="label">{{ tdash('statCredits') }}</div>
        <div class="value">{{ fmtNumber(summary.total_credits) }}</div>
        <div class="sub">近 {{ days }} 天</div>
      </div>
      <div class="stat-card">
        <div class="label">{{ tdash('statRequests') }}</div>
        <div class="value">{{ fmtNumber(summary.total_requests) }}</div>
        <div class="sub">近 {{ days }} 天</div>
      </div>
      <div class="stat-card">
        <div class="label">{{ tdash('statAvailable') }}</div>
        <div class="value">{{ fmtNumber(wallet.total_available) }}</div>
        <div class="sub">
          {{ tdash('statAvailableSub', { a: fmtNumber(wallet.quota_remaining), b: fmtNumber(wallet.granted_balance), c: fmtNumber(wallet.purchased_balance) }) }}
          <RouterLink to="/tenant/account" class="link-sm">{{ tdash('myAccountLink') }}</RouterLink>
        </div>
      </div>
    </div>
    <div class="stat-grid" v-else-if="loading">
      <div class="stat-card skeleton" v-for="i in 3" :key="i" />
    </div>

    <div class="card chart-card" v-if="summary">
      <div class="card-title">{{ tdash('chartModelTitle') }} <span class="hint">{{ tdash('chartModelHint') }}</span></div>
      <div v-if="!summary.by_model.length" class="empty">{{ tdash('chartModelEmpty') }}</div>
      <div v-else class="bar-chart">
        <button
          v-for="row in summary.by_model"
          :key="row.model"
          type="button"
          class="bar-row"
          :class="{ active: selectedModel === row.model }"
          @click="showModelDetail(row.model)"
        >
          <span class="bar-label" :title="row.model">{{ row.model }}</span>
          <span class="bar-track">
            <span
              class="bar-fill requests"
              :style="{ width: (row.requests / maxModelRequests * 100) + '%' }"
            />
          </span>
          <span class="bar-meta">{{ fmtNumber(row.requests) }} {{ tdash('chartModelUnit') }}</span>
        </button>
      </div>
    </div>

    <div class="card chart-card" v-if="summary">
      <div class="card-title">{{ tdash('chartTrendTitle') }} <span class="hint">{{ tdash('chartTrendHint') }}</span></div>
      <div v-if="!summary.trend.length" class="empty">{{ tdash('chartTrendEmpty') }}</div>
      <div v-else class="trend-grid">
        <div class="trend-section">
          <div class="trend-label">{{ tdash('chartTrendCredits') }}</div>
          <div class="trend-bars">
            <button
              v-for="row in summary.trend"
              :key="'c-' + row.date"
              type="button"
              class="trend-col"
              :class="{ active: selectedDate === row.date }"
              :title="tdash('chartTrendCreditsTip', { date: row.date, n: row.credits })"
              @click="showDateDetail(row.date)"
            >
              <span
                class="trend-bar credits"
                :style="{ height: (row.credits / maxTrendCredits * 100) + '%' }"
              />
              <span class="trend-date">{{ row.date.slice(5) }}</span>
            </button>
          </div>
        </div>
        <div class="trend-section">
          <div class="trend-label">{{ tdash('chartTrendRequests') }}</div>
          <div class="trend-bars">
            <button
              v-for="row in summary.trend"
              :key="'r-' + row.date"
              type="button"
              class="trend-col"
              :class="{ active: selectedDate === row.date }"
              :title="tdash('chartTrendRequestsTip', { date: row.date, n: row.requests })"
              @click="showDateDetail(row.date)"
            >
              <span
                class="trend-bar requests"
                :style="{ height: (row.requests / maxTrendRequests * 100) + '%' }"
              />
              <span class="trend-date">{{ row.date.slice(5) }}</span>
            </button>
          </div>
        </div>
      </div>
    </div>

    <div class="card chart-card" v-if="summary">
      <div class="card-title">{{ tdash('tableModelUsage') }} <span class="hint">{{ tdash('tableModelUsageHint') }}</span></div>
      <table v-if="summary.by_model.length" class="model-table">
        <thead>
          <tr>
            <th>{{ tdash('tableColModel') }}</th>
            <th class="text-end">{{ tdash('tableColRequests') }}</th>
            <th class="text-end">{{ tdash('tableColCredits') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in summary.by_model"
            :key="'tbl-' + row.model"
            class="clickable"
            :class="{ active: selectedModel === row.model }"
            @click="showModelDetail(row.model)"
          >
            <td><code>{{ row.model }}</code></td>
            <td class="num">{{ fmtNumber(row.requests) }}</td>
            <td class="num credits">{{ fmtNumber(row.credits) }}</td>
          </tr>
        </tbody>
      </table>
      <div v-else class="empty">{{ tdash('emptyTable') }}</div>
    </div>

    <div v-if="detailTitle" class="card detail-card">
      <div class="card-title">{{ detailTitle }}</div>
      <div v-if="detailLoading" class="empty">{{ tdash('detailLoading') }}</div>
      <table v-else-if="detailRows.length" class="detail-table">
        <thead>
          <tr>
            <th>{{ tdash('detailColTime') }}</th>
            <th>{{ tdash('detailColModel') }}</th>
            <th>{{ tdash('detailColStatus') }}</th>
            <th class="text-end">{{ tdash('detailColCredits') }}</th>
            <th>{{ tdash('detailColRequestId') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in detailRows" :key="r.request_id">
            <td class="mono">{{ fmtDateTime(r.ts) }}</td>
            <td><code>{{ r.client_model || r.outbound_model || '—' }}</code></td>
            <td>
              <span class="badge" :class="r.success ? 'badge-green' : 'badge-red'">
                {{ r.success ? tdash('statusOk') : tdash('statusFail') }}
              </span>
            </td>
            <td class="num credits">{{ creditsDisplay(r.credits_charged) }}</td>
            <td class="mono">
              <RouterLink :to="{ path: '/request-logs', query: { q: r.request_id } }">
                {{ r.request_id.slice(0, 8) }}…
              </RouterLink>
            </td>
          </tr>
        </tbody>
      </table>
      <div v-else class="empty">{{ tdash('detailEmpty') }}</div>
      <div class="detail-footer">
        <RouterLink :to="'/request-logs'" class="link-sm">{{ tdash('detailFooterLogs') }}</RouterLink>
        <RouterLink :to="'/tenant/usage'" class="link-sm">{{ tdash('detailFooterUsage') }}</RouterLink>
      </div>
    </div>

    <div
      v-if="!loading && summary && summary.total_requests === 0"
      class="empty onboarding"
    >
      {{ tdash('onboarding') }}
      <RouterLink to="/tenant/models">{{ tdash('onboardingModels') }}</RouterLink>
      {{ tdash('onboardingModelsHint') }}
      <RouterLink to="/keys">{{ tdash('onboardingKeys') }}</RouterLink>
      {{ tdash('onboardingKeysHint') }}
    </div>
  </div>
</template>

<style scoped>
.page-header-title {
  display: flex;
  align-items: center;
  gap: 10px;
}
.page-header-actions {
  display: flex;
  gap: 8px;
  align-items: center;
}
.subscription-card {
  margin-bottom: 16px;
  padding: 14px 16px;
}
.subscription-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 12px;
}
.subscription-title {
  font-size: 14px;
  font-weight: 600;
}
.subscription-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
  gap: 12px 20px;
}
.sub-item {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.sub-label {
  font-size: 11px;
  color: var(--muted);
}
.sub-value {
  font-size: 14px;
  font-weight: 600;
}
.sub-value.highlight {
  color: #f59e0b;
  font-family: 'SF Mono', 'Fira Code', monospace;
}
.subscription-empty {
  font-size: 13px;
  color: var(--muted);
}
.days-select {
  width: 100px;
  padding: 4px 8px;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 4px;
  color: var(--text);
  font-size: 13px;
}
.stat-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  gap: 16px;
  margin-bottom: 20px;
}
.stat-card {
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 16px;
}
.stat-card.highlight {
  border-color: rgba(99, 102, 241, 0.4);
  background: rgba(99, 102, 241, 0.06);
}
.stat-card .label {
  font-size: 12px;
  color: var(--muted);
}
.stat-card .value {
  font-size: 28px;
  font-weight: 700;
  margin-top: 4px;
}
.stat-card .sub {
  font-size: 11px;
  color: var(--muted);
  margin-top: 6px;
}
.stat-card.skeleton {
  min-height: 90px;
  background: var(--border);
  opacity: 0.3;
}
.tenant-badge {
  display: inline-flex;
  padding: 4px 10px;
  border-radius: 12px;
  font-size: 12px;
  background: rgba(59, 130, 246, 0.1);
  color: #3b82f6;
}
.card {
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 16px;
  margin-bottom: 16px;
}
.card-title {
  font-size: 14px;
  font-weight: 600;
  margin-bottom: 14px;
}
.card-title .hint {
  font-weight: 400;
  font-size: 12px;
  color: var(--muted);
  margin-inline-start: 8px;
}
.bar-chart {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.bar-row {
  display: grid;
  grid-template-columns: 140px 1fr 72px;
  gap: 10px;
  align-items: center;
  background: none;
  border: 1px solid transparent;
  border-radius: 6px;
  padding: 6px 8px;
  cursor: pointer;
  color: inherit;
  text-align: start;
}
.bar-row:hover,
.bar-row.active {
  background: rgba(99, 102, 241, 0.08);
  border-color: rgba(99, 102, 241, 0.25);
}
.bar-label {
  font-size: 12px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.bar-track {
  height: 10px;
  background: rgba(255, 255, 255, 0.06);
  border-radius: 5px;
  overflow: hidden;
}
.bar-fill {
  display: block;
  height: 100%;
  border-radius: 5px;
}
.bar-fill.requests {
  background: linear-gradient(90deg, #6366f1, #818cf8);
}
.bar-meta {
  font-size: 12px;
  text-align: end;
  color: var(--muted);
}
.model-table {
  width: 100%;
  border-collapse: collapse;
}
.model-table th,
.model-table td {
  padding: 8px 10px;
  border-bottom: 1px solid var(--border);
  font-size: 13px;
}
.model-table tr.clickable {
  cursor: pointer;
}
.model-table tr.clickable:hover,
.model-table tr.active {
  background: rgba(99, 102, 241, 0.06);
}
.num {
  text-align: end;
  font-family: 'SF Mono', 'Fira Code', monospace;
}
.num.credits {
  color: #f59e0b;
}
.trend-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 20px;
}
@media (max-width: 800px) {
  .trend-grid { grid-template-columns: 1fr; }
}
.trend-label {
  font-size: 12px;
  color: var(--muted);
  margin-bottom: 8px;
}
.trend-bars {
  display: flex;
  align-items: flex-end;
  gap: 6px;
  height: 120px;
  padding-bottom: 22px;
  position: relative;
}
.trend-col {
  flex: 1;
  min-width: 0;
  height: 100%;
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
  align-items: center;
  background: none;
  border: none;
  cursor: pointer;
  padding: 0 2px;
  position: relative;
}
.trend-col.active .trend-bar {
  opacity: 1;
  box-shadow: 0 0 0 2px rgba(99, 102, 241, 0.5);
}
.trend-bar {
  width: 100%;
  max-width: 28px;
  min-height: 2px;
  border-radius: 3px 3px 0 0;
  opacity: 0.85;
}
.trend-bar.credits {
  background: linear-gradient(180deg, #f59e0b, #d97706);
}
.trend-bar.requests {
  background: linear-gradient(180deg, #6366f1, #4f46e5);
}
.trend-date {
  position: absolute;
  bottom: 0;
  font-size: 10px;
  color: var(--muted);
  white-space: nowrap;
}
.detail-card {
  margin-top: 4px;
}
.detail-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
}
.detail-table th,
.detail-table td {
  padding: 8px;
  border-bottom: 1px solid var(--border);
}
.mono {
  font-family: 'SF Mono', 'Fira Code', monospace;
  font-size: 12px;
}
.badge {
  padding: 2px 8px;
  border-radius: 8px;
  font-size: 11px;
}
.badge-green { background: rgba(34,197,94,.15); color: #4ade80; }
.badge-red { background: rgba(239,68,68,.15); color: #f87171; }
.detail-footer {
  display: flex;
  gap: 16px;
  margin-top: 12px;
}
.link-sm {
  font-size: 12px;
  color: var(--accent-h);
}
.empty {
  text-align: center;
  padding: 24px;
  color: var(--muted);
  font-size: 13px;
}
.onboarding {
  margin-top: 24px;
}
.text-end {
  text-align: end;
}
</style>
