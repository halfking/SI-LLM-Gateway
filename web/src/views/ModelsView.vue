<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import {
  listModels, listTags, patchModelTags, resetModelTags,
  listModelFamilies, createModel, getModel, updateModel,
  createModelAlias, createModelAliasesBulk, updateModelAlias, discoverModels, getModelDiscoveryStatus,
  type ModelCanonical, type ModelDetail, type ModelFamily, type TagNamespaceGroup,
  type DiscoverModelsResult, type ModelDiscoveryRun,
} from '../api'
import TagEditor from '../components/TagEditor.vue'

type ModelStatus = 'active' | 'disabled' | 'deprecated' | 'hidden'

const models = ref<ModelCanonical[]>([])
const families = ref<ModelFamily[]>([])
const namespaces = ref<TagNamespaceGroup[]>([])
const loading = ref(false)
const error = ref('')
const search = ref('')
const activeTags = ref<string[]>([])
const statusFilter = ref('')
const editingId = ref<number | null>(null)
const editTags = ref<string[]>([])
const detail = ref<ModelDetail | null>(null)
const detailLoading = ref(false)
const editInfo = ref({ display_name: '', family: '', modality: 'text', context_window: '', parameters_b: '', notes: '', status: 'active' as ModelStatus, disabled_reason: '' })
const newAlias = ref({ raw_name: '', surface: '', quantization: '', notes: '' })
const bulkAliasText = ref('')
const bulkAliasProfiles = ref('')
const creating = ref(false)
const discovering = ref(false)
const discoverResult = ref<DiscoverModelsResult | null>(null)
const discoverRun = ref<ModelDiscoveryRun | null>(null)
const discoverMessage = ref('')
const createForm = ref({ canonical_name: '', display_name: '', family: '', modality: 'text', context_window: '', parameters_b: '', aliases: '', notes: '' })

const statuses: ModelStatus[] = ['active', 'disabled', 'deprecated', 'hidden']
const modalities = ['text', 'vision', 'audio', 'multimodal', 'embedding']

async function loadTags() {
  try {
    const r = await listTags()
    namespaces.value = r.namespaces
  } catch (e) { /* ignore */ }
}

async function loadFamilies() {
  try {
    const r = await listModelFamilies()
    families.value = r.items
  } catch (e) { /* ignore */ }
}

async function loadModels() {
  loading.value = true
  error.value = ''
  try {
    const r = await listModels({ tags: activeTags.value, status: statusFilter.value || undefined })
    models.value = r.items
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : '加载失败'
  } finally {
    loading.value = false
  }
}

async function reloadAll() {
  await Promise.all([loadTags(), loadFamilies(), loadModels()])
}

function toggleTag(t: string) {
  if (activeTags.value.includes(t)) {
    activeTags.value = activeTags.value.filter((x) => x !== t)
  } else {
    activeTags.value = [...activeTags.value, t]
  }
  loadModels()
}

function clearFilters() {
  activeTags.value = []
  statusFilter.value = ''
  loadModels()
}

const filtered = computed(() => {
  const q = search.value.toLowerCase().trim()
  if (!q) return models.value
  return models.value.filter((m) =>
    m.canonical_name.toLowerCase().includes(q) ||
    (m.display_name ?? '').toLowerCase().includes(q) ||
    (m.family ?? '').toLowerCase().includes(q) ||
    m.tags.some((t) => t.toLowerCase().includes(q))
  )
})

function beginEditTags(m: ModelCanonical) {
  editingId.value = m.id
  editTags.value = [...m.tags]
}

async function saveTags(m: ModelCanonical) {
  try {
    const updated = await patchModelTags(m.id, editTags.value)
    Object.assign(m, updated)
    if (detail.value?.id === m.id) Object.assign(detail.value, updated)
    editingId.value = null
    await loadTags()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : '保存失败'
  }
}

async function doReset(m: ModelCanonical) {
  try {
    const updated = await resetModelTags(m.id)
    Object.assign(m, updated)
    if (detail.value?.id === m.id) Object.assign(detail.value, updated)
    if (editingId.value === m.id) editTags.value = [...updated.tags]
    await loadTags()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : '重置失败'
  }
}

