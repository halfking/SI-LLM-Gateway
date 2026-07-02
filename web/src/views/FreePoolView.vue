<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import {
  getFreePoolStatus,
  getFreePoolMethods,
  getFreePoolKeys,
  getFreePoolSignupHub,
  addFreePoolKey,
  registerFreeProvider,
  importFreePoolEnv,
  discoverFreePool,
  bridgeFreePoolOAuth,
  bootstrapFreePool,
  probeFreePoolCredential,
  quickEntryFreePool,
  createFreePoolTempEmail,
  pollFreePoolTempEmail,
  type FreePoolStatusResponse,
  type FreePoolEntry,
  type FreePoolCatalogEntry,
  type FreePoolModelEntry,
  type FreePoolMethod,
  type FreePoolAuditRule,
  type FreePoolKeyEntry,
  type SignupHubResponse,
  type SignupPlatformEntry,
} from '../api'

const { t } = useI18n()
const fp = (k: string, params?: Record<string, unknown>): string =>
  t(`freePool.${k}` as never, params as never)

const poolData  = ref<FreePoolStatusResponse | null>(null)
const poolKeys  = ref<FreePoolKeyEntry[]>([])
const methodsData = ref<{ methods: FreePoolMethod[]; audit_rules: FreePoolAuditRule[]; scheduler: { interval_sec: number; last_result: Record<string, unknown> } } | null>(null)
const loading   = ref(false)
const syncing   = ref(false)
const error     = ref('')
const message   = ref('')
const modelQuery = ref('')
const activeTab = ref<'models' | 'providers' | 'catalog' | 'keys' | 'guide' | 'assistant'>('assistant')

const showAddForm = ref(false)
const showKeyForm = ref(false)
const signupHub = ref<SignupHubResponse | null>(null)
const hubCategory = ref('all')
const hubQuery = ref('')

const quickEntry = ref({
  signup_url: '',
  base_url: '',
  api_key: '',
  display_name: '',
  catalog_code: '',
  source: 'signup',
  source_detail: '',
  platform_id: '',
})
const quickProbing = ref(false)
const quickSaving = ref(false)
const probeResult = ref<Record<string, unknown> | null>(null)

const tempEmail = ref<{ address: string; password: string; token: string; web_url: string } | null>(null)
const tempEmailLoading = ref(false)
const tempInbox = ref<Array<{ id: string; from?: string; subject?: string; intro?: string }>>([])
const tempPolling = ref(false)
const keySubmitting = ref(false)
const newKey = ref({
  catalog_code: 'openrouter-free',
  api_key: '',
  source: 'signup',
  source_detail: '',
  label: '',
})
const submitting   = ref(false)
const newProvider = ref({
  catalog_code: '',
  display_name: '',
  base_url: '',
  protocol: 'openai-completions',
  api_key: '',
  models: '',
})

const catalog = computed(() => poolData.value?.catalog ?? [])
const liveModels = computed(() => poolData.value?.models ?? [])

const filteredModels = computed(() => {
  const q = modelQuery.value.trim().toLowerCase()
  if (!q) return liveModels.value
  return liveModels.value.filter(m =>
    m.raw_model_name.toLowerCase().includes(q)
    || m.provider_name.toLowerCase().includes(q)
    || m.catalog_code.toLowerCase().includes(q),
  )
})

const routableModels = computed(() => liveModels.value.filter(m => m.routable))

const catalogSummary = computed(() => {
  const items = catalog.value
  const registered = items.filter(c => c.pool_registered).length
  const templateModels = items.reduce((n, c) => n + (c.model_count_template || 0), 0)
  return { total: items.length, registered, templateModels }
})

const hubPlatforms = computed(() => {
  const rows = signupHub.value?.platforms ?? []
  const q = hubQuery.value.trim().toLowerCase()
  return rows.filter(p => {
    if (hubCategory.value !== 'all' && p.category !== hubCategory.value) return false
    if (!q) return true
    return (
      p.name.toLowerCase().includes(q)
      || p.catalog_code.toLowerCase().includes(q)
      || p.notes.toLowerCase().includes(q)
      || (p.tags && p.tags.some(t => t.toLowerCase().includes(q)))
    )
  })
})

const hubCategories = computed(() => signupHub.value?.categories ?? [])

async function load() {
  loading.value = true
  error.value = ''
  try {
    const [status, methods, keysRes, hub] = await Promise.all([
      getFreePoolStatus(),
      getFreePoolMethods(),
      getFreePoolKeys(),
      getFreePoolSignupHub(),
    ])
    poolData.value = status
    methodsData.value = methods
    poolKeys.value = keysRes.keys
    signupHub.value = hub
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : fp('error.loadFailed')
  } finally {
    loading.value = false
  }
}

async function runBootstrap() {
  syncing.value = true
  error.value = ''
  message.value = ''
  try {
    const res = await bootstrapFreePool()
    const mirror = (res.mirror as { registered?: number })?.registered ?? 0
    const discover = (res.discover as { registered?: number })?.registered ?? 0
    message.value = fp('error.bootstrapDone', { mirrors: mirror, discovered: discover })
    await load()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : fp('error.bootstrapFailed')
  } finally {
    syncing.value = false
  }
}

async function runBridgeOAuth() {
  syncing.value = true
  error.value = ''
  message.value = ''
  try {
    const res = await bridgeFreePoolOAuth()
    message.value = fp('error.oauthBridgeDone', { n: res.registered ?? 0 })
    await load()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : fp('error.oauthBridgeFailed')
  } finally {
    syncing.value = false
  }
}

async function runDiscover() {
  syncing.value = true
  error.value = ''
  message.value = ''
  try {
    const res = await discoverFreePool()
    message.value = fp('error.discoverDone', { n: res.registered ?? 0 })
    await load()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : fp('error.discoverFailed')
  } finally {
    syncing.value = false
  }
}

