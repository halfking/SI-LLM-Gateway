<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { getCatalog, type CatalogEntry } from '../api'

const entries  = ref<CatalogEntry[]>([])
const loading  = ref(false)
const error    = ref('')
const tierFilter = ref('all')
const search     = ref('')

const tiers = ['all', 'local', 'tier1', 'tier2', 'tier3', 'tier4']

const tierLabel: Record<string, string> = {
  all: '全部',
  local: '本地',
  tier1: 'Tier 1',
  tier2: 'Tier 2',
  tier3: 'Tier 3',
  tier4: 'Tier 4',
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    const tier = tierFilter.value === 'all' ? undefined : tierFilter.value
    entries.value = await getCatalog(tier)
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : '加载失败'
  } finally {
    loading.value = false
  }
}

const filtered = computed(() => {
  const q = search.value.toLowerCase()
  if (!q) return entries.value
  return entries.value.filter(e =>
    e.display_name.toLowerCase().includes(q) ||
    e.display_name_en.toLowerCase().includes(q) ||
    e.code.toLowerCase().includes(q) ||
    e.category.toLowerCase().includes(q)
  )
})

function tierBadge(tier: string) {
  const map: Record<string, string> = {
    local: 'badge-green', tier1: 'badge-blue',
    tier2: 'badge-blue', tier3: 'badge-yellow', tier4: 'badge-gray',
  }
  return map[tier] ?? 'badge-gray'
}

function modelCount(entry: CatalogEntry) {
  try {
    const m = typeof entry.models_manifest_json === 'string'
      ? JSON.parse(entry.models_manifest_json as unknown as string)
      : entry.models_manifest_json
    return Array.isArray(m) ? m.length : 0
  } catch { return 0 }
}

function topModels(entry: CatalogEntry): string[] {
  try {
    const m = typeof entry.models_manifest_json === 'string'
      ? JSON.parse(entry.models_manifest_json as unknown as string)
      : entry.models_manifest_json
    if (!Array.isArray(m)) return []
    return m.slice(0, 4).map((x: { id: string }) => x.id)
  } catch { return [] }
}

onMounted(load)
</script>

<template>
  <div>
    <div class="page-header">
      <h2>模型目录</h2>
      <span class="badge badge-gray">{{ filtered.length }} 个提供商</span>
    </div>

    <div class="filter-bar">
      <div style="display:flex;gap:6px;flex-wrap:wrap">
        <button
          v-for="t in tiers" :key="t"
          class="btn btn-sm"
          :class="tierFilter === t ? 'btn-primary' : 'btn-ghost'"
          @click="tierFilter = t; load()"
        >{{ tierLabel[t] }}</button>
      </div>
      <input v-model="search" placeholder="搜索提供商…" style="max-width:220px" />
    </div>

    <div v-if="error" class="alert alert-danger">{{ error }}</div>
    <div v-if="loading" class="empty">加载中…</div>

    <div class="catalog-grid" v-if="!loading">
      <div class="catalog-card card" v-for="entry in filtered" :key="entry.code">
        <div class="card-header">
          <div>
            <div class="card-name">{{ entry.display_name }}</div>
            <div class="card-name-en">{{ entry.display_name_en }}</div>
          </div>
          <div style="display:flex;gap:4px;flex-wrap:wrap;justify-content:flex-end">
            <span class="badge" :class="tierBadge(entry.tier)">{{ entry.tier }}</span>
            <span class="badge badge-green" v-if="entry.domestic">国内</span>
          </div>
        </div>
        <div class="meta-row">
          <span class="tag">{{ entry.category }}</span>
          <span class="tag">{{ entry.kind }}</span>
          <span class="tag">{{ entry.protocol }}</span>
        </div>
        <div class="model-count">{{ modelCount(entry) }} 个模型</div>
        <div class="model-tags">
          <span class="model-tag" v-for="m in topModels(entry)" :key="m">{{ m }}</span>
          <span class="model-tag-more" v-if="modelCount(entry) > 4">+{{ modelCount(entry) - 4 }}</span>
        </div>
        <div class="card-footer" v-if="entry.docs_url">
          <a :href="entry.docs_url" target="_blank" rel="noopener">文档 →</a>
        </div>
      </div>
    </div>
    <div v-if="!loading && filtered.length === 0" class="empty">无匹配结果</div>
  </div>
</template>

<style scoped>
.filter-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 20px;
  flex-wrap: wrap;
}
.catalog-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 14px;
}
.catalog-card { display: flex; flex-direction: column; gap: 10px; }
.card-header { display: flex; justify-content: space-between; align-items: flex-start; gap: 8px; }
.card-name { font-size: 14px; font-weight: 600; }
.card-name-en { font-size: 11px; color: var(--muted); }
.meta-row { display: flex; flex-wrap: wrap; gap: 4px; }
.model-count { font-size: 12px; color: var(--muted); }
.model-tags { display: flex; flex-wrap: wrap; gap: 4px; }
.model-tag {
  display: inline-block;
  padding: 1px 7px;
  background: rgba(255,255,255,.05);
  border: 1px solid var(--border);
  border-radius: 4px;
  font-size: 11px;
  color: var(--muted);
  font-family: monospace;
}
.model-tag-more { font-size: 11px; color: var(--muted); align-self: center; }
.card-footer { border-top: 1px solid var(--border); padding-top: 8px; font-size: 12px; }
</style>