async function openDetail(m: ModelCanonical) {
  detailLoading.value = true
  error.value = ''
  try {
    detail.value = await getModel(m.id)
    editInfo.value = {
      display_name: detail.value.display_name || detail.value.canonical_name,
      family: detail.value.family || '',
      modality: detail.value.modality,
      context_window: detail.value.context_window == null ? '' : String(detail.value.context_window),
      parameters_b: detail.value.parameters_b == null ? '' : String(detail.value.parameters_b),
      notes: detail.value.notes || '',
      status: detail.value.status,
      disabled_reason: detail.value.disabled_reason || '',
    }
    newAlias.value = { raw_name: '', surface: '', quantization: '', notes: '' }
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : '加载详情失败'
  } finally {
    detailLoading.value = false
  }
}

async function saveInfo() {
  if (!detail.value) return
  const updated = await updateModel(detail.value.id, {
    display_name: editInfo.value.display_name || null,
    family: editInfo.value.family || null,
    modality: editInfo.value.modality,
    context_window: editInfo.value.context_window ? Number(editInfo.value.context_window) : null,
    parameters_b: editInfo.value.parameters_b ? Number(editInfo.value.parameters_b) : null,
    notes: editInfo.value.notes || null,
    status: editInfo.value.status,
    disabled_reason: editInfo.value.disabled_reason || null,
  })
  Object.assign(detail.value, updated)
  const row = models.value.find((m) => m.id === updated.id)
  if (row) Object.assign(row, updated)
  await Promise.all([loadFamilies(), loadTags()])
}

async function toggleModelStatus(m: ModelCanonical) {
  const next: ModelStatus = m.status === 'active' ? 'disabled' : 'active'
  const updated = await updateModel(m.id, {
    status: next,
    disabled_reason: next === 'disabled' ? 'manual disable from admin UI' : null,
  })
  Object.assign(m, updated)
  if (detail.value?.id === m.id) Object.assign(detail.value, updated)
  await loadTags()
}

async function bulkImportAliases() {
  if (!detail.value || !bulkAliasText.value.trim()) return
  const raw_names = bulkAliasText.value.split('\n').map((x) => x.trim()).filter(Boolean)
  const profiles = bulkAliasProfiles.value
    .split(',')
    .map((x) => x.trim())
    .filter(Boolean)
  await createModelAliasesBulk(detail.value.id, {
    raw_names,
    client_profiles: profiles.length ? profiles : null,
    notes: 'agent terminal bulk import',
  })
  bulkAliasText.value = ''
  await openDetail(models.value.find((m) => m.id === detail.value!.id)!)
  await loadModels()
}

async function addAlias() {
  if (!detail.value || !newAlias.value.raw_name.trim()) return
  const created = await createModelAlias(detail.value.id, {
    raw_name: newAlias.value.raw_name.trim(),
    surface: newAlias.value.surface || null,
    quantization: newAlias.value.quantization || null,
    notes: newAlias.value.notes || null,
  })
  detail.value.aliases = [...detail.value.aliases, created]
  newAlias.value = { raw_name: '', surface: '', quantization: '', notes: '' }
  await loadModels()
}

async function setAliasStatus(aliasId: number, status: ModelStatus) {
  if (!detail.value) return
  const updated = await updateModelAlias(detail.value.id, aliasId, { status })
  const idx = detail.value.aliases.findIndex((a) => a.id === aliasId)
  if (idx >= 0) detail.value.aliases[idx] = updated
  await loadModels()
}

async function submitCreate() {
  creating.value = true
  error.value = ''
  try {
    const aliases = createForm.value.aliases.split('\n').map((x) => x.trim()).filter(Boolean)
    const created = await createModel({
      canonical_name: createForm.value.canonical_name.trim(),
      display_name: createForm.value.display_name || null,
      family: createForm.value.family || null,
      modality: createForm.value.modality,
      context_window: createForm.value.context_window ? Number(createForm.value.context_window) : null,
      parameters_b: createForm.value.parameters_b ? Number(createForm.value.parameters_b) : null,
      aliases,
      notes: createForm.value.notes || null,
    })
    createForm.value = { canonical_name: '', display_name: '', family: '', modality: 'text', context_window: '', parameters_b: '', aliases: '', notes: '' }
    await reloadAll()
    const row = models.value.find((m) => m.id === created.id)
    if (row) await openDetail(row)
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : '新增失败'
  } finally {
    creating.value = false
  }
}