async function runImportEnv() {
  syncing.value = true
  error.value = ''
  message.value = ''
  try {
    const res = await importFreePoolEnv()
    message.value = fp('error.importEnvDone', { n: res.registered ?? 0 })
    await load()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : fp('error.importEnvFailed')
  } finally {
    syncing.value = false
  }
}

function useTemplate(tpl: FreePoolCatalogEntry) {
  newProvider.value.catalog_code = tpl.catalog_code
  newProvider.value.display_name = tpl.display_name
  newProvider.value.base_url = tpl.base_url
  newProvider.value.models = (tpl.models || []).join(',')
  showAddForm.value = true
}

function fillFromPlatform(p: SignupPlatformEntry) {
  quickEntry.value.platform_id = p.id
  quickEntry.value.signup_url = p.signup_url
  quickEntry.value.base_url = p.base_url
  quickEntry.value.catalog_code = p.catalog_code
  quickEntry.value.display_name = p.display_name
  quickEntry.value.source_detail = p.name
  activeTab.value = 'assistant'
  probeResult.value = null
}

function openUrl(url: string) {
  if (url) window.open(url, '_blank', 'noopener,noreferrer')
}

async function runQuickProbe() {
  if (!quickEntry.value.base_url.trim()) {
    error.value = fp('error.baseUrlRequired')
    return
  }
  quickProbing.value = true
  error.value = ''
  message.value = ''
  try {
    const res = await probeFreePoolCredential({
      base_url: quickEntry.value.base_url.trim(),
      api_key: quickEntry.value.api_key.trim() || undefined,
    })
    probeResult.value = res.probe
    message.value = res.probe?.ok
      ? fp('error.probePassed', { status: res.probe.status_code, n: res.probe.model_count ?? 0 })
      : fp('error.probeFailed', { reason: res.probe?.reason || res.probe?.error || fp('error.probeFailedReason') })
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : fp('error.probeFailed', { reason: fp('error.probeFailedReason') })
  } finally {
    quickProbing.value = false
  }
}

async function runQuickSave(probeFirst = true) {
  if (!quickEntry.value.base_url.trim()) {
    error.value = fp('error.baseUrlRequired')
    return
  }
  quickSaving.value = true
  error.value = ''
  message.value = ''
  try {
    const res = await quickEntryFreePool({
      signup_url: quickEntry.value.signup_url || undefined,
      base_url: quickEntry.value.base_url.trim(),
      api_key: quickEntry.value.api_key.trim() || undefined,
      display_name: quickEntry.value.display_name || undefined,
      catalog_code: quickEntry.value.catalog_code || undefined,
      source: quickEntry.value.source,
      source_detail: quickEntry.value.source_detail || undefined,
      platform_id: quickEntry.value.platform_id || undefined,
      probe_first: probeFirst,
      save: true,
    })
    probeResult.value = res.probe ?? null
    if (res.status === 'ok') {
      message.value = fp('error.credentialSaved', {
        code: res.catalog_code,
        id: res.credential_id ?? fp('error.credentialSavedPlaceholder'),
      })
      quickEntry.value.api_key = ''
      await load()
    } else {
      error.value = res.error || `${fp('error.saveFailed')} (${res.status})`
    }
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : fp('error.saveFailed')
  } finally {
    quickSaving.value = false
  }
}

async function generateTempEmail() {
  tempEmailLoading.value = true
  error.value = ''
  try {
    const res = await createFreePoolTempEmail()
    if (!res.ok || !res.address) {
      error.value = res.error || fp('error.tempEmailFailed')
      return
    }
    tempEmail.value = {
      address: res.address,
      password: res.password || '',
      token: res.token || '',
      web_url: res.web_url || 'https://mail.tm/en/',
    }
    tempInbox.value = []
    message.value = fp('error.tempEmailCreated', { address: res.address })
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : fp('error.tempEmailFailed')
  } finally {
    tempEmailLoading.value = false
  }
}

async function pollTempInbox() {
  if (!tempEmail.value?.token) return
  tempPolling.value = true
  try {
    const res = await pollFreePoolTempEmail(tempEmail.value.token)
    if (res.ok && res.messages) {
      tempInbox.value = res.messages
      message.value = fp('error.inboxCount', { n: res.total ?? res.messages.length })
    } else {
      error.value = res.error || fp('error.fetchInboxFailed')
    }
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : fp('error.fetchInboxFailed')
  } finally {
    tempPolling.value = false
  }
}

async function copyText(text: string) {
  try {
    await navigator.clipboard.writeText(text)
    message.value = fp('error.copySuccess')
  } catch {
    error.value = fp('error.copyFailed')
  }
}

async function submitKey() {
  if (!newKey.value.catalog_code || (!newKey.value.api_key && newKey.value.source !== 'no_key')) {
    error.value = fp('error.catalogAndApiKeyRequired')
    return
  }
  keySubmitting.value = true
  error.value = ''
  message.value = ''
  try {
    await addFreePoolKey({
      catalog_code: newKey.value.catalog_code,
      api_key: newKey.value.api_key,
      source: newKey.value.source,
      source_detail: newKey.value.source_detail || undefined,
      label: newKey.value.label || undefined,
    })
    message.value = fp('error.encryptedWriteSuccess')
    showKeyForm.value = false
    newKey.value = { catalog_code: 'openrouter-free', api_key: '', source: 'signup', source_detail: '', label: '' }
    await load()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : fp('error.writeFailed')
  } finally {
    keySubmitting.value = false
  }
}

