<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import MemoraStatusButton from '../components/MemoraStatusButton.vue'
import TenantDashboardView from './TenantDashboardView.vue'
import {
  getUsageSummary,
  getUsageByModel,
  getDashboardOverview,
  getHotApiKeys,
  getModelDiscoveryStatus,
  getHealth,
  getRecentModelFailures,
  getCompressionStats,
  type UsageSummary,
  type ModelUsage,
  type DashboardOverview,
  type HotApiKeyEntry,
  type ModelDiscoveryStatusResponse,
  type HealthResponse,
  type CompressionStats,
} from '../api'
import { store, isSuperAdmin, isDefaultTenant, getCurrentTenantId } from '../store'
import { useLocale } from '../i18n/useLocale'

const { t } = useI18n()
const { locale } = useLocale() // ensures `t()` re-renders when locale changes

const days    = ref(7)
const summary = ref<UsageSummary | null>(null)
const overview = ref<DashboardOverview | null>(null)
const models  = ref<ModelUsage[]>([])
const hotKeys = ref<HotApiKeyEntry[]>([])
const discoveryStatus = ref<ModelDiscoveryStatusResponse | null>(null)
const recentModelFailures = ref<{ raw_model_name: string; creds_affected: number; total_failures: number; last_failed_at: string; sample_error_code: string }[]>([])
const health = ref<HealthResponse | null>(null)
const compStats = ref<CompressionStats | null>(null)
const loading = ref(false)
const error   = ref('')
let discoveryPollTimer: ReturnType<typeof setInterval> | null = null
let healthPollTimer: ReturnType<typeof setInterval> | null = null
let probeFailuresPollTimer: ReturnType<typeof setInterval> | null = null

// Tenant info display
const tenantLabel = computed(() => {
  const tenantId = getCurrentTenantId()
  const isAdmin = isSuperAdmin()
  const isDefault = isDefaultTenant()

  if (isAdmin && isDefault) {
    return t('dashboard.tenantLabel.default')
  } else if (isDefault) {
    return t('dashboard.tenantLabel.super')
  } else {
    return t('dashboard.tenantLabel.tenant', { tenantId })
  }
})

const showTenantDashboard = computed(() => !isDefaultTenant())

const proxyWarning = computed(() => {
  const p = health.value?.proxy
  if (!p) return null
  if (!p.proxy) return null
  if (p.health_done && p.healthy === false) {
    return {
      proxy: p.proxy,
      detail: t('dashboard.proxyWarning.detail', { proxy: p.proxy }),
    }
  }
  if (!p.health_done) {
    return {
      proxy: p.proxy,
      detail: t('dashboard.proxyWarning.detail', { proxy: p.proxy }) + ' (probing…)',
    }
  }
  return null
})

async function load() {
  loading.value = true
  error.value = ''
  try {
    const [s, m, o, h] = await Promise.all([
      getUsageSummary(days.value),
      getUsageByModel(days.value),
      getDashboardOverview(days.value),
      getHotApiKeys(days.value, 10),
    ])
    summary.value = s
    models.value  = m
    overview.value = o
    hotKeys.value = h
    void loadCompressionStats()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : t('dashboard.loadError')
  } finally {
    loading.value = false
  }
}

async function loadCompressionStats() {
  try { compStats.value = await getCompressionStats({ hours: 24 }) } catch { /* non-blocking */ }
}

function fmt(n: number | undefined, decimals = 0) {
  if (n === undefined || n === null) return '—'
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M'
  if (n >= 1_000)     return (n / 1_000).toFixed(1) + 'K'
  return Number(n).toFixed(decimals)
}

function fmtCost(v: number | undefined) {
  if (v === undefined || v === null) return '—'
  return '$' + Number(v).toFixed(4)
}

function fmtPct(v: number | undefined) {
  if (v === undefined || v === null) return '—'
  return (Number(v) * 100).toFixed(1) + '%'
}

