<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { getKeys, listModels, getFeatured, applyForKey, revealKey, type ApiKey, type ModelCanonical } from '../api'
import {
  TOOLS, OS_INFO,
  type ToolId, type OS, type ModelScope,
  renderZCodeConfig, renderOpenCodeConfig,
  renderCherryStudioConfig, renderRooCodeSettings,
  generateShellScript, getManualSteps,
  downloadFile, auditAction,
} from '../composables/useClientConfig'

const props = defineProps<{ tool: ToolId; open: boolean }>()
const emit = defineEmits<{ (e: 'close'): void }>()
const router = useRouter()
const { t } = useI18n()

const toolInfo = computed(() => TOOLS.find(t => t.id === props.tool)!)

// ── Step 1: Key selection (all tenant keys for admin) ──────────────────────
const keys = ref<ApiKey[]>([])
const selectedKeyId = ref<number | null>(null)
const keysLoading = ref(false)
const applyDialogOpen = ref(false)
const applying = ref(false)
const applyError = ref('')
const applyForm = ref({ application_code: 'default-app', description: '' })

async function loadKeys() {
  keysLoading.value = true
  try {
    keys.value = await getKeys()
    if (keys.value.length > 0 && !selectedKeyId.value) {
      selectedKeyId.value = keys.value[0].id
    }
  } catch {
    keys.value = []
  } finally {
    keysLoading.value = false
  }
}

async function submitApply() {
  applying.value = true
  applyError.value = ''
  try {
    const resp = await applyForKey({
      application_code: applyForm.value.application_code,
      description: applyForm.value.description,
    })
    applyDialogOpen.value = false
    await loadKeys()
    if (resp?.id && keys.value.length > 0) {
      const found = keys.value.find(k => k.id === resp.id)
      if (found) selectedKeyId.value = found.id
    }
    applyForm.value = { application_code: 'default-app', description: '' }
  } catch (e: any) {
    applyError.value = e?.message || t('clientConfigDialog.error.applyFailed')
  } finally {
    applying.value = false
  }
}

// ── Step 2: OS selection ─────────────────────────────────────────────────────
const selectedOS = ref<OS>('macos')

// ── Step 3: Model scope + custom selection ──────────────────────────────────
const selectedScope = ref<ModelScope>('featured')
const selectedModels = ref<string[]>([])
const allModels = ref<ModelCanonical[]>([])
const allModelsLoading = ref(false)
const allModelsLoaded = ref(false)
const featuredModels = ref<string[]>([])
const featuredLoading = ref(false)
const featuredLoaded = ref(false)
const modelSearch = ref('')

async function loadFeaturedModels() {
  if (featuredLoaded.value) return
  featuredLoading.value = true
  try {
    const resp = await getFeatured()
    featuredModels.value = resp.featured_models || []
    featuredLoaded.value = true
    if (selectedModels.value.length === 0 && featuredModels.value.length > 0) {
      selectedModels.value = [...featuredModels.value]
    }
  } catch {
    featuredModels.value = []
  } finally {
    featuredLoading.value = false
  }
}

async function loadAllModels() {
  if (allModelsLoaded.value) return
  allModelsLoading.value = true
  try {
    const resp = await listModels({ status: 'active' })
    allModels.value = resp.items.filter(m => m.status === 'active')
    allModelsLoaded.value = true
  } catch {
    allModels.value = []
  } finally {
    allModelsLoading.value = false
  }
}

watch(selectedScope, async (scope) => {
  if (scope === 'all') {
    await loadAllModels()
  }
})

function toggleModel(modelId: string) {
  const idx = selectedModels.value.indexOf(modelId)
  if (idx >= 0) {
    selectedModels.value.splice(idx, 1)
  } else {
    selectedModels.value.push(modelId)
  }
}

function selectAllModels() {
  selectedModels.value = filteredModels.value.map(m => m.canonical_name)
}

