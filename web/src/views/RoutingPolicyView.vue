<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import {
  getPolicy, patchPolicy, getFeatured, patchFeatured,
  getScoringWeights, updateScoringWeights,
  type RoutingPolicy, type ScoringWeights,
} from '../api'
import ModelPicker from '../components/ModelPicker.vue'

const { t } = useI18n()
const rp = (k: string, params?: Record<string, unknown>): string =>
  t(`routing.policy.${k}` as never, params as never)

const policy   = ref<RoutingPolicy | null>(null)
const draft    = ref<Partial<RoutingPolicy>>({})
const featuredArray = ref<string[]>([])
const loading  = ref(false)
const saving   = ref(false)
const error    = ref('')
const message  = ref('')

const weights   = ref<ScoringWeights>({
  price: 10,
  session_load: 5,
  failure_penalty: 20,
  default_price_cny: 5.0,
  default_price_usd: 5.0,
})
const weightsDraft = ref<ScoringWeights>({ ...weights.value })

const FIELDS: { key: keyof RoutingPolicy; label: string; min?: number; max?: number; step?: number }[] = [
  { key: 'algorithm_version',         label: rp('fields.algorithm_version'), min: 1, max: 2, step: 1 },
  { key: 'retry_per_credential',      label: rp('fields.retry_per_credential'), min: 0, max: 5, step: 1 },
  { key: 'tier_fallback_max',         label: rp('fields.tier_fallback_max'), min: 1, max: 20, step: 1 },
  { key: 'slot_soft_limit_ratio',     label: rp('fields.slot_soft_limit_ratio'), min: 0.1, max: 5,  step: 0.1 },
  { key: 'slot_hard_limit_ratio',     label: rp('fields.slot_hard_limit_ratio'), min: 0.1, max: 5,  step: 0.1 },
  { key: 'slot_wait_max_ms',          label: rp('fields.slot_wait_max_ms'), min: 0, max: 5000, step: 10 },
  { key: 'circuit_open_seconds',      label: rp('fields.circuit_open_seconds'), min: 1, max: 3600, step: 1 },
  { key: 'circuit_failure_threshold', label: rp('fields.circuit_failure_threshold'), min: 1, max: 50, step: 1 },
  { key: 'circuit_max_open_seconds',  label: rp('fields.circuit_max_open_seconds'), min: 1, max: 86400, step: 1 },
]

const formulaPreview = computed(() => {
  const w = weightsDraft.value
  return rp('formulaPrefix', { price: w.price, session_load: w.session_load, failure_penalty: w.failure_penalty })
})

async function load() {
  loading.value = true
  error.value = ''
  try {
    policy.value = await getPolicy()
    draft.value  = { ...policy.value }
    const f = await getFeatured()
    featuredArray.value = (f.featured_models || []).slice()
    const w = await getScoringWeights()
    weights.value = w
    weightsDraft.value = { ...w }
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : rp('loading')
  } finally {
    loading.value = false
  }
}

const dirtyKeys = computed<string[]>(() => {
  if (!policy.value) return []
  const out: string[] = []
  for (const f of FIELDS) {
    const a = (policy.value as any)[f.key]
    const b = (draft.value  as any)[f.key]
    if (String(a) !== String(b)) out.push(String(f.key))
  }
  return out
})

const weightsDirty = computed(() => {
  return JSON.stringify(weights.value) !== JSON.stringify(weightsDraft.value)
})

async function savePolicy() {
  if (!dirtyKeys.value.length) {
    message.value = rp('noChanges')
    return
  }
  saving.value = true
  error.value = ''
  message.value = ''
  try {
    const patch: Record<string, unknown> = { actor: 'admin' }
    for (const k of dirtyKeys.value) patch[k] = (draft.value as any)[k]
    const updated = await patchPolicy(patch as Partial<RoutingPolicy>)
    policy.value = updated
    draft.value  = { ...updated }
    message.value = rp('updatedPolicy')
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : rp('saveFailed')
  } finally {
    saving.value = false
  }
}

async function saveWeights() {
  saving.value = true
  error.value = ''
  message.value = ''
  try {
    await updateScoringWeights(weightsDraft.value)
    weights.value = { ...weightsDraft.value }
    message.value = rp('updatedWeights')
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : rp('saveFailed')
  } finally {
    saving.value = false
  }
}

async function saveFeatured() {
  saving.value = true
  error.value = ''
  message.value = ''
  try {
    const list = featuredArray.value.map(s => s.trim()).filter(Boolean)
    await patchFeatured(list)
    message.value = rp('updatedFeatured', { n: list.length })
    await load()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : rp('saveFailed')
  } finally {
    saving.value = false
  }
}

onMounted(load)
</script>

