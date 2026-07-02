<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { getAuditLogs, type AuditLogEntry } from '../api'
import { useFormat } from '../i18n/useFormat'

const { t } = useI18n()
const { fmtDate: fmtDateBase, fmtTime: fmtTimeBase, fmtDateTime: fmtDateTimeBase } = useFormat()
// Short alias for the auditLog locale namespace.
const al = (k: string, params?: Record<string, unknown>): string =>
  t(`auditLog.${k}` as never, params as never)

const entries = ref<AuditLogEntry[]>([])
const total = ref(0)
const page = ref(1)
const size = ref(50)
const loading = ref(false)
const error = ref('')

const filterActor = ref('')
const filterAction = ref('')
const filterFrom = ref('')
const filterTo = ref('')

const detailVisible = ref(false)
const detailEntry = ref<AuditLogEntry | null>(null)

const totalPages = computed(() => Math.max(1, Math.ceil(total.value / size.value)))

async function load() {
  loading.value = true
  error.value = ''
  try {
    const r = await getAuditLogs({
      page: page.value,
      size: size.value,
      actor: filterActor.value.trim() || undefined,
      action: filterAction.value.trim() || undefined,
      from: filterFrom.value ? new Date(filterFrom.value).toISOString() : undefined,
      to: filterTo.value ? new Date(filterTo.value).toISOString() : undefined,
    })
    entries.value = r.entries || []
    total.value = r.total || 0
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : al('errors.loadFailed')
    entries.value = []
    total.value = 0
  } finally {
    loading.value = false
  }
}

function resetPageAndLoad() {
  page.value = 1
  load()
}

function changePage(delta: number) {
  const next = page.value + delta
  if (next < 1 || next > totalPages.value) return
  page.value = next
  load()
}

function clearFilters() {
  filterActor.value = ''
  filterAction.value = ''
  filterFrom.value = ''
  filterTo.value = ''
  resetPageAndLoad()
}

function actionBadgeClass(action: string): string {
  if (action.startsWith('user.create')) return 'badge-system'
  if (action.startsWith('user.delete')) return 'badge-red'
  if (action.startsWith('user.')) return 'badge-blue'
  if (action.startsWith('auth.login_failed') || action.startsWith('auth.rate_limited')) return 'badge-red'
  if (action.startsWith('auth.')) return 'badge-green'
  return 'badge-gray'
}

function actionLabel(action: string): string {
  // Use the auditLog.actions map; falls back to the raw action key.
  const translated = al(`actions.${action}`)
  if (translated && translated !== `actions.${action}`) return translated
  return action
}

function fmtDate(s: string) {
  if (!s) return al('pagination.dash')
  return fmtDateBase(s)
}

function fmtTime(s: string) {
  if (!s) return al('pagination.dash')
  return fmtTimeBase(s)
}

function fmtTs(s: string) {
  if (!s) return al('pagination.dash')
  return fmtDateTimeBase(s)
}

function fmtJson(v: unknown): string {
  if (v == null) return ''
  if (typeof v === 'string') {
    try {
      return JSON.stringify(JSON.parse(v), null, 2)
    } catch {
      return v
    }
  }
  try {
    return JSON.stringify(v, null, 2)
  } catch {
    return String(v)
  }
}

function detailPreview(e: AuditLogEntry): string {
  const raw = e.after_json ?? e.before_json
  if (raw == null) return al('pagination.dash')
  const text = typeof raw === 'string' ? raw : JSON.stringify(raw)
  if (text.length <= 80) return text
  return text.slice(0, 79) + '…'
}

function openDetail(e: AuditLogEntry) {
  detailEntry.value = e
  detailVisible.value = true
}

function closeDetail() {
  detailVisible.value = false
  detailEntry.value = null
}

onMounted(load)
</script>

