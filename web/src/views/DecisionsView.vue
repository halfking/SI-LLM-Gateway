<script setup lang="ts">
import { ref, watch, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { getDecisions, type RoutingDecision } from '../api'
import ModelPicker from '../components/ModelPicker.vue'
import { useFormat } from '../i18n/useFormat'

const { t } = useI18n()
const { fmtTime, fmtNumber } = useFormat()
// Short alias for the decisions locale namespace.
const dz = (k: string, params?: Record<string, unknown>): string =>
  t(`decisions.${k}` as never, params as never)

const rows = ref<RoutingDecision[]>([])
const loading = ref(false)
const error = ref<string | null>(null)
const sinceMinutes = ref(30)
const filterModel = ref('')
const filterSuccess = ref<'' | 'true' | 'false'>('')
const limit = ref(50)
const offset = ref(0)
const total = ref(0)
const autoRefresh = ref(true)

// Detail panel
const selectedRow = ref<RoutingDecision | null>(null)

function openDetail(row: RoutingDecision) {
  selectedRow.value = row
}
function closeDetail() {
  selectedRow.value = null
}

let timer: ReturnType<typeof setInterval> | null = null

function startAutoRefresh() {
  stopAutoRefresh()
  if (autoRefresh.value) {
    timer = setInterval(load, 5000)
  }
}

function stopAutoRefresh() {
  if (timer) {
    clearInterval(timer)
    timer = null
  }
}

watch(autoRefresh, (newVal) => {
  if (newVal) {
    startAutoRefresh()
  } else {
    stopAutoRefresh()
  }
})

async function load() {
  loading.value = true
  error.value = null
  try {
    const params: Record<string, unknown> = {
      since_minutes: sinceMinutes.value,
      limit: limit.value,
    }
    if (filterModel.value.trim()) params.model = filterModel.value.trim()
    if (filterSuccess.value !== '') params.success = filterSuccess.value === 'true'
    params.offset = offset.value
    const resp = await getDecisions(params)
    rows.value = resp.decisions
    total.value = resp.total
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : String(e)
  } finally {
    loading.value = false
  }
}

function fmtTs(ts: string) {
  return fmtTime(ts)
}

function traceList(v: unknown): string {
  if (!Array.isArray(v) || !v.length) return dz('value.dash')
  return v
    .map((item) => {
      if (!item || typeof item !== 'object') return String(item)
      const row = item as Record<string, unknown>
      const provider = row.provider_id ?? dz('value.dash')
      const credential = row.credential_id ?? dz('value.dash')
      const reason = row.reason ?? row.raw_model ?? ''
      return `p${provider}/c${credential} ${reason}`.trim()
    })
    .join(' | ')
}

function resetAndLoad() {
  offset.value = 0
  load()
}

onMounted(() => {
  load()
  startAutoRefresh()
})
onUnmounted(() => {
  stopAutoRefresh()
})
</script>

<template>
  <div>
    <div class="page-header" style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px">
      <h2 style="margin:0">{{ dz('page.title') }}</h2>
      <label style="display:flex;align-items:center;gap:6px;font-size:12px;color:var(--muted);cursor:pointer;user-select:none">
        <input type="checkbox" v-model="autoRefresh" style="cursor:pointer;margin:0">
        <span>{{ dz('page.autoRefresh') }}</span>
      </label>
    </div>

    <div class="compact-filter-bar compact-filter-bar--stacked">
      <div class="cf-row">
        <select v-model="filterSuccess" class="cf-select cf-status" :title="dz('filter.status')" @change="resetAndLoad">
          <option value="">{{ dz('filter.statusAll') }}</option>
          <option value="true">{{ dz('filter.statusSuccess') }}</option>
          <option value="false">{{ dz('filter.statusFail') }}</option>
        </select>
        <select v-model="sinceMinutes" class="cf-select cf-hours" :title="dz('filter.timeRange')" @change="resetAndLoad">
          <option :value="10">{{ dz('filter.range10m') }}</option>
          <option :value="30">{{ dz('filter.range30m') }}</option>
          <option :value="60">{{ dz('filter.range1h') }}</option>
          <option :value="360">{{ dz('filter.range6h') }}</option>
          <option :value="1440">{{ dz('filter.range24h') }}</option>
        </select>
        <select v-model="limit" class="cf-select" style="width:72px" :title="dz('filter.count')" @change="resetAndLoad">
          <option :value="20">{{ dz('filter.count20') }}</option>
          <option :value="50">{{ dz('filter.count50') }}</option>
          <option :value="100">{{ dz('filter.count100') }}</option>
          <option :value="200">{{ dz('filter.count200') }}</option>
        </select>
        <button class="btn btn-ghost btn-sm" @click="load">{{ dz('filter.refresh') }}</button>
        <span class="cf-meta">{{ dz('pagination.totalShort', { n: total }) }}</span>
      </div>
      <div class="cf-row cf-row--secondary">
        <div class="cf-field cf-field--grow">
          <span class="cf-label">{{ dz('filter.modelLabel') }}</span>
          <div class="decisions-model-picker">
            <ModelPicker
              v-model="filterModel"
              :placeholder="dz('filter.modelPlaceholder')"
              :title="dz('filter.modelTitle')"
              @update:model-value="resetAndLoad"
            />
          </div>
        </div>
      </div>
    </div>

    <div v-if="error" class="error-banner">{{ error }}</div>

    <!-- Top Pagination -->
    <div v-if="total > 0" class="card" style="margin-bottom:12px;display:flex;justify-content:space-between;align-items:center;font-size:13px">
      <div style="color:var(--muted)">
        {{ dz('pagination.total', { total: total, start: offset + 1, end: Math.min(offset + limit, total) }) }}
      </div>
      <div style="display:flex;gap:8px;align-items:center">
        <button class="btn btn-ghost btn-sm" :disabled="offset === 0" @click="offset = Math.max(0, offset - limit); load()">{{ dz('pagination.previous') }}</button>
        <button class="btn btn-ghost btn-sm" :disabled="offset + limit >= total" @click="offset = offset + limit; load()">{{ dz('pagination.next') }}</button>
      </div>
    </div>

    <div class="card" style="overflow:auto">
      <table class="data-table" style="min-width:1500px">
        <thead>
          <tr>
            <th>{{ dz('table.time') }}</th>
            <th>{{ dz('table.status') }}</th>
            <th>{{ dz('table.model') }}</th>
            <th>{{ dz('table.resolution') }}</th>
            <th>{{ dz('table.tier') }}</th>
            <th>{{ dz('table.latency') }}</th>
            <th>{{ dz('table.provider') }}</th>
            <th>{{ dz('table.outbound') }}</th>
            <th>{{ dz('table.promptT') }}</th>
            <th>{{ dz('table.compT') }}</th>
            <th>{{ dz('table.cost') }}</th>
            <th>{{ dz('table.candidates') }}</th>
            <th>{{ dz('table.blocked') }}</th>
            <th>{{ dz('table.error') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="!rows.length && !loading">
            <td colspan="13" style="text-align:center;padding:32px;color:var(--muted)">
              {{ dz('page.empty') }}
            </td>
          </tr>
          <tr v-for="r in rows" :key="r.request_id + r.ts" :class="{ 'row-fail': !r.success }" class="row-clickable" @click="openDetail(r)">
            <td style="white-space:nowrap;font-size:12px">{{ fmtTs(r.ts) }}</td>
            <td>
              <span :class="r.success ? 'badge-ok' : 'badge-err'">
                {{ r.success ? '✓' : '✗' }}
              </span>
            </td>
            <td style="font-size:12px;max-width:160px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">{{ r.model }}</td>
            <td style="font-size:11px;max-width:220px;overflow:hidden;text-overflow:ellipsis">
              <div>{{ r.resolution_path ?? dz('table.dash') }} / {{ r.canonical_model ?? dz('table.dash') }}</div>
              <div style="color:var(--muted)">{{ (r.resolution_raw_models || []).join(', ') || dz('table.dash') }}</div>
            </td>
            <td style="text-align:center">{{ r.tier ?? dz('table.dash') }}</td>
            <td style="text-align:right">{{ r.latency_ms != null ? r.latency_ms + dz('table.msUnit') : dz('table.dash') }}</td>
            <td style="font-size:12px">{{ r.chosen_provider_id ?? dz('table.dash') }}</td>
            <td style="font-size:12px;max-width:160px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">{{ r.outbound_model ?? dz('table.dash') }}</td>
            <td style="text-align:right">{{ r.prompt_tokens ?? dz('table.dash') }}</td>
            <td style="text-align:right">{{ r.completion_tokens ?? dz('table.dash') }}</td>
            <td style="text-align:right;font-size:12px">
              {{ r.cost_usd != null ? dz('table.costUnit') + Number(r.cost_usd).toFixed(5) : dz('table.dash') }}
            </td>
            <td style="font-size:11px;max-width:260px;overflow:hidden;text-overflow:ellipsis">
              {{ traceList((r.decision_trace || {}).planned_candidates) }}
            </td>
            <td style="font-size:11px;max-width:260px;overflow:hidden;text-overflow:ellipsis;color:var(--warning)">
              {{ traceList((r.decision_trace || {}).blocked_candidates) }}
            </td>
            <td style="font-size:11px;color:var(--danger);max-width:140px;overflow:hidden;text-overflow:ellipsis">
              {{ r.failure_detail_code ?? r.error_class ?? '' }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <div v-if="loading" style="text-align:center;padding:8px;font-size:12px;color:var(--muted)">{{ dz('page.loading') }}</div>

    <!-- Pagination -->
    <div v-if="total > 0" class="card" style="margin-top:12px;display:flex;justify-content:space-between;align-items:center;font-size:13px">
      <div style="color:var(--muted)">
        {{ dz('pagination.total', { total: total, start: offset + 1, end: Math.min(offset + limit, total) }) }}
      </div>
      <div style="display:flex;gap:8px;align-items:center">
        <button class="btn btn-ghost btn-sm" :disabled="offset === 0" @click="offset = Math.max(0, offset - limit); load()">{{ dz('pagination.previous') }}</button>
        <button class="btn btn-ghost btn-sm" :disabled="offset + limit >= total" @click="offset = offset + limit; load()">{{ dz('pagination.next') }}</button>
      </div>
    </div>

    <!-- Row detail modal -->
    <Teleport to="body">
      <div v-if="selectedRow" class="drawer-backdrop" @click="closeDetail">
        <div class="drawer-panel card" @click.stop>
          <div class="drawer-header">
            <span style="font-size:14px;font-weight:600">{{ dz('detail.title') }}</span>
            <button class="btn btn-ghost btn-sm" @click="closeDetail">{{ dz('detail.closeBtn') }}</button>
          </div>
          <div class="detail-body">

            <!-- Basic -->
            <div class="drawer-section">
              <div class="drawer-section-title">{{ dz('detail.sections.basic') }}</div>
              <div class="detail-grid">
                <span class="dk">{{ dz('detail.keys.time') }}</span><span class="dv">{{ selectedRow.ts }}</span>
                <span class="dk">{{ dz('detail.keys.requestId') }}</span><span class="dv mono">{{ selectedRow.request_id }}</span>
                <span class="dk">{{ dz('detail.keys.idempotency') }}</span><span class="dv mono">{{ selectedRow.idempotency_key ?? dz('table.dash') }}</span>
                <span class="dk">{{ dz('detail.keys.tenant') }}</span><span class="dv mono">{{ selectedRow.tenant_id }}</span>
                <span class="dk">{{ dz('detail.keys.status') }}</span>
                <span class="dv">
                  <span :class="selectedRow.success ? 'badge-ok' : 'badge-err'">
                    {{ selectedRow.success ? dz('detail.successOk') : dz('detail.successFail') }}
                  </span>
                </span>
                <span class="dk">{{ dz('detail.keys.latency') }}</span><span class="dv">{{ selectedRow.latency_ms != null ? selectedRow.latency_ms + dz('detail.keys.latencyUnit') : dz('table.dash') }}</span>
                <span class="dk">{{ dz('detail.keys.clientModel') }}</span><span class="dv mono">{{ selectedRow.client_model ?? selectedRow.model }}</span>
                <span class="dk">{{ dz('detail.keys.outbound') }}</span><span class="dv mono">{{ selectedRow.outbound_model ?? dz('table.dash') }}</span>
                <span class="dk">{{ dz('detail.keys.requestMode') }}</span><span class="dv">{{ selectedRow.request_mode ?? dz('table.dash') }}</span>
                <span class="dk">{{ dz('detail.keys.protocol') }}</span><span class="dv">{{ selectedRow.egress_protocol ?? dz('table.dash') }}</span>
                <span class="dk">{{ dz('detail.keys.stickyHit') }}</span><span class="dv">{{ selectedRow.sticky_hit ? dz('detail.stickyHitOk') : dz('detail.stickyHitNo') }}</span>
              </div>
            </div>

            <!-- Resolution -->
            <div class="drawer-section">
              <div class="drawer-section-title">{{ dz('detail.sections.resolution') }}</div>
              <div class="detail-grid">
                <span class="dk">{{ dz('detail.keys.resolutionPath') }}</span><span class="dv mono">{{ selectedRow.resolution_path ?? dz('table.dash') }}</span>
                <span class="dk">{{ dz('detail.keys.canonicalModel') }}</span><span class="dv mono">{{ selectedRow.canonical_model ?? dz('table.dash') }}</span>
                <span class="dk">{{ dz('detail.keys.rawModels') }}</span>
                <span class="dv mono">{{ (selectedRow.resolution_raw_models || []).join(', ') || dz('table.dash') }}</span>
                <span class="dk">{{ dz('detail.keys.clientProfile') }}</span><span class="dv">{{ selectedRow.client_profile ?? dz('table.dash') }}</span>
                <span class="dk">{{ dz('detail.keys.transformRule') }}</span><span class="dv mono">{{ selectedRow.transform_rule_id ?? dz('table.dash') }}</span>
              </div>
            </div>

            <!-- Routing -->
            <div class="drawer-section">
              <div class="drawer-section-title">{{ dz('detail.sections.routing') }}</div>
              <div class="detail-grid">
                <span class="dk">{{ dz('detail.keys.providerId') }}</span><span class="dv">{{ selectedRow.chosen_provider_id ?? dz('table.dash') }}</span>
                <span class="dk">{{ dz('detail.keys.credentialId') }}</span><span class="dv">{{ selectedRow.chosen_credential_id ?? dz('table.dash') }}</span>
                <span class="dk">{{ dz('detail.keys.tier') }}</span><span class="dv">{{ selectedRow.tier ?? dz('table.dash') }}</span>
                <span class="dk">{{ dz('detail.keys.candidatesTried') }}</span><span class="dv">{{ selectedRow.candidates_tried }}</span>
              </div>
            </div>

            <!-- Tokens & Cost -->
            <div class="drawer-section">
              <div class="drawer-section-title">{{ dz('detail.sections.tokens') }}</div>
              <div class="detail-grid">
                <span class="dk">{{ dz('detail.keys.promptTokens') }}</span><span class="dv">{{ selectedRow.prompt_tokens ?? dz('table.dash') }}</span>
                <span class="dk">{{ dz('detail.keys.completionTokens') }}</span><span class="dv">{{ selectedRow.completion_tokens ?? dz('table.dash') }}</span>
                <span class="dk">{{ dz('detail.keys.costUsd') }}</span>
                <span class="dv">{{ selectedRow.cost_usd != null ? dz('table.costUnit') + Number(selectedRow.cost_usd).toFixed(6) : dz('table.dash') }}</span>
                <span class="dk">{{ dz('detail.keys.requestBytes') }}</span><span class="dv">{{ selectedRow.request_bytes != null ? selectedRow.request_bytes + dz('detail.keys.bytesUnit') : dz('table.dash') }}</span>
                <span class="dk">{{ dz('detail.keys.responseBytes') }}</span><span class="dv">{{ selectedRow.response_bytes != null ? selectedRow.response_bytes + dz('detail.keys.bytesUnit') : dz('table.dash') }}</span>
              </div>
            </div>

            <!-- Error -->
            <div v-if="!selectedRow.success" class="drawer-section">
              <div class="drawer-section-title" style="color:var(--danger)">{{ dz('detail.sections.error') }}</div>
              <div class="detail-grid">
                <span class="dk">{{ dz('detail.keys.errorClass') }}</span><span class="dv" style="color:var(--danger)">{{ selectedRow.error_class ?? dz('table.dash') }}</span>
                <span class="dk">{{ dz('detail.keys.failureStage') }}</span><span class="dv">{{ selectedRow.failure_stage ?? dz('table.dash') }}</span>
                <span class="dk">{{ dz('detail.keys.failureCode') }}</span><span class="dv mono">{{ selectedRow.failure_detail_code ?? dz('table.dash') }}</span>
              </div>
            </div>

            <!-- Decision Trace -->
            <div class="drawer-section">
              <div class="drawer-section-title">{{ dz('detail.sections.trace') }}</div>
              <pre class="trace-json">{{ JSON.stringify(selectedRow.decision_trace, null, 2) }}</pre>
            </div>

          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.data-table { width: 100%; border-collapse: collapse; }
.data-table th {
  text-align: left;
  padding: 8px 12px;
  font-size: 12px;
  color: var(--muted);
  border-bottom: 1px solid var(--border);
  white-space: nowrap;
}
.data-table td {
  padding: 7px 12px;
  border-bottom: 1px solid var(--border);
  vertical-align: middle;
}
.row-fail td { background: rgba(239,68,68,.05); }
.badge-ok  { color: #22c55e; font-weight: 600; }
.badge-err { color: #ef4444; font-weight: 600; }
.error-banner {
  background: rgba(239,68,68,.15);
  border: 1px solid #ef4444;
  border-radius: 8px;
  padding: 12px 16px;
  color: #ef4444;
  margin-bottom: 16px;
}
.row-clickable { cursor: pointer; }
.row-clickable:hover td { background: rgba(var(--accent-rgb, 99,102,241), .06); }

.detail-body {
  flex: 1;
  overflow-y: auto;
  padding: 16px 20px;
  display: flex;
  flex-direction: column;
  gap: 20px;
}
.drawer-section {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.drawer-section-title {
  font-size: 11px;
  font-weight: 700;
  letter-spacing: .06em;
  text-transform: uppercase;
  color: var(--muted);
  padding-bottom: 4px;
  border-bottom: 1px solid var(--border);
}
.detail-grid {
  display: grid;
  grid-template-columns: 140px 1fr;
  gap: 4px 12px;
  font-size: 13px;
}
.dk {
  color: var(--muted);
  font-size: 12px;
  padding: 2px 0;
  white-space: nowrap;
}
.dv {
  word-break: break-all;
  padding: 2px 0;
}
.mono { font-family: monospace; font-size: 12px; }
.trace-json {
  font-family: monospace;
  font-size: 11px;
  white-space: pre-wrap;
  word-break: break-all;
  background: var(--bg, #13131f);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 12px;
  margin: 0;
  max-height: 320px;
  overflow-y: auto;
  color: var(--text, #cdd6f4);
}
</style>