async function runDiscovery() {
  discovering.value = true
  discoverResult.value = null
  discoverMessage.value = ''
  error.value = ''
  try {
    const started = await discoverModels({ use_manifest_fallback: true, force: true })
    discoverRun.value = started.run
    discoverMessage.value = started.reason === 'already_running' ? '已有扫描正在运行，继续等待结果' : '扫描任务已启动'
    await pollDiscovery(started.run.id)
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : '发现模型失败'
  } finally {
    discovering.value = false
  }
}

async function pollDiscovery(runId?: number) {
  for (;;) {
    const status = await getModelDiscoveryStatus()
    discoverRun.value = status.running || status.latest
    const latest = status.latest
    if (latest?.summary) discoverResult.value = latest.summary
    if (!status.running || (runId && latest?.id === runId && latest.status !== 'running')) {
      if (latest?.status === 'failed') error.value = latest.error || '扫描失败'
      if (latest?.status === 'succeeded') {
        discoverMessage.value = '扫描完成'
        await reloadAll()
        window.dispatchEvent(new CustomEvent('llm-gateway:models-updated'))
      }
      return
    }
    await new Promise((resolve) => window.setTimeout(resolve, 3000))
  }
}

async function loadDiscoveryStatus() {
  try {
    const status = await getModelDiscoveryStatus()
    discoverRun.value = status.running || status.latest
    if (status.latest?.summary) discoverResult.value = status.latest.summary
    if (status.running) {
      discovering.value = true
      discoverMessage.value = '扫描正在后台运行'
      await pollDiscovery(status.running.id)
    }
  } catch (e) { /* ignore */ }
}

function tagBadgeClass(tag: string): string {
  if (tag.startsWith('cap:')) return 'badge-blue'
  if (tag.startsWith('family:')) return 'badge-green'
  if (tag.startsWith('series:')) return 'badge-green'
  if (tag.startsWith('generation:')) return 'badge-blue'
  if (tag.startsWith('variant:')) return 'badge-purple'
  if (tag.startsWith('modality:')) return 'badge-yellow'
  if (tag.startsWith('user:')) return 'badge-gray'
  return 'badge-gray'
}

function statusBadgeClass(status: string): string {
  if (status === 'active') return 'badge-green'
  if (status === 'disabled') return 'badge-red'
  if (status === 'deprecated') return 'badge-yellow'
  return 'badge-gray'
}

function healthBadgeClass(status?: string): string {
  if (status === 'healthy') return 'badge-green'
  if (status === 'warning') return 'badge-yellow'
  if (status === 'unreachable') return 'badge-red'
  return 'badge-gray'
}

function healthLabel(status?: string): string {
  if (status === 'healthy') return '正常'
  if (status === 'warning') return '警示'
  if (status === 'unreachable') return '不可达'
  return '未探测'
}

onMounted(async () => {
  await reloadAll()
  await loadDiscoveryStatus()
})
</script>

