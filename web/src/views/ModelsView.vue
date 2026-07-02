<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import {
  listModels, listTags, patchModelTags, resetModelTags,
  listModelFamilies, createModel, getModel, updateModel,
  createModelAlias, createModelAliasesBulk, updateModelAlias, discoverModels, getModelDiscoveryStatus,
  getProviders, getFeatured, patchFeatured, getFeaturedModelsDynamic,
  type ModelCanonical, type ModelDetail, type ModelFamily, type TagNamespaceGroup,
  type DiscoverModelsResult, type ModelDiscoveryRun, type Provider,
  type FeaturedModel,
} from '../api'
import ActiveFilterChips from '../components/ActiveFilterChips.vue'
import CatalogPanel from '../components/CatalogPanel.vue'
import ModelPicker from '../components/ModelPicker.vue'
import { useFilterChips } from '../composables/useFilterChips'
import ModelCatalogFilterBar from '../components/ModelCatalogFilterBar.vue'
import { useDynamicNamespaceFilters } from '../composables/useDynamicNamespaceFilters'
import { isReadOnlyMode, isPlatformOpsView } from '../store'
import { normalizeTags, resolveVendor, matchesModelCatalogSearch } from '../utils/modelCatalog'

const { t } = useI18n()
const md = (k: string, params?: Record<string, unknown>): string =>
  t(`models.${k}` as never, params as never)

type PageTab = 'canonical' | 'catalog'

const route = useRoute()
const router = useRouter()
const isPlatformOps = computed(() => isPlatformOpsView())
const activeTab = ref<PageTab>(isPlatformOps.value ? 'canonical' : 'catalog')

function tabFromQuery(q: unknown): PageTab | null {
  if (q === 'canonical' || q === 'models') return 'canonical'
  if (q === 'catalog') return 'catalog'
  return null
}

function setTab(tab: PageTab) {
  if (tab === 'canonical' && !isPlatformOps.value) return
  activeTab.value = tab
  const nextQuery = { ...route.query }
  if (tab === 'canonical') delete nextQuery.tab
  else nextQuery.tab = tab
  router.replace({ path: '/models', query: nextQuery })
}

function syncTabFromRoute() {
  const fromQuery = tabFromQuery(route.query.tab)
  if (fromQuery === 'canonical' && !isPlatformOps.value) {
    router.replace({ path: '/models', query: { tab: 'catalog' } })
    activeTab.value = 'catalog'
    return
  }
  if (fromQuery) {
    activeTab.value = fromQuery
    return
  }
  activeTab.value = isPlatformOps.value ? 'canonical' : 'catalog'
}

watch(() => route.query.tab, syncTabFromRoute)

const readOnly = computed(() => isReadOnlyMode())

type ModelStatus = 'active' | 'disabled' | 'deprecated' | 'hidden'

const models = ref<ModelCanonical[]>([])
const families = ref<ModelFamily[]>([])
const providers = ref<Provider[]>([])
const namespaces = ref<TagNamespaceGroup[]>([])
const loading = ref(false)
const error = ref('')
const pickedModel = ref('')
const textSearch = ref('')
const searchStub = ref('')
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
const showDiscoveryCard = ref(false)
const showCreateModal = ref(false)
const showFeaturedDrawer = ref(false)
const featuredArray = ref<string[]>([])
const featuredLoading = ref(false)
const featuredSaving = ref(false)
const featuredError = ref('')
const featuredMessage = ref('')
const featuredRecommendPreview = ref<FeaturedModel[]>([])
const featuredRecommendLoading = ref(false)
const featuredRecommendMessage = ref('')
const createForm = ref({ canonical_name: '', display_name: '', family: '', modality: 'text', context_window: '', parameters_b: '', aliases: '', notes: '' })
const showNamespaceFilters = ref(false)

// 新增：厂商和模型选择
const selectedVendor = ref('')
const selectedCanonical = ref('')

const statuses: ModelStatus[] = ['active', 'disabled', 'deprecated', 'hidden']
const modalities = ['text', 'vision', 'audio', 'multimodal', 'embedding']
const singleSelectNamespaces = new Set(['family', 'generation', 'modality', 'series', 'variant', 'version'])

const modelStatusOptions = [
  { value: 'active', label: 'active' },
  { value: 'disabled', label: 'disabled' },
  { value: 'deprecated', label: 'deprecated' },
  { value: 'hidden', label: 'hidden' },
]

function modelVendorName(model: ModelCanonical): string {
  return resolveVendor(
    model.canonical_name,
    model.family,
    model.vendor ?? families.value.find((f) => f.id === model.family)?.vendor,
  )
}

function matchesVendor(model: ModelCanonical, vendor: string): boolean {
  if (!vendor) return true
  return modelVendorName(model) === vendor
}

function matchesSearch(model: ModelCanonical, _query: string): boolean {
  return matchesModelCatalogSearch(
    model.canonical_name,
    model.display_name ?? '',
    modelVendorName(model),
    pickedModel.value,
    textSearch.value,
    [model.family ?? '', ...normalizeTags(model.tags)],
  )
}

const {
  filterItems: filterModels,
  filtered,
  namespaceOptions,
  tagNamespace,
  toggleTag: toggleNamespaceTag,
} = useDynamicNamespaceFilters<ModelCanonical>({
  items: models,
  namespaceGroups: namespaces,
  activeTags,
  search: searchStub,
  vendor: selectedVendor,
  getTags: (model) => normalizeTags(model.tags),
  getFamily: (model) => model.family ?? null,
  matchesSearch,
  matchesVendor,
  singleSelectNamespaces,
})

// 计算厂商列表
const vendors = computed(() => {
  const vendorSet = new Set<string>()
  const base = filterModels(models.value, { tags: activeTags.value })
  base.forEach((model) => vendorSet.add(modelVendorName(model)))
  if (selectedVendor.value) vendorSet.add(selectedVendor.value)
  return Array.from(vendorSet).sort((a, b) => a.localeCompare(b, 'zh-CN'))
})