function fmtDate(v: string | null | undefined) {
  if (!v) return '—'
  // locale-aware short date+time (e.g. "7/1/26, 9:04 PM" for en-US, "2026/7/1 21:04" for zh-CN)
  try {
    return new Date(v).toLocaleString(locale.value, { dateStyle: 'short', timeStyle: 'short' })
  } catch {
    return new Date(v).toLocaleString('en-US', { dateStyle: 'short', timeStyle: 'short' })
  }
}

async function loadDiscoveryStatus() {
  try {
    discoveryStatus.value = await getModelDiscoveryStatus()
  } catch {
    /* non-blocking */
  }
}

async function loadHealth() {
  try {
    health.value = await getHealth()
  } catch {
    /* non-blocking */
  }
}

async function loadRecentProbeFailures() {
  try {
    const r = await getRecentModelFailures({ limit: 10 })
    recentModelFailures.value = r.models
  } catch {
    /* non-blocking */
  }
}

function scheduleDiscoveryPoll() {
  if (discoveryPollTimer) clearInterval(discoveryPollTimer)
  discoveryPollTimer = setInterval(() => {
    void loadDiscoveryStatus()
  }, 15000)
}

function scheduleHealthPoll() {
  if (healthPollTimer) clearInterval(healthPollTimer)
  healthPollTimer = setInterval(() => { void loadHealth() }, 30000)
}

onMounted(() => {
  void load()
  void loadDiscoveryStatus()
  void loadHealth()
  void loadRecentProbeFailures()
  scheduleDiscoveryPoll()
  scheduleHealthPoll()
  scheduleProbeFailuresPoll()
})

onUnmounted(() => {
  if (discoveryPollTimer) clearInterval(discoveryPollTimer)
  if (healthPollTimer) clearInterval(healthPollTimer)
  if (probeFailuresPollTimer) clearInterval(probeFailuresPollTimer)
})

function scheduleProbeFailuresPoll() {
  if (probeFailuresPollTimer) clearInterval(probeFailuresPollTimer)
  probeFailuresPollTimer = setInterval(() => {
    void loadRecentProbeFailures()
  }, 30000) // 30s — cheap endpoint
}
</script>

