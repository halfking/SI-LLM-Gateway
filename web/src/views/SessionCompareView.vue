<template>
  <div class="page-layout">
    <div class="page-header">
      <div>
        <h2>{{ tc('title') }}</h2>
        <p class="text-muted" v-if="sessionId">{{ tc('subtitleWithId', { id: sessionId, model: data?.model_used || '' }) }}</p>
        <p class="text-muted" v-else>{{ tc('subtitleEmpty') }}</p>
      </div>
      <div class="header-actions">
        <input
          v-model="sessionIdInput"
          class="cf-input"
          :placeholder="tc('inputPlaceholder')"
          @keyup.enter="loadByInput"
        />
        <button class="btn btn-primary" @click="loadByInput">{{ tc('view') }}</button>
      </div>
    </div>

    <!-- Context Usage Bar -->
    <div class="card" v-if="data" style="margin-bottom: 12px;">
      <div style="display: flex; justify-content: space-between; font-size: 12px; color: var(--muted); margin-bottom: 6px;">
        <span>{{ tc('contextUsage') }}</span>
        <span>{{ tc('contextUsageValue', { pct: Math.round(data.context_usage), tokens: (data.context_window || 128000).toLocaleString() }) }}</span>
      </div>
      <div style="height: 8px; background: var(--border); border-radius: 4px; overflow: hidden;">
        <div :style="{ width: Math.min(data.context_usage, 100) + '%', height: '100%', background: data.context_usage >= 85 ? 'var(--danger)' : data.context_usage >= 70 ? 'var(--warning)' : 'var(--accent)', borderRadius: '4px', transition: 'width 0.3s' }"></div>
      </div>
      <div v-if="data.context_usage >= 80" class="alert alert-warning" style="margin-top: 8px; font-size: 12px;">
        {{ tc('handoffWarn') }}
      </div>
    </div>

    <!-- Stats Bar -->
    <div class="card" v-if="data" style="margin-bottom: 12px; display: flex; gap: 32px; flex-wrap: wrap;">
      <div><div class="cell-line2">{{ tc('stats.originalTokens') }}</div><div class="cell-line1">{{ data.stats.original_tokens.toLocaleString() }}</div></div>
      <div><div class="cell-line2">{{ tc('stats.compressedTokens') }}</div><div class="cell-line1">{{ data.stats.compressed_tokens.toLocaleString() }}</div></div>
      <div v-if="data.is_compressed"><div class="cell-line2">{{ tc('stats.saved') }}</div><div class="cell-line1" style="color: var(--success);">{{ tc('stats.savedValue', { tokens: data.stats.saved_tokens.toLocaleString(), pct: Math.round(data.stats.saved_percent) }) }}</div></div>
      <div><div class="cell-line2">{{ tc('stats.msgCount') }}</div><div class="cell-line1">{{ data.msg_count }}</div></div>
      <div><div class="cell-line2">{{ tc('stats.strategy') }}</div><div class="cell-line1"><span class="badge badge-blue">{{ strategyLabel }}</span></div></div>
      <div><div class="cell-line2">{{ tc('stats.cache') }}</div><div class="cell-line1">{{ cacheLabel }}</div></div>
    </div>

    <!-- Loading & Error -->
    <div v-if="loading" class="empty" style="padding: 60px;">{{ tc('panels.empty') }}</div>
    <div v-if="error" class="alert alert-danger" style="margin-bottom: 12px;">{{ error }}</div>
    <div v-if="!sessionId && !loading" class="empty" style="padding: 60px;">{{ tc('panels.empty') }}</div>

    <!-- Four Panel Comparison -->
    <div class="four-panel" v-if="data">
      <!-- Panel 1: Original -->
      <div class="card" style="display: flex; flex-direction: column; min-width: 0; padding: 0; overflow: hidden;">
        <div class="card-header" style="flex-shrink: 0;">
          <span style="font-weight: 600;">{{ tc('panels.original') }}</span>
          <span class="text-muted" style="font-size: 12px;">{{ data.original_msgs.length }} {{ tc('panels.original') }}</span>
        </div>
        <div class="msg-scroll" ref="p1" @scroll="syncScroll(1)">
          <div v-for="msg in data.original_msgs" :key="'o'+msg.index" :class="['msg-row', msg.role]">
            <div class="role-tag">{{ roleLabel(msg.role) }}</div>
            <div class="msg-text">{{ msg.content || tc('emptyContent') }}</div>
            <div v-if="msg.tool_calls" class="tool-preview">{{ msg.tool_calls }}</div>
            <div class="text-muted" style="text-align:right;font-size:10px;">{{ msg.token_count }} tok</div>
          </div>
          <div v-if="!data.original_msgs.length" class="empty">{{ tc('panels.emptyOriginal') }}</div>
        </div>
      </div>

      <!-- Panel 2: Compressed -->
      <div class="card" style="display: flex; flex-direction: column; min-width: 0; padding: 0; overflow: hidden;">
        <div class="card-header" style="flex-shrink: 0;">
          <span style="font-weight: 600;">{{ tc('panels.compressed') }}</span>
          <span class="text-muted" style="font-size: 12px;">{{ data.compressed_msgs.length }}</span>
          <span v-if="data.is_compressed" class="badge badge-blue">{{ strategyLabel }}</span>
          <span v-else class="badge badge-gray">{{ tc('panels.notCompressed') }}</span>
        </div>
        <div class="msg-scroll" ref="p2" @scroll="syncScroll(2)">
          <div v-if="!data.is_compressed" class="empty" style="padding: 24px;">{{ tc('panels.notCompressed') }}</div>
          <div v-for="msg in data.compressed_msgs" :key="'c'+msg.index" :class="['msg-row', msg.role]">
            <div class="role-tag">{{ roleLabel(msg.role) }}</div>
            <div class="msg-text">{{ msg.content || tc('emptyContent') }}</div>
            <div v-if="msg.tool_calls" class="tool-preview">{{ msg.tool_calls }}</div>
            <div class="text-muted" style="text-align:right;font-size:10px;">{{ msg.token_count }} tok</div>
          </div>
          <div v-if="!data.compressed_msgs.length && data.is_compressed" class="empty">{{ tc('panels.emptyCompressed') }}</div>
        </div>
      </div>

      <!-- Panel 3: Response -->
      <div class="card" style="display: flex; flex-direction: column; min-width: 0; padding: 0; overflow: hidden;">
        <div class="card-header" style="flex-shrink: 0;">
          <span style="font-weight: 600;">{{ tc('panels.response') }}</span>
          <span class="text-muted" style="font-size: 12px;">{{ data.response_msgs.length }}</span>
        </div>
        <div class="msg-scroll" ref="p3" @scroll="syncScroll(3)">
          <div v-for="msg in data.response_msgs" :key="'r'+msg.index" :class="['msg-row', msg.role]">
            <div class="role-tag">{{ roleLabel(msg.role) }}</div>
            <div class="msg-text">{{ msg.content || tc('emptyContent') }}</div>
            <div class="text-muted" style="text-align:right;font-size:10px;">{{ msg.token_count }} tok</div>
          </div>
          <div v-if="!data.response_msgs.length" class="empty">{{ tc('panels.emptyResponse') }}</div>
        </div>
      </div>

      <!-- Panel 4: Cache & Handoff -->
      <div class="card" style="display: flex; flex-direction: column; min-width: 0; padding: 0; overflow: hidden;">
        <div class="card-header" style="flex-shrink: 0;">
          <span style="font-weight: 600;">{{ tc('panels.cacheSavings') }}</span>
        </div>
        <div class="msg-scroll" style="padding: 12px;">
          <!-- Cache -->
          <div class="card-title" style="margin-bottom: 8px;">{{ tc('cache.title') }}</div>
          <table class="data-table" style="margin-bottom: 16px;">
            <tr><td>{{ tc('cache.l1') }}</td><td style="text-align:right"><span :class="data.cache_info.l1_hit ? 'badge badge-green' : 'badge badge-red'">{{ data.cache_info.l1_hit ? tc('cache.hit') : tc('cache.miss') }}</span></td></tr>
            <tr><td>{{ tc('cache.l2') }}</td><td style="text-align:right"><span :class="data.cache_info.l2_hit ? 'badge badge-green' : 'badge badge-red'">{{ data.cache_info.l2_hit ? tc('cache.hit') : tc('cache.miss') }}</span></td></tr>
            <tr><td>{{ tc('cache.l3') }}</td><td style="text-align:right"><span :class="data.cache_info.l3_fallback ? 'badge badge-yellow' : 'badge badge-gray'">{{ data.cache_info.l3_fallback ? tc('cache.fallback') : tc('cache.noFallback') }}</span></td></tr>
          </table>

          <!-- Token Savings -->
          <div class="card-title" style="margin-bottom: 8px;">{{ tc('cache.tokenTitle') }}</div>
          <table class="data-table" style="margin-bottom: 16px;">
            <tr><td>{{ tc('cache.original') }}</td><td style="text-align:right;font-family:monospace">{{ data.stats.original_tokens.toLocaleString() }}</td></tr>
            <tr><td>{{ tc('cache.compressed') }}</td><td style="text-align:right;font-family:monospace">{{ data.stats.compressed_tokens.toLocaleString() }}</td></tr>
            <tr v-if="data.is_compressed"><td style="color:var(--success)">{{ tc('cache.saved') }}</td><td style="text-align:right;font-family:monospace;color:var(--success)">{{ tc('stats.savedValue', { tokens: data.stats.saved_tokens.toLocaleString(), pct: Math.round(data.stats.saved_percent) }) }}</td></tr>
            <tr><td>{{ tc('cache.strategy') }}</td><td style="text-align:right"><span class="badge badge-blue">{{ strategyLabel }}</span></td></tr>
          </table>

          <!-- Handoff -->
          <div v-if="data.context_usage >= 80" style="border-top: 1px solid var(--border); padding-top: 12px;">
            <div class="card-title" style="margin-bottom: 8px; color: var(--warning);">{{ tc('handoff.warnTitle') }}</div>
            <p style="font-size:12px;color:var(--muted);margin-bottom:8px;">
              {{ tc('handoff.warnBody', { pct: Math.round(data.context_usage) }) }}
            </p>
            <div style="display:flex;gap:8px;flex-wrap:wrap;">
              <button class="btn btn-warning btn-sm" @click="execHandoff" :disabled="handoffLoading">
                {{ handoffLoading ? tc('handoff.running') : tc('handoff.run') }}
              </button>
              <button class="btn btn-sm" @click="showHint = !showHint">{{ tc('handoff.showHint') }}</button>
              <button class="btn btn-sm" @click="copyCompareUrl">{{ tc('handoff.copyLink') }}</button>
            </div>
            <div v-if="showHint" class="card" style="margin-top:8px;padding:8px;font-size:12px;">
              <p style="margin-bottom:4px;">{{ tc('handoff.hintLabel') }}</p>
              <pre style="background:var(--bg);padding:8px;border-radius:4px;white-space:pre-wrap;">{{ newSessionHint }}</pre>
              <button class="btn btn-sm" @click="copyHint">{{ tc('handoff.copy') }}</button>
            </div>
            <div v-if="handoffResult" class="card" style="margin-top:8px;padding:8px;">
              <div class="card-title" style="margin-bottom:4px;">{{ tc('handoff.resultTitle') }}</div>
              <pre style="font-size:11px;white-space:pre-wrap;">{{ handoffResult.handoff_summary }}</pre>
              <div v-if="handoffResult.new_session_id" style="margin-top:4px;">
                {{ tc('handoff.newSession') }} <code style="background:var(--bg);padding:1px 4px;border-radius:3px;">{{ handoffResult.new_session_id }}</code>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { getSessionCompare, executeHandoff as callHandoff } from '../api'