function deselectAllModels() {
  selectedModels.value = []
}

const filteredModels = computed(() => {
  const q = modelSearch.value.trim().toLowerCase()
  if (!q) return allModels.value
  return allModels.value.filter(m =>
    m.canonical_name.toLowerCase().includes(q) ||
    (m.vendor && m.vendor.toLowerCase().includes(q)) ||
    (m.display_name && m.display_name.toLowerCase().includes(q))
  )
})

const groupedModels = computed(() => {
  const groups = new Map<string, ModelCanonical[]>()
  for (const m of filteredModels.value) {
    const key = m.family || m.vendor || 'Other'
    if (!groups.has(key)) groups.set(key, [])
    groups.get(key)!.push(m)
  }
  return Array.from(groups.entries()).sort(([a], [b]) => a.localeCompare(b))
})

function groupSelection(family: string): 'all' | 'none' | 'some' {
  const list = groupedModels.value.find(([f]) => f === family)?.[1] || []
  if (list.length === 0) return 'none'
  const selectedCount = list.filter(m => selectedModels.value.includes(m.canonical_name)).length
  if (selectedCount === 0) return 'none'
  if (selectedCount === list.length) return 'all'
  return 'some'
}

function toggleGroup(family: string) {
  const list = groupedModels.value.find(([f]) => f === family)?.[1] || []
  const state = groupSelection(family)
  const ids = list.map(m => m.canonical_name)
  if (state === 'all') {
    selectedModels.value = selectedModels.value.filter(id => !ids.includes(id))
  } else {
    const set = new Set(selectedModels.value)
    for (const id of ids) set.add(id)
    selectedModels.value = Array.from(set)
  }
}

// ── Generated content ───────────────────────────────────────────────────────
const generatedFile = ref('')
const generatedScript = ref('')
const generatedManual = ref('')
const hasGenerated = ref(false)
const activeTab = ref<'file' | 'script' | 'manual'>('file')
const generating = ref(false)

watch(() => props.open, (val) => {
  if (val) {
    loadKeys()
    loadFeaturedModels()
    hasGenerated.value = false
    generatedFile.value = ''
    generatedScript.value = ''
    activeTab.value = 'file'
    selectedScope.value = 'featured'
    selectedModels.value = []
    selectedOS.value = 'macos'
  }
}, { immediate: true })

watch(selectedScope, async (scope) => {
  if (scope === 'all') {
    await loadAllModels()
  } else if (scope === 'featured') {
    await loadFeaturedModels()
    if (featuredModels.value.length > 0) {
      selectedModels.value = [...featuredModels.value]
    }
  }
})

const selectedKey = computed(() => keys.value.find(k => k.id === selectedKeyId.value))

const fileExt = computed(() => props.tool === 'cherry_studio' ? '.json' : '.json')
const scriptExt = computed(() => selectedOS.value === 'windows' ? '.ps1' : '.sh')

async function generate() {
  if (!selectedKey.value) return
  generating.value = true
  hasGenerated.value = false

  const key = selectedKey.value
  const baseURL = 'https://[GATEWAY_DOMAIN]/v1'
  let models = selectedModels.value
  if (selectedScope.value === 'featured') models = [...featuredModels.value]

  // Pre-existing safety bug (caught by vue-tsc): the render helpers
  // expect a string apiKey, but `key` is the full ApiKey object.
  // The old code passed the object, which JSON.stringify would have
  // serialized to a giant metadata blob — the generated config
  // never worked because the consumer expected a string. Reveal the
  // real key server-side, then pass the string.
  const revealed = await revealKey(key.id)
  const apiKey = revealed.api_key

  let fileContent: any
  if (props.tool === 'zcode') {
    fileContent = renderZCodeConfig(apiKey, models)
  } else if (props.tool === 'opencode') {
    fileContent = renderOpenCodeConfig(apiKey, models)
  } else if (props.tool === 'cherry_studio') {
    fileContent = renderCherryStudioConfig(apiKey, models)
  } else if (props.tool === 'roocode') {
    fileContent = renderRooCodeSettings(apiKey, baseURL)
  } else {
    fileContent = { note: 'Cursor 不支持文件写入，请在 Settings UI 中手动配置' }
  }

  generatedFile.value = JSON.stringify(fileContent, null, 2)
  generatedScript.value = generateShellScript(props.tool, selectedOS.value, generatedFile.value, apiKey)
  generatedManual.value = getManualSteps(props.tool, selectedOS.value)
  hasGenerated.value = true
  generating.value = false

  await auditAction({
    action: 'generate',
    tool: props.tool,
    os: selectedOS.value,
    keyId: key.id,
    modelCount: models.length,
    modelScope: selectedScope.value,
  })
}