<template>
  <div>
    <div class="page-header">
      <h2>模型 Taxonomy</h2>
      <div style="display:flex;gap:8px;align-items:center">
        <span class="badge badge-gray">{{ filtered.length }} 个模型</span>
        <button class="btn btn-primary btn-sm" :disabled="discovering" @click="runDiscovery">
          {{ discovering ? '扫描中…' : '强制扫描供应商模型' }}
        </button>
      </div>
    </div>

    <div v-if="discoverRun || discoverResult" class="card discovery-card">
      <div class="card-header"><h3>发现任务</h3></div>
      <div class="card-body">
        <div v-if="discoverRun" class="summary-row">
          <span class="badge" :class="discoverRun.status === 'succeeded' ? 'badge-green' : discoverRun.status === 'failed' ? 'badge-red' : 'badge-blue'">{{ discoverRun.status }}</span>
          <span class="badge badge-gray">{{ discoverRun.trigger }}</span>
          <span class="muted small">#{{ discoverRun.id }} · {{ discoverMessage || '最近一次扫描' }}</span>
        </div>
        <div class="summary-row">
          <span class="badge badge-blue">凭据 {{ discoverResult?.credentials_succeeded ?? 0 }}/{{ discoverResult?.credentials_scanned ?? 0 }}</span>
          <span class="badge badge-green">模型 {{ discoverResult?.models_seen ?? 0 }}</span>
          <span class="badge badge-purple">offers {{ discoverResult?.offers_upserted ?? 0 }}</span>
          <span v-if="discoverResult?.credentials_failed" class="badge badge-yellow">失败 {{ discoverResult.credentials_failed }}</span>
        </div>
        <div class="summary-row" v-if="discoverResult">
          <span class="badge badge-green">正常 {{ discoverResult.healthy_credentials ?? 0 }}</span>
          <span class="badge badge-yellow">警示 {{ discoverResult.warning_credentials ?? 0 }}</span>
          <span class="badge badge-red">不可达 {{ discoverResult.unreachable_credentials ?? 0 }}</span>
        </div>
        <div v-if="discoverResult" class="discover-items">
          <div v-for="item in discoverResult.items" :key="`${item.provider_id}-${item.credential_id}`" class="discover-item">
            <strong>{{ item.provider_name }}</strong>
            <span class="muted">#{{ item.credential_id }} · {{ item.source }} · {{ item.models }} models</span>
            <span class="badge" :class="healthBadgeClass(item.health_status)" style="width:max-content">{{ healthLabel(item.health_status) }}</span>
            <span v-if="item.sample?.length" class="muted small">{{ item.sample.join(', ') }}</span>
            <span v-if="item.warning_code" class="muted small">{{ item.warning_code }}</span>
            <span v-if="item.probe_model" class="muted small">Probe {{ item.probe_model }}</span>
            <span v-if="item.error" class="muted small">{{ item.error }}</span>
          </div>
        </div>
      </div>
    </div>

    <div class="grid">
      <section class="card create-card">
        <div class="card-header"><h3>新增模型</h3></div>
        <div class="card-body form-grid">
          <input v-model="createForm.canonical_name" class="input" placeholder="canonical name" />
          <input v-model="createForm.display_name" class="input" placeholder="显示名" />
          <select v-model="createForm.family" class="input">
            <option value="">选择 family</option>
            <option v-for="f in families" :key="f.id" :value="f.id">{{ f.display_name }} · {{ f.id }}</option>
          </select>
          <select v-model="createForm.modality" class="input">
            <option v-for="m in modalities" :key="m" :value="m">{{ m }}</option>
          </select>
          <input v-model="createForm.context_window" class="input" placeholder="context window" />
          <input v-model="createForm.parameters_b" class="input" placeholder="parameters B" />
          <textarea v-model="createForm.aliases" class="input span-2" rows="3" placeholder="aliases，每行一个 raw model name" />
          <textarea v-model="createForm.notes" class="input span-2" rows="2" placeholder="备注" />
          <button class="btn btn-primary" :disabled="creating || !createForm.canonical_name" @click="submitCreate">新增并自动归集标签</button>
        </div>
      </section>

      <section class="card" v-if="namespaces.length">
        <div class="card-header">
          <h3>筛选</h3>
          <button v-if="activeTags.length || statusFilter" class="btn btn-ghost btn-sm" @click="clearFilters">清空</button>
        </div>
        <div class="card-body">
          <select v-model="statusFilter" class="input" style="max-width:180px;margin-bottom:8px" @change="loadModels">
            <option value="">全部状态</option>
            <option v-for="s in statuses" :key="s" :value="s">{{ s }}</option>
          </select>
          <div v-for="g in namespaces" :key="g.namespace" class="ns-block">
            <div class="ns-label">{{ g.namespace }}</div>
            <div class="tag-list">
              <button
                v-for="t in g.tags"
                :key="t.tag"
                type="button"
                class="tag-chip"
                :class="{ active: activeTags.includes(t.tag), [tagBadgeClass(t.tag)]: true }"
                @click="toggleTag(t.tag)"
                :title="`${t.count} 个模型`"
              >
                {{ t.tag }} <span class="cnt">{{ t.count }}</span>
              </button>
            </div>
          </div>
        </div>
      </section>
    </div>

    <div class="card" style="margin-top:12px">
      <div class="card-header">
        <h3>模型清单</h3>
        <input v-model="search" class="input" placeholder="搜索名称 / family / 标签" style="max-width:280px" />
      </div>
      <div class="card-body">
        <div v-if="error" class="alert alert-error">{{ error }}</div>
        <div v-if="loading" class="muted">加载中…</div>
        <table v-else class="table">
          <thead>
            <tr>
              <th>规范名</th>
              <th>family</th>
              <th>状态</th>
              <th>modality</th>
              <th>ctx</th>
              <th>aliases/offers</th>
              <th>标签</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="m in filtered" :key="m.id" :class="{ mutedRow: m.status !== 'active' }">
              <td>
                <code>{{ m.canonical_name }}</code>
                <div class="muted small">{{ m.display_name || '-' }}</div>
                <span v-if="m.tags_locked" class="badge badge-yellow">locked</span>
              </td>
              <td>{{ m.family || '-' }}</td>
              <td><span class="badge" :class="statusBadgeClass(m.status)">{{ m.status }}</span></td>
              <td>{{ m.modality }}</td>
              <td>{{ m.context_window ?? '-' }}</td>
              <td>{{ m.alias_count ?? 0 }} / {{ m.offer_count ?? 0 }}</td>
              <td style="min-width:280px">
                <template v-if="editingId === m.id">
                  <TagEditor v-model="editTags" :locked="m.tags_locked" @reset="doReset(m)" />
                </template>
                <template v-else>
                  <span v-for="t in m.tags" :key="t" class="badge" :class="tagBadgeClass(t)" style="margin:2px">{{ t }}</span>
                  <span v-if="!m.tags.length" class="muted">（无）</span>
                </template>
              </td>
              <td style="white-space:nowrap">
                <template v-if="editingId === m.id">
                  <button class="btn btn-primary btn-sm" @click="saveTags(m)">保存标签</button>
                  <button class="btn btn-ghost btn-sm" @click="editingId = null">取消</button>
                </template>
                <template v-else>
                  <button class="btn btn-ghost btn-sm" @click="openDetail(m)">详情</button>
                  <button class="btn btn-ghost btn-sm" @click="beginEditTags(m)">标签</button>
                  <button class="btn btn-ghost btn-sm" @click="toggleModelStatus(m)">{{ m.status === 'active' ? '禁用' : '启用' }}</button>
                  <button v-if="m.tags_locked" class="btn btn-ghost btn-sm" @click="doReset(m)">重置</button>
                </template>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <section v-if="detail" class="card detail-card">
      <div class="card-header">
        <h3>{{ detail.canonical_name }}</h3>
        <button class="btn btn-ghost btn-sm" @click="detail = null">关闭</button>
      </div>
      <div class="card-body">
        <div v-if="detailLoading" class="muted">加载中…</div>
        <div class="form-grid">
          <input v-model="editInfo.display_name" class="input" placeholder="显示名" />
          <select v-model="editInfo.family" class="input">
            <option value="">无 family</option>
            <option v-for="f in families" :key="f.id" :value="f.id">{{ f.display_name }} · {{ f.id }}</option>
          </select>
          <select v-model="editInfo.status" class="input">
            <option v-for="s in statuses" :key="s" :value="s">{{ s }}</option>
          </select>
          <select v-model="editInfo.modality" class="input">
            <option v-for="m in modalities" :key="m" :value="m">{{ m }}</option>
          </select>
          <input v-model="editInfo.context_window" class="input" placeholder="context window" />
          <input v-model="editInfo.parameters_b" class="input" placeholder="parameters B" />
          <input v-model="editInfo.disabled_reason" class="input span-2" placeholder="禁用/弃用原因" />
          <textarea v-model="editInfo.notes" class="input span-2" rows="2" placeholder="备注" />
          <button class="btn btn-primary" @click="saveInfo">保存基础信息</button>
        </div>

        <h4>Aliases</h4>
        <div class="alias-add">
          <input v-model="newAlias.raw_name" class="input" placeholder="raw model name" />
          <input v-model="newAlias.surface" class="input" placeholder="surface" />
          <input v-model="newAlias.quantization" class="input" placeholder="quantization" />
          <input v-model="newAlias.notes" class="input" placeholder="备注" />
          <button class="btn btn-primary btn-sm" @click="addAlias">新增 alias</button>
        </div>
        <div style="margin:12px 0">
          <div style="font-size:12px;color:var(--muted);margin-bottom:6px">批量导入（每行一个 agent 终端模型名）</div>
          <textarea v-model="bulkAliasText" class="input" rows="4" placeholder="gpt-4o&#10;claude-sonnet-4&#10;composer" />
          <input v-model="bulkAliasProfiles" class="input" style="margin-top:6px" placeholder="client profiles 逗号分隔，如 cursor,roocode" />
          <button class="btn btn-ghost btn-sm" style="margin-top:6px" @click="bulkImportAliases">批量导入 alias</button>
        </div>
        <table class="table alias-table">
          <thead><tr><th>raw</th><th>surface</th><th>quant</th><th>状态</th><th>备注</th><th>操作</th></tr></thead>
          <tbody>
            <tr v-for="a in detail.aliases" :key="a.id" :class="{ mutedRow: a.status !== 'active' }">
              <td><code>{{ a.raw_name }}</code></td>
              <td>{{ a.surface || '-' }}</td>
              <td>{{ a.quantization || '-' }}</td>
              <td><span class="badge" :class="statusBadgeClass(a.status)">{{ a.status }}</span></td>
              <td>{{ a.notes || '-' }}</td>
              <td>
                <button class="btn btn-ghost btn-sm" @click="setAliasStatus(a.id, a.status === 'active' ? 'disabled' : 'active')">
                  {{ a.status === 'active' ? '禁用' : '启用' }}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>