const familyOptions = computed(() => {
  const base = filterModels(models.value, { vendor: selectedVendor.value })
  const counts = new Map<string, number>()
  base.forEach((model) => {
    if (!model.family) return
    counts.set(model.family, (counts.get(model.family) ?? 0) + 1)
  })
  return families.value
    .filter((family) => counts.has(family.id) || activeTags.value.includes(`family:${family.id}`))
    .map((family) => ({ ...family, count: counts.get(family.id) ?? 0 }))
    .sort((a, b) => (b.count - a.count) || a.id.localeCompare(b.id))
})

const selectedFamily = computed(() => {
  const tag = activeTags.value.find((item) => item.startsWith('family:'))
  return tag ? tag.slice('family:'.length) : ''
})

function setFamilyFilter(familyId: string) {
  const familyTag = `family:${familyId}`
  if (activeTags.value.includes(familyTag)) {
    activeTags.value = activeTags.value.filter((tag) => tag !== familyTag)
    return
  }
  activeTags.value = [
    ...activeTags.value.filter((tag) => !tag.startsWith('family:')),
    familyTag,
  ]
}

// 根据选择的规范模型获取详情和供应商信息
const selectedModelDetail = ref<ModelDetail | null>(null)
const loadingDetail = ref(false)

// 获取供应商信息
async function loadProviders() {
  try {
    providers.value = await getProviders()
  } catch (e) { /* ignore */ }
}

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
    const r = await listModels({ status: statusFilter.value || undefined })
    models.value = r.items
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : md('error.loadFailed')
  } finally {
    loading.value = false
  }
}

async function reloadAll() {
  await Promise.all([loadTags(), loadFamilies(), loadModels(), loadProviders()])
}

function toggleTag(t: string) {
  toggleNamespaceTag(t)
}

function clearFilters() {
  const shouldReload = Boolean(statusFilter.value)
  activeTags.value = []
  statusFilter.value = ''
  selectedVendor.value = ''
  selectedCanonical.value = ''
  selectedModelDetail.value = null
  pickedModel.value = ''
  textSearch.value = ''
  if (shouldReload) loadModels()
}

function onStatusFilterChange(status: string) {
  statusFilter.value = status
  loadModels()
}

function removeTag(tag: string) {
  if (!activeTags.value.includes(tag)) return
  activeTags.value = activeTags.value.filter((item) => item !== tag)
}

function clearStatusFilter() {
  if (!statusFilter.value) return
  statusFilter.value = ''
  loadModels()
}

function clearVendorFilter() {
  selectedVendor.value = ''
}

function clearSearchFilter() {
  pickedModel.value = ''
  textSearch.value = ''
}

const activeFilterChips = useFilterChips(() => [
  statusFilter.value ? {
    key: `status:${statusFilter.value}`,
    label: md('chip.status', { value: statusFilter.value }),
    onRemove: clearStatusFilter,
    className: 'badge-gray',
  } : null,
  selectedVendor.value ? {
    key: `vendor:${selectedVendor.value}`,
    label: md('chip.vendor', { value: selectedVendor.value }),
    onRemove: clearVendorFilter,
    className: 'badge-gray',
  } : null,
  pickedModel.value.trim() || textSearch.value.trim() ? {
    key: `search:${pickedModel.value}:${textSearch.value}`,
    label: md('chip.model', { value: pickedModel.value || textSearch.value.trim() }),
    onRemove: clearSearchFilter,
    className: 'badge-gray',
  } : null,
  ...activeTags.value.map((tag) => ({
    key: `tag:${tag}`,
    label: tag,
    onRemove: () => removeTag(tag),
    className: tagBadgeClass(tag),
  })),
])

const namespaceTagCount = computed(() =>
  namespaceOptions.value.reduce((total, group) => total + group.tags.length, 0)
)

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
    error.value = e instanceof Error ? e.message : md('error.saveFailed')
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
    error.value = e instanceof Error ? e.message : md('error.resetFailed')
  }
}

async function openDetail(m: ModelCanonical) {
  detailLoading.value = true
  error.value = ''
  selectedCanonical.value = m.canonical_name
  try {
    detail.value = await getModel(m.id)
    selectedModelDetail.value = detail.value
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
    error.value = e instanceof Error ? e.message : md('error.loadDetailFailed')
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
    showCreateModal.value = false
    await reloadAll()
    const row = models.value.find((m) => m.id === created.id)
    if (row) await openDetail(row)
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : md('error.createFailed')
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
    showDiscoveryCard.value = true
    discoverMessage.value = started.reason === 'already_running' ? md('discovery.alreadyRunning') : md('discovery.started')
    await pollDiscovery(started.run.id)
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : md('error.discoverFailed')
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
      if (latest?.status === 'failed') error.value = latest.error || md('discovery.failed')
      if (latest?.status === 'succeeded') {
        discoverMessage.value = md('discovery.completed')
        await reloadAll()
        window.dispatchEvent(new CustomEvent('llm-gateway:models-updated'))
      }
      refreshDiscoveryCardVisibility()
      return
    }
    await new Promise((resolve) => window.setTimeout(resolve, 3000))
  }
}

function discoveryHasStats(result: DiscoverModelsResult | null | undefined): boolean {
  if (!result) return false
  return (
    (result.credentials_scanned ?? 0) > 0 ||
    (result.models_seen ?? 0) > 0 ||
    (result.offers_upserted ?? 0) > 0 ||
    (result.credentials_failed ?? 0) > 0
  )
}

