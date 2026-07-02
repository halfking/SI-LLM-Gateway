<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import {
  listSettings,
  getSetting,
  updateSetting,
  rollbackSetting,
  type SettingItem,
  type SettingSpec,
} from '../api'

const { t } = useI18n()
// Short alias for the settings locale namespace.
const s = (k: string, params?: Record<string, unknown>): string =>
  t(`settings.${k}` as never, params as never)

const items = ref<SettingItem[]>([])
const loading = ref(false)
const saving = ref(false)
const error = ref<string | null>(null)
const selectedKey = ref<string>('')
const selected = ref<SettingSpec | null>(null)
const currentValue = ref<any>(null)
const currentSource = ref<string>('')
const editBuffer = ref<string>('') // JSON text editor
const filterCategory = ref<string>('')

const categories = [
  { key: '',                   labelKey: 'category.all',         icon: '📋' },
  { key: 'compression',        labelKey: 'category.compression',  icon: '🗜'  },
  { key: 'rate_limit',         labelKey: 'category.rateLimit',    icon: '🚦'  },
  { key: 'timeout',            labelKey: 'category.timeout',      icon: '⏱'  },
  { key: 'routing',            labelKey: 'category.routing',      icon: '🔀'  },
  { key: 'session',            labelKey: 'category.session',      icon: '💬'  },
  { key: 'security',           labelKey: 'category.security',     icon: '🔐'  },
  { key: 'circuit_breaker',    labelKey: 'category.circuitBreaker', icon: '⚡'  },
  { key: 'general',            labelKey: 'category.general',      icon: '⚙️' },
]

function dangerLabel(level: number): string {
  const map: Record<number, string> = {
    1: s('dangerLevel.note'),
    2: s('dangerLevel.warn'),
    3: s('dangerLevel.danger'),
  }
  return map[level] || ''
}

async function loadList() {
  loading.value = true
  error.value = null
  try {
    const r = await listSettings({ category: filterCategory.value || undefined })
    items.value = r.items
  } catch (e: any) {
    error.value = e.message || s('detail.errors.loadListFailed')
  } finally {
    loading.value = false
  }
}

async function selectKey(key: string) {
  selectedKey.value = key
  try {
    const resp = await getSetting(key)
    selected.value = resp.spec
    currentValue.value = resp.value
    currentSource.value = resp.source

    // Smart initialization based on type
    if (resp.spec.type === 'bool') {
      editBuffer.value = String(resp.value ?? resp.spec.default)
    } else if (resp.spec.type === 'int' || resp.spec.type === 'float' || resp.spec.type === 'string') {
      editBuffer.value = String(resp.value ?? resp.spec.default)
    } else {
      editBuffer.value = JSON.stringify(resp.value ?? resp.spec.default, null, 2)
    }
  } catch (e: any) {
    error.value = e.message || s('detail.errors.loadDetailFailed')
  }
}

async function save() {
  if (!selectedKey.value || !selected.value) return
  saving.value = true
  error.value = null
  try {
    let parsed: any
    // Smart parsing based on type
    if (selected.value.type === 'bool') {
      parsed = editBuffer.value === 'true'
    } else if (selected.value.type === 'int' || selected.value.type === 'float') {
      parsed = Number(editBuffer.value)
      if (isNaN(parsed)) {
        throw new Error(s('detail.errors.invalidNumber'))
      }
    } else if (selected.value.type === 'string') {
      parsed = String(editBuffer.value)
    } else {
      // Fallback to JSON parsing
      parsed = JSON.parse(editBuffer.value)
    }

    await updateSetting(selectedKey.value, { value: parsed })
    await loadList()
    await selectKey(selectedKey.value)
  } catch (e: any) {
    error.value = e.message || s('detail.errors.saveFailed')
  } finally {
    saving.value = false
  }
}