function copyFile() {
  navigator.clipboard.writeText(generatedFile.value)
  auditAction({ action: 'copy_config', tool: props.tool, os: selectedOS.value, keyId: selectedKeyId.value || 0, modelCount: selectedModels.value.length, modelScope: selectedScope.value })
}

function downloadScript() {
  const filename = `${props.tool}-config${scriptExt.value}`
  downloadFile(generatedScript.value, filename, 'text/plain')
  auditAction({ action: 'download_script', tool: props.tool, os: selectedOS.value, keyId: selectedKeyId.value || 0, modelCount: selectedModels.value.length, modelScope: selectedScope.value })
}

function downloadFileContent() {
  const filename = `${props.tool}-config${fileExt.value}`
  downloadFile(generatedFile.value, filename, 'application/json')
}

function close() {
  emit('close')
}

function goManageFeatured() {
  close()
  router.push('/routing-policy')
}
</script>

<template>
  <div v-if="open" class="drawer-backdrop" @click.self="close">
    <div class="drawer-panel drawer-panel-wide" @click.stop>
      <div class="drawer-header">
        <div class="dialog-title">
          <span>{{ toolInfo.icon }}</span>
          <span>{{ t('clientConfigDialog.title', { tool: toolInfo.name }) }}</span>
        </div>
        <button class="btn btn-ghost btn-sm" @click="close">{{ t('clientConfigDialog.close') }} ✕</button>
      </div>

      <div class="drawer-body-scroll">

        <!-- Step 1: API Key -->
        <div class="step-section">
          <div class="step-label">
            <span>{{ t('clientConfigDialog.step1.title') }}</span>
            <button class="btn btn-ghost btn-sm refresh-btn" :disabled="keysLoading" @click="loadKeys">
              {{ keysLoading ? t('clientConfigDialog.step1.refreshing') : '↻ ' + t('clientConfigDialog.step1.refresh') }}
            </button>
          </div>
          <select v-if="!keysLoading && keys.length > 0" v-model="selectedKeyId" class="select-field">
            <option v-for="k in keys" :key="k.id" :value="k.id">
              {{ k.key_prefix }}**** ({{ k.application_code }}, {{ k.status }})
            </option>
          </select>
          <div v-else-if="keysLoading" class="state-row">{{ t('clientConfigDialog.step1.loading') }}</div>
          <div v-else class="empty-state">
            <div class="empty-state-icon">🔑</div>
            <div class="empty-state-title">{{ t('clientConfigDialog.step1.empty.title') }}</div>
            <div class="empty-state-desc">
              {{ t('clientConfigDialog.step1.empty.description') }}
            </div>
            <button class="btn btn-primary" @click="applyDialogOpen = true">
              {{ t('clientConfigDialog.step1.empty.applyButton') }}
            </button>
          </div>
          <div v-if="selectedKey" class="key-info">
            {{ t('clientConfigDialog.step1.selected') }}<code>{{ selectedKey.key_prefix }}****</code>
            <span class="badge" :class="selectedKey.status === 'active' ? 'badge-green' : 'badge-yellow'">{{ selectedKey.status }}</span>
          </div>
        </div>

        <!-- Step 2: OS -->
        <div class="step-section">
          <div class="step-label">{{ t('clientConfigDialog.step2.title') }}</div>
          <div class="os-tabs">
            <button
              v-for="(info, os) in OS_INFO"
              :key="os"
              :class="['os-tab', selectedOS === os ? 'active' : '']"
              @click="selectedOS = os as OS"
            >{{ info.label }}</button>
          </div>
          <div class="path-hint">
            {{ t('clientConfigDialog.step2.pathHint') }}<code>{{ OS_INFO[selectedOS].paths[tool] }}</code>
          </div>
        </div>

        <!-- Step 3: Model scope -->
        <div class="step-section">
          <div class="step-label">{{ t('clientConfigDialog.step3.title') }}</div>
          <div class="scope-radios">
            <label class="radio-label">
              <input type="radio" value="featured" v-model="selectedScope" />
              <span>{{ t('clientConfigDialog.step3.featured') }}</span>
            </label>
            <label class="radio-label">
              <input type="radio" value="all" v-model="selectedScope" />
              <span>{{ t('clientConfigDialog.step3.all') }}</span>
            </label>
          </div>

          <!-- Featured preview -->
          <div v-if="selectedScope === 'featured'" class="model-preview">
            <div v-if="featuredLoading" class="models-loading">{{ t('clientConfigDialog.step3.featuredPreview.loading') }}</div>
            <div v-else-if="featuredModels.length === 0" class="empty-mini-state">
              <div class="empty-mini-title">{{ t('clientConfigDialog.step3.featuredPreview.empty') }}</div>
              <button class="btn btn-primary btn-sm" @click="goManageFeatured">
                {{ t('clientConfigDialog.step3.featuredPreview.manageButton') }}
              </button>
            </div>
            <template v-else>
              <span class="model-tag" v-for="m in featuredModels" :key="m">{{ m }}</span>
              <button class="btn btn-ghost btn-sm manage-link" @click="goManageFeatured">
                {{ t('clientConfigDialog.step3.featuredPreview.manage') }}
              </button>
            </template>
          </div>

          <!-- All models from API -->
          <div v-if="selectedScope === 'all'" class="all-models-panel">
            <div class="all-models-toolbar">
              <button class="btn btn-ghost btn-sm" @click="selectAllModels">{{ t('clientConfigDialog.step3.allModels.selectAll') }}</button>
              <button class="btn btn-ghost btn-sm" @click="deselectAllModels">{{ t('clientConfigDialog.step3.allModels.deselectAll') }}</button>
              <span class="model-count-label">
                <strong>{{ selectedModels.length }}</strong> / {{ allModels.length }} {{ t('clientConfigDialog.step3.allModels.selected') }}
                <span v-if="modelSearch" class="filter-hint">{{ t('clientConfigDialog.step3.allModels.filterHint', { count: filteredModels.length }) }}</span>
              </span>
            </div>
            <input
              v-model="modelSearch"
              type="text"
              class="model-search-input"
              :placeholder="t('clientConfigDialog.step3.allModels.searchPlaceholder')"
            />
            <div v-if="allModelsLoading" class="models-loading">{{ t('clientConfigDialog.step3.allModels.loading') }}</div>
            <div v-else-if="filteredModels.length === 0" class="models-loading">{{ t('clientConfigDialog.step3.allModels.noMatch') }}</div>
            <div v-else class="models-grouped">
              <div v-for="[family, list] in groupedModels" :key="family" class="model-family-group">
                <label class="model-family-header">
                  <input
                    type="checkbox"
                    class="group-master-checkbox"
                    :checked="groupSelection(family) === 'all'"
                    :indeterminate.prop="groupSelection(family) === 'some'"
                    @change="toggleGroup(family)"
                  />
                  <span class="model-family-name">{{ family }}</span>
                  <span class="model-family-count">{{ list.filter(m => selectedModels.includes(m.canonical_name)).length }} / {{ list.length }}</span>
                </label>
                <div class="models-checklist">
                  <label
                    v-for="m in list"
                    :key="m.canonical_name"
                    class="model-check-item"
                  >
                    <input
                      type="checkbox"
                      :checked="selectedModels.includes(m.canonical_name)"
                      @change="toggleModel(m.canonical_name)"
                    />
                    <span class="model-check-name" :title="m.canonical_name">{{ m.canonical_name }}</span>
                  </label>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Sticky footer with primary action -->
        <div class="drawer-footer">
          <div class="footer-info" v-if="hasGenerated">
            <span class="footer-hint">{{ t('clientConfigDialog.footer.generated', { count: selectedModels.length }) }}</span>
          </div>
          <button
            v-if="!hasGenerated"
            class="btn btn-primary footer-generate"
            :disabled="!selectedKeyId || generating"
            @click="generate"
          >
            {{ generating ? t('clientConfigDialog.footer.generating') : t('clientConfigDialog.footer.generate') }}
          </button>
          <button
            v-else
            class="btn btn-ghost footer-regenerate"
            @click="generate"
            :disabled="generating"
          >
            {{ t('clientConfigDialog.footer.regenerate') }}
          </button>
        </div>

        <!-- Results -->
        <div v-if="hasGenerated" class="results-section">
          <div class="result-tabs">
            <button :class="['tab-btn', activeTab === 'file' ? 'active' : '']" @click="activeTab = 'file'">{{ t('clientConfigDialog.results.tabs.file') }}</button>
            <button
              v-if="tool !== 'cherry_studio' && tool !== 'cursor'"
              :class="['tab-btn', activeTab === 'script' ? 'active' : '']" @click="activeTab = 'script'"
            >{{ t('clientConfigDialog.results.tabs.script') }}</button>
            <button :class="['tab-btn', activeTab === 'manual' ? 'active' : '']" @click="activeTab = 'manual'">{{ t('clientConfigDialog.results.tabs.manual') }}</button>
          </div>

          <!-- File Tab -->
          <div v-if="activeTab === 'file'" class="tab-content">
            <pre class="code-preview">{{ generatedFile }}</pre>
            <div class="result-actions">
              <button class="btn btn-ghost btn-sm" @click="copyFile">{{ t('clientConfigDialog.results.actions.copyContent') }}</button>
              <button class="btn btn-ghost btn-sm" @click="downloadFileContent">{{ t('clientConfigDialog.results.actions.downloadFile') }}</button>
            </div>
          </div>

          <!-- Script Tab -->
          <div v-if="activeTab === 'script'" class="tab-content">
            <pre class="code-preview script-code">{{ generatedScript }}</pre>
            <div class="result-actions">
              <button class="btn btn-primary btn-sm" @click="downloadScript">{{ t('clientConfigDialog.results.actions.downloadScript') }}</button>
              <span class="action-hint">{{ t('clientConfigDialog.results.actions.scriptHint') }}</span>
            </div>
          </div>

          <!-- Manual Tab -->
          <div v-if="activeTab === 'manual'" class="tab-content">
            <pre class="code-preview manual-text">{{ generatedManual }}</pre>
          </div>
        </div>

      </div>
    </div>
  </div>

  <!-- Apply Key Dialog (separate from main drawer) -->
  <div v-if="applyDialogOpen" class="modal-backdrop" @click.self="applyDialogOpen = false">
    <div class="modal-panel card" @click.stop>
      <div class="modal-header">
        <h4 style="margin:0">{{ t('clientConfigDialog.applyDialog.title') }}</h4>
        <button class="btn btn-ghost btn-sm" @click="applyDialogOpen = false">{{ t('clientConfigDialog.applyDialog.close') }} ✕</button>
      </div>
      <div class="modal-body">
        <div class="form-group">
          <label>{{ t('clientConfigDialog.applyDialog.applicationCode') }}</label>
          <input v-model="applyForm.application_code" class="form-input" :placeholder="t('clientConfigDialog.applyDialog.applicationCodePlaceholder')" />
        </div>
        <div class="form-group">
          <label>{{ t('clientConfigDialog.applyDialog.description') }}</label>
          <textarea v-model="applyForm.description" class="form-input" rows="3" :placeholder="t('clientConfigDialog.applyDialog.descriptionPlaceholder')"></textarea>
        </div>
        <div v-if="applyError" class="alert alert-danger">{{ applyError }}</div>
      </div>
      <div class="modal-footer">
        <button class="btn btn-ghost" @click="applyDialogOpen = false">{{ t('clientConfigDialog.applyDialog.cancel') }}</button>
        <button class="btn btn-primary" :disabled="applying" @click="submitApply">
          {{ applying ? t('clientConfigDialog.applyDialog.submitting') : t('clientConfigDialog.applyDialog.submit') }}
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.dialog-title {
  display: flex;
  align-items: center;
  gap: 8px;
  font-weight: 600;
  font-size: 15px;
}