async function submitNew() {
  if (!newProvider.value.catalog_code || !newProvider.value.base_url) {
    error.value = fp('error.catalogAndBaseUrlRequired')
    return
  }
  submitting.value = true
  error.value = ''
  message.value = ''
  try {
    const models = newProvider.value.models
      .split(',')
      .map(s => s.trim())
      .filter(Boolean)

    const res = await registerFreeProvider({
      catalog_code: newProvider.value.catalog_code,
      display_name: newProvider.value.display_name || newProvider.value.catalog_code,
      base_url: newProvider.value.base_url,
      protocol: newProvider.value.protocol,
      api_key: newProvider.value.api_key || undefined,
      models: models.length > 0 ? models : undefined,
    })
    message.value = fp('error.providerRegistered', { id: res.provider_id })
    showAddForm.value = false
    newProvider.value = {
      catalog_code: '',
      display_name: '',
      base_url: '',
      protocol: 'openai-completions',
      api_key: '',
      models: '',
    }
    await load()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : fp('error.registerFailed')
  } finally {
    submitting.value = false
  }
}

function statusBadgeClass(entry: FreePoolEntry | FreePoolModelEntry): string {
  if (entry.credential_status !== 'active') return 'badge-red'
  if (entry.availability_state === 'rate_limited' || entry.availability_state === 'cooling' || entry.availability_state === 'unreachable') return 'badge-orange'
  const quota = entry.quota_state
  if (quota === 'exhausted' || quota === 'balance_exhausted') return 'badge-orange'
  if ('routable' in entry && !entry.routable) return 'badge-orange'
  return 'badge-green'
}

function statusLabel(entry: FreePoolEntry): string {
  if (entry.credential_status !== 'active') return fp('status.disabled')
  if (entry.availability_state === 'rate_limited') return fp('status.rateLimited')
  if (entry.availability_state === 'cooling') return fp('status.cooling')
  if (entry.availability_state === 'unreachable') return fp('status.unreachable')
  if (entry.quota_state === 'exhausted') return fp('status.quotaExhausted')
  return fp('status.available')
}

function modelStatusLabel(m: FreePoolModelEntry): string {
  if (m.credential_status !== 'active') return fp('status.disabled')
  if (!m.available) return fp('status.modelClosed')
  if (!m.routable) return fp('status.notRoutable')
  return fp('status.routable')
}

function riskClass(risk: string): string {
  if (risk === 'high') return 'risk-high'
  if (risk === 'medium') return 'risk-medium'
  return 'risk-low'
}

function acquisitionLabel(mode: string): string {
  const map: Record<string, string> = {
    signup: fp('acquisition.signup'),
    env: fp('acquisition.env'),
    no_key: fp('acquisition.noKey'),
    oauth: fp('acquisition.oauth'),
    mirrored: fp('acquisition.mirrored'),
    manual: fp('acquisition.manual'),
    discovered: fp('acquisition.discovered'),
  }
  return map[mode] || mode
}

function categoryLabel(id: string): string {
  const row = hubCategories.value.find(c => c.id === id)
  return row?.label || id
}

onMounted(load)
</script>