<template>
  <TenantDashboardView v-if="showTenantDashboard" />
  <div v-else>
    <div class="page-header">
      <div class="page-header-title">
        <h2>{{ t('dashboard.title') }}</h2>
        <MemoraStatusButton />
      </div>
      <div class="page-header-actions">
        <span class="tenant-badge" :class="{ 'tenant-badge--admin': isSuperAdmin(), 'tenant-badge--default': isDefaultTenant() }">
          {{ tenantLabel }}
        </span>
        <select v-model.number="days" style="width:100px" @change="load">
          <option :value="1">{{ t('dashboard.range.today') }}</option>
          <option :value="7">{{ t('dashboard.range.last7d') }}</option>
          <option :value="30">{{ t('dashboard.range.last30d') }}</option>
          <option :value="90">{{ t('dashboard.range.last90d') }}</option>
        </select>
        <button class="btn btn-ghost btn-sm" @click="load" :disabled="loading">{{ t('dashboard.refresh') }}</button>
      </div>
    </div>

    <div v-if="error" class="alert alert-danger">{{ error }}</div>

    <div
      v-if="proxyWarning"
      class="proxy-warning-banner"
    >
      <strong>{{ t('dashboard.proxyWarning.title') }}</strong>
      <span>{{ t('dashboard.proxyWarning.detail', { proxy: proxyWarning.proxy }) }}</span>
      <span class="proxy-warning-hint">{{ t('dashboard.proxyWarning.hint') }}</span>
    </div>

    <div
      v-if="discoveryStatus?.running"
      class="background-tasks-banner background-tasks-banner--active"
    >
      <strong>{{ t('dashboard.backgroundTasks.title') }}</strong>
      <span>{{ t('dashboard.backgroundTasks.running', { trigger: discoveryStatus.running.trigger }) }}</span>
      <span>{{ t('dashboard.backgroundTasks.startedAt', { time: fmtDate(discoveryStatus.running.started_at) }) }}</span>
      <span>{{ t('dashboard.backgroundTasks.heartbeat', { time: fmtDate(discoveryStatus.running.heartbeat_at) }) }}</span>
      <span class="background-tasks-hint">{{ t('dashboard.backgroundTasks.slow') }}</span>
      <RouterLink to="/models">{{ t('dashboard.backgroundTasks.detailsLink') }}</RouterLink>
    </div>
    <div
      v-else-if="discoveryStatus?.latest"
      class="background-tasks-banner"
    >
      <span>{{ t('dashboard.discovery.latest') }}{{ discoveryStatus.latest.status }}</span>
      <span>{{ fmtDate(discoveryStatus.latest.finished_at || discoveryStatus.latest.started_at) }}</span>
      <RouterLink to="/models">{{ t('nav.item.modelsCatalog') }}</RouterLink>
    </div>

    <!-- 模型发现 · 最近测试失败计数（spec 2026-06-18-model-probe-rounds） -->
    <div
      v-if="recentModelFailures.length > 0"
      class="probe-failures-banner"
    >
      <strong>{{ t('dashboard.discovery.failuresTitle') }}</strong>
      <span class="probe-failures-count">
        {{ t('dashboard.discovery.failuresTally', {
          n: recentModelFailures.reduce((s, m) => s + m.total_failures, 0),
          m: recentModelFailures.length,
        }) }}
      </span>
      <details class="probe-failures-details">
        <summary>{{ t('dashboard.discovery.summary') }}</summary>
        <ul>
          <li v-for="m in recentModelFailures" :key="m.raw_model_name">
            <code class="mono-sm">{{ m.raw_model_name }}</code>
            <span class="probe-failures-meta">
              {{ t('dashboard.discovery.meta', {
                n: m.total_failures,
                m: m.creds_affected,
                date: fmtDate(m.last_failed_at),
                code: m.sample_error_code || '—',
              }) }}
            </span>
          </li>
        </ul>
      </details>
      <RouterLink to="/routing-v2?tab=resolve&row=model">{{ t('nav.item.routingOverview') }}</RouterLink>
    </div>

    <div class="stat-grid" v-if="summary && overview">
      <div class="stat-card">
        <div class="label">{{ t('dashboard.stat.totalRequests') }}</div>
        <div class="value">{{ fmt(summary.total_requests) }}</div>
        <div class="sub">{{ t('dashboard.stat.inLastDays', { days }) }}</div>
      </div>
      <div class="stat-card">
        <div class="label">{{ t('dashboard.stat.totalTokens') }}</div>
        <div class="value">{{ fmt((summary.total_prompt_tokens ?? 0) + (summary.total_completion_tokens ?? 0)) }}</div>
        <div class="sub">
          {{ t('dashboard.stat.prompt', { n: fmt(summary.total_prompt_tokens) }) }} ·
          {{ t('dashboard.stat.completion', { n: fmt(summary.total_completion_tokens) }) }}
        </div>
      </div>
      <div class="stat-card">
        <div class="label">{{ t('dashboard.stat.totalCost') }}</div>
        <div class="value">{{ fmtCost(summary.total_cost_usd) }}</div>
        <div class="sub">{{ t('dashboard.stat.costUnit') }}</div>
      </div>
      <div class="stat-card">
        <div class="label">{{ t('dashboard.stat.successRate') }}</div>
        <div class="value" :style="{ color: (summary.success_rate ?? 1) > 0.95 ? 'var(--success)' : 'var(--warning)' }">
          {{ fmtPct(summary.success_rate) }}
        </div>
        <div class="sub">
          {{ t('dashboard.stat.avgLatency', { n: fmt(summary.avg_latency_ms) }) }}
          <RouterLink
            v-if="(summary.success_rate ?? 1) < 0.95"
            :to="{ path: '/request-logs', query: { success: 'failure', hours: String(days * 24) } }"
            class="dashboard-fail-link"
          >{{ t('dashboard.viewFailedRequests') }}</RouterLink>
        </div>
      </div>
      <div class="stat-card">
        <div class="label">{{ t('dashboard.stat.apiKeys') }}</div>
        <div class="value">{{ fmt(overview.total_api_keys) }}</div>
        <div class="sub">
          {{ t('dashboard.stat.enabledActive', {
            enabled: fmt(overview.active_api_keys),
            active: fmt(overview.active_api_keys_in_window),
          }) }}
        </div>
      </div>
      <div class="stat-card">
        <div class="label">{{ t('dashboard.stat.models') }}</div>
        <div class="value">{{ fmt(overview.total_models) }}</div>
        <div class="sub">
          {{ t('dashboard.stat.activeInDays', {
            days,
            n: fmt(overview.active_models_in_window),
          }) }}
        </div>
      </div>
      <div class="stat-card">
        <div class="label">{{ t('dashboard.stat.providers') }}</div>
        <div class="value">{{ fmt(overview.total_providers) }}</div>
        <div class="sub">
          {{ t('dashboard.stat.enabledCredentials', {
            enabled: fmt(overview.active_providers),
            total: fmt(overview.total_credentials),
          }) }}
        </div>
      </div>
      <div class="stat-card">
        <div class="label">{{ t('dashboard.stat.offline') }}</div>
        <div class="value">{{ fmt((overview.offline_models ?? 0) + (overview.offline_credentials ?? 0)) }}</div>
        <div class="sub">
          {{ t('dashboard.stat.modelsCredentials', {
            models: fmt(overview.offline_models),
            creds: fmt(overview.offline_credentials),
          }) }}
        </div>
      </div>
      <!-- v3 压缩统计卡 (2026-06-20 P2) -->
      <div class="stat-card" v-if="compStats">
        <div class="label">
          {{ t('dashboard.compression.title') }}
          <span class="badge ml-4 fs-9">24h</span>
        </div>
        <div class="value">
          {{ compStats.compressed_total }}
          <span style="font-size:12px;color:var(--text-secondary,#6b7280)">/ {{ compStats.total_requests }}</span>
        </div>
        <div class="sub">
          <span v-if="compStats.strategy_distribution['delta_append']">{{ t('dashboard.compression.delta') }} {{ compStats.strategy_distribution['delta_append'] }} ·</span>
          <span v-if="compStats.strategy_distribution['sliding_window_token'] || compStats.strategy_distribution['sliding_window_count']">
            {{ t('dashboard.compression.sliding') }} {{ (compStats.strategy_distribution['sliding_window_token']||0)+(compStats.strategy_distribution['sliding_window_count']||0) }} ·
          </span>
          <span v-if="compStats.strategy_distribution['delta_append'] || compStats.strategy_distribution['sliding_window_token']" style="color:var(--success,#22c55e)">
            {{ t('dashboard.compression.outboundTokens', { n: compStats.total_outbound_tokens ? fmt(compStats.total_outbound_tokens) : '—' }) }}
          </span>
        </div>
      </div>
    </div>
    <div class="stat-grid" v-else-if="loading">
      <div class="stat-card" v-for="i in 9" :key="i">
        <div class="label" style="background:var(--border);height:12px;width:80px;border-radius:4px"></div>
        <div class="value" style="background:var(--border);height:32px;width:60px;border-radius:4px;margin-top:8px"></div>
      </div>
    </div>

    <div class="card" style="margin-top:20px" v-if="hotKeys.length > 0 || loading">
      <div style="font-size:14px;font-weight:600;margin-bottom:12px">{{ t('dashboard.table.hotKeysTitle') }}</div>
      <div v-if="loading" class="empty">{{ t('dashboard.loading') }}</div>
      <table v-else>
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
            <td><code style="font-size:12px">{{ k.key_prefix ?? '—' }}***</code></td>
            <td>{{ k.application_code ?? '—' }}</td>
            <td>{{ k.owner_user ?? '—' }}</td>
            <td class="text-end">{{ fmt(k.request_count) }}</td>
            <td class="text-end">{{ fmt(k.total_tokens) }}</td>
            <td class="text-end">{{ fmtCost(k.total_cost_usd) }}</td>
            <td>{{ fmtDate(k.last_used_at) }}</td>
          </tr>
        </tbody>
      </table>
      <div v-if="!loading && hotKeys.length === 0" class="empty">{{ t('dashboard.noData') }}</div>
    </div>

    <div class="card" style="margin-top:20px" v-if="models.length > 0 || loading">
      <div style="font-size:14px;font-weight:600;margin-bottom:12px">{{ t('dashboard.table.byModelTitle') }}</div>
      <div v-if="loading" class="empty">{{ t('dashboard.loading') }}</div>
      <table v-else>
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
            <td><code style="font-size:12px">{{ m.model }}</code></td>
            <td><span class="badge badge-blue">{{ m.provider_code }}</span></td>
            <td class="text-end">{{ fmt(m.total_requests) }}</td>
            <td class="text-end">{{ fmt(m.total_tokens) }}</td>
            <td class="text-end">{{ fmtCost(m.total_cost_usd) }}</td>
          </tr>
        </tbody>
      </table>
      <div v-if="!loading && models.length === 0" class="empty">{{ t('dashboard.noData') }}</div>
    </div>
    <div v-if="!loading && !error && (!summary || summary.total_requests === 0)" class="empty" style="margin-top:40px">
      <span v-html="t('dashboard.empty.firstUse')"></span>
    </div>
  </div>