import type { SessionCompareData, HandoffResponse } from '../api'

const { t } = useI18n()
const tc = (k: string, params?: Record<string, unknown>): string =>
  t(`sessions.compare.${k}` as never, params as never)

const route = useRoute()
const sessionId = ref('')
const sessionIdInput = ref('')
const data = ref<SessionCompareData | null>(null)
const loading = ref(false)
const error = ref('')
const showHint = ref(false)
const handoffLoading = ref(false)
const handoffResult = ref<HandoffResponse | null>(null)

const p1 = ref<HTMLElement | null>(null)
const p2 = ref<HTMLElement | null>(null)
const p3 = ref<HTMLElement | null>(null)

const strategyLabel = computed(() => {
  const s = data.value?.stats?.compression_strategy || ''
  const translated = s ? tc(`strategies.${s}` as any) : ''
  if (translated && translated !== `sessions.compare.strategies.${s}`) return translated
  return s || '—'
})
const cacheLabel = computed(() => {
  const c = data.value?.cache_info
  if (!c) return '—'
  const parts: string[] = []
  if (c.l1_hit) parts.push('L1✓')
  if (c.l2_hit) parts.push('L2✓')
  if (c.l3_fallback) parts.push('DB✓')
  return parts.join(' ') || tc('cache.notCached')
})