<template>
  <div>
    <div class="page-header">
      <h2>{{ fp('page.title') }}</h2>
      <div style="display:flex;gap:8px;flex-wrap:wrap">
        <button class="btn btn-ghost" @click="load" :disabled="loading || syncing">{{ fp('header.refresh') }}</button>
        <button class="btn btn-ghost" @click="runBootstrap" :disabled="loading || syncing">
          {{ syncing ? fp('header.bootstrapSyncing') : fp('header.bootstrap') }}
        </button>
        <button class="btn btn-ghost" @click="runBridgeOAuth" :disabled="loading || syncing">
          {{ fp('header.bridgeOAuth') }}
        </button>
        <button class="btn btn-ghost" @click="runImportEnv" :disabled="loading || syncing">
          {{ fp('header.importEnv') }}
        </button>
        <button class="btn btn-ghost" @click="runDiscover" :disabled="loading || syncing">
          {{ fp('header.discover') }}
        </button>
        <button class="btn btn-primary" @click="activeTab = 'assistant'; showKeyForm = false; showAddForm = false">
          {{ fp('header.quickEntry') }}
        </button>
        <button class="btn btn-primary" @click="showKeyForm = !showKeyForm">
          {{ showKeyForm ? fp('header.hideKeyForm') : fp('header.showKeyForm') }}
        </button>
        <button class="btn btn-primary" @click="showAddForm = !showAddForm">
          {{ showAddForm ? fp('header.hideAddForm') : fp('header.showAddForm') }}
        </button>
      </div>
    </div>
    <p style="color:var(--muted);margin-bottom:20px" v-html="fp('page.desc')" />

    <div v-if="error" class="alert alert-danger">{{ error }}</div>
    <div v-if="message" class="alert alert-success">{{ message }}</div>

    <div v-if="poolData" class="stat-row" style="margin-bottom:20px">
      <div class="stat-inline">
        <span class="stat-label">{{ fp('stats.routableModels') }}</span>
        <span class="stat-value stat-ok">{{ poolData.stats.routable_models }}</span>
        <span class="stat-sub">/ {{ poolData.stats.free_models }} {{ fp('stats.offerUnit') }}</span>
      </div>
      <div class="stat-inline">
        <span class="stat-label">{{ fp('stats.availableProviders') }}</span>
        <span class="stat-value stat-ok">{{ poolData.stats.available_providers }}</span>
        <span class="stat-sub">/ {{ poolData.stats.total_providers }}</span>
      </div>
      <div class="stat-inline">
        <span class="stat-label">{{ fp('stats.templatesLinked') }}</span>
        <span class="stat-value">{{ poolData.stats.catalog_registered }}</span>
        <span class="stat-sub">/ {{ poolData.stats.catalog_templates }} {{ fp('stats.templatesUnit') }}</span>
      </div>
      <div class="stat-inline">
        <span class="stat-label">{{ fp('stats.templateModels') }}</span>
        <span class="stat-value">{{ catalogSummary.templateModels }}</span>
        <span class="stat-sub">{{ fp('stats.catalogKnown') }}</span>
      </div>
    </div>

    <div v-if="showKeyForm" class="card" style="margin-bottom:20px">
      <h3 style="margin-top:0">{{ fp('keyForm.title') }}</h3>
      <p class="cell-muted" style="margin:0 0 12px" v-html="fp('keyForm.desc')" />
      <div class="form-grid">
        <div class="form-item">
          <label>{{ fp('keyForm.catalogCode') }}</label>
          <select v-model="newKey.catalog_code" class="input">
            <option v-for="tpl in catalog" :key="tpl.catalog_code" :value="tpl.catalog_code">
              {{ tpl.display_name }} ({{ tpl.catalog_code }})
            </option>
          </select>
        </div>
        <div class="form-item">
          <label>{{ fp('keyForm.source') }}</label>
          <select v-model="newKey.source" class="input">
            <option value="signup">signup（官方注册）</option>
            <option value="env">env（环境变量导入）</option>
            <option value="manual">manual（手动）</option>
            <option value="oauth">oauth</option>
            <option value="mirrored">mirrored</option>
          </select>
        </div>
        <div class="form-item" style="grid-column:1/-1">
          <label>{{ fp('keyForm.apiKey') }}</label>
          <input v-model="newKey.api_key" class="input" type="password" placeholder="sk-..." />
        </div>
        <div class="form-item">
          <label>{{ fp('keyForm.sourceDetail') }}</label>
          <input v-model="newKey.source_detail" class="input" :placeholder="fp('keyForm.sourceDetailPlaceholder')" />
        </div>
        <div class="form-item">
          <label>{{ fp('keyForm.label') }}</label>
          <input v-model="newKey.label" class="input" :placeholder="fp('keyForm.labelPlaceholder')" />
        </div>
      </div>
      <div style="margin-top:12px;display:flex;gap:8px">
        <button class="btn btn-primary" :disabled="keySubmitting" @click="submitKey">
          {{ keySubmitting ? fp('keyForm.submitting') : fp('keyForm.submit') }}
        </button>
        <button class="btn btn-ghost" @click="showKeyForm = false">{{ fp('keyForm.cancel') }}</button>
      </div>
    </div>

    <div v-if="showAddForm" class="card" style="margin-bottom:20px">
      <h3 style="margin-top:0">{{ fp('providerForm.title') }}</h3>
      <div class="form-grid">
        <div class="form-item">
          <label>{{ fp('providerForm.catalogCode') }}</label>
          <input v-model="newProvider.catalog_code" class="input" :placeholder="fp('providerForm.catalogCodePlaceholder')" />
        </div>
        <div class="form-item">
          <label>{{ fp('providerForm.displayName') }}</label>
          <input v-model="newProvider.display_name" class="input" :placeholder="fp('providerForm.displayNamePlaceholder')" />
        </div>
        <div class="form-item" style="grid-column: 1 / -1">
          <label>{{ fp('providerForm.baseUrl') }}</label>
          <input v-model="newProvider.base_url" class="input" :placeholder="fp('providerForm.baseUrlPlaceholder')" />
        </div>
        <div class="form-item">
          <label>{{ fp('providerForm.protocol') }}</label>
          <select v-model="newProvider.protocol" class="input">
            <option value="openai-completions">openai-completions</option>
            <option value="openai-responses">openai-responses</option>
            <option value="anthropic-messages">anthropic-messages</option>
          </select>
        </div>
        <div class="form-item">
          <label>{{ fp('providerForm.apiKey') }}</label>
          <input v-model="newProvider.api_key" class="input" type="password" :placeholder="fp('providerForm.apiKeyPlaceholder')" />
        </div>
        <div class="form-item" style="grid-column: 1 / -1">
          <label>{{ fp('providerForm.models') }}</label>
          <input v-model="newProvider.models" class="input" :placeholder="fp('providerForm.modelsPlaceholder')" />
        </div>
      </div>

      <div style="margin-top:16px">
        <h4 style="font-size:13px;margin-bottom:8px;color:var(--muted)">{{ fp('providerForm.templatesTitle') }}</h4>
        <div style="display:flex;gap:8px;flex-wrap:wrap">
          <button
            v-for="tpl in catalog"
            :key="tpl.catalog_code"
            class="btn btn-ghost btn-sm"
            @click="useTemplate(tpl)"
            style="font-size:12px"
            :title="tpl.pool_registered ? fp('providerForm.templateInPool') : (tpl.env_configured ? fp('providerForm.templateEnvConfigured') : (tpl.needs_key ? fp('providerForm.templateNeedsKey') : fp('providerForm.templateNoKey')))"
          >
            {{ tpl.display_name }}{{ tpl.pool_registered ? ' ✓' : (tpl.env_configured ? ' 🔑' : '') }}
          </button>
        </div>
      </div>

      <div style="margin-top:16px;display:flex;gap:8px;align-items:center">
        <button class="btn btn-primary" @click="submitNew" :disabled="submitting">
          {{ submitting ? fp('providerForm.submitting') : fp('providerForm.submit') }}
        </button>
        <button class="btn btn-ghost" @click="showAddForm = false" :disabled="submitting">{{ fp('providerForm.cancel') }}</button>
      </div>
    </div>

    <div v-if="loading" class="empty">{{ t('common.feedback.loading') }}</div>

    <template v-else-if="poolData">
      <div class="tab-bar" style="margin-bottom:16px">
        <button class="tab-btn" :class="{ active: activeTab === 'assistant' }" @click="activeTab = 'assistant'">
          {{ fp('tab.assistant') }}
        </button>
        <button class="tab-btn" :class="{ active: activeTab === 'models' }" @click="activeTab = 'models'">
          {{ fp('tab.models', { n: liveModels.length }) }}
        </button>
        <button class="tab-btn" :class="{ active: activeTab === 'providers' }" @click="activeTab = 'providers'">
          {{ fp('tab.providers', { n: poolData.pool.length }) }}
        </button>
        <button class="tab-btn" :class="{ active: activeTab === 'catalog' }" @click="activeTab = 'catalog'">
          {{ fp('tab.catalog', { n: catalog.length }) }}
        </button>
        <button class="tab-btn" :class="{ active: activeTab === 'keys' }" @click="activeTab = 'keys'">
          {{ fp('tab.keys', { n: poolKeys.length }) }}
        </button>
        <button class="tab-btn" :class="{ active: activeTab === 'guide' }" @click="activeTab = 'guide'">
          {{ fp('tab.guide') }}
        </button>
      </div>

      <!-- Assistant tab -->
      <div v-if="activeTab === 'assistant'" class="assistant-layout">
        <div class="card quick-entry-card">
          <h3 style="margin-top:0">{{ fp('assistant.title') }}</h3>
          <p class="cell-muted" style="margin:0 0 12px">
            {{ fp('assistant.desc') }}
          </p>
          <div class="form-grid">
            <div class="form-item" style="grid-column:1/-1">
              <label>{{ fp('assistant.signupUrl') }}</label>
              <input v-model="quickEntry.signup_url" class="input" :placeholder="fp('assistant.signupUrlPlaceholder')" />
            </div>
            <div class="form-item" style="grid-column:1/-1">
              <label>{{ fp('assistant.baseUrl') }}</label>
              <input v-model="quickEntry.base_url" class="input" :placeholder="fp('assistant.baseUrlPlaceholder')" />
            </div>
            <div class="form-item">
              <label>{{ fp('assistant.catalogCode') }}</label>
              <input v-model="quickEntry.catalog_code" class="input" :placeholder="fp('assistant.catalogCodePlaceholder')" />
            </div>
            <div class="form-item">
              <label>{{ fp('assistant.displayName') }}</label>
              <input v-model="quickEntry.display_name" class="input" :placeholder="fp('assistant.displayNamePlaceholder')" />
            </div>
            <div class="form-item" style="grid-column:1/-1">
              <label>{{ fp('assistant.apiKey') }}</label>
              <input v-model="quickEntry.api_key" class="input" type="password" placeholder="sk-..." />
            </div>
            <div class="form-item">
              <label>{{ fp('assistant.source') }}</label>
              <select v-model="quickEntry.source" class="input">
                <option value="signup">signup（官方注册）</option>
                <option value="manual">manual（中转/手动）</option>
                <option value="env">env</option>
                <option value="discovered">discovered</option>
              </select>
            </div>
            <div class="form-item">
              <label>{{ fp('assistant.sourceDetail') }}</label>
              <input v-model="quickEntry.source_detail" class="input" :placeholder="fp('assistant.sourceDetailPlaceholder')" />
            </div>
          </div>
          <div v-if="probeResult" class="probe-box">
            <strong>{{ fp('assistant.probeResult') }}</strong>
            <pre>{{ JSON.stringify(probeResult, null, 2) }}</pre>
          </div>
          <div style="margin-top:12px;display:flex;gap:8px;flex-wrap:wrap">
            <button class="btn btn-ghost" :disabled="quickProbing || quickSaving" @click="runQuickProbe">
              {{ quickProbing ? fp('assistant.probeOnlyLoading') : fp('assistant.probeOnly') }}
            </button>
            <button class="btn btn-primary" :disabled="quickProbing || quickSaving" @click="runQuickSave(true)">
              {{ quickSaving ? fp('assistant.probeAndSaveLoading') : fp('assistant.probeAndSave') }}
            </button>
            <button
              v-if="quickEntry.signup_url"
              class="btn btn-ghost"
              @click="openUrl(quickEntry.signup_url)"
            >{{ fp('assistant.openSignup') }}</button>
          </div>
        </div>

        <div class="card">
          <h3 style="margin-top:0">{{ fp('assistant.tempEmailTitle') }}</h3>
          <p class="cell-muted" style="margin:0 0 12px">
            {{ fp('assistant.tempEmailDesc') }}
          </p>
          <div style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:12px">
            <button class="btn btn-primary" :disabled="tempEmailLoading" @click="generateTempEmail">
              {{ tempEmailLoading ? fp('assistant.generateTempEmailLoading') : fp('assistant.generateTempEmail') }}
            </button>
            <button
              v-if="tempEmail"
              class="btn btn-ghost"
              :disabled="tempPolling"
              @click="pollTempInbox"
            >{{ tempPolling ? fp('assistant.refreshInboxLoading') : fp('assistant.refreshInbox') }}</button>
            <button v-if="tempEmail" class="btn btn-ghost" @click="openUrl(tempEmail.web_url)">{{ fp('assistant.openMailTm') }}</button>
          </div>
          <div v-if="tempEmail" class="temp-email-box">
            <div class="temp-row">
              <span class="cell-muted">{{ fp('assistant.address') }}</span>
              <code>{{ tempEmail.address }}</code>
              <button class="btn btn-ghost btn-sm" @click="copyText(tempEmail.address)">{{ fp('assistant.copy') }}</button>
            </div>
            <div class="temp-row">
              <span class="cell-muted">{{ fp('assistant.password') }}</span>
              <code>{{ tempEmail.password }}</code>
              <button class="btn btn-ghost btn-sm" @click="copyText(tempEmail.password)">{{ fp('assistant.copy') }}</button>
            </div>
          </div>
          <ul v-if="tempInbox.length" class="inbox-list">
            <li v-for="m in tempInbox" :key="m.id">
              <strong>{{ m.subject || fp('assistant.noSubject') }}</strong>
              <div class="cell-muted">{{ m.from }} · {{ m.intro }}</div>
            </li>
          </ul>
          <div v-if="signupHub" class="tool-links" style="margin-top:16px">
            <span class="cell-muted">{{ fp('assistant.otherTools') }}</span>
            <button
              v-for="t in signupHub.tools.filter(x => x.tool_type === 'temp_email' && !x.builtin)"
              :key="t.id"
              class="btn btn-ghost btn-sm"
              @click="openUrl(t.url)"
            >{{ t.name }}</button>
          </div>
        </div>

        <div class="card platform-hub">
          <div class="section-header">
            <div>
              <h3 style="margin:0">{{ fp('assistant.hubTitle') }}</h3>
              <p class="cell-muted" style="margin:4px 0 0">{{ fp('assistant.hubDesc') }}</p>
            </div>
            <input v-model="hubQuery" class="input search-input" :placeholder="fp('assistant.searchPlaceholder')" />
          </div>
          <div class="hub-filters">
            <button
              class="tab-btn btn-sm"
              :class="{ active: hubCategory === 'all' }"
              @click="hubCategory = 'all'"
            >{{ fp('assistant.filterAll') }}</button>
            <button
              v-for="cat in hubCategories"
              :key="cat.id"
              class="tab-btn btn-sm"
              :class="{ active: hubCategory === cat.id }"
              @click="hubCategory = cat.id"
            >{{ cat.label }}</button>
          </div>
          <div class="platform-grid">
            <div v-for="p in hubPlatforms" :key="p.id" class="platform-card">
              <div class="platform-head">
                <strong>{{ p.name }}</strong>
                <span class="badge" :class="p.pool_registered ? 'badge-green' : 'badge-gray'">
                  {{ p.pool_registered ? fp('assistant.registered') : fp('assistant.notRegistered') }}
                </span>
              </div>
              <div class="cell-muted">{{ categoryLabel(p.category) }} · {{ p.difficulty }}</div>
              <code class="model-code" style="display:block;margin:6px 0">{{ p.base_url }}</code>
              <p v-if="p.notes" class="cell-muted" style="margin:0 0 8px">{{ p.notes }}</p>
              <div v-if="p.models_hint" class="cell-muted">{{ fp('assistant.modelsLabel') }}{{ p.models_hint }}</div>
              <div v-if="p.tags && p.tags.length" class="tag-row">
                <span v-for="tag in p.tags" :key="tag" class="model-tag template">{{ tag }}</span>
              </div>
              <div class="platform-actions">
                <button class="btn btn-primary btn-sm" @click="fillFromPlatform(p)">{{ fp('assistant.fillForm') }}</button>
                <button class="btn btn-ghost btn-sm" @click="openUrl(p.signup_url)">{{ fp('assistant.openSignup2') }}</button>
                <button
                  v-if="p.api_key_url && p.api_key_url !== p.signup_url"
                  class="btn btn-ghost btn-sm"
                  @click="openUrl(p.api_key_url)"
                >{{ fp('assistant.getKey') }}</button>
              </div>
            </div>
          </div>
          <div v-if="signupHub?.workflow?.length" style="margin-top:20px">
            <h4 style="margin-bottom:8px">{{ fp('assistant.recommendedWorkflow') }}</h4>
            <ol class="guide-steps">
              <li v-for="step in signupHub.workflow" :key="step.step">
                <strong>{{ step.title }}</strong> — {{ step.detail }}
              </li>
            </ol>
          </div>
        </div>
      </div>

      <!-- Models tab -->
      <div v-if="activeTab === 'models'" class="card">
        <div class="section-header">
          <div>
            <h3 style="margin:0">{{ fp('models.title') }}</h3>
            <p class="cell-muted" style="margin:4px 0 0">
              {{ fp('models.desc', { n: routableModels.length }) }}
            </p>
          </div>
          <input v-model="modelQuery" class="input search-input" :placeholder="fp('models.searchPlaceholder')" />
        </div>

        <div v-if="filteredModels.length === 0" class="empty">{{ fp('models.empty') }}</div>
        <table v-else>
          <thead>
            <tr>
              <th>{{ fp('models.colName') }}</th>
              <th>{{ fp('models.colProvider') }}</th>
              <th>{{ fp('models.colCatalog') }}</th>
              <th>{{ fp('models.colTier') }}</th>
              <th>{{ fp('models.colStatus') }}</th>
              <th>{{ fp('models.colCredential') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="m in filteredModels" :key="m.offer_id">
              <td>
                <code class="model-code">{{ m.raw_model_name }}</code>
                <div v-if="m.standardized_name && m.standardized_name !== m.raw_model_name" class="cell-muted">
                  {{ fp('models.standardName') }}{{ m.standardized_name }}
                </div>
              </td>
              <td>{{ m.provider_name }}</td>
              <td><code style="font-size:11px">{{ m.catalog_code }}</code></td>
              <td><span class="tier-pill">T{{ m.routing_tier }}</span></td>
              <td>
                <span class="badge" :class="statusBadgeClass(m)">{{ modelStatusLabel(m) }}</span>
              </td>
              <td>
                <div class="cell-muted">{{ m.credential_label }}</div>
                <div class="cell-muted">#{{ m.credential_id }}</div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Providers tab -->
      <div v-if="activeTab === 'providers'" class="card">
        <h3 style="margin-top:0">{{ fp('providers.title') }}</h3>
        <div v-if="poolData.pool.length === 0" class="empty">{{ fp('providers.empty') }}</div>
        <table v-else>
          <thead>
            <tr>
              <th>{{ fp('providers.colCatalogName') }}</th>
              <th>{{ fp('providers.colCredential') }}</th>
              <th>{{ fp('providers.colStatus') }}</th>
              <th>{{ fp('providers.colModels') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="entry in poolData.pool" :key="entry.credential_id">
              <td>
                <code style="font-size:11px">{{ entry.catalog_code }}</code>
                <div>{{ entry.provider_name }}</div>
              </td>
              <td>
                <div>{{ entry.credential_label }}</div>
                <div class="cell-muted">#{{ entry.credential_id }} · {{ entry.availability_state || fp('providers.ready') }}</div>
              </td>
              <td>
                <span class="badge" :class="statusBadgeClass(entry)">{{ statusLabel(entry) }}</span>
              </td>
              <td>
                <div v-if="entry.models && entry.models.length" class="model-tags">
                  <span
                    v-for="m in entry.models"
                    :key="m.offer_id"
                    class="model-tag"
                    :class="{ routable: m.routable, dim: !m.available }"
                    :title="m.routable ? fp('providers.routable') : fp('providers.notRoutable')"
                  >{{ m.raw_model_name }}</span>
                </div>
                <div v-else class="cell-muted">{{ fp('providers.noModels') }}</div>
                <div class="cell-muted">{{ fp('providers.freeUnit') }} {{ entry.free_offers }} / {{ fp('providers.availableUnit') }} {{ entry.available_offers }}</div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Catalog tab -->
      <div v-if="activeTab === 'catalog'" class="card">
        <h3 style="margin-top:0">{{ fp('catalog.title') }}</h3>
        <p class="cell-muted" style="margin-top:0;margin-bottom:16px">
          {{ fp('catalog.desc') }}
        </p>
        <table>
          <thead>
            <tr>
              <th>{{ fp('catalog.colProvider') }}</th>
              <th>{{ fp('catalog.colInPool') }}</th>
              <th>{{ fp('catalog.colAcquisition') }}</th>
              <th>{{ fp('catalog.colTemplateModels') }}</th>
              <th>{{ fp('catalog.colLiveModels') }}</th>
              <th>{{ fp('catalog.colActions') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="tpl in catalog" :key="tpl.catalog_code">
              <td>
                <div>{{ tpl.display_name }}</div>
                <code style="font-size:11px">{{ tpl.catalog_code }}</code>
                <div class="cell-muted">{{ tpl.base_url }}</div>
              </td>
              <td>
                <span class="badge" :class="tpl.pool_registered ? 'badge-green' : 'badge-gray'">
                  {{ tpl.pool_registered ? fp('catalog.registered') : fp('catalog.notRegistered') }}
                </span>
                <div v-if="tpl.env_configured" class="cell-muted">{{ fp('catalog.envConfigured') }}</div>
              </td>
              <td>
                <span class="acq-pill">{{ acquisitionLabel(tpl.acquisition_mode) }}</span>
                <div v-if="tpl.needs_key && tpl.env_vars && tpl.env_vars.length" class="cell-muted">
                  {{ tpl.env_vars.join(' / ') }}
                </div>
                <div v-if="tpl.rpm_limit" class="cell-muted">~{{ tpl.rpm_limit }} {{ fp('catalog.rpmUnit') }}</div>
              </td>
              <td>
                <div class="model-tags">
                  <span v-for="name in (tpl.models || [])" :key="name" class="model-tag template">{{ name }}</span>
                </div>
              </td>
              <td>
                <div v-if="tpl.live_models && tpl.live_models.length" class="model-tags">
                  <span v-for="name in tpl.live_models" :key="name" class="model-tag routable">{{ name }}</span>
                </div>
                <span v-else class="cell-muted">—</span>
              </td>
              <td>
                <a v-if="tpl.signup_url" :href="tpl.signup_url" target="_blank" rel="noopener" class="btn btn-ghost btn-sm">{{ fp('catalog.signup') }}</a>
                <button class="btn btn-ghost btn-sm" @click="useTemplate(tpl)">{{ fp('catalog.fillForm') }}</button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Keys tab -->
      <div v-if="activeTab === 'keys'" class="card">
        <h3 style="margin-top:0">{{ fp('keys.title') }}</h3>
        <p class="cell-muted" style="margin:0 0 12px">
          {{ fp('keys.desc') }}
        </p>
        <table v-if="poolKeys.length">
          <thead>
            <tr>
              <th>{{ fp('keys.colProvider') }}</th>
              <th>{{ fp('keys.colKeyMasked') }}</th>
              <th>{{ fp('keys.colSource') }}</th>
              <th>{{ fp('keys.colDetail') }}</th>
              <th>{{ fp('keys.colStatus') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="k in poolKeys" :key="k.credential_id">
              <td>
                <div>{{ k.provider_name }}</div>
                <code style="font-size:11px">{{ k.catalog_code }}</code>
                <div class="cell-muted">#{{ k.credential_id }} · {{ k.credential_label }}</div>
              </td>
              <td><code class="model-code">{{ k.key_masked || (k.has_secret ? '***' : fp('keys.noKey')) }}</code></td>
              <td><span class="acq-pill">{{ acquisitionLabel(k.acquisition_source || 'manual') }}</span></td>
              <td class="cell-muted">{{ k.acquisition_detail || '—' }}</td>
              <td>
                <span class="badge" :class="k.credential_status === 'active' ? 'badge-green' : 'badge-gray'">
                  {{ k.credential_status }}
                </span>
                <div class="cell-muted">{{ k.availability_state }}</div>
              </td>
            </tr>
          </tbody>
        </table>
        <div v-else class="empty">{{ fp('keys.empty') }}</div>
      </div>

      <!-- Guide tab -->
      <div v-if="activeTab === 'guide' && methodsData" class="card">
        <h3 style="margin-top:0">{{ fp('guide.title') }}</h3>
        <p class="cell-muted" style="margin-top:0;margin-bottom:16px" v-html="fp('guide.desc', { n: Math.round(methodsData.scheduler.interval_sec / 60) })" />
        <div class="guide-grid">
          <div v-for="m in methodsData.methods" :key="m.mode" class="guide-card">
            <div class="guide-head">
              <strong>{{ m.title }}</strong>
              <span class="acq-pill" :class="riskClass(m.risk)">{{ acquisitionLabel(m.mode) }}</span>
            </div>
            <p class="cell-muted">{{ m.summary }}</p>
            <ol class="guide-steps">
              <li v-for="(step, i) in m.steps" :key="i">{{ step }}</li>
            </ol>
            <div class="cell-muted">{{ m.automated ? fp('guide.automated') : fp('guide.manual') }} · {{ fp('guide.riskLabel') }} {{ m.risk }}</div>
          </div>
        </div>
        <h4 style="margin:24px 0 12px">{{ fp('guide.auditTitle') }}</h4>
        <table>
          <thead>
            <tr><th>{{ fp('guide.auditColRule') }}</th><th>{{ fp('guide.auditColStatus') }}</th><th>{{ fp('guide.auditColDetail') }}</th></tr>
          </thead>
          <tbody>
            <tr v-for="rule in methodsData.audit_rules" :key="rule.id">
              <td>{{ rule.title }}</td>
              <td><span class="badge badge-green">{{ rule.status }}</span></td>
              <td class="cell-muted">{{ rule.detail }}</td>
            </tr>
          </tbody>
        </table>
        <div v-if="methodsData.scheduler.last_result && Object.keys(methodsData.scheduler.last_result).length" style="margin-top:16px">
          <h4 style="margin-bottom:8px">{{ fp('guide.lastRunTitle') }}</h4>
          <pre class="discovery-log">{{ JSON.stringify(methodsData.scheduler.last_result, null, 2) }}</pre>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
.cell-muted { color: var(--muted); font-size: 11px; margin-top: 3px; }

.stat-row {
  display: flex;
  flex-wrap: nowrap;
  gap: 10px;
  overflow-x: auto;
}
.stat-inline {
  display: flex;
  align-items: baseline;
  gap: 8px;
  flex: 1 1 0;
  min-width: 160px;
  padding: 10px 14px;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  white-space: nowrap;
}
.stat-label { font-size: 12px; color: var(--muted); }
.stat-value { font-size: 20px; font-weight: 700; color: var(--text); }
.stat-value.stat-ok { color: var(--success); }
.stat-sub { font-size: 12px; color: var(--muted); }

.form-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}
.form-item {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.form-item label {
  font-size: 12px;
  font-weight: 600;
  color: var(--muted);
}

.tab-bar { display: flex; gap: 8px; flex-wrap: wrap; }
.tab-btn {
  border: 1px solid var(--border);
  background: var(--bg-subtle, var(--card));
  color: var(--text);
  padding: 8px 14px;
  border-radius: 8px;
  cursor: pointer;
  font-size: 13px;
  transition: background .15s, color .15s;
}
.tab-btn:hover:not(.active) {
  border-color: var(--accent);
  color: var(--accent-h);
}
.tab-btn.active {
  background: var(--accent);
  color: #fff;
  border-color: transparent;
}

.section-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 12px;
  margin-bottom: 16px;
  flex-wrap: wrap;
}
.search-input { max-width: 280px; min-width: 200px; }

.model-code { font-size: 12px; font-weight: 600; color: var(--accent-h); }
.model-tags { display: flex; flex-wrap: wrap; gap: 6px; }
.model-tag {
  display: inline-block;
  font-size: 11px;
  padding: 2px 8px;
  border-radius: 999px;
  background: rgba(139,148,158,.12);
  color: var(--text);
  border: 1px solid var(--border);
}
.model-tag.routable {
  background: rgba(63,185,80,.15);
  border-color: rgba(63,185,80,.35);
  color: var(--success);
}
.model-tag.template {
  background: rgba(99,102,241,.12);
  border-color: rgba(99,102,241,.35);
  color: var(--accent-h);
}
.model-tag.dim { opacity: 0.45; }

.tier-pill {
  font-size: 11px;
  font-weight: 700;
  padding: 2px 8px;
  border-radius: 6px;
  background: rgba(210,153,34,.15);
  color: var(--warning);
}
.acq-pill {
  font-size: 11px;
  padding: 2px 8px;
  border-radius: 6px;
  background: rgba(139,148,158,.12);
  color: var(--text);
}
.acq-pill.risk-high { color: var(--danger); background: rgba(248,81,73,.12); }
.acq-pill.risk-medium { color: var(--warning); background: rgba(210,153,34,.12); }
.acq-pill.risk-low { color: var(--success); background: rgba(63,185,80,.12); }

.guide-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 12px;
}
.guide-card {
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 12px;
  background: var(--bg-subtle, var(--bg));
}
.guide-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
  margin-bottom: 8px;
}
.guide-steps {
  margin: 8px 0 8px 18px;
  font-size: 12px;
  color: var(--text);
}
.discovery-log {
  font-size: 11px;
  padding: 12px;
  border-radius: var(--radius);
  background: var(--bg);
  border: 1px solid var(--border);
  color: var(--muted);
  overflow-x: auto;
  max-height: 240px;
}

.badge-orange { background: rgba(210,153,34,.15); color: var(--warning); }
.badge-gray { background: rgba(139,148,158,.15); color: var(--muted); }

.assistant-layout {
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.platform-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 12px;
  margin-top: 12px;
}
.platform-card {
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 12px;
  background: var(--bg-subtle, var(--bg));
}
.platform-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
  margin-bottom: 4px;
}
.platform-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-top: 10px;
}
.hub-filters {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}
.btn-sm { font-size: 12px; padding: 4px 10px; }
.tag-row { display: flex; flex-wrap: wrap; gap: 4px; margin-top: 6px; }
.probe-box {
  margin-top: 12px;
  padding: 10px;
  border-radius: var(--radius);
  border: 1px solid var(--border);
  background: var(--bg);
}
.probe-box pre {
  font-size: 11px;
  margin: 8px 0 0;
  overflow-x: auto;
  max-height: 120px;
  color: var(--muted);
}
.temp-email-box {
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 10px;
  background: var(--bg-subtle, var(--bg));
}
.temp-row {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
  margin-bottom: 6px;
}
.temp-row code { font-size: 12px; word-break: break-all; }
.inbox-list {
  margin: 12px 0 0;
  padding-left: 18px;
  font-size: 12px;
}
.tool-links { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }
</style>