<style scoped>
.grid { display: grid; grid-template-columns: minmax(320px, 1fr) minmax(320px, 1fr); gap: 12px; }
.form-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; align-items: start; }
.span-2 { grid-column: span 2; }
.ns-block { margin-bottom: 8px; }
.ns-label { font-size: 11px; font-weight: 600; color: var(--text-muted); text-transform: uppercase; margin-bottom: 4px; }
.tag-list { display: flex; flex-wrap: wrap; gap: 4px; }
.tag-chip {
  border: 1px solid var(--border); background: var(--bg);
  border-radius: 12px; padding: 2px 8px; font-size: 12px; cursor: pointer;
  display: inline-flex; align-items: center; gap: 4px;
}
.tag-chip.active { outline: 2px solid var(--primary, #6366f1); }
.tag-chip .cnt { color: var(--text-muted); font-size: 10px; }
.muted { color: var(--text-muted); }
.small { font-size: 11px; margin-top: 3px; }
.mutedRow { opacity: .62; }
.detail-card { margin-top: 12px; }
.discovery-card { margin-bottom: 12px; }
.summary-row { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 8px; }
.discover-items { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 8px; }
.discover-item { border: 1px solid var(--border); border-radius: 6px; padding: 8px; display: flex; flex-direction: column; gap: 3px; }
.alias-add { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)) auto; gap: 8px; align-items: center; margin: 8px 0; }
.alias-table { margin-top: 8px; }
.badge-red { background: #fee2e2; color: #991b1b; }
.badge-green { background: #dcfce7; color: #166534; }
.badge-blue { background: #dbeafe; color: #1e40af; }
.badge-yellow { background: #fef3c7; color: #92400e; }
.badge-purple { background: #ede9fe; color: #5b21b6; }
.badge-gray { background: #f3f4f6; color: #374151; }
@media (max-width: 900px) {
  .grid, .form-grid, .alias-add { grid-template-columns: 1fr; }
  .span-2 { grid-column: span 1; }
}
</style>
