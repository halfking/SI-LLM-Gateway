<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import {
  getAdminMaasModelRates,
  updateAdminMaasSettings,
  upsertAdminMaasModelRate,
  deleteAdminMaasModelRate,
  resetAdminMaasModelRateFields,
  type AdminMaasModelRate,
  type MaasAdminSettings,
  type MaasModelRateUpsert,
} from '../api'
import ModelCatalogFilterBar from '../components/ModelCatalogFilterBar.vue'
import { useModelCatalogFilters } from '../composables/useModelCatalogFilters'

const { t } = useI18n()
const smp = (k: string, params?: Record<string, unknown>): string =>
  t(`standardModelPricing.${k}` as never, params as never)

type RateField = 'in' | 'out' | 'cache_in' | 'cache_out'

const loading = ref(false)
const savingSettings = ref(false)
const error = ref('')
const settingsMsg = ref('')
const models = ref<AdminMaasModelRate[]>([])
const settings = ref<MaasAdminSettings | null>(null)

function isFullyManual(m: AdminMaasModelRate) {
  return m.manual_in && m.manual_out && m.manual_cache_in && m.manual_cache_out
}

const pricingStatusOptions = [
  { value: 'default', label: '仅全局基准' },
  { value: 'custom', label: '含手工定价' },
  { value: 'partial', label: '部分手工' },
]

const {
  pickedModel,
  filterVendor,
  extraFilter: filterMode,
  vendorOptions,
  filtered,
  clearFilters: clearCatalogFilters,
} = useModelCatalogFilters<AdminMaasModelRate>({
  items: models,
  getVendor: (m) => m.vendor?.trim() || smp('filter.otherVendor'),
  getCanonicalName: (m) => m.canonical_name,
  getDisplayName: (m) => m.display_name,
  matchExtra: (m, mode) => {
    if (mode === 'custom') return m.is_custom
    if (mode === 'default') return !m.is_custom
    if (mode === 'partial') return m.is_custom && !isFullyManual(m)
    return true
  },
})

const editRow = ref<AdminMaasModelRate | null>(null)
const editForm = ref<MaasModelRateUpsert>(emptyEditForm())
const savingRow = ref(false)

function emptyEditForm(): MaasModelRateUpsert {
  return {
    credits_per_1m_in: 0,
    credits_per_1m_out: 0,
    credits_per_1m_cache_in: 0,
    credits_per_1m_cache_out: 0,
    manual_in: false,
    manual_out: false,
    manual_cache_in: false,
    manual_cache_out: false,
  }
}

const customCount = computed(() => models.value.filter((m) => m.is_custom).length)
const defaultCount = computed(() => models.value.length - customCount.value)

const discountPercent = computed({
  get: () => Math.round((settings.value?.global_discount ?? 1) * 100),
  set: (v: number) => {
    if (settings.value) settings.value.global_discount = Math.min(100, Math.max(1, v)) / 100
  },
})

function manualCount(m: AdminMaasModelRate) {
  return [m.manual_in, m.manual_out, m.manual_cache_in, m.manual_cache_out].filter(Boolean).length
}

function fmtCredits(n: number) {
  return n.toLocaleString('zh-CN')
}

function pricePer1M(credits: number) {
  const st = settings.value
  if (!st || credits <= 0) return '—'
  const yuan = (credits * st.cents_per_credit) / 100
  return `${st.currency_display === 'CNY' ? '¥' : st.currency_display}${yuan.toFixed(4)}`
}