const newSessionHint = computed(() => tc('sessionHint'))

let syncing = false
function syncScroll(src: number) {
  if (syncing) return
  syncing = true
  const els = [p1.value, p2.value, p3.value]
  const srcEl = els[src - 1]
  if (!srcEl) { syncing = false; return }
  const ratio = srcEl.scrollTop / (srcEl.scrollHeight - srcEl.clientHeight) || 0
  for (let i = 0; i < els.length; i++) {
    if (i !== src - 1 && els[i]) {
      const el = els[i]!
      el.scrollTop = ratio * (el.scrollHeight - el.clientHeight)
    }
  }
  requestAnimationFrame(() => { syncing = false })
}

function roleLabel(r: string) {
  const translated = tc(`roles.${r}` as any)
  if (translated && translated !== `sessions.compare.roles.${r}`) return translated
  return r
}

async function loadData() {
  if (!sessionId.value) return
  loading.value = true
  error.value = ''
  handoffResult.value = null
  try {
    data.value = await getSessionCompare(sessionId.value)
  } catch (e: any) {
    error.value = e?.message || tc('loadFailed')
  } finally {
    loading.value = false
  }
}

function loadByInput() {
  const v = sessionIdInput.value.trim()
  if (v) {
    sessionId.value = v
    loadData()
  }
}