<template>
  <div class="audit-page">
    <div class="page-header">
      <h2>{{ al('page.title') }}</h2>
      <div class="header-actions">
        <span class="count-chip" aria-live="polite">{{ al('page.totalChip', { n: total }) }}</span>
        <button class="btn btn-primary btn-sm" :disabled="loading" @click="load">
          {{ loading ? al('page.refreshing') : al('page.refresh') }}
        </button>
      </div>
    </div>

    <p class="page-desc">{{ al('page.desc') }}</p>

    <div v-if="error" class="alert alert-danger" role="alert">{{ error }}</div>

    <div class="compact-filter-bar compact-filter-bar--stacked">
      <div class="cf-row">
        <div class="cf-field cf-field--actor">
          <span class="cf-label">{{ al('filter.actorLabel') }}</span>
          <input
            v-model="filterActor"
            type="text"
            class="cf-input"
            :placeholder="al('filter.actorPlaceholder')"
            :aria-label="al('filter.actorAria')"
            @keyup.enter="resetPageAndLoad"
          />
        </div>
        <div class="cf-field cf-field--action">
          <span class="cf-label">{{ al('filter.actionLabel') }}</span>
          <input
            v-model="filterAction"
            type="text"
            class="cf-input"
            :placeholder="al('filter.actionPlaceholder')"
            :aria-label="al('filter.actionAria')"
            @keyup.enter="resetPageAndLoad"
          />
        </div>
        <div class="cf-field cf-field--time">
          <span class="cf-label">{{ al('filter.fromLabel') }}</span>
          <input v-model="filterFrom" type="datetime-local" class="cf-input" :aria-label="al('filter.fromAria')" />
        </div>
        <div class="cf-field cf-field--time">
          <span class="cf-label">{{ al('filter.toLabel') }}</span>
          <input v-model="filterTo" type="datetime-local" class="cf-input" :aria-label="al('filter.toAria')" />
        </div>
        <button class="btn btn-primary btn-sm" :disabled="loading" @click="resetPageAndLoad">{{ al('filter.query') }}</button>
        <button class="btn btn-ghost btn-sm" :disabled="loading" @click="clearFilters">{{ al('filter.reset') }}</button>
      </div>
    </div>

    <div v-if="!loading && total > 0" class="pagination-bar">
      <div class="pagination-meta">
        <span>{{ al('pagination.total', { n: total }) }}</span>
        <span>{{ al('pagination.pageOf', { page: page, total: totalPages }) }}</span>
        <label class="page-size-label">
          <span class="text-muted">{{ al('pagination.perPage') }}</span>
          <select v-model.number="size" class="page-size-select" @change="resetPageAndLoad">
            <option :value="25">25</option>
            <option :value="50">50</option>
            <option :value="100">100</option>
            <option :value="200">200</option>
          </select>
        </label>
      </div>
      <div class="pagination-actions">
        <button class="btn btn-ghost btn-sm" :disabled="page <= 1" @click="changePage(-1)">{{ al('pagination.previous') }}</button>
        <button class="btn btn-ghost btn-sm" :disabled="page >= totalPages" @click="changePage(1)">{{ al('pagination.next') }}</button>
      </div>
    </div>

    <div class="card table-card">
      <div class="table-wrap">
        <table class="data-table audit-table">
          <thead>
            <tr>
              <th class="col-time">{{ al('table.headers.time') }}</th>
              <th class="col-actor">{{ al('table.headers.actor') }}</th>
              <th class="col-action">{{ al('table.headers.action') }}</th>
              <th class="col-target">{{ al('table.headers.target') }}</th>
              <th class="col-details">{{ al('table.headers.details') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="loading">
              <td colspan="5" class="state-cell">{{ al('page.loading') }}</td>
            </tr>
            <tr v-else-if="!entries.length">
              <td colspan="5" class="state-cell">
                <p>{{ al('page.emptyTitle') }}</p>
                <p class="text-muted">{{ al('page.emptyHint') }}</p>
              </td>
            </tr>
            <tr
              v-for="e in entries"
              v-else
              :key="e.id"
              class="audit-row"
              tabindex="0"
              :aria-label="`${e.actor} ${e.action}`"
              @click="openDetail(e)"
              @keyup.enter="openDetail(e)"
            >
              <td class="col-time" :title="fmtTs(e.ts)">
                <div class="cell-line1">{{ fmtDate(e.ts) }}</div>
                <div class="cell-line2">{{ fmtTime(e.ts) }}</div>
              </td>
              <td class="col-actor">
                <span class="actor-name">{{ e.actor || al('pagination.dash') }}</span>
              </td>
              <td class="col-action">
                <span class="badge" :class="actionBadgeClass(e.action)" :title="e.action">
                  {{ actionLabel(e.action) }}
                </span>
              </td>
              <td class="col-target">
                <template v-if="e.target_type">
                  <span class="target-type">{{ e.target_type }}</span>
                  <span class="target-id">#{{ e.target_id ?? '?' }}</span>
                </template>
                <span v-else class="text-muted">{{ al('pagination.dash') }}</span>
              </td>
              <td class="col-details">
                <code class="detail-preview" :title="detailPreview(e)">{{ detailPreview(e) }}</code>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <div v-if="!loading && total > 0" class="pagination-bar">
      <div class="pagination-meta">
        <span>{{ al('pagination.total', { n: total }) }}</span>
        <span>{{ al('pagination.pageOf', { page: page, total: totalPages }) }}</span>
        <label class="page-size-label">
          <span class="text-muted">{{ al('pagination.perPage') }}</span>
          <select v-model.number="size" class="page-size-select" @change="resetPageAndLoad">
            <option :value="25">25</option>
            <option :value="50">50</option>
            <option :value="100">100</option>
            <option :value="200">200</option>
          </select>
        </label>
      </div>
      <div class="pagination-actions">
        <button class="btn btn-ghost btn-sm" :disabled="page <= 1" @click="changePage(-1)">{{ al('pagination.previous') }}</button>
        <button class="btn btn-ghost btn-sm" :disabled="page >= totalPages" @click="changePage(1)">{{ al('pagination.next') }}</button>
      </div>
    </div>

    <div v-if="detailVisible && detailEntry" class="drawer-backdrop" @click="closeDetail">
      <div class="drawer-panel card drawer-panel-wide" role="dialog" aria-labelledby="audit-detail-title" @click.stop>
        <div class="drawer-header">
          <h3 id="audit-detail-title">{{ al('detail.titleWithId', { id: detailEntry.id }) }}</h3>
          <button class="btn btn-sm btn-ghost" @click="closeDetail">{{ al('detail.close') }}</button>
        </div>

        <div class="drawer-section detail-meta">
          <span><strong>{{ al('detail.metaTime') }}</strong> {{ fmtTs(detailEntry.ts) }}</span>
          <span><strong>{{ al('detail.metaActor') }}</strong> {{ detailEntry.actor || al('pagination.dash') }}</span>
          <span>
            <strong>{{ al('detail.metaAction') }}</strong>
            <span class="badge" :class="actionBadgeClass(detailEntry.action)">{{ detailEntry.action }}</span>
          </span>
          <span v-if="detailEntry.target_type">
            <strong>{{ al('detail.metaTarget') }}</strong> {{ detailEntry.target_type }} #{{ detailEntry.target_id ?? '?' }}
          </span>
        </div>

        <div v-if="detailEntry.before_json" class="drawer-section">
          <div class="drawer-section-title">{{ al('detail.beforeTitle') }}</div>
          <pre class="json-block">{{ fmtJson(detailEntry.before_json) }}</pre>
        </div>

        <div v-if="detailEntry.after_json" class="drawer-section">
          <div class="drawer-section-title">{{ al('detail.afterTitle') }}</div>
          <pre class="json-block">{{ fmtJson(detailEntry.after_json) }}</pre>
        </div>

        <div v-if="!detailEntry.before_json && !detailEntry.after_json" class="drawer-section">
          <p class="text-muted">{{ al('detail.noExtra') }}</p>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.page-header h2 {
  margin: 0;
  font-size: 18px;
  font-weight: 600;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.page-desc {
  margin: -12px 0 16px;
  font-size: 12px;
  color: var(--muted);
}

.count-chip {
  display: inline-flex;
  align-items: center;
  padding: 4px 10px;
  border-radius: 12px;
  font-size: 12px;
  font-weight: 500;
  background: rgba(99, 102, 241, 0.12);
  color: var(--accent-h);
}

.compact-filter-bar .cf-field--actor,
.compact-filter-bar .cf-field--action {
  flex: 1 1 160px;
  min-width: 140px;
  max-width: 220px;
}

.compact-filter-bar .cf-field--time {
  flex: 0 1 200px;
  min-width: 168px;
}

.table-card {
  padding: 0;
  overflow: hidden;
}

.table-wrap {
  overflow-x: auto;
}

.audit-table {
  width: 100%;
  font-size: 12px;
}

.audit-table th,
.audit-table td {
  padding: 8px 12px;
  vertical-align: top;
}

.col-time {
  width: 5rem;
  white-space: nowrap;
}

.col-actor {
  min-width: 6rem;
  max-width: 10rem;
}

.col-action {
  min-width: 7rem;
  max-width: 11rem;
}

.col-target {
  min-width: 6rem;
  max-width: 9rem;
}

.col-details {
  min-width: 12rem;
}

.cell-line1 {
  font-size: 12px;
  line-height: 1.35;
}

.cell-line2 {
  color: var(--muted);
  font-size: 10px;
  line-height: 1.35;
  margin-top: 2px;
  font-variant-numeric: tabular-nums;
}

.actor-name {
  font-weight: 600;
  word-break: break-all;
}

.target-type {
  font-size: 12px;
}

.target-id {
  margin-left: 4px;
  font-family: ui-monospace, monospace;
  font-size: 11px;
  color: var(--muted);
}

.detail-preview {
  display: block;
  font-family: ui-monospace, monospace;
  font-size: 11px;
  color: var(--muted);
  word-break: break-all;
  white-space: pre-wrap;
  line-height: 1.4;
  background: transparent;
  padding: 0;
}

.audit-row {
  cursor: pointer;
}

.audit-row:hover td,
.audit-row:focus-visible td {
  background: color-mix(in srgb, var(--accent) 8%, transparent);
}

.audit-row:focus-visible {
  outline: none;
}

.state-cell {
  text-align: center;
  padding: 36px 16px !important;
  color: var(--muted);
}

.state-cell p {
  margin: 0 0 4px;
}

.text-muted {
  color: var(--muted);
  font-size: 11px;
}

.pagination-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-top: 12px;
  flex-wrap: wrap;
}

.pagination-meta {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  color: var(--muted);
  flex-wrap: wrap;
}

.page-size-label {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}

.page-size-select {
  width: auto;
  padding: 2px 6px;
  font-size: 12px;
}

.pagination-actions {
  display: flex;
  gap: 8px;
}

.detail-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 12px 20px;
  font-size: 12px;
}

.json-block {
  margin: 0;
  padding: 12px;
  border-radius: var(--radius);
  border: 1px solid var(--border);
  background: var(--bg);
  font-family: ui-monospace, monospace;
  font-size: 11px;
  line-height: 1.5;
  white-space: pre-wrap;
  word-break: break-all;
  max-height: 320px;
  overflow: auto;
}

@media (max-width: 720px) {
  .compact-filter-bar .cf-field--actor,
  .compact-filter-bar .cf-field--action,
  .compact-filter-bar .cf-field--time {
    flex: 1 1 100%;
    max-width: none;
  }

  .pagination-bar {
    flex-direction: column;
    align-items: stretch;
  }

  .pagination-actions {
    justify-content: flex-end;
  }
}

@media (prefers-reduced-motion: reduce) {
  .audit-row:hover td,
  .audit-row:focus-visible td {
    transition: none;
  }
}
</style>