</template>

<style scoped>
.stat-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  gap: 16px;
}

.text-end {
  text-align: end;
}

.tenant-badge {
  display: inline-flex;
  align-items: center;
  padding: 4px 10px;
  border-radius: 12px;
  font-size: 12px;
  font-weight: 500;
  background: var(--surface-secondary, #f3f4f6);
  color: var(--text-secondary, #6b7280);
}

.tenant-badge--admin {
  background: rgba(59, 130, 246, 0.1);
  color: #3b82f6;
}

.tenant-badge--default {
  background: rgba(34, 197, 94, 0.1);
  color: #22c55e;
}

.proxy-warning-banner {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 12px 16px;
  padding: 10px 14px;
  margin-bottom: 16px;
  border-radius: var(--radius);
  font-size: 13px;
  background: rgba(248, 81, 73, 0.10);
  border: 1px solid rgba(248, 81, 73, 0.45);
  color: var(--text);
}
.proxy-warning-banner strong {
  color: var(--danger);
}
.proxy-warning-banner code {
  background: rgba(0, 0, 0, 0.25);
  padding: 1px 6px;
  border-radius: 4px;
  font-size: 12px;
}
.proxy-warning-hint {
  color: var(--muted);
  font-size: 12px;
  font-style: italic;
}

.dashboard-fail-link {
  display: inline-block;
  margin-inline-start: 8px;
  font-size: 12px;
  color: var(--warning);
  text-decoration: underline;
}
.dashboard-fail-link:hover {
  color: var(--accent);
}

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

/* Model probe failures (spec 2026-06-18-model-probe-rounds) */
.probe-failures-banner {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px 16px;
  padding: 10px 14px;
  margin-bottom: 16px;
  border-radius: var(--radius);
  font-size: 13px;
  background: rgba(215, 58, 73, 0.06);
  border: 1px solid rgba(215, 58, 73, 0.30);
  color: var(--text);
}
.probe-failures-banner strong {
  color: var(--danger);
}
.probe-failures-count {
  color: var(--text-secondary, #6b7280);
  font-variant-numeric: tabular-nums;
}
.probe-failures-details {
  flex: 1 1 100%;
  margin-top: 4px;
}
.probe-failures-details summary {
  cursor: pointer;
  color: var(--accent);
  font-size: 12px;
  user-select: none;
}
.probe-failures-details ul {
  margin: 8px 0 0;
  padding: 0 0 0 16px;
  list-style: disc;
  max-height: 240px;
  overflow-y: auto;
  font-size: 12px;
}
.probe-failures-details li {
  margin: 2px 0;
  display: flex;
  gap: 8px;
  align-items: baseline;
}
.probe-failures-meta {
  color: var(--text-secondary, #6b7280);
  font-size: 11px;
}
</style>