async function execHandoff() {
  if (!sessionId.value) return
  handoffLoading.value = true
  try {
    handoffResult.value = await callHandoff({ session_id: sessionId.value, create_new: true })
  } catch (e: any) {
    error.value = tc('handoff.failed', { msg: e?.message || '' })
  } finally {
    handoffLoading.value = false
  }
}

function copyHint() { navigator.clipboard.writeText(newSessionHint.value) }
function copyCompareUrl() {
  const url = `${location.origin}${location.pathname}?session_id=${sessionId.value}`
  navigator.clipboard.writeText(url)
}

onMounted(() => {
  if (route.query.session_id) {
    sessionId.value = route.query.session_id as string
    sessionIdInput.value = sessionId.value
    loadData()
  }
})
</script>

<style scoped>
.page-layout { padding: 16px; max-width: 1600px; margin: 0 auto; }
.header-actions { display: flex; gap: 8px; align-items: center; }
.cf-input { background: var(--card); border: 1px solid var(--border); border-radius: var(--radius); padding: 6px 12px; color: var(--text); font-size: 13px; width: 280px; }

.four-panel { display: grid; grid-template-columns: 1fr 1fr 1fr 320px; gap: 12px; flex: 1; min-height: 0; min-height: 60vh; }
.card-header { display: flex; align-items: center; gap: 8px; padding: 10px 12px; border-bottom: 1px solid var(--border); background: var(--bg-subtle); }
.card-title { font-size: 12px; font-weight: 600; color: var(--muted); text-transform: uppercase; letter-spacing: 0.05em; }

.msg-scroll { flex: 1; overflow-y: auto; padding: 8px; }
.msg-scroll::-webkit-scrollbar { width: 6px; }
.msg-scroll::-webkit-scrollbar-track { background: transparent; }
.msg-scroll::-webkit-scrollbar-thumb { background: var(--border); border-radius: 3px; }

.msg-row { padding: 8px; margin-bottom: 6px; border-radius: 6px; font-size: 12px; line-height: 1.5; }
.msg-row.user { background: color-mix(in srgb, var(--accent) 10%, var(--card)); border-left: 3px solid var(--accent); }
.msg-row.assistant { background: color-mix(in srgb, var(--success) 8%, var(--card)); border-left: 3px solid var(--success); }
.msg-row.system { background: color-mix(in srgb, #8b5cf6 8%, var(--card)); border-left: 3px solid #8b5cf6; }
.msg-row.tool { background: color-mix(in srgb, var(--warning) 8%, var(--card)); border-left: 3px solid var(--warning); }
.role-tag { font-size: 10px; color: var(--muted); margin-bottom: 4px; text-transform: uppercase; }
.msg-text { white-space: pre-wrap; word-break: break-word; }
.tool-preview { margin-top: 4px; padding: 4px; background: var(--bg); border-radius: 4px; font-family: monospace; font-size: 10px; color: var(--warning); }

.text-muted { color: var(--muted); }
.badge { font-size: 10px; padding: 1px 6px; border-radius: 4px; }
.badge-blue { background: color-mix(in srgb, var(--accent) 20%, transparent); color: var(--accent-h); }
.badge-green { background: color-mix(in srgb, var(--success) 20%, transparent); color: var(--success); }
.badge-red { background: color-mix(in srgb, var(--danger) 20%, transparent); color: var(--danger); }
.badge-yellow { background: color-mix(in srgb, var(--warning) 20%, transparent); color: var(--warning); }
.badge-gray { background: var(--border); color: var(--muted); }

@media (max-width: 1100px) {
  .four-panel { grid-template-columns: 1fr 1fr; }
}
@media (max-width: 700px) {
  .four-panel { grid-template-columns: 1fr; }
}
</style>