function refreshDiscoveryCardVisibility() {
  if (discovering.value) {
    showDiscoveryCard.value = true
    return
  }
  const run = discoverRun.value
  const result = discoverResult.value
  if (discoveryHasStats(result)) {
    showDiscoveryCard.value = true
    return
  }
  if (run && (run.status === 'succeeded' || run.status === 'failed')) {
    showDiscoveryCard.value = true
    return
  }
  if (run?.status === 'running' && run.trigger === 'manual') {
    showDiscoveryCard.value = true
    return
  }
  showDiscoveryCard.value = false
}

async function loadDiscoveryStatus() {
  try {
    const status = await getModelDiscoveryStatus()
    if (status.running?.trigger === 'manual') {
      discoverRun.value = status.running
      if (status.running.summary) discoverResult.value = status.running.summary
      discovering.value = true
      discoverMessage.value = md('discovery.runningInBackground')
      showDiscoveryCard.value = true
      await pollDiscovery(status.running.id)
      return
    }
    discoverRun.value = status.latest
    if (status.latest?.summary) discoverResult.value = status.latest.summary
    if (status.running?.trigger === 'scheduled') {
      discoverMessage.value = ''
    }
    refreshDiscoveryCardVisibility()
  } catch (e) { /* ignore */ }
}

async function openFeaturedDrawer() {
  showFeaturedDrawer.value = true
  featuredError.value = ''
  featuredMessage.value = ''
  featuredRecommendPreview.value = []
  featuredRecommendMessage.value = ''
  try {
    featuredLoading.value = true
    const r = await getFeatured()
    featuredArray.value = (r.featured_models || []).slice()
  } catch (e: unknown) {
    featuredError.value = e instanceof Error ? e.message : md('error.loadFeaturedFailed')
    featuredArray.value = []
  } finally {
    featuredLoading.value = false
  }
}

function closeFeaturedDrawer() {
  showFeaturedDrawer.value = false
  featuredError.value = ''
  featuredMessage.value = ''
  featuredRecommendPreview.value = []
  featuredRecommendMessage.value = ''
}

async function saveFeatured() {
  featuredSaving.value = true
  featuredError.value = ''
  featuredMessage.value = ''
  try {
    const list = featuredArray.value.map((s) => s.trim()).filter(Boolean)
    const r = await patchFeatured(list)
    featuredArray.value = (r.featured_models || []).slice()
    featuredMessage.value = md('drawer.featuredUpdated', { n: list.length })
  } catch (e: unknown) {
    featuredError.value = e instanceof Error ? e.message : md('error.saveFeaturedFailed')
  } finally {
    featuredSaving.value = false
  }
}

async function previewRecommendedFeatured() {
  featuredRecommendLoading.value = true
  featuredRecommendMessage.value = ''
  try {
    const r = await getFeaturedModelsDynamic()
    const list: FeaturedModel[] = (r.models ?? []).filter((m) => m.name)
    featuredRecommendPreview.value = list
    if (list.length === 0) {
      featuredRecommendMessage.value = md('drawer.noRecommend')
    } else {
      const tagged = list.map((m) => `${m.name}${m.count > 0 ? ` (${m.count})` : ''}`)
      featuredRecommendMessage.value = md('drawer.recommendLoaded', { n: list.length, preview: tagged.slice(0, 5).join('、') + (list.length > 5 ? '…' : '') })
    }
  } catch (e: unknown) {
    featuredRecommendMessage.value = e instanceof Error ? e.message : md('drawer.recommendLoadFailed')
    featuredRecommendPreview.value = []
  } finally {
    featuredRecommendLoading.value = false
  }
}

