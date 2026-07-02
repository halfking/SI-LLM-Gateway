<script setup lang="ts">
import { ref, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import {
  resolveRouting, probeModel,
  getScoreDetails, updateManualPriority,
  type RoutingCandidate, type ProbeResult, type RoutingResolveResponse,
  type ScoreDetail,
} from '../api'
import ModelPicker from '../components/ModelPicker.vue'

const { t } = useI18n()
const rt = (k: string, params?: Record<string, unknown>): string =>
  t(`routing.test.${k}` as never, params as never)

const modelInput  = ref('')
const clientProfile = ref('')
const resolution  = ref<RoutingResolveResponse | null>(null)
const candidates  = ref<RoutingCandidate[]>([])
const resolving   = ref(false)
const resolveErr  = ref('')
const resolved    = ref(false)
const showUnavailable = ref(false)

const probing     = ref(false)
const probeResult = ref<ProbeResult | null>(null)
const probeErr    = ref('')

const scoreDetails = ref<ScoreDetail[]>([])
const loadingScores = ref(false)
const editingPriority = ref<number | null>(null)
const editingValue = ref(99)

const filteredCandidates = computed(() =>
  showUnavailable.value ? candidates.value : candidates.value.filter(c => c.routable)
)

const unavailableCount = computed(() =>
  candidates.value.filter(c => !c.routable).length
)

const compositeScores = computed(() => {
  const map = new Map<number, number>()
  for (const d of scoreDetails.value) {
    map.set(d.credential_id, d.composite_score)
  }
  return map
})

async function onModelPicked(value: string | string[]) {
  const name = typeof value === 'string' ? value.trim() : ''
  if (!name) return
  await selectModel(name)
}

async function selectModel(name: string) {
  modelInput.value = name
  await doResolve()
}

async function doResolve() {
  if (!modelInput.value.trim()) return
  resolving.value = true
  resolveErr.value = ''
  probeResult.value = null
  probeErr.value = ''
  try {
    const res = await resolveRouting(
      modelInput.value.trim(),
      clientProfile.value.trim() || undefined,
    )
    resolution.value = res
    candidates.value = res.candidates
    resolved.value = true
    await loadScoreDetails()
  } catch (e: unknown) {
    resolveErr.value = e instanceof Error ? e.message : rt('resolveFailed')
  } finally {
    resolving.value = false
  }
}

async function loadScoreDetails() {
  if (!modelInput.value.trim()) return
  loadingScores.value = true
  try {
    const res = await getScoreDetails(modelInput.value.trim())
    scoreDetails.value = res.candidates
  } catch (e) {
    console.warn('Failed to load score details:', e)
    scoreDetails.value = []
  } finally {
    loadingScores.value = false
  }
}

async function doProbe() {
  if (!modelInput.value.trim()) return
  probing.value = true
  probeErr.value = ''
  probeResult.value = null
  try {
    probeResult.value = await probeModel(
      modelInput.value.trim(),
      undefined,
      20,
      clientProfile.value.trim() || 'roocode',
    )
  } catch (e: unknown) {
    probeErr.value = e instanceof Error ? e.message : rt('testFailed')
  } finally {
    probing.value = false
  }
}

function startEditPriority(credId: number, current: number) {
  editingPriority.value = credId
  editingValue.value = current
}

async function savePriority(credId: number, modelName: string) {
  if (editingValue.value < 1 || editingValue.value > 99) {
    alert(rt('priorityRangeError'))
    return
  }
  try {
    await updateManualPriority(credId, modelName, editingValue.value)
    editingPriority.value = null
    await loadScoreDetails()
    await doResolve()
  } catch (e: unknown) {
    alert(rt('prioritySaveFailed', { msg: e instanceof Error ? e.message : rt('unknownError') }))
  }
}

function cancelEdit() {
  editingPriority.value = null
}

function getScoreFor(c: RoutingCandidate): number | null {
  if (c.composite_score != null) return c.composite_score
  return compositeScores.value.get(c.credential_id) ?? null
}

function getScoreBreakdown(credId: number): ScoreDetail | null {
  return scoreDetails.value.find(s => s.credential_id === credId) ?? null
}

function latencyLabel(ms: number): string {
  if (ms <= 0) return '—'
  if (ms < 1000) return `${Math.round(ms)}ms`
  return `${(ms / 1000).toFixed(1)}s`
}

function rateLabel(r: number): string {
  return r <= 0 ? '—' : `${(r * 100).toFixed(1)}%`
}

function money(value: number | string | null | undefined, currency = 'USD'): string {
  if (value === null || value === undefined) return '—'
  const n = typeof value === 'string' ? Number(value) : value
  return Number.isNaN(n) ? '—' : `${n.toFixed(4)} ${currency}`
}

function priceLabel(c: RoutingCandidate): string {
  return `${money(c.unit_price_in_per_1m, c.currency || 'USD')} / ${money(c.unit_price_out_per_1m, c.currency || 'USD')}`
}

function quotaLabel(c: RoutingCandidate): string {
  const cap = Number(c.quota_cap_usd || 0)
  const used = Number(c.quota_used_usd || 0)
  if (cap > 0) return `${money(Math.max(0, cap - used), 'USD')} left`
  return money(c.balance_usd, 'USD')
}

function dateWindow(c: RoutingCandidate): string {
  const start = c.effective_at ? c.effective_at.slice(0, 10) : 'now'
  const end = c.expires_at ? c.expires_at.slice(0, 10) : '∞'
  return `${start} → ${end}`
}
</script>

<template>
  <div>
    <div class="page-header">
      <h2>{{ rt('title') }}</h2>
    </div>
    <p style="color:var(--muted);margin-bottom:20px">
      {{ rt('description') }}
    </p>

    <div class="card" style="margin-bottom:20px">
      <div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap">
        <div style="flex:1;min-width:240px">
          <ModelPicker
            v-model="modelInput"
            :placeholder="rt('shared.pickModel')"
            :title="rt('modelPickerTitle')"
            @update:model-value="onModelPicked"
          />
        </div>
        <input
          v-model="clientProfile"
          class="input"
          style="width:160px"
          :placeholder="rt('shared.clientProfilePlaceholder')"
          :title="rt('shared.clientProfileTitle')"
        />
        <button class="btn btn-primary" @click="doResolve" :disabled="resolving || !modelInput.trim()">
          {{ resolving ? rt('querying') : rt('resolve') }}
        </button>
        <button
          class="btn btn-ghost"
          @click="doProbe"
          :disabled="probing || !modelInput.trim()"
          :title="rt('probeTitle')"
        >
          {{ probing ? rt('probing') : rt('probe') }}
        </button>
      </div>
    </div>

    <div v-if="resolveErr" class="alert alert-danger">{{ resolveErr }}</div>

    <div class="card" v-if="resolution" style="margin-bottom:20px">
      <h4 style="margin:0 0 12px">{{ rt('modelResolve') }}</h4>
      <div style="display:flex;gap:20px;flex-wrap:wrap;font-size:13px;align-items:baseline">
        <div><span class="cell-muted">{{ rt('clientModel') }}</span><code>{{ resolution.client_model }}</code></div>
        <div><span class="cell-muted">{{ rt('resolutionPath') }}</span>{{ resolution.resolution_path }}</div>
        <div><span class="cell-muted">{{ rt('canonical') }}</span>{{ resolution.canonical_name || '—' }}</div>
        <div><span class="cell-muted">{{ rt('rawModels') }}</span><code style="font-size:11px">{{ resolution.raw_models.join(', ') }}</code></div>
      </div>
      <div v-if="resolution.plan_order.length" style="margin-top:12px;font-size:12px;color:var(--muted)">
        {{ rt('executionOrder') }}
        <span v-for="(p, i) in resolution.plan_order" :key="p.credential_id">
          {{ i > 0 ? ' → ' : '' }}#{{ p.credential_id }} ({{ p.raw_model }})
        </span>
      </div>
    </div>

    <div class="card" v-if="resolved" style="margin-bottom:20px">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px;flex-wrap:wrap;gap:8px">
        <h4 style="margin:0">{{ rt('candidatesTitle', { model: modelInput }) }}</h4>
        <label v-if="unavailableCount > 0" style="display:flex;align-items:center;gap:6px;font-size:13px;cursor:pointer;color:var(--muted)">
          <input type="checkbox" v-model="showUnavailable" style="width:auto" />
          {{ rt('showUnavailable', { n: unavailableCount }) }}
        </label>
      </div>
      <div v-if="candidates.length === 0" class="alert alert-danger" style="margin:0">
        {{ rt('noCredError') }}
      </div>
      <div v-else-if="filteredCandidates.length === 0 && !showUnavailable" class="alert alert-danger" style="margin:0">
        {{ rt('noAvailableCred', { n: unavailableCount }) }}
      </div>
      <table v-else-if="filteredCandidates.length > 0">
        <thead>
          <tr>
            <th>{{ rt('tableHeaders.0') }}</th>
            <th>{{ rt('tableHeaders.1') }}</th>
            <th>{{ rt('tableHeaders.2') }}</th>
            <th>{{ rt('tableHeaders.3') }}</th>
            <th>{{ rt('tableHeaders.4') }}</th>
            <th>{{ rt('tableHeaders.5') }}</th>
            <th>{{ rt('tableHeaders.6') }}</th>
            <th>{{ rt('tableHeaders.7') }}</th>
            <th>{{ rt('tableHeaders.8') }}</th>
            <th>{{ rt('tableHeaders.9') }}</th>
            <th>{{ rt('tableHeaders.10') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="c in filteredCandidates" :key="c.credential_id" :style="c.routable ? '' : 'opacity:0.55'">
            <td style="text-align:center">
              <span
                class="score-badge"
                :class="getScoreFor(c) === 0 ? 'score-free' : (getScoreFor(c) !== null && getScoreFor(c)! < 20 ? 'score-good' : 'score-normal')"
                :title="getScoreFor(c) === 0 ? rt('scoreTitle') : ''"
              >
                {{ getScoreFor(c) !== null ? getScoreFor(c)!.toFixed(1) : '—' }}
              </span>
              <div v-if="getScoreBreakdown(c.credential_id)" class="cell-muted" style="font-size:10px">
                <span :title="rt('manualPriorityTitle')">P{{ getScoreBreakdown(c.credential_id)!.manual_priority }}</span> ·
                <span :title="rt('costTitle')">C{{ getScoreBreakdown(c.credential_id)!.normalized_cost.toFixed(2) }}</span> ·
                <span :title="rt('sessionLoadTitle')">L{{ getScoreBreakdown(c.credential_id)!.session_load.toFixed(2) }}</span> ·
                <span :title="rt('failuresTitle')">F{{ getScoreBreakdown(c.credential_id)!.consecutive_failures }}</span>
              </div>
            </td>
            <td>{{ c.provider_name }}</td>
            <td><code style="font-size:11px">{{ c.catalog_code }}</code></td>
            <td>
              <div>{{ c.credential_label }}</div>
              <div class="cell-muted">#{{ c.credential_id }} · {{ rt('concurrency', { n: c.effective_concurrency ?? c.concurrency_limit ?? '—' }) }}</div>
            </td>
            <td><code style="font-size:11px">{{ c.model_name }}</code></td>
            <td>
              <span class="badge" :class="c.billing_round === 1 ? 'badge-green' : ''" style="font-size:11px">
                {{ c.billing_mode || 'token' }}
              </span>
              <div v-if="c.billing_round === 2" class="cell-muted">{{ rt('billingRound2') }}</div>
            </td>
            <td>T{{ c.tier }} · w{{ c.weight }}</td>
            <td>
              <div v-if="editingPriority === c.credential_id" style="display:flex;gap:4px;align-items:center">
                <input
                  v-model.number="editingValue"
                  type="number"
                  min="1"
                  max="99"
                  style="width:50px;padding:2px 6px;font-size:12px"
                  @keyup.enter="savePriority(c.credential_id, c.model_name)"
                  @keyup.esc="cancelEdit"
                />
                <button class="btn btn-primary btn-sm" @click="savePriority(c.credential_id, c.model_name)" style="font-size:11px;padding:2px 6px">{{ rt('save') }}</button>
                <button class="btn btn-ghost btn-sm" @click="cancelEdit" style="font-size:11px;padding:2px 6px">{{ rt('cancel') }}</button>
              </div>
              <div v-else style="cursor:pointer" @click="startEditPriority(c.credential_id, getScoreBreakdown(c.credential_id)?.manual_priority ?? c.manual_priority ?? 99)">
                <span style="font-weight:600">{{ getScoreBreakdown(c.credential_id)?.manual_priority ?? c.manual_priority ?? 99 }}</span>
                <span class="cell-muted" style="font-size:10px;margin-left:4px">✎</span>
              </div>
            </td>
            <td>{{ priceLabel(c) }}</td>
            <td>
              <div style="font-size:12px">
                {{ rt('shared.sessionError').split('/')[0] }}: <strong>{{ getScoreBreakdown(c.credential_id)?.active_sessions ?? 0 }}</strong>
                / {{ c.concurrency_limit ?? '—' }}
              </div>
              <div class="cell-muted" style="font-size:11px">
                {{ rt('shared.sessionError').split('/')[1] }}: {{ getScoreBreakdown(c.credential_id)?.consecutive_failures ?? 0 }}
              </div>
            </td>
            <td>
              <span class="badge" :class="c.routable ? 'badge-green' : 'badge-red'">
                {{ c.routable ? rt('shared.routable') : rt('shared.unavailable') }}
              </span>
              <div class="cell-muted">{{ c.credential_status }} · {{ c.circuit_state || 'closed' }}</div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div v-if="probeErr" class="alert alert-danger">{{ probeErr }}</div>
    <div class="card" v-if="probeResult" style="margin-bottom:20px">
      <h4 class="probe-result-title">
        {{ rt('probeResult') }}
        <span class="badge probe-result-badge" :class="probeResult.success ? 'badge-green' : 'badge-red'">
          {{ probeResult.success ? rt('shared.success') : rt('shared.failed') }}
        </span>
      </h4>
      <div class="stat-grid">
        <div class="stat-card">
          <div class="stat-label">{{ rt('probeProvider') }}</div>
          <div class="stat-value" style="font-size:16px">{{ probeResult.provider_name }}</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">{{ rt('probeCatalog') }}</div>
          <div class="stat-value" style="font-size:16px">{{ probeResult.catalog_code }}</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">{{ rt('probeLatency') }}</div>
          <div class="stat-value" style="font-size:16px">{{ latencyLabel(probeResult.latency_ms) }}</div>
        </div>
      </div>
      <div v-if="probeResult.reply" style="margin-top:16px">
        <div style="font-size:12px;color:var(--muted);margin-bottom:6px">{{ rt('probeReply') }}</div>
        <pre style="background:var(--bg-subtle,#161b22);border:1px solid var(--border,#30363d);border-radius:6px;padding:12px;font-size:13px;margin:0;white-space:pre-wrap;color:var(--text,#e6edf3)">{{ probeResult.reply }}</pre>
      </div>
      <div v-if="probeResult.error" class="alert alert-danger" style="margin-top:12px">
        {{ probeResult.error }}
      </div>
    </div>
  </div>
</template>

<style scoped>
.cell-muted { color: var(--muted); font-size: 11px; margin-top: 3px; }

.score-badge {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 10px;
  font-weight: 600;
  font-size: 12px;
  min-width: 40px;
  text-align: center;
}
.score-free {
  background: #dcfce7;
  color: #166534;
}
.score-good {
  background: #dbeafe;
  color: #1e40af;
}
.score-normal {
  background: #f3f4f6;
  color: #374151;
}
.edit-pencil {
  font-size: 10px;
  margin-inline-start: 4px;
}
.probe-result-title {
  margin: 0 0 12px;
}
.probe-result-badge {
  margin-inline-start: 8px;
}
</style>