function effectiveGlobal(field: RateField) {
  const st = settings.value
  if (!st) return 0
  const disc = st.global_discount ?? 1
  const pick = (base: number | undefined, fallback: number) =>
    Math.ceil((base && base > 0 ? base : fallback) * disc)
  const inBase = st.base_credits_per_1m_in ?? st.base_credits_per_1m
  switch (field) {
    case 'in':
      return pick(st.base_credits_per_1m_in, inBase)
    case 'out':
      return pick(st.base_credits_per_1m_out, inBase)
    case 'cache_in':
      return pick(st.base_credits_per_1m_cache_in, inBase)
    case 'cache_out':
      return pick(st.base_credits_per_1m_cache_out, inBase)
  }
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    const rates = await getAdminMaasModelRates()
    models.value = rates.items ?? []
    settings.value = {
      ...rates.settings,
      base_credits_per_1m_in: rates.settings.base_credits_per_1m_in ?? rates.settings.base_credits_per_1m,
      base_credits_per_1m_out: rates.settings.base_credits_per_1m_out ?? rates.settings.base_credits_per_1m,
      base_credits_per_1m_cache_in: rates.settings.base_credits_per_1m_cache_in ?? rates.settings.base_credits_per_1m,
      base_credits_per_1m_cache_out: rates.settings.base_credits_per_1m_cache_out ?? rates.settings.base_credits_per_1m,
      global_discount: rates.settings.global_discount ?? 1,
    }
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : smp('error.loadFailed')
  } finally {
    loading.value = false
  }
}

async function saveSettings() {
  if (!settings.value) return
  savingSettings.value = true
  settingsMsg.value = ''
  error.value = ''
  try {
    await updateAdminMaasSettings({
      cents_per_credit: settings.value.cents_per_credit,
      base_credits_per_1m_in: settings.value.base_credits_per_1m_in ?? settings.value.base_credits_per_1m,
      base_credits_per_1m_out: settings.value.base_credits_per_1m_out,
      base_credits_per_1m_cache_in: settings.value.base_credits_per_1m_cache_in,
      base_credits_per_1m_cache_out: settings.value.base_credits_per_1m_cache_out,
      global_discount: settings.value.global_discount ?? 1,
      currency_display: settings.value.currency_display,
    })
    settingsMsg.value = smp('settings.saved')
    await load()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : smp('error.saveFailed')
  } finally {
    savingSettings.value = false
  }
}

function openEdit(row: AdminMaasModelRate) {
  editRow.value = row
  editForm.value = {
    credits_per_1m_in: row.manual_in ? (row.custom_credits_per_1m_in ?? row.credits_per_1m_in) : effectiveGlobal('in'),
    credits_per_1m_out: row.manual_out ? (row.custom_credits_per_1m_out ?? row.credits_per_1m_out) : effectiveGlobal('out'),
    credits_per_1m_cache_in: row.manual_cache_in ? (row.custom_credits_per_1m_cache_in ?? row.credits_per_1m_cache_in) : effectiveGlobal('cache_in'),
    credits_per_1m_cache_out: row.manual_cache_out ? (row.custom_credits_per_1m_cache_out ?? row.credits_per_1m_cache_out) : effectiveGlobal('cache_out'),
    manual_in: row.manual_in,
    manual_out: row.manual_out,
    manual_cache_in: row.manual_cache_in,
    manual_cache_out: row.manual_cache_out,
  }
}

function closeEdit() {
  editRow.value = null
}

async function saveEdit() {
  if (!editRow.value) return
  if (!editForm.value.manual_in && !editForm.value.manual_out && !editForm.value.manual_cache_in && !editForm.value.manual_cache_out) {
    error.value = smp('editModal.needOneManual')
    return
  }
  savingRow.value = true
  error.value = ''
  try {
    await upsertAdminMaasModelRate(editRow.value.canonical_id, { ...editForm.value })
    closeEdit()
    await load()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : smp('error.saveFailed')
  } finally {
    savingRow.value = false
  }
}

async function resetAll(row: AdminMaasModelRate) {
  if (!row.is_custom) return
  if (!confirm(smp('editModal.resetConfirm', { name: row.canonical_name }))) return
  error.value = ''
  try {
    await deleteAdminMaasModelRate(row.canonical_id)
    await load()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : smp('error.resetFailed')
  }
}

async function resetField(row: AdminMaasModelRate, field: RateField) {
  error.value = ''
  try {
    await resetAdminMaasModelRateFields(row.canonical_id, [field])
    if (editRow.value?.canonical_id === row.canonical_id) closeEdit()
    await load()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : smp('error.resetFailed')
  }
}