<template>
  <div>
    <div class="page-header">
      <h2>{{ rp('title') }}</h2>
      <button class="btn btn-ghost" @click="load" :disabled="loading">{{ rp('loading') }}</button>
    </div>
    <p style="color:var(--muted);margin-bottom:16px">
      {{ rp('description') }}
    </p>

    <div v-if="error" class="alert alert-danger">{{ error }}</div>
    <div v-if="message" class="alert alert-success">{{ message }}</div>
    <div v-if="loading" class="empty">{{ rp('loading') }}</div>

    <div v-if="!loading && policy" class="card" style="margin-bottom:16px">
      <h3 style="margin-top:0">{{ rp('globalTitle') }}</h3>
      <table>
        <thead>
          <tr><th style="width:40%">{{ rp('tableHeaders.0') }}</th><th>{{ rp('tableHeaders.1') }}</th><th>{{ rp('tableHeaders.2') }}</th></tr>
        </thead>
        <tbody>
          <tr v-for="f in FIELDS" :key="String(f.key)">
            <td>{{ f.label }} <code style="font-size:10px;color:var(--muted)">{{ String(f.key) }}</code></td>
            <td><code>{{ (policy as any)[f.key] }}</code></td>
            <td>
              <input
                type="number"
                v-model.number="(draft as any)[f.key]"
                :min="f.min"
                :max="f.max"
                :step="f.step"
                style="width:140px"
              />
            </td>
          </tr>
        </tbody>
      </table>
      <div style="margin-top:12px;display:flex;gap:8px;align-items:center">
        <button class="btn btn-primary" @click="savePolicy" :disabled="saving || !dirtyKeys.length">
          {{ saving ? rp('saving') : rp('savePolicy') }}
        </button>
        <span v-if="dirtyKeys.length" style="color:var(--muted);font-size:12px">
          {{ rp('dirtyHint', { n: dirtyKeys.length, keys: dirtyKeys.join(', ') }) }}
        </span>
      </div>
    </div>

    <div v-if="!loading" class="card" style="margin-bottom:16px">
      <h3 style="margin-top:0">{{ rp('weightsTitle') }}</h3>
      <p style="color:var(--muted);font-size:12px;margin-bottom:12px">
        {{ rp('formulaLabel') }}<strong>{{ rp('freeHighlight') }}</strong>
      </p>
      <div style="background:var(--bg-subtle,#161b22);border:1px solid var(--border,#30363d);padding:12px;border-radius:6px;margin-bottom:16px;font-family:monospace;font-size:13px;color:var(--text,#e6edf3)">
        {{ formulaPreview }}
      </div>
      <div class="weights-grid">
        <div class="weight-item">
          <label>{{ rp('weights.price') }}</label>
          <input type="number" v-model.number="weightsDraft.price" min="0" max="100" step="1" />
          <span class="cell-muted">{{ rp('weights.priceHint') }}</span>
        </div>
        <div class="weight-item">
          <label>{{ rp('weights.sessionLoad') }}</label>
          <input type="number" v-model.number="weightsDraft.session_load" min="0" max="100" step="1" />
          <span class="cell-muted">{{ rp('weights.sessionLoadHint') }}</span>
        </div>
        <div class="weight-item">
          <label>{{ rp('weights.errorPenalty') }}</label>
          <input type="number" v-model.number="weightsDraft.failure_penalty" min="0" max="100" step="1" />
          <span class="cell-muted">{{ rp('weights.errorPenaltyHint') }}</span>
        </div>
        <div class="weight-item">
          <label>{{ rp('weights.defaultPriceCny') }}</label>
          <input type="number" v-model.number="weightsDraft.default_price_cny" min="0.01" max="100" step="0.1" />
          <span class="cell-muted">{{ rp('weights.defaultPriceHint') }}</span>
        </div>
        <div class="weight-item">
          <label>{{ rp('weights.defaultPriceUsd') }}</label>
          <input type="number" v-model.number="weightsDraft.default_price_usd" min="0.01" max="100" step="0.1" />
          <span class="cell-muted">{{ rp('weights.defaultPriceHint') }}</span>
        </div>
      </div>
      <div style="margin-top:12px;display:flex;gap:8px;align-items:center">
        <button class="btn btn-primary" @click="saveWeights" :disabled="saving || !weightsDirty">
          {{ saving ? rp('saving') : rp('savingWeights') }}
        </button>
        <span v-if="weightsDirty" style="color:var(--muted);font-size:12px">
          {{ rp('weightsDirty') }}
        </span>
      </div>
    </div>

    <div v-if="!loading" class="card">
      <h3 style="margin-top:0">{{ rp('featuredTitle') }}</h3>
      <p style="color:var(--muted);font-size:12px;margin-bottom:8px">
        {{ rp('featuredDescription') }}
      </p>
      <ModelPicker
        v-model="featuredArray"
        mode="multi"
        :placeholder="rp('featuredPlaceholder')"
        :title="rp('featuredMultiTitle')"
      />
      <div style="margin-top:8px">
        <button class="btn btn-primary" @click="saveFeatured" :disabled="saving">
          {{ saving ? rp('saving') : rp('saveFeatured') }}
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.weights-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 16px;
}
.weight-item {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.weight-item label {
  font-weight: 600;
  font-size: 13px;
}
.weight-item input {
  width: 100%;
  padding: 6px 10px;
  border: 1px solid var(--border, #e5e7eb);
  border-radius: 4px;
  font-size: 14px;
}
.cell-muted {
  color: var(--muted);
  font-size: 11px;
}

.featured-recommend-bar {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
  margin-bottom: 10px;
  padding: 8px 10px;
  background: var(--bg-subtle, #161b22);
  border: 1px solid var(--border, #30363d);
  border-radius: 6px;
}
.featured-recommend-msg {
  font-size: 11px;
  color: var(--muted);
  flex: 1;
  min-width: 200px;
}
</style>