.drawer-body-scroll {
  flex: 1;
  overflow-y: auto;
  padding: 16px 20px;
  display: flex;
  flex-direction: column;
  gap: 18px;
  min-height: 0;
}

.step-section {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.step-label {
  font-weight: 600;
  font-size: 13px;
  color: var(--text, #e6edf3);
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.refresh-btn {
  font-weight: 400;
  font-size: 11px;
  padding: 2px 8px;
  color: var(--muted, #8b949e);
}

.select-field {
  width: 100%;
  padding: 8px 12px;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid var(--border, #30363d);
  border-radius: 8px;
  color: var(--text, #e6edf3);
  font-size: 13px;
  outline: none;
}

.select-field:focus {
  border-color: rgba(99, 102, 241, 0.5);
}

.key-info {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  color: var(--muted, #8b949e);
}

.badge {
  font-size: 11px;
  padding: 1px 6px;
  border-radius: 4px;
}

.badge-green {
  background: rgba(63, 185, 80, 0.15);
  color: #4ade80;
}

.badge-yellow {
  background: rgba(210, 153, 34, 0.15);
  color: #fbbf24;
}

.os-tabs {
  display: flex;
  gap: 6px;
}

.os-tab {
  padding: 5px 14px;
  border-radius: 6px;
  border: 1px solid var(--border, #30363d);
  background: none;
  color: var(--muted, #8b949e);
  font-size: 13px;
  cursor: pointer;
  transition: all 0.15s;
}

.os-tab.active {
  background: rgba(99, 102, 241, 0.2);
  border-color: rgba(99, 102, 241, 0.5);
  color: #818cf8;
}

.path-hint {
  font-size: 12px;
  color: var(--muted, #8b949e);
}

.scope-radios {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.radio-label {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 13px;
  color: var(--text, #e6edf3);
  cursor: pointer;
}

.model-preview {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  padding: 10px 12px;
  background: rgba(255, 255, 255, 0.03);
  border-radius: 6px;
  align-items: center;
}

.empty-mini-state {
  display: flex;
  flex-direction: column;
  gap: 8px;
  align-items: flex-start;
  width: 100%;
  padding: 4px 0;
}

.empty-mini-title {
  font-size: 12px;
  color: var(--muted, #8b949e);
}

.manage-link {
  margin-left: auto;
  font-size: 11px;
  padding: 2px 8px;
}

.model-tag {
  font-size: 12px;
  padding: 2px 8px;
  background: rgba(99, 102, 241, 0.15);
  color: #818cf8;
  border-radius: 4px;
}

.all-models-panel {
  display: flex;
  flex-direction: column;
  gap: 0;
  border: 1px solid var(--border, #30363d);
  border-radius: 8px;
  overflow: hidden;
  background: rgba(0, 0, 0, 0.15);
}

.all-models-toolbar {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 12px;
  background: rgba(255, 255, 255, 0.04);
  border-bottom: 1px solid var(--border, #30363d);
}

.model-count-label {
  font-size: 12px;
  color: var(--muted, #8b949e);
  margin-left: auto;
}

.model-count-label strong {
  color: var(--accent-h, #818cf8);
  font-size: 13px;
}

.filter-hint {
  color: var(--muted, #8b949e);
  font-size: 11px;
}

.model-search-input {
  width: 100%;
  padding: 8px 12px;
  background: rgba(255, 255, 255, 0.03);
  border: none;
  border-bottom: 1px solid var(--border, #30363d);
  color: var(--text, #e6edf3);
  font-size: 13px;
  outline: none;
  box-sizing: border-box;
}

.model-search-input:focus {
  background: rgba(99, 102, 241, 0.08);
  border-bottom-color: var(--accent, #6366f1);
}

.model-search-input::placeholder {
  color: var(--muted, #8b949e);
}

.models-loading {
  padding: 20px;
  text-align: center;
  font-size: 13px;
  color: var(--muted, #8b949e);
}

.models-grouped {
  max-height: 360px;
  overflow-y: auto;
  padding: 4px 0;
}

.model-family-group {
  margin-bottom: 4px;
}

.model-family-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 6px 12px;
  background: rgba(255, 255, 255, 0.03);
  border-top: 1px solid var(--border, #30363d);
  border-bottom: 1px solid var(--border, #30363d);
  position: sticky;
  top: 0;
  z-index: 1;
}

.model-family-header:first-child {
  border-top: none;
}

.model-family-name {
  font-size: 11px;
  font-weight: 600;
  color: var(--muted, #8b949e);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.model-family-count {
  font-size: 11px;
  color: var(--muted, #8b949e);
  background: rgba(255, 255, 255, 0.05);
  padding: 1px 6px;
  border-radius: 8px;
}

.models-checklist {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
  gap: 2px;
  padding: 4px 8px 8px;
}

.model-check-item {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 5px 8px;
  cursor: pointer;
  font-size: 12px;
  border-radius: 4px;
  transition: background 0.1s;
}

.model-check-item:hover {
  background: rgba(99, 102, 241, 0.12);
}

.model-check-item input[type="checkbox"] {
  flex-shrink: 0;
  margin: 0;
  cursor: pointer;
}

.model-check-name {
  color: var(--text, #e6edf3);
  font-family: ui-monospace, 'SF Mono', Menlo, monospace;
  font-size: 11.5px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  min-width: 0;
}

.drawer-footer {
  position: sticky;
  bottom: -16px;
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 12px;
  padding: 12px 0;
  background: var(--card, #1c2128);
  border-top: 1px solid var(--border, #30363d);
  margin: 8px -20px -16px -20px;
  padding-left: 20px;
  padding-right: 20px;
  z-index: 5;
}

.footer-info {
  margin-right: auto;
}

.footer-hint {
  font-size: 12px;
  color: var(--muted, #8b949e);
}

.footer-generate,
.footer-regenerate {
  min-width: 140px;
  font-weight: 600;
}

.generate-section {
  align-items: center;
}

.results-section {
  border-top: 1px solid var(--border, #30363d);
  padding-top: 16px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.result-tabs {
  display: flex;
  gap: 4px;
  border-bottom: 1px solid var(--border, #30363d);
  padding-bottom: 0;
}

.tab-btn {
  padding: 6px 14px;
  border: none;
  background: none;
  color: var(--muted, #8b949e);
  font-size: 13px;
  cursor: pointer;
  border-bottom: 2px solid transparent;
  margin-bottom: -1px;
  transition: all 0.15s;
}

.tab-btn.active {
  color: #818cf8;
  border-bottom-color: #818cf8;
}

.tab-content {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.code-preview {
  background: #0d1117;
  color: #e6edf3;
  border: 1px solid var(--border, #30363d);
  border-radius: 8px;
  padding: 14px;
  font-size: 12px;
  line-height: 1.6;
  overflow-x: auto;
  max-height: 320px;
  overflow-y: auto;
  white-space: pre;
  margin: 0;
}

.script-code {
  color: #79c0ff;
}

.manual-text {
  white-space: pre-wrap;
}

.result-actions {
  display: flex;
  align-items: center;
  gap: 10px;
}

.action-hint {
  font-size: 12px;
  color: var(--muted, #8b949e);
}

/* ── Empty state (no keys) ─────────────────────────────────────────── */
.state-row {
  padding: 8px 12px;
  font-size: 12px;
  color: var(--muted, #8b949e);
  background: rgba(255, 255, 255, 0.03);
  border-radius: 6px;
}

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  padding: 24px 16px;
  background: rgba(99, 102, 241, 0.05);
  border: 1px dashed rgba(99, 102, 241, 0.3);
  border-radius: 10px;
  text-align: center;
}

.empty-state-icon {
  font-size: 28px;
  line-height: 1;
}

.empty-state-title {
  font-weight: 600;
  font-size: 14px;
  color: var(--text, #e6edf3);
}

.empty-state-desc {
  font-size: 12px;
  color: var(--muted, #8b949e);
  line-height: 1.5;
  max-width: 320px;
}

/* ── Group master checkbox ─────────────────────────────────────────── */
.model-family-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 12px;
  background: rgba(255, 255, 255, 0.04);
  border-top: 1px solid var(--border, #30363d);
  border-bottom: 1px solid var(--border, #30363d);
  position: sticky;
  top: 0;
  z-index: 1;
  cursor: pointer;
  user-select: none;
}

.model-family-header:hover {
  background: rgba(99, 102, 241, 0.08);
}

.group-master-checkbox {
  flex-shrink: 0;
  margin: 0;
  cursor: pointer;
  width: 14px;
  height: 14px;
  accent-color: var(--accent, #6366f1);
}

.group-master-checkbox:indeterminate {
  accent-color: var(--accent, #6366f1);
}

/* ── Modal (apply key) ──────────────────────────────────────────────── */
.modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.6);
  z-index: 1100;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
}

.modal-panel {
  width: 100%;
  max-width: 480px;
  background: var(--card, #1c2128);
  border: 1px solid var(--border, #30363d);
  border-radius: 12px;
  box-shadow: 0 24px 60px rgba(0, 0, 0, 0.5);
  display: flex;
  flex-direction: column;
}

.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 18px;
  border-bottom: 1px solid var(--border, #30363d);
}

.modal-body {
  padding: 16px 18px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.modal-footer {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 8px;
  padding: 12px 18px;
  border-top: 1px solid var(--border, #30363d);
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.form-group label {
  font-size: 12px;
  color: var(--muted, #8b949e);
  font-weight: 500;
}

.form-input {
  width: 100%;
  padding: 8px 10px;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid var(--border, #30363d);
  border-radius: 6px;
  color: var(--text, #e6edf3);
  font-size: 13px;
  outline: none;
  font-family: inherit;
  box-sizing: border-box;
}

.form-input:focus {
  border-color: rgba(99, 102, 241, 0.5);
  background: rgba(99, 102, 241, 0.05);
}

textarea.form-input {
  resize: vertical;
  min-height: 60px;
}

.alert {
  padding: 8px 12px;
  border-radius: 6px;
  font-size: 12px;
  line-height: 1.5;
}

.alert-danger {
  background: rgba(248, 81, 73, 0.12);
  color: #f97583;
  border: 1px solid rgba(248, 81, 73, 0.3);
}
</style>