// Helper to get friendly label for enum values
function getEnumLabel(key: string, value: any): string {
  const labels: Record<string, Record<string, string>> = {
    'compression.mode': {
      '0': s('compression.enumLabels.off'),
      '1': s('compression.enumLabels.auto'),
      '2': s('compression.enumLabels.on4xx'),
    },
    'compression.strategy': {
      'naive': s('compression.strategyEnum.naive'),
      'smart': s('compression.strategyEnum.smart'),
      'adaptive': s('compression.strategyEnum.adaptive'),
    },
  }
  return labels[key]?.[String(value)] || String(value)
}

// Get description for enum options
function getEnumDescription(key: string, value: string): string {
  const descriptions: Record<string, Record<string, string>> = {
    'compression.mode': {
      '0': s('compression.enumDescriptions.off'),
      '1': s('compression.enumDescriptions.auto'),
      '2': s('compression.enumDescriptions.on4xx'),
    },
  }
  return descriptions[key]?.[value] || ''
}

// Get detailed documentation for settings
function getSettingDocs(key: string): { title: string; content: string } | null {
  const docs: Record<string, { titleKey: string; contentKey: string }> = {
    'compression.mode': {
      titleKey: 'docs.compressionModeTitle',
      contentKey: 'docs.compressionModeContent',
    },
    'cache.enabled': {
      titleKey: 'docs.cacheEnabledTitle',
      contentKey: 'docs.cacheEnabledContent',
    },
    'format_conversion.enabled': {
      titleKey: 'docs.formatConversionTitle',
      contentKey: 'docs.formatConversionContent',
    },
    'rate_limit_rpm': {
      titleKey: 'docs.rateLimitRpmTitle',
      contentKey: 'docs.rateLimitRpmContent',
    },
    'rate_limit_concurrent': {
      titleKey: 'docs.rateLimitConcurrentTitle',
      contentKey: 'docs.rateLimitConcurrentContent',
    },
  }
  const e = docs[key]
  if (!e) return null
  return { title: s(e.titleKey), content: s(e.contentKey) }
}

async function rollback() {
  if (!selectedKey.value) return
  if (!confirm(s('detail.errors.confirmRollback', { key: selectedKey.value }))) return
  try {
    await rollbackSetting(selectedKey.value)
    await loadList()
    await selectKey(selectedKey.value)
  } catch (e: any) {
    error.value = e.message || s('detail.errors.rollbackFailed')
  }
}

function switchCategory(key: string) {
  filterCategory.value = key
  loadList()
}

const filteredCount = computed(() => items.value.length)
</script>