function fillGlobalToEdit() {
  editForm.value.credits_per_1m_in = effectiveGlobal('in')
  editForm.value.credits_per_1m_out = effectiveGlobal('out')
  editForm.value.credits_per_1m_cache_in = effectiveGlobal('cache_in')
  editForm.value.credits_per_1m_cache_out = effectiveGlobal('cache_out')
}

const rateFields: { key: RateField; formKey: keyof MaasModelRateUpsert; manualKey: keyof MaasModelRateUpsert; valueKey: keyof AdminMaasModelRate; manualFlag: keyof AdminMaasModelRate }[] = [
  { key: 'in', formKey: 'credits_per_1m_in', manualKey: 'manual_in', valueKey: 'credits_per_1m_in', manualFlag: 'manual_in' },
  { key: 'out', formKey: 'credits_per_1m_out', manualKey: 'manual_out', valueKey: 'credits_per_1m_out', manualFlag: 'manual_out' },
  { key: 'cache_in', formKey: 'credits_per_1m_cache_in', manualKey: 'manual_cache_in', valueKey: 'credits_per_1m_cache_in', manualFlag: 'manual_cache_in' },
  { key: 'cache_out', formKey: 'credits_per_1m_cache_out', manualKey: 'manual_cache_out', valueKey: 'credits_per_1m_cache_out', manualFlag: 'manual_cache_out' },
]

onMounted(load)
</script>