function adoptRecommendedFeatured() {
  if (featuredRecommendPreview.value.length === 0) return
  const recommended = featuredRecommendPreview.value.map((m) => m.name)
  const merged = Array.from(new Set([...featuredArray.value, ...recommended]))
  featuredArray.value = merged
  featuredRecommendMessage.value = md('drawer.recommendAdopted', { n: recommended.length, m: merged.length })
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

function healthBadgeClass(status: string | null | undefined): string {
  if (status === 'healthy') return 'badge-green'
  if (status === 'warning') return 'badge-yellow'
  if (status === 'unreachable') return 'badge-red'
  return 'badge-gray'
}

function healthLabel(status: string | null | undefined): string {
  if (status === 'healthy') return md('health.healthy')
  if (status === 'warning') return md('health.warning')
  if (status === 'unreachable') return md('health.unreachable')
  return md('health.unknown')
}

onMounted(async () => {
  syncTabFromRoute()
  await reloadAll()
})
</script>

<template>
  <div>
    <div class="page-header">
      <h2>{{ md('page.title') }}</h2>
      <div v-if="activeTab === 'canonical'" style="display:flex;gap:8px;align-items:center">
        <span class="badge badge-gray">{{ md('page.countBadge', { n: filtered.length }) }}</span>
        <button v-if="!readOnly" class="btn btn-ghost btn-sm" @click="openFeaturedDrawer">
          {{ md('header.featured') }}
        </button>
        <button v-if="!readOnly" class="btn btn-primary btn-sm" @click="showCreateModal = true">
          {{ md('header.create') }}
        </button>
        <button v-if="!readOnly" class="btn btn-ghost btn-sm" :disabled="discovering" @click="runDiscovery">
          {{ discovering ? md('header.discovering') : md('header.discover') }}
        </button>
      </div>
    </div>

    <div class="tab-bar" style="margin-bottom:16px">
      <button
        v-if="isPlatformOps"
        type="button"
        class="tab-btn"
        :class="{ active: activeTab === 'canonical' }"
        @click="setTab('canonical')"
      >
        {{ md('tab.canonical', { n: filtered.length }) }}
      </button>
      <button
        type="button"
        class="tab-btn"
        :class="{ active: activeTab === 'catalog' }"
        @click="setTab('catalog')"
      >
        {{ md('tab.catalog') }}
      </button>
    </div>

    <CatalogPanel v-if="activeTab === 'catalog'" />

    <template v-else>
    <div v-if="readOnly" class="alert alert-info" style="margin-bottom:12px">
      {{ md('readOnly') }}
    </div>

    <!-- 发现任务状态 -->
    <div v-if="showDiscoveryCard" class="card discovery-card">
      <div class="card-header"><h3>{{ md('discovery.title') }}</h3></div>
      <div class="card-body">
        <div v-if="discoverRun" class="summary-row">
          <span
            class="badge"
            :class="discoverRun.status === 'succeeded' ? 'badge-green' : discoverRun.status === 'failed' ? 'badge-red' : (discovering ? 'badge-blue' : 'badge-gray')"
          >{{ discovering ? discoverRun.status : (discoverRun.status === 'running' ? md('discovery.idle') : discoverRun.status) }}</span>
          <span class="badge badge-gray">{{ discoverRun.trigger }}</span>
          <span class="muted small">#{{ discoverRun.id }} · {{ discoverMessage || (discovering ? md('discovery.running') : md('discovery.latest')) }}</span>
        </div>
        <div class="summary-row">
          <span class="badge badge-blue">{{ md('discovery.credentials', { ok: discoverResult?.credentials_succeeded ?? 0, total: discoverResult?.credentials_scanned ?? 0 }) }}</span>
          <span class="badge badge-green">{{ md('discovery.models', { n: discoverResult?.models_seen ?? 0 }) }}</span>
          <span class="badge badge-purple">{{ md('discovery.offers', { n: discoverResult?.offers_upserted ?? 0 }) }}</span>
          <span v-if="discoverResult?.credentials_failed" class="badge badge-yellow">{{ md('discovery.failedCount', { n: discoverResult.credentials_failed }) }}</span>
        </div>
        <div class="summary-row" v-if="discoverResult">
          <span class="badge badge-green">{{ md('discovery.healthy', { n: discoverResult.healthy_credentials ?? 0 }) }}</span>
          <span class="badge badge-yellow">{{ md('discovery.warning', { n: discoverResult.warning_credentials ?? 0 }) }}</span>
          <span class="badge badge-red">{{ md('discovery.unreachable', { n: discoverResult.unreachable_credentials ?? 0 }) }}</span>
        </div>
      </div>
    </div>

    <!-- 筛选区域 -->
    <div class="card filter-card" style="margin-bottom:12px">
      <div class="card-header">
        <div class="filter-heading">
          <h3>{{ md('filter.title') }}</h3>
          <div v-if="namespaceOptions.length" class="filter-summary-row">
            <span class="muted small">{{ md('filter.tagDimensions', { n: namespaceOptions.length, m: namespaceTagCount }) }}</span>
            <span v-if="activeTags.length" class="muted small">{{ md('filter.selectedTags', { n: activeTags.length }) }}</span>
          </div>
        </div>
        <div class="filter-header-actions">
          <button
            v-if="namespaceOptions.length"
            class="btn btn-ghost btn-sm"
            @click="showNamespaceFilters = !showNamespaceFilters"
          >
            {{ showNamespaceFilters ? md('filter.collapse') : md('filter.expand') }}
          </button>
          <button v-if="activeTags.length || statusFilter || selectedVendor || pickedModel.trim() || textSearch.trim()" class="btn btn-ghost btn-sm" @click="clearFilters">{{ md('filter.clear') }}</button>
        </div>
      </div>
      <div class="card-body">
        <ModelCatalogFilterBar
          v-model:picked-model="pickedModel"
          v-model:filter-vendor="selectedVendor"
          v-model:extra-filter="statusFilter"
          v-model:text-search="textSearch"
          :vendor-options="vendors"
          :count="filtered.length"
          :picker-title="md('filter.pickerTitle')"
          :picker-placeholder="md('filter.pickerPlaceholder')"
          :status-label="md('filter.allStatus')"
          :status-options="modelStatusOptions"
          show-text-search
          :text-search-placeholder="md('filter.textSearchPlaceholder')"
          :show-clear="false"
          @status-change="onStatusFilterChange"
        />

        <div v-if="familyOptions.length" class="family-quick-row">
          <span class="muted small">{{ md('filter.familyQuick') }}</span>
          <button
            v-for="family in familyOptions.slice(0, 18)"
            :key="family.id"
            type="button"
            class="family-chip"
            :class="{ active: selectedFamily === family.id }"
            :title="md('filter.familyTooltip', { vendor: family.vendor || md('filter.familyVendorUnknown'), id: family.id })"
            @click="setFamilyFilter(family.id)"
          >
            <span>{{ family.vendor || family.display_name }}</span>
            <code>{{ family.id }}</code>
            <span class="cnt">{{ family.count }}</span>
          </button>
        </div>

        <ActiveFilterChips :chips="activeFilterChips" />

        <div v-if="showNamespaceFilters && namespaceOptions.length" class="namespace-panel">
          <div v-for="g in namespaceOptions" :key="g.namespace" class="ns-block">
            <div class="ns-label-row">
              <div class="ns-label">{{ g.namespace }}</div>
              <span class="badge badge-gray">{{ g.tags.length }}</span>
            </div>
            <div class="tag-list">
              <button
                v-for="t in g.tags"
                :key="t.tag"
                type="button"
                class="tag-chip"
                :class="{ active: activeTags.includes(t.tag), disabled: t.disabled, [tagBadgeClass(t.tag)]: true }"
                @click="toggleTag(t.tag)"
                :disabled="t.disabled"
                :title="t.disabled ? md('filter.tagNoMatch') : md('filter.tagCount', { n: t.count })"
              >
                {{ t.tag }} <span class="cnt">{{ t.count }}</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 模型列表 -->
    <div class="card" style="margin-top:12px">
      <div class="card-header">
        <h3>{{ md('table.title') }}</h3>
      </div>
      <div class="card-body">
        <div v-if="error" class="alert alert-error">{{ error }}</div>
        <div v-if="loading" class="muted">{{ t('common.feedback.loading') }}</div>
        <table v-else class="table">
          <thead>
            <tr>
              <th>{{ md('table.colCanonical') }}</th>
              <th>{{ md('table.colDisplay') }}</th>
              <th>{{ md('table.colVendor') }}</th>
              <th>{{ md('table.colFamily') }}</th>
              <th>{{ md('table.colStatus') }}</th>
              <th>{{ md('table.colModality') }}</th>
              <th>{{ md('table.colCtx') }}</th>
              <th>{{ md('table.colAliasesOffers') }}</th>
              <th>{{ md('table.colActions') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="m in filtered" :key="m.id" :class="{ mutedRow: m.status !== 'active' }">
              <td>
                <code>{{ m.canonical_name }}</code>
              </td>
              <td>{{ m.display_name || '-' }}</td>
              <td>{{ modelVendorName(m) }}</td>
              <td>{{ m.family || '-' }}</td>
              <td><span class="badge" :class="statusBadgeClass(m.status)">{{ m.status }}</span></td>
              <td>{{ m.modality }}</td>
              <td>{{ m.context_window ?? '-' }}</td>
              <td>{{ m.alias_count ?? 0 }} / {{ m.offer_count ?? 0 }}</td>
              <td style="white-space:nowrap">
                <button class="btn btn-primary btn-sm" @click="openDetail(m)">{{ md('table.viewDetail') }}</button>
                <button class="btn btn-ghost btn-sm" @click="toggleModelStatus(m)">{{ m.status === 'active' ? md('table.disable') : md('table.enable') }}</button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- 特色模型抽屉 -->
    <div v-if="showFeaturedDrawer" class="drawer-backdrop" @click="closeFeaturedDrawer">
      <div class="drawer-panel card drawer-panel-wide" @click.stop>
        <div class="drawer-header">
          <h3>{{ md('drawer.featured') }}</h3>
          <button class="btn btn-ghost btn-sm" @click="closeFeaturedDrawer">{{ md('drawer.close') }}</button>
        </div>
        <div class="drawer-body">
          <p class="muted small" style="margin-top:0" v-html="md('drawer.featuredDesc')" />

          <div v-if="featuredError" class="alert alert-error">{{ featuredError }}</div>
          <div v-if="featuredMessage" class="alert alert-success">{{ featuredMessage }}</div>

          <div v-if="featuredLoading" class="muted">{{ t('common.feedback.loading') }}</div>
          <template v-else>
            <div class="featured-recommend-bar">
              <button class="btn btn-sm btn-ghost" :disabled="featuredRecommendLoading" @click="previewRecommendedFeatured">
                {{ featuredRecommendLoading ? md('drawer.recommendBtnLoading') : md('drawer.recommendBtn') }}
              </button>
              <button
                v-if="featuredRecommendPreview.length"
                class="btn btn-sm btn-primary"
                @click="adoptRecommendedFeatured"
              >{{ md('drawer.adoptRecommend') }}</button>
              <span v-if="featuredRecommendMessage" class="featured-recommend-msg">{{ featuredRecommendMessage }}</span>
            </div>

            <div class="form-group">
              <label>{{ md('drawer.featuredList') }}</label>
              <ModelPicker
                v-model="featuredArray"
                mode="multi"
                :placeholder="md('drawer.featuredPlaceholder')"
                :title="md('drawer.featuredTitle')"
              />
            </div>

            <div class="drawer-actions">
              <button class="btn btn-primary" @click="saveFeatured" :disabled="featuredSaving">
                {{ featuredSaving ? md('drawer.savingFeatured') : md('drawer.saveFeatured') }}
              </button>
              <button class="btn btn-ghost" @click="closeFeaturedDrawer">{{ md('drawer.close') }}</button>
            </div>
          </template>
        </div>
      </div>
    </div>

    <!-- 模型详情弹层 -->
    <div v-if="detail" class="drawer-backdrop" @click="detail = null">
      <div class="drawer-panel card drawer-panel-wide" @click.stop>
        <div class="drawer-header">
          <h3>{{ detail.canonical_name }}</h3>
          <button class="btn btn-ghost btn-sm" @click="detail = null">{{ md('drawer.close') }}</button>
        </div>
        <div class="drawer-body">
          <div v-if="detailLoading" class="muted">{{ t('common.feedback.loading') }}</div>

          <!-- 基础信息 -->
          <div class="section">
            <h4>{{ md('detail.basicInfo') }}</h4>
            <div class="form-grid">
              <div class="form-group">
                <label>{{ md('detail.displayName') }}</label>
                <input v-model="editInfo.display_name" class="input" :placeholder="md('detail.displayName')" />
              </div>
              <div class="form-group">
                <label>{{ md('detail.vendorFamily') }}</label>
                <select v-model="editInfo.family" class="input">
                  <option value="">{{ md('detail.noFamily') }}</option>
                  <option v-for="f in families" :key="f.id" :value="f.id">{{ f.vendor ? f.vendor + ' - ' : '' }}{{ f.display_name }} · {{ f.id }}</option>
                </select>
              </div>
              <div class="form-group">
                <label>{{ md('detail.status') }}</label>
                <select v-model="editInfo.status" class="input">
                  <option v-for="s in statuses" :key="s" :value="s">{{ s }}</option>
                </select>
              </div>
              <div class="form-group">
                <label>{{ md('detail.modality') }}</label>
                <select v-model="editInfo.modality" class="input">
                  <option v-for="m in modalities" :key="m" :value="m">{{ m }}</option>
                </select>
              </div>
              <div class="form-group">
                <label>{{ md('detail.contextWindow') }}</label>
                <input v-model="editInfo.context_window" class="input" :placeholder="md('detail.contextWindowPlaceholder')" />
                <span class="help-text">{{ md('detail.contextWindowHelp') }}</span>
              </div>
              <div class="form-group">
                <label>{{ md('detail.parametersB') }}</label>
                <input v-model="editInfo.parameters_b" class="input" :placeholder="md('detail.parametersBPlaceholder')" />
                <span class="help-text">{{ md('detail.parametersBHelp') }}</span>
              </div>
              <div class="form-group span-2">
                <label>{{ md('detail.disabledReason') }}</label>
                <input v-model="editInfo.disabled_reason" class="input" :placeholder="md('detail.disabledReasonPlaceholder')" />
              </div>
              <div class="form-group span-2">
                <label>{{ md('detail.notes') }}</label>
                <textarea v-model="editInfo.notes" class="input" rows="2" :placeholder="md('detail.notesPlaceholder')" />
              </div>
              <div class="form-group">
                <button class="btn btn-primary" @click="saveInfo">{{ md('detail.saveBasicInfo') }}</button>
              </div>
            </div>
          </div>

          <!-- Aliases 部分 -->
          <div class="section">
            <h4>{{ md('detail.aliasesTitle') }}</h4>
            <p class="help-text">{{ md('detail.aliasesHelp') }}</p>

            <div class="alias-add">
              <div class="form-group">
                <label>{{ md('detail.rawModelName') }}</label>
                <input v-model="newAlias.raw_name" class="input" :placeholder="md('detail.rawModelNamePlaceholder')" />
                <span class="help-text">{{ md('detail.rawModelNameHelp') }}</span>
              </div>
              <div class="form-group">
                <label>{{ md('detail.surfaceName') }}</label>
                <input v-model="newAlias.surface" class="input" :placeholder="md('detail.surfaceNamePlaceholder')" />
                <span class="help-text">{{ md('detail.surfaceNameHelp') }}</span>
              </div>
              <div class="form-group">
                <label>{{ md('detail.quantization') }}</label>
                <input v-model="newAlias.quantization" class="input" :placeholder="md('detail.quantizationPlaceholder')" />
                <span class="help-text">{{ md('detail.quantizationHelp') }}</span>
              </div>
              <div class="form-group">
                <label>{{ md('detail.notes') }}</label>
                <input v-model="newAlias.notes" class="input" :placeholder="md('detail.notesPlaceholder')" />
              </div>
              <div class="form-group" style="align-self:end">
                <button class="btn btn-primary btn-sm" @click="addAlias">{{ md('detail.addAlias') }}</button>
              </div>
            </div>

            <div style="margin:12px 0">
              <div style="font-size:12px;color:var(--muted);margin-bottom:6px">{{ md('detail.bulkImportTitle') }}</div>
              <textarea v-model="bulkAliasText" class="input" rows="4" placeholder="gpt-4o&#10;claude-sonnet-4&#10;gemini-pro" />
              <input v-model="bulkAliasProfiles" class="input" style="margin-top:6px" :placeholder="md('detail.bulkImportProfilesPlaceholder')" />
              <button class="btn btn-ghost btn-sm" style="margin-top:6px" @click="bulkImportAliases">{{ md('detail.bulkImport') }}</button>
            </div>

            <table class="table alias-table">
              <thead><tr><th>{{ md('detail.aliasColRaw') }}</th><th>{{ md('detail.aliasColSurface') }}</th><th>{{ md('detail.aliasColQuant') }}</th><th>{{ md('detail.aliasColStatus') }}</th><th>{{ md('detail.aliasColNotes') }}</th><th>{{ md('detail.aliasColActions') }}</th></tr></thead>
              <tbody>
                <tr v-for="a in detail.aliases" :key="a.id" :class="{ mutedRow: a.status !== 'active' }">
                  <td><code>{{ a.raw_name }}</code></td>
                  <td>{{ a.surface || '-' }}</td>
                  <td>{{ a.quantization || '-' }}</td>
                  <td><span class="badge" :class="statusBadgeClass(a.status)">{{ a.status }}</span></td>
                  <td>{{ a.notes || '-' }}</td>
                  <td>
                    <button class="btn btn-ghost btn-sm" @click="setAliasStatus(a.id, a.status === 'active' ? 'disabled' : 'active')">
                      {{ a.status === 'active' ? md('table.disable') : md('table.enable') }}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <!-- 供应商信息 -->
          <div class="section">
            <h4>{{ md('detail.providersTitle') }}</h4>
            <p class="help-text">{{ md('detail.providersHelp') }}</p>

            <div v-if="detail.offers && detail.offers.length > 0">
              <table class="table offers-table">
                <thead>
                  <tr>
                    <th>{{ md('detail.colProvider') }}</th>
                    <th>{{ md('detail.colCredential') }}</th>
                    <th>{{ md('detail.colRawModel') }}</th>
                    <th>{{ md('detail.colInPrice') }}</th>
                    <th>{{ md('detail.colOutPrice') }}</th>
                    <th>{{ md('detail.colSuccessRate') }}</th>
                    <th>{{ md('detail.colP95') }}</th>
                    <th>{{ md('detail.colHealth') }}</th>
                    <th>{{ md('detail.colStatus') }}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="offer in detail.offers" :key="`${offer.provider_id}-${offer.credential_id}-${offer.raw_model_name}`">
                    <td>
                      <div class="provider-cell">
                        <span class="provider-name">{{ offer.provider_name }}</span>
                        <span class="badge badge-gray">{{ offer.catalog_code }}</span>
                      </div>
                    </td>
                    <td>
                      <div class="credential-cell">
                        <span>{{ offer.credential_label || `#${offer.credential_id}` }}</span>
                        <span v-if="offer.concurrency_limit" class="muted small">{{ md('detail.concurrentPrefix') }}{{ offer.concurrency_limit }}</span>
                      </div>
                    </td>
                    <td><code>{{ offer.raw_model_name }}</code></td>
                    <td v-if="offer.standardized_name"><code style="color:var(--accent)">{{ offer.standardized_name }}</code></td>
                    <td>{{ offer.input_price ? `¥${offer.input_price}${md('detail.priceUnit')}` : '-' }}</td>
                    <td>{{ offer.output_price ? `¥${offer.output_price}${md('detail.priceUnit')}` : '-' }}</td>
                    <td>
                      <span v-if="offer.success_rate !== null" :class="offer.success_rate >= 0.95 ? 'text-green' : offer.success_rate >= 0.8 ? 'text-yellow' : 'text-red'">
                        {{ (offer.success_rate * 100).toFixed(1) }}%
                      </span>
                      <span v-else>-</span>
                    </td>
                    <td>{{ offer.p95_latency_ms ? `${offer.p95_latency_ms}ms` : '-' }}</td>
                    <td><span class="badge" :class="healthBadgeClass(offer.health_status)">{{ healthLabel(offer.health_status) }}</span></td>
                    <td>
                      <span class="badge" :class="offer.available ? 'badge-green' : 'badge-red'">
                        {{ offer.available ? md('detail.available') : md('detail.unavailable') }}
                      </span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <div v-else class="muted">
              {{ md('detail.noOffers') }}
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 新增模型弹层 -->
    <div v-if="showCreateModal" class="modal-overlay" @click.self="showCreateModal = false">
      <div class="modal-content create-modal" @click.stop>
        <div class="modal-header">
          <h3>{{ md('createModal.title') }}</h3>
          <button class="btn btn-ghost btn-sm" @click="showCreateModal = false">{{ md('drawer.close') }}</button>
        </div>
        <div class="modal-body">
          <div class="form-grid">
            <div class="form-group">
              <label>{{ md('createModal.canonicalName') }} <span class="required">*</span></label>
              <input v-model="createForm.canonical_name" class="input" :placeholder="md('createModal.canonicalNamePlaceholder')" />
              <span class="help-text">{{ md('createModal.canonicalNameHelp') }}</span>
            </div>
            <div class="form-group">
              <label>{{ md('createModal.displayName') }}</label>
              <input v-model="createForm.display_name" class="input" :placeholder="md('createModal.displayNamePlaceholder')" />
              <span class="help-text">{{ md('createModal.displayNameHelp') }}</span>
            </div>
            <div class="form-group">
              <label>{{ md('createModal.vendorFamily') }}</label>
              <select v-model="createForm.family" class="input">
                <option value="">{{ md('createModal.selectFamily') }}</option>
                <option v-for="f in families" :key="f.id" :value="f.id">{{ f.vendor ? f.vendor + ' - ' : '' }}{{ f.display_name }} · {{ f.id }}</option>
              </select>
              <span class="help-text">{{ md('createModal.familyHelp') }}</span>
            </div>
            <div class="form-group">
              <label>{{ md('createModal.modality') }}</label>
              <select v-model="createForm.modality" class="input">
                <option v-for="m in modalities" :key="m" :value="m">{{ m }}</option>
              </select>
              <span class="help-text">{{ md('createModal.modalityHelp') }}</span>
            </div>
            <div class="form-group">
              <label>{{ md('createModal.contextWindow') }}</label>
              <input v-model="createForm.context_window" class="input" :placeholder="md('createModal.contextWindowPlaceholder')" />
              <span class="help-text">{{ md('createModal.contextWindowHelp') }}</span>
            </div>
            <div class="form-group">
              <label>{{ md('createModal.parametersB') }}</label>
              <input v-model="createForm.parameters_b" class="input" :placeholder="md('createModal.parametersBPlaceholder')" />
              <span class="help-text">{{ md('createModal.parametersBHelp') }}</span>
            </div>
            <div class="form-group span-2">
              <label>{{ md('createModal.aliases') }}</label>
              <textarea v-model="createForm.aliases" class="input" rows="3" placeholder="gpt-4o-2024-08-06&#10;gpt-4o-latest&#10;openai/gpt-4o" />
              <span class="help-text">{{ md('createModal.aliasesHelp') }}</span>
            </div>
            <div class="form-group span-2">
              <label>{{ md('createModal.notes') }}</label>
              <textarea v-model="createForm.notes" class="input" rows="2" :placeholder="md('createModal.notesPlaceholder')" />
            </div>
          </div>
          <div class="modal-footer">
            <button class="btn btn-ghost" @click="showCreateModal = false">{{ md('createModal.cancel') }}</button>
            <button class="btn btn-primary" :disabled="creating || !createForm.canonical_name" @click="submitCreate">
              {{ creating ? md('createModal.submitting') : md('createModal.submit') }}
            </button>
          </div>
        </div>
      </div>
    </div>
    </template>
  </div>
</template>

<style scoped>
.tab-bar { display: flex; gap: 8px; flex-wrap: wrap; }
.tab-btn {
  border: 1px solid var(--border);
  background: rgba(255,255,255,.02);
  border-radius: 999px;
  padding: 6px 14px;
  font-size: 13px;
  cursor: pointer;
  color: var(--muted);
}
.tab-btn:hover:not(.active) { color: var(--text); }
.tab-btn.active {
  border-color: var(--primary, #6366f1);
  color: var(--text);
  font-weight: 600;
  outline: 2px solid color-mix(in srgb, var(--primary, #6366f1) 24%, transparent);
}
.tab-count {
  font-size: 11px;
  opacity: .75;
  margin-left: 2px;
}

.page-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 16px;
}

.filter-row {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
  align-items: center;
}

.filter-card {
  padding: 12px 14px;
}

.filter-card .card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  margin-bottom: 8px;
}

.filter-card .card-header h3 {
  margin: 0;
  font-size: 15px;
}

.filter-heading {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}

.filter-card .card-body {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.filter-header-actions {
  display: flex;
  gap: 8px;
  align-items: center;
  flex-wrap: wrap;
}

.filter-summary-row {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
  align-items: center;
}

.family-quick-row {
  display: flex;
  gap: 6px;
  flex-wrap: wrap;
  align-items: center;
  padding-top: 4px;
}

.family-chip {
  border: 1px solid var(--border);
  background: rgba(139,148,158,.15);
  border-radius: 999px;
  padding: 4px 9px;
  font-size: 12px;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: var(--text);
}
.family-chip code {
  color: var(--text-muted, var(--muted));
}

.family-chip.active {
  border-color: var(--primary, #6366f1);
  outline: 2px solid color-mix(in srgb, var(--primary, #6366f1) 24%, transparent);
}

.family-chip code {
  font-size: 11px;
}

.family-chip .cnt {
  color: var(--text-muted);
  font-size: 10px;
}

.namespace-panel {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 10px;
  padding-top: 10px;
  border-top: 1px solid var(--border);
  max-height: 320px;
  overflow: auto;
  padding-right: 4px;
}

.ns-block {
  margin-bottom: 0;
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 10px;
  background: rgba(255,255,255,.02);
}

.ns-label-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  margin-bottom: 6px;
}

.ns-label { font-size: 11px; font-weight: 600; color: var(--text-muted); text-transform: uppercase; }
.tag-list { display: flex; flex-wrap: wrap; gap: 4px; }
.tag-chip {
  border: 1px solid var(--border); background: var(--bg);
  border-radius: 12px; padding: 2px 8px; font-size: 12px; cursor: pointer;
  display: inline-flex; align-items: center; gap: 4px;
}
.tag-chip.active { outline: 2px solid var(--primary, #6366f1); }
.tag-chip.disabled { opacity: .38; cursor: not-allowed; }
.tag-chip:disabled { opacity: .38; cursor: not-allowed; }
.tag-chip .cnt { color: var(--text-muted); font-size: 10px; }
.muted { color: var(--text-muted); }
.small { font-size: 11px; margin-top: 3px; }
.mutedRow { opacity: .62; }
.discovery-card { margin-bottom: 12px; }
.summary-row { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 8px; }

.drawer-actions {
  display: flex;
  gap: 8px;
  margin-top: 12px;
}

.drawer-backdrop {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.5);
  z-index: 1000;
}

.drawer-panel {
  position: fixed;
  top: 0;
  right: 0;
  bottom: 0;
  width: 680px;
  max-width: 90vw;
  border-radius: 0;
  overflow-y: auto;
  z-index: 1001;
}

.drawer-panel-wide {
  width: 860px;
}

.drawer-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 20px 24px;
  border-bottom: 1px solid var(--border);
}

.drawer-header h3 {
  margin: 0;
  font-size: 18px;
}

.drawer-body {
  padding: 24px;
}

.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  justify-content: center;
  align-items: flex-start;
  padding: 40px 20px;
  z-index: 1000;
  overflow-y: auto;
}

.create-modal {
  background: var(--bg);
  border-radius: 12px;
  width: 100%;
  max-width: 900px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
}

.modal-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 20px 24px;
  border-bottom: 1px solid var(--border);
}

.modal-header h3 {
  margin: 0;
  font-size: 18px;
}

.modal-body {
  padding: 24px;
}

.modal-footer {
  display: flex;
  justify-content: flex-end;
  gap: 12px;
  margin-top: 24px;
  padding-top: 16px;
  border-top: 1px solid var(--border);
}

/* 表单样式 */
.form-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 16px;
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.form-group label {
  font-size: 13px;
  font-weight: 600;
  color: var(--text);
}

.form-group .required {
  color: #ef4444;
}

.form-group .help-text {
  font-size: 11px;
  color: var(--text-muted);
  line-height: 1.4;
}

.span-2 {
  grid-column: span 2;
}

.section {
  margin-bottom: 24px;
  padding-bottom: 24px;
  border-bottom: 1px solid var(--border);
}

.section:last-child {
  border-bottom: none;
  margin-bottom: 0;
  padding-bottom: 0;
}

.section h4 {
  margin: 0 0 12px 0;
  font-size: 15px;
  font-weight: 600;
}

/* Alias 添加样式 */
.alias-add {
  display: grid;
  grid-template-columns: repeat(4, 1fr) auto;
  gap: 12px;
  align-items: start;
  margin: 12px 0;
}

.alias-table {
  margin-top: 12px;
}

/* 供应商网格 */
.provider-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  gap: 12px;
}

.provider-card {
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 12px;
}

.provider-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 8px;
}

.provider-name {
  font-weight: 600;
  font-size: 14px;
}

.provider-info {
  display: flex;
  gap: 8px;
  align-items: center;
}

/* 供应商表格样式 */
.offers-table {
  margin-top: 12px;
  font-size: 13px;
}

.offers-table th {
  font-size: 12px;
  font-weight: 600;
  color: var(--text-muted);
  text-transform: uppercase;
}

.provider-cell {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.credential-cell {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.text-green { color: #166534; }
.text-yellow { color: #92400e; }
.text-red { color: #991b1b; }

/* Badge 样式 */
.badge-red { background: #fee2e2; color: #991b1b; }
.badge-green { background: #dcfce7; color: #166534; }
.badge-blue { background: #dbeafe; color: #1e40af; }
.badge-yellow { background: #fef3c7; color: #92400e; }
.badge-purple { background: #ede9fe; color: #5b21b6; }
.badge-gray { background: #f3f4f6; color: #374151; }

@media (max-width: 900px) {
  .form-grid, .alias-add { grid-template-columns: 1fr; }
  .span-2 { grid-column: span 1; }
  .create-modal { margin: 20px; }
  .drawer-panel { width: 95vw; }
  .drawer-panel-wide { width: 95vw; }
  .filter-card .card-header { align-items: flex-start; }
  .filter-heading { width: 100%; }
  .filter-header-actions { width: 100%; justify-content: flex-start; }
  .filter-row { flex-direction: column; }
  .namespace-panel { grid-template-columns: 1fr; max-height: 280px; }
}
</style>