<template>
  <div class="settings-view">
    <div v-if="error" class="error-banner">{{ error }}</div>
    <div class="layout">
      <aside class="category-bar">
        <button
          v-for="c in categories" :key="c.key"
          class="cat-btn" :class="{ active: filterCategory === c.key }"
          @click="switchCategory(c.key)"
        >
          <span class="cat-icon">{{ c.icon }}</span>
          <span class="cat-label">{{ s(c.labelKey) }}</span>
        </button>
      </aside>

      <section class="list-pane">
        <div class="list-header">
          <span>{{ s('list.total', { n: filteredCount }) }}</span>
        </div>
        <div v-if="loading" class="loading">{{ s('list.loading') }}</div>
        <div v-else-if="!items.length" class="empty">{{ s('list.empty') }}</div>
        <table v-else class="settings-table">
          <thead>
            <tr>
              <th>{{ s('list.table.setting') }}</th>
              <th>{{ s('list.table.currentValue') }}</th>
              <th>{{ s('list.table.source') }}</th>
              <th>{{ s('list.table.danger') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="it in items" :key="it.key"
              :class="{ active: selectedKey === it.key }"
              @click="selectKey(it.key)"
            >
              <td class="cell-key">
                <code>{{ it.key }}</code>
                <div class="cell-desc">{{ it.description }}</div>
              </td>
              <td class="cell-value">
                <code>{{ JSON.stringify(it.value) }}</code>
              </td>
              <td>
                <span class="src-badge" :class="'src-' + it.source">{{ it.source || '—' }}</span>
              </td>
              <td>{{ dangerLabel(it.danger_level) }}</td>
            </tr>
          </tbody>
        </table>
      </section>

      <aside class="detail-pane" v-if="selected">
        <h3 class="detail-title">
          <code>{{ selectedKey }}</code>
        </h3>
        <p class="detail-desc">{{ selected.description }}</p>

        <!-- Tenant-scoped warning -->
        <div v-if="selected.scope === 'tenant'" class="tenant-warning">
          <div class="warning-icon">⚠️</div>
          <div class="warning-content">
            <strong>{{ s('detail.tenantWarningTitle') }}</strong>
            <p v-html="s('detail.tenantWarningBody')"></p>
          </div>
        </div>

        <!-- Detailed documentation -->
        <div v-if="getSettingDocs(selectedKey)" class="detail-docs">
          <div class="docs-title" v-html="getSettingDocs(selectedKey)!.title"></div>
          <div class="docs-content" v-html="getSettingDocs(selectedKey)!.content"></div>
        </div>

        <dl class="meta">
          <dt>{{ s('detail.type') }}</dt><dd>{{ selected.type }}</dd>
          <dt>{{ s('detail.currentValue') }}</dt>
          <dd>
            <code class="current-value">{{ JSON.stringify(currentValue) }}</code>
            <span class="src-badge" :class="'src-' + currentSource">{{ currentSource }}</span>
          </dd>
          <dt>{{ s('detail.defaultValue') }}</dt><dd><code>{{ JSON.stringify(selected.default) }}</code></dd>
          <dt v-if="selected.options">{{ s('detail.options') }}</dt>
          <dd v-if="selected.options">
            <code v-for="o in selected.options" :key="o" class="opt-chip">{{ o }}</code>
          </dd>
          <dt>{{ s('detail.dangerLevel') }}</dt><dd>{{ dangerLabel(selected.danger_level) }}</dd>
          <dt>{{ s('detail.hotReload') }}</dt>
          <dd>
            <span v-if="selected.hot_reload" class="src-badge src-db">{{ s('detail.hotReloadYes') }}</span>
            <span v-else class="src-badge src-default">{{ s('detail.hotReloadNo') }}</span>
          </dd>
          <dt v-if="selected.observability">{{ s('detail.observability') }}</dt>
          <dd v-if="selected.observability">
            <a :href="selected.observability" target="_blank" rel="noopener">
              <code>{{ selected.observability }}</code>
            </a>
          </dd>
        </dl>

        <div v-if="selected.scope !== 'tenant'" class="editor">
          <label class="editor-label">{{ s('editor.newValueLabel') }}</label>

          <!-- Boolean type: Switch -->
          <div v-if="selected.type === 'bool'" class="editor-boolean">
            <label class="switch-label">
              <input
                type="checkbox"
                v-model="editBuffer"
                :true-value="'true'"
                :false-value="'false'"
                class="switch-input"
              />
              <span class="switch-track"></span>
              <span class="switch-text">{{ editBuffer === 'true' ? s('editor.enabledText') : s('editor.disabledText') }}</span>
            </label>
          </div>

          <!-- Enum type with known options: Select -->
          <div v-else-if="selectedKey === 'compression.mode'" class="editor-select">
            <select v-model="editBuffer" class="select-input">
              <option value="0">{{ s('compression.selectLabels.off') }}</option>
              <option value="1">{{ s('compression.selectLabels.auto') }}</option>
              <option value="2">{{ s('compression.selectLabels.on4xx') }}</option>
            </select>
            <div class="select-hint">
              <div v-if="editBuffer === '0'" class="hint-item">{{ s('compression.hint.off') }}</div>
              <div v-else-if="editBuffer === '1'" class="hint-item">{{ s('compression.hint.auto') }}</div>
              <div v-else-if="editBuffer === '2'" class="hint-item">{{ s('compression.hint.on4xx') }}</div>
            </div>
          </div>

          <!-- Number type: Number input -->
          <div v-else-if="selected.type === 'int' || selected.type === 'float'" class="editor-number">
            <input
              type="number"
              v-model="editBuffer"
              class="number-input"
              :step="selected.type === 'float' ? '0.01' : '1'"
            />
          </div>

          <!-- String type: Text input -->
          <div v-else-if="selected.type === 'string'" class="editor-string">
            <input
              type="text"
              v-model="editBuffer"
              class="text-input"
              :placeholder="s('editor.stringPlaceholder')"
            />
          </div>

          <!-- Fallback: JSON textarea -->
          <div v-else class="editor-json">
            <textarea
              v-model="editBuffer"
              rows="4"
              class="editor-textarea"
              spellcheck="false"
              :placeholder="s('editor.jsonPlaceholder')"
            />
            <div class="json-hint">{{ s('editor.jsonHint') }}</div>
          </div>

          <div class="editor-actions">
            <button class="btn btn-primary" :disabled="saving" @click="save">
              {{ saving ? s('editor.saving') : s('editor.save') }}
            </button>
            <button class="btn btn-ghost" @click="rollback">{{ s('editor.rollback') }}</button>
          </div>
        </div>
      </aside>

      <div v-else class="detail-pane empty-detail">
        <p>{{ s('detail.selectPrompt') }}</p>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* === Dark theme — consistent with rest of app === */
.settings-view {
  padding: 16px;
  max-width: 1400px;
  margin: 0 auto;
  color: var(--text-primary, #e6edf3);
  font-size: 13px;
}
.error-banner {
  padding: 10px;
  background: rgba(248, 113, 113, 0.1);
  border: 1px solid rgba(248, 113, 113, 0.3);
  color: #f87171;
  border-radius: 6px;
  margin-bottom: 12px;
}

.layout {
  display: grid;
  grid-template-columns: 160px 1fr 360px;
  gap: 12px;
  min-height: 70vh;
}

/* === Category bar === */
.category-bar {
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.cat-btn {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  border: 1px solid transparent;
  background: transparent;
  color: var(--text-secondary, #8b949e);
  border-radius: 6px;
  font-size: 13px;
  cursor: pointer;
  text-align: left;
}
.cat-btn:hover {
  background: var(--bg-hover, #21262d);
}
.cat-btn.active {
  background: var(--bg-card, #161b22);
  color: var(--text-primary, #e6edf3);
  border-color: var(--accent, #6366f1);
}
.cat-icon { font-size: 16px; }

/* === List pane === */
.list-pane {
  background: var(--bg-card, #161b22);
  border: 1px solid var(--border, #30363d);
  border-radius: 8px;
  overflow: auto;
}
.list-header {
  padding: 8px 12px;
  border-bottom: 1px solid var(--border, #30363d);
  color: var(--text-secondary, #8b949e);
  font-size: 12px;
}
.loading, .empty {
  text-align: center;
  padding: 32px;
  color: var(--text-secondary, #8b949e);
}

.settings-table {
  width: 100%;
  border-collapse: collapse;
}
.settings-table th,
.settings-table td {
  padding: 10px 12px;
  text-align: left;
  border-bottom: 1px solid var(--border, #30363d);
  vertical-align: top;
}
.settings-table th {
  color: var(--text-secondary, #8b949e);
  font-weight: 500;
  background: var(--bg, #0f1117);
  font-size: 12px;
}
.settings-table tr {
  cursor: pointer;
}
.settings-table tr.active td {
  background: rgba(99, 102, 241, 0.1);
}
.settings-table tr:hover:not(.active) td {
  background: var(--bg-hover, #21262d);
}
.cell-key code {
  font-family: ui-monospace, SFMono-Regular, monospace;
  font-size: 12px;
  color: var(--accent-h, #818cf8);
}
.cell-desc {
  margin-top: 4px;
  font-size: 11px;
  color: var(--text-secondary, #8b949e);
}
.cell-value code {
  padding: 1px 6px;
  background: var(--bg, #0f1117);
  border-radius: 3px;
  font-size: 11px;
  font-family: ui-monospace, SFMono-Regular, monospace;
}

/* === Source badges === */
.src-badge {
  display: inline-block;
  padding: 1px 6px;
  border-radius: 4px;
  font-size: 10px;
  font-weight: 500;
  margin-left: 4px;
}
.src-badge.src-db {
  background: rgba(52, 211, 153, 0.15);
  color: #34d399;
}
.src-badge.src-env {
  background: rgba(99, 102, 241, 0.15);
  color: #818cf8;
}
.src-badge.src-default {
  background: rgba(139, 148, 158, 0.15);
  color: #8b949e;
}

/* === Detail pane === */
.detail-pane {
  background: var(--bg-card, #161b22);
  border: 1px solid var(--border, #30363d);
  border-radius: 8px;
  padding: 16px;
  overflow: auto;
}
.empty-detail {
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-secondary, #8b949e);
  font-size: 14px;
}
.detail-title {
  margin: 0 0 6px;
  font-size: 14px;
}
.detail-title code {
  font-family: ui-monospace, SFMono-Regular, monospace;
  color: var(--accent-h, #818cf8);
}
.detail-desc {
  font-size: 12px;
  color: var(--text-secondary, #8b949e);
  margin: 0 0 12px;
}
.meta {
  display: grid;
  grid-template-columns: 80px 1fr;
  gap: 6px 12px;
  font-size: 12px;
  margin: 0 0 16px;
}
.meta dt {
  color: var(--text-secondary, #8b949e);
}
.meta dd {
  margin: 0;
  color: var(--text-primary, #e6edf3);
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 4px;
}
.meta code {
  padding: 1px 6px;
  background: var(--bg, #0f1117);
  border-radius: 3px;
  font-size: 11px;
  font-family: ui-monospace, SFMono-Regular, monospace;
}
.meta a {
  color: var(--accent-h, #818cf8);
  text-decoration: none;
}
.meta a:hover {
  text-decoration: underline;
}
.opt-chip {
  background: var(--bg, #0f1117);
  color: var(--text-secondary, #8b949e);
}
.current-value {
  font-weight: 600;
  color: var(--text-primary, #e6edf3);
}

/* === Editor === */
.editor {
  border-top: 1px solid var(--border, #30363d);
  padding-top: 12px;
}
.editor-label {
  display: block;
  font-size: 12px;
  color: var(--text-secondary, #8b949e);
  margin-bottom: 6px;
}
.editor-textarea {
  width: 100%;
  padding: 8px;
  background: var(--bg, #0f1117);
  border: 1px solid var(--border, #30363d);
  border-radius: 6px;
  color: var(--text-primary, #e6edf3);
  font-family: ui-monospace, SFMono-Regular, monospace;
  font-size: 12px;
  resize: vertical;
  margin-bottom: 8px;
}
.editor-textarea:focus {
  outline: none;
  border-color: var(--accent, #6366f1);
}
.editor-actions {
  display: flex;
  gap: 8px;
}

/* === Buttons === */
.btn {
  padding: 6px 14px;
  border-radius: 6px;
  font-size: 13px;
  cursor: pointer;
  border: 1px solid transparent;
}
.btn-primary {
  background: var(--accent, #6366f1);
  color: #fff;
}
.btn-primary:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
.btn-ghost {
  background: transparent;
  color: var(--text-primary, #e6edf3);
  border: 1px solid var(--border, #30363d);
}
.btn-ghost:hover {
  background: var(--bg-hover, #21262d);
}

/* === Smart Editor Styles === */
.editor-boolean {
  padding: 16px 0;
}

.switch-label {
  display: inline-flex;
  align-items: center;
  gap: 12px;
  cursor: pointer;
  user-select: none;
}

.switch-input {
  position: absolute;
  opacity: 0;
  pointer-events: none;
}

.switch-track {
  position: relative;
  width: 44px;
  height: 24px;
  background: var(--border);
  border-radius: 12px;
  transition: background 0.2s;
}

.switch-track::after {
  content: '';
  position: absolute;
  top: 2px;
  left: 2px;
  width: 20px;
  height: 20px;
  background: white;
  border-radius: 50%;
  transition: transform 0.2s;
}

.switch-input:checked + .switch-track {
  background: var(--primary, #3b82f6);
}

.switch-input:checked + .switch-track::after {
  transform: translateX(20px);
}

.switch-text {
  font-size: 14px;
  font-weight: 500;
  color: var(--text);
}

.editor-select, .editor-number, .editor-string, .editor-json {
  margin: 12px 0;
}

.select-input, .number-input, .text-input {
  width: 100%;
  padding: 8px 12px;
  border: 1px solid var(--border);
  border-radius: 6px;
  background: var(--bg-secondary);
  color: var(--text);
  font-size: 14px;
  font-family: inherit;
}

.select-input:focus, .number-input:focus, .text-input:focus {
  outline: none;
  border-color: var(--primary, #3b82f6);
  box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
}

.select-hint {
  margin-top: 8px;
  padding: 8px 12px;
  background: rgba(59, 130, 246, 0.05);
  border-left: 3px solid var(--primary, #3b82f6);
  border-radius: 4px;
}

.hint-item {
  font-size: 13px;
  line-height: 1.5;
  color: var(--muted);
}

.json-hint {
  margin-top: 6px;
  font-size: 12px;
  color: var(--muted);
}

/* === Documentation Section === */
.tenant-warning {
  display: flex;
  gap: 12px;
  margin: 16px 0;
  padding: 16px;
  background: rgba(251, 191, 36, 0.1);
  border: 1px solid rgba(251, 191, 36, 0.3);
  border-left: 4px solid rgb(251, 191, 36);
  border-radius: 8px;
}

.warning-icon {
  font-size: 24px;
  line-height: 1;
}

.warning-content {
  flex: 1;
}

.warning-content strong {
  display: block;
  font-size: 14px;
  font-weight: 600;
  color: var(--text);
  margin-bottom: 6px;
}

.warning-content p {
  font-size: 13px;
  line-height: 1.5;
  color: var(--text);
  margin: 0;
}

.detail-docs {
  margin: 16px 0;
  padding: 16px;
  background: var(--bg-secondary);
  border: 1px solid var(--border);
  border-radius: 8px;
}

.docs-title {
  font-size: 14px;
  font-weight: 600;
  color: var(--text);
  margin-bottom: 12px;
}

.docs-content {
  font-size: 13px;
  line-height: 1.6;
  color: var(--text);
}

.docs-content p {
  margin: 8px 0;
}

.docs-content ul {
  margin: 8px 0;
  padding-left: 20px;
}

.docs-content li {
  margin: 4px 0;
}

.docs-content code {
  padding: 2px 6px;
  background: rgba(99, 102, 241, 0.1);
  border-radius: 3px;
  font-size: 12px;
  font-family: 'Menlo', 'Monaco', 'Courier New', monospace;
}

.docs-note {
  margin-top: 12px;
  padding: 8px 12px;
  background: rgba(59, 130, 246, 0.08);
  border-left: 3px solid var(--primary, #3b82f6);
  border-radius: 4px;
  font-size: 13px;
}

/* === Responsive === */
@media (max-width: 1100px) {
  .layout {
    grid-template-columns: 1fr;
  }
  .category-bar {
    flex-direction: row;
    overflow-x: auto;
  }
}
</style>