<template>
  <div class="pricing-page">
    <div class="page-header">
      <h2>{{ smp('page.title') }}</h2>
      <button class="btn btn-ghost btn-sm" :disabled="loading" @click="load">
        {{ loading ? smp('page.refreshLoading') : smp('page.refresh') }}
      </button>
    </div>

    <p class="page-desc" v-html="smp('desc')" />

    <div v-if="error" class="alert alert-danger">{{ error }}</div>
    <div v-if="settingsMsg" class="alert alert-success">{{ settingsMsg }}</div>

    <div v-if="settings" class="card settings-card">
      <h3 class="section-title">{{ smp('settings.title') }}</h3>
      <div class="settings-grid">
        <label class="field">
          <span class="field-label">{{ smp('settings.inputToken') }}</span>
          <input v-model.number="settings.base_credits_per_1m_in" type="number" min="1" class="input compact" />
          <span class="field-hint">{{ smp('settings.effective', { value: fmtCredits(effectiveGlobal('in')) }) }}</span>
        </label>
        <label class="field">
          <span class="field-label">{{ smp('settings.outputToken') }}</span>
          <input v-model.number="settings.base_credits_per_1m_out" type="number" min="1" class="input compact" />
          <span class="field-hint">{{ smp('settings.effective', { value: fmtCredits(effectiveGlobal('out')) }) }}</span>
        </label>
        <label class="field">
          <span class="field-label">{{ smp('settings.cacheReadToken') }}</span>
          <input v-model.number="settings.base_credits_per_1m_cache_in" type="number" min="1" class="input compact" />
          <span class="field-hint">{{ smp('settings.effective', { value: fmtCredits(effectiveGlobal('cache_in')) }) }}</span>
        </label>
        <label class="field">
          <span class="field-label">{{ smp('settings.cacheWriteToken') }}</span>
          <input v-model.number="settings.base_credits_per_1m_cache_out" type="number" min="1" class="input compact" />
          <span class="field-hint">{{ smp('settings.effective', { value: fmtCredits(effectiveGlobal('cache_out')) }) }}</span>
        </label>
        <label class="field">
          <span class="field-label">{{ smp('settings.discount') }}</span>
          <div class="discount-row">
            <input v-model.number="discountPercent" type="range" min="10" max="100" step="1" class="discount-slider" />
            <span class="discount-val">{{ discountPercent }}%</span>
          </div>
          <span class="field-hint">{{ smp('settings.discountHint') }}</span>
        </label>
        <label class="field">
          <span class="field-label">{{ smp('settings.centsPerCredit') }}</span>
          <input v-model.number="settings.cents_per_credit" type="number" min="0.0001" step="0.0001" class="input compact" />
        </label>
        <label class="field">
          <span class="field-label">{{ smp('settings.currencyDisplay') }}</span>
          <select v-model="settings.currency_display" class="input compact">
            <option value="CNY">CNY</option>
            <option value="USD">USD</option>
          </select>
        </label>
      </div>
      <div class="settings-actions">
        <button class="btn btn-primary btn-sm" :disabled="savingSettings" @click="saveSettings">
          {{ savingSettings ? smp('settings.saving') : smp('settings.save') }}
        </button>
        <span class="cf-meta">
          {{ smp('filter.summary', { custom: customCount, defaults: defaultCount, total: models.length }) }}
        </span>
      </div>
    </div>

    <ModelCatalogFilterBar
      v-model:picked-model="pickedModel"
      v-model:filter-vendor="filterVendor"
      v-model:extra-filter="filterMode"
      :vendor-options="vendorOptions"
      :count="filtered.length"
      :picker-title="smp('filter.title')"
      :picker-placeholder="smp('filter.placeholder')"
      :status-label="smp('filter.allPricing')"
      :status-options="pricingStatusOptions"
      @clear="clearCatalogFilters"
    />

    <div class="card table-wrap">
      <table class="data-table pricing-table">
        <thead>
          <tr>
            <th>{{ smp('table.colModel') }}</th>
            <th>{{ smp('table.colVendor') }}</th>
            <th v-for="f in rateFields" :key="f.key" class="num">{{ smp(`field.${f.key}`) }}</th>
            <th>{{ smp('table.colStatus') }}</th>
            <th>{{ smp('table.colActions') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="!loading && filtered.length === 0">
            <td :colspan="4 + rateFields.length" class="empty-cell">{{ smp('table.empty') }}</td>
          </tr>
          <tr v-for="row in filtered" :key="row.canonical_id">
            <td>
              <div class="model-name">{{ row.display_name }}</div>
              <code class="mono-sm">{{ row.canonical_name }}</code>
            </td>
            <td class="cell-muted">{{ row.vendor || '—' }}</td>
            <td v-for="f in rateFields" :key="f.key" class="num rate-cell">
              <span>{{ fmtCredits(row[f.valueKey] as number) }}</span>
              <span v-if="row[f.manualFlag]" class="manual-tag" :title="smp('table.manualTagTitle')">{{ smp('table.manualTag') }}</span>
            </td>
            <td>
              <span v-if="!row.is_custom" class="badge badge-gray">{{ smp('table.statusDefault') }}</span>
              <span v-else-if="isFullyManual(row)" class="badge badge-blue">{{ smp('table.statusFullCustom') }}</span>
              <span v-else class="badge badge-yellow">{{ smp('table.statusPartialCustom', { n: manualCount(row) }) }}</span>
            </td>
            <td class="actions">
              <button class="btn btn-ghost btn-sm" @click="openEdit(row)">{{ smp('table.edit') }}</button>
              <button v-if="row.is_custom" class="btn btn-ghost btn-sm" @click="resetAll(row)">{{ smp('table.reset') }}</button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div v-if="editRow" class="modal-backdrop" @click.self="closeEdit">
      <div class="modal card">
        <h3 class="section-title">{{ smp('editModal.title', { name: editRow.display_name }) }}</h3>
        <code class="mono-sm modal-code">{{ editRow.canonical_name }}</code>
        <p class="modal-hint">{{ smp('editModal.hint') }}</p>
        <div class="edit-grid">
          <div v-for="f in rateFields" :key="f.key" class="edit-field">
            <label class="edit-head">
              <input v-model="editForm[f.manualKey]" type="checkbox" />
              <span>{{ smp(`field.${f.key}`) }}{{ smp('editModal.fieldSuffix') }}</span>
              <button
                v-if="editRow[f.manualFlag]"
                type="button"
                class="link-sm"
                @click="resetField(editRow, f.key)"
              >{{ smp('editModal.resetBase') }}</button>
            </label>
            <input
              v-model.number="editForm[f.formKey]"
              type="number"
              min="1"
              class="input compact"
              :disabled="!editForm[f.manualKey]"
            />
            <span class="field-hint">{{ smp('editModal.globalApprox', { value: fmtCredits(effectiveGlobal(f.key)) }) }}</span>
          </div>
        </div>
        <div class="modal-actions">
          <button class="btn btn-primary btn-sm" :disabled="savingRow" @click="saveEdit">
            {{ savingRow ? smp('editModal.saving') : smp('editModal.save') }}
          </button>
          <button class="btn btn-ghost btn-sm" type="button" @click="fillGlobalToEdit">{{ smp('editModal.fillGlobal') }}</button>
          <button class="btn btn-ghost btn-sm" type="button" @click="closeEdit">{{ smp('editModal.cancel') }}</button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.page-desc { color: var(--muted); font-size: 13px; margin: -8px 0 16px; line-height: 1.6; }
.section-title { font-size: 14px; font-weight: 600; margin: 0 0 12px; }
.settings-card { margin-bottom: 16px; }
.settings-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 14px;
}
@media (max-width: 1100px) { .settings-grid { grid-template-columns: repeat(2, 1fr); } }
@media (max-width: 640px) { .settings-grid { grid-template-columns: 1fr; } }
.field { display: flex; flex-direction: column; gap: 4px; }
.field-label { font-size: 12px; color: var(--muted); }
.field-hint { font-size: 11px; color: var(--muted); }
.input.compact { width: 100%; max-width: 100%; }
.discount-row { display: flex; align-items: center; gap: 10px; }
.discount-slider { flex: 1; }
.discount-val { font-size: 13px; font-weight: 600; min-width: 42px; }
.settings-actions {
  display: flex; align-items: center; gap: 12px;
  margin-top: 16px; padding-top: 12px; border-top: 1px solid var(--border);
}
.table-wrap { overflow-x: auto; }
.pricing-table { width: 100%; font-size: 13px; min-width: 960px; }
.model-name { font-weight: 600; }
.mono-sm { font-family: ui-monospace, Menlo, monospace; font-size: 11px; color: var(--muted); }
.cell-muted { color: var(--muted); }
.num { text-align: right; font-variant-numeric: tabular-nums; }
.rate-cell { white-space: nowrap; }
.manual-tag {
  display: inline-block; margin-left: 4px; padding: 0 4px;
  font-size: 10px; border-radius: 4px;
  background: rgba(59, 130, 246, 0.15); color: #60a5fa;
}
.actions { white-space: nowrap; display: flex; gap: 6px; justify-content: flex-end; }
.empty-cell { text-align: center; color: var(--muted); padding: 24px; }
.badge { padding: 2px 8px; border-radius: 8px; font-size: 11px; }
.badge-gray { background: rgba(156,163,175,.15); color: #9ca3af; }
.badge-blue { background: rgba(59,130,246,.15); color: #60a5fa; }
.badge-yellow { background: rgba(234,179,8,.15); color: #fbbf24; }
.modal-backdrop {
  position: fixed; inset: 0; z-index: 100;
  background: rgba(0,0,0,.45); display: flex; align-items: center; justify-content: center; padding: 20px;
}
.modal { width: min(560px, 100%); padding: 20px; max-height: 90vh; overflow-y: auto; }
.modal-code { display: block; margin-bottom: 8px; }
.modal-hint { font-size: 12px; color: var(--muted); margin: 0 0 16px; }
.edit-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
@media (max-width: 520px) { .edit-grid { grid-template-columns: 1fr; } }
.edit-field { display: flex; flex-direction: column; gap: 6px; }
.edit-head { display: flex; align-items: center; gap: 8px; font-size: 13px; }
.link-sm { font-size: 11px; margin-left: auto; background: none; border: none; color: var(--accent-h, #6366f1); cursor: pointer; }
.modal-actions { display: flex; gap: 8px; margin-top: 18px; padding-top: 12px; border-top: 1px solid var(--border); }
</style>
