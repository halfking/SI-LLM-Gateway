<script setup lang="ts">
import { ref, onMounted, computed, onBeforeUnmount, watch, Teleport } from 'vue'
import { useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import {
  getRequestLogs,
  getRequestLogDetail,
  getSessionSummary,
  sessionSummaryToMemora,
  getKeys,
  getAttachments,
  type RequestLogRow,
  type RequestLogDetail,
  type ApiKey,
  type RequestLogsResponse,
  type SessionSummaryResponse,
  type SessionSummaryToMemoraResponse,
  type Attachment,
} from '../api'
import ModelPicker from '../components/ModelPicker.vue'
import { isSuperAdmin, isDefaultTenant, getCurrentTenantId } from '../store'
import { useFormat } from '../i18n/useFormat'
import { localeRef } from '../i18n'

const { t } = useI18n()
const { fmtDateTime } = useFormat()

const rows = ref<RequestLogRow[]>([])
const keys = ref<ApiKey[]>([])
const loading = ref(false)
const error = ref<string | null>(null)
const apiKeyId = ref<number | ''>('')
const keyword = ref('')
const modelFilter = ref('')
const hours = ref(24)
const successFilter = ref<'' | 'success' | 'failure' | 'in_progress'>('')
const errorKindFilter = ref('')
const usageSourceFilter = ref<'' | 'llm' | 'estimated'>('')
const gwSessionFilter = ref('')
const gwTaskFilter = ref('')
const summaryLoading = ref(false)
const summaryError = ref<string | null>(null)
const summaryResult = ref<SessionSummaryResponse | null>(null)
const memoraLoading = ref(false)
const memoraError = ref<string | null>(null)
const memoraResult = ref<SessionSummaryToMemoraResponse['memora'] | null>(null)

const page = ref(1)
const pageSize = ref(50)
const total = ref(0)
const autoRefresh = ref(false)
let autoRefreshTimer: ReturnType<typeof setInterval> | null = null

function startAutoRefresh() {
  stopAutoRefresh()
  autoRefreshTimer = setInterval(() => {
    if (!loading.value) {
      load()
    }
  }, 30000)
}

function stopAutoRefresh() {
  if (autoRefreshTimer !== null) {
    clearInterval(autoRefreshTimer)
    autoRefreshTimer = null
  }
}

watch(autoRefresh, (enabled) => {
  if (enabled) {
    startAutoRefresh()
  } else {
    stopAutoRefresh()
  }
})

onBeforeUnmount(() => {
  stopAutoRefresh()
  window.removeEventListener('keydown', handleKeydown)
})

// 2026-07-02: close the image preview lightbox on ESC, regardless of
// focus. bound globally so the operator does not have to click back
// into the modal first.
function handleKeydown(e: KeyboardEvent) {
  if (e.key === 'Escape' && previewAttachment.value) {
    closeImagePreview()
  }
}

const showCompressionGuide = ref(false)

// Compute compression statistics for the info bar at the top.
const compressionStats = computed(() => {
  const present = rows.value.filter(r => r.compression_strategy || r.outbound_body)
  const delta = present.filter(r => r.compression_strategy === 'delta_append')
  const sliding = present.filter(r => r.compression_strategy && r.compression_strategy.startsWith('sliding_window'))
  const v7 = present.filter(r => r.compression_reason)
  const mechanical = present.filter(r => r.compression_strategy === 'mechanical_trim')
  return {
    totalCompressed: present.length,
    deltaCount: delta.length,
    slidingCount: sliding.length,
    v7Count: v7.length,
    mechanicalCount: mechanical.length,
  }
})

const detailVisible = ref(false)
const detailLoading = ref(false)
const detail = ref<RequestLogDetail | null>(null)
const detailTab = ref<'request' | 'outbound' | 'response' | 'attachments'>('request')

// Attachments
const attachments = ref<Attachment[]>([])
const attachmentsLoading = ref(false)

// 2026-07-02: image preview lightbox. The thumbnail in each
// attachment row is a small 80x80 cover; clicking it pops a full-size
// modal so the operator can see the actual image at native
// resolution. previewAttachment holds the currently-displayed
// attachment (null = modal closed).
const previewAttachment = ref<Attachment | null>(null)

function openImagePreview(att: Attachment) {
  if (!att.media_type.startsWith('image/')) return
  previewAttachment.value = att
}
function closeImagePreview() {
  previewAttachment.value = null
}

// Tenant info for display
const tenantLabel = computed(() => {
  const tenantId = getCurrentTenantId()
  const isAdmin = isSuperAdmin()
  const isDefault = isDefaultTenant()

  if (isAdmin && isDefault) {
    return t('requests.defaultTenantOptions.whole')
  } else if (isDefault) {
    return t('requests.defaultTenantOptions.defaultTenant')
  } else {
    return t('requests.defaultTenantOptions.tenantPrefix', { id: tenantId })
  }
})

// Non-default tenants can only view last 3 days (72 hours)
const maxHoursForTenant = computed(() => isDefaultTenant() ? 168 : 72)

// Validate hours when tenant changes
function validateHours() {
  const maxHours = maxHoursForTenant.value
  if (hours.value > maxHours) {
    hours.value = maxHours
  }
}

async function loadKeys() {
  try {
    keys.value = await getKeys()
  } catch {
    keys.value = []
  }
}

function timeRange() {
  const end = new Date()
  const start = new Date(end.getTime() - hours.value * 3600 * 1000)
  return { from: start.toISOString(), to: end.toISOString() }
}

function onModelFilterChange(name: string | string[]) {
  modelFilter.value = typeof name === 'string' ? name.trim() : ''
}

// Kind label maps — populated from i18n so the Chinese UI doesn't need
// hand-maintained Records. Falls back to the raw kind string for unknown
// codes (the backend can add new ones before the locale is updated).
const ERROR_KIND_LABELS: Record<string, string> = {
  model_not_found: t('requests.errorKind.model_not_found'),
  provider_error: t('requests.errorKind.provider_error'),
  auth_error: t('requests.errorKind.auth_error'),
  missing_key: t('requests.errorKind.missing_key'),
  invalid_key: t('requests.errorKind.invalid_key'),
  auth_unavailable: t('requests.errorKind.auth_unavailable'),
  body_read_error: t('requests.errorKind.body_read_error'),
  body_too_large: t('requests.errorKind.body_too_large'),
  json_parse_error: t('requests.errorKind.json_parse_error'),
  rate_limit: t('requests.errorKind.rate_limit'),
  rate_limit_exceeded: t('requests.errorKind.rate_limit_exceeded'),
  key_throttled: t('requests.errorKind.key_throttled'),
  budget_exhausted: t('requests.errorKind.budget_exhausted'),
  insufficient_credits: t('requests.errorKind.insufficient_credits'),
  timeout: t('requests.errorKind.timeout'),
  canceled: t('requests.errorKind.canceled'),
  upstream_error: t('requests.errorKind.upstream_error'),
  stream_error: t('requests.errorKind.stream_error'),
  no_candidate: t('requests.errorKind.no_candidate'),
  session_forbidden: t('requests.errorKind.session_forbidden'),
  executor_unavailable: t('requests.errorKind.executor_unavailable'),
}

// 2026-06-19 T-NEW-7: labels for actual gateway failure codes (the only
// values that should ever appear in failure_detail_code now that
// upstream_finish_reason has been split out). eof_without_done and
// client_cancel are kept as "successful with caveat" in the status
// column; only the "真" gateway errors get a Chinese label here.
const FAILURE_DETAIL_LABELS: Record<string, string> = {
  gw_rpm_exceeded: t('requests.gwErrorKind.gw_rpm_exceeded'),
  gw_concurrent_exceeded: t('requests.gwErrorKind.gw_concurrent_exceeded'),
  gw_tpm_exceeded: t('requests.gwErrorKind.gw_tpm_exceeded'),
  gw_key_throttled: t('requests.gwErrorKind.gw_key_throttled'),
  gw_budget_exhausted: t('requests.gwErrorKind.gw_budget_exhausted'),
  gw_no_candidate: t('requests.gwErrorKind.gw_no_candidate'),
  gw_session_forbidden: t('requests.gwErrorKind.gw_session_forbidden'),
  eof_without_done: t('requests.gwErrorKind.eof_without_done'),
  stream_timeout: t('requests.gwErrorKind.stream_timeout'),
  client_cancel: t('requests.gwErrorKind.client_cancel'),
  client_disconnected: t('requests.gwErrorKind.client_disconnected'),
  no_deltas: t('requests.gwErrorKind.no_deltas'),
  invalid_first_chunk: t('requests.gwErrorKind.invalid_first_chunk'),
  invalid_json: t('requests.gwErrorKind.invalid_json'),
  upstream_5xx: t('requests.gwErrorKind.upstream_5xx'),
  upstream_4xx: t('requests.gwErrorKind.upstream_4xx'),
  unexpected_status: t('requests.gwErrorKind.unexpected_status'),
  connection_reset: t('requests.gwErrorKind.connection_reset'),
  write_failed: t('requests.gwErrorKind.write_failed'),
  hangup: t('requests.gwErrorKind.hangup'),
  body_too_large: t('requests.gwErrorKind.body_too_large'),
  eof_mid_tool_call: t('requests.gwErrorKind.eof_mid_tool_call'),
  first_byte_timeout: t('requests.gwErrorKind.first_byte_timeout'),
}

// 2026-06-19 T-NEW-7: labels for the SOLE home of the upstream
// finish_reason (stop, tool_calls, length, end_turn, …). These are NOT
// failures; the UI surfaces them as informational metadata in the
// request detail panel, not as a "失败详情" pill.
const UPSTREAM_FINISH_REASON_LABELS: Record<string, string> = {
  stop: t('requests.finish.stop'),
  tool_calls: t('requests.finish.tool_calls'),
  function_call: t('requests.finish.function_call'),
  length: t('requests.finish.length'),
  end_turn: t('requests.finish.end_turn'),
  max_tokens: t('requests.finish.max_tokens'),
}

function upstreamFinishReasonLabel(v: string | null | undefined): string {
  if (!v) return ''
  return UPSTREAM_FINISH_REASON_LABELS[v] ?? v
}

function statusLabel(row: RequestLogRow): string {
  if (row.request_status === 'in_progress') return t('requests.status.in_progress')
  if (row.request_status === 'success' || row.success) return t('requests.status.success')
  // 2026-06-19 T-NEW-7: failure_detail_code now contains ONLY real failure
  // codes. upstream_finish_reason is informational and should never be
  // read as a failure label.
  const detail = row.failure_detail_code || ''
  if (FAILURE_DETAIL_LABELS[detail]) return FAILURE_DETAIL_LABELS[detail]
  const kind = row.error_kind || ''
  if (ERROR_KIND_LABELS[kind]) return ERROR_KIND_LABELS[kind]
  if (detail.startsWith('gw_')) return `${t('requests.errorKind.gw_prefix')}${detail.slice(3)}`
  return kind || detail || t('requests.status.failure')
}

function statusTitle(row: RequestLogRow): string {
  const parts: string[] = []
  if (row.failure_stage) parts.push(`stage=${row.failure_stage}`)
  if (row.error_kind) parts.push(`error_kind=${row.error_kind}`)
  if (row.failure_detail_code) parts.push(`detail=${row.failure_detail_code}`)
  // 2026-06-19 T-NEW-7: surface the upstream finish_reason separately so
  // operators can still see it on a successful row (and confirm it really
  // is a normal `stop` / `tool_calls` finish, not a disguised failure).
  if (row.upstream_finish_reason) {
    parts.push(`finish=${row.upstream_finish_reason}`)
  }
  return parts.join(' · ') || ''
}

function statusColor(row: RequestLogRow): string {
  if (row.request_status === 'in_progress') return 'var(--warning, #f59e0b)'
  if (row.request_status === 'success' || row.success) return 'var(--success)'
  return 'var(--error)'
}

// jumpToParent filters the list down to the parent of the current
// compressed row. Lets operators click "← <prefix>" in the compression
// badge and immediately see the original (pre-compression) request.
//
// Round 47 compression v7 Q5: the parent breadcrumb click handler.
// We use gw_task_id (which is stable across the original + retry
// attempts) so the parent row appears in the filtered list alongside
// any sibling compressed rows for the same task. If the row has no
// task_id, we fall back to scrolling the badge title into view (no
// filter is applied — the meta popover already shows the full id).
function jumpToParent(row: RequestLogRow) {
  if (!row.parent_request_id) return
  if (row.gw_task_id) {
    gwTaskFilter.value = row.gw_task_id
  }
  // No requestIdFilter exists in this view; the badge's title attr
  // already exposes the full parent id for copy/paste.
}

// Round 47 compression v7 + v3 session-level (2026-06-19): badge + label
// for the compression_reason / compression_strategy pair. Returns null
// when the request was not compressed at all (neither v7 nor v3 fired).
function compressionLabel(row: RequestLogRow): { reason: string; strategy: string; tip: string } | null {
  // v3 strategies have no compression_reason (they're proactive, not 4xx-triggered).
  // v7 strategies always have compression_reason. Either way, a non-null
  // compression_strategy means something fired.
  if (!row.compression_reason && !row.compression_strategy) return null
  const reasonMap: Record<string, string> = {
    'mode_1_auto_threshold': t('requests.compression.mode_1_auto_threshold'),
    'mode_2_on_4xx': t('requests.compression.mode_2_on_4xx'),
    'sliding_window_token': t('requests.compression.sliding_window_token'),
    'sliding_window_count': t('requests.compression.sliding_window_count'),
    'sliding_window_idle': t('requests.compression.sliding_window_idle'),
    'sliding_window_mechanical_trim': t('requests.compression.sliding_window_mechanical_trim'),
  }
  const strategyMap: Record<string, string> = {
    'mechanical_trim': t('requests.compression.mechanical_trim'),
    'memora_l1_inject': t('requests.compression.memora_l1_inject'),
    'llm_summary': t('requests.compression.llm_summary'),
    'noop': t('requests.compression.noop'),
    // v3 (2026-06-19) session-level strategies
    'delta_append': t('requests.compression.short.delta_append'),
    'sliding_window_token': t('requests.compression.short.sliding_window_token'),
    'sliding_window_count': t('requests.compression.short.sliding_window_count'),
    'sliding_window_idle': t('requests.compression.short.sliding_window_idle'),
  }
  // For v3 sliding-window triggered entries, the "reason" label is the
  // window trigger (stored in compression_strategy) and the v7 reason
  // column is empty. Display the trigger as the reason in that case.
  let reason = reasonMap[row.compression_reason || ''] || row.compression_reason || ''
  let strategy = strategyMap[row.compression_strategy || ''] || (row.compression_strategy || '?')
  // Special case: v3 delta_append has compression_reason empty + strategy = 'delta_append'.
  // Treat as '增量拼接' strategy with reason '同会话增量'.
  if (row.compression_strategy === 'delta_append' && !row.compression_reason) {
    reason = t('requests.compression.reason.same_session_delta')
  }
  // Build a tooltip with byte/token deltas from compression_meta when present.
  let tip = `${t('requests.detail_extra.tipReason', { r: reason })}\n${t('requests.detail_extra.tipStrategy', { s: strategy })}`
  const meta = row.compression_meta as Record<string, any> | null
  if (meta) {
    if (meta.tokens_before && meta.tokens_after) {
      const ratio = Math.round((meta.tokens_after / meta.tokens_before) * 100)
      tip += `\nTokens: ${meta.tokens_before} → ${meta.tokens_after} (${ratio}%)`
    }
    if (meta.bytes_before && meta.bytes_after) {
      const kbBefore = Math.round(meta.bytes_before / 1024)
      const kbAfter = Math.round(meta.bytes_after / 1024)
      tip += `\nBytes: ${kbBefore}KB → ${kbAfter}KB`
    }
    if (meta.latency_ms) {
      tip += `\n${t('requests.detail_extra.tipLatency', { n: meta.latency_ms })}`
    }
    // v3 fields: window_triggered + summary_marker
    if (meta.window_triggered) {
      tip += `\n${t('requests.detail_extra.tipTrigger', { v: meta.window_triggered })}`
    }
    if (meta.summary_marker) {
      tip += `\n${t('requests.detail_extra.tipSummaryMarker', { v: String(meta.summary_marker).slice(0, 24) })}`
    }
  }
  // v3 outbound counts (always when outbound body was set, regardless of meta)
  if (typeof row.outbound_msg_count === 'number') {
    tip += `\n${t('requests.detail_extra.tipOutboundMsgCount', { n: row.outbound_msg_count })}`
    if (typeof row.outbound_token_est === 'number') {
      tip += ` (≈${row.outbound_token_est} tokens)`
    }
  }
  if (row.parent_request_id) {
    tip += `\n${t('requests.detail_extra.tipParentRequest', { id: row.parent_request_id })}`
  }
  return { reason, strategy, tip }
}

const traceMode = computed(() =>
  Boolean(gwTaskFilter.value.trim() || gwSessionFilter.value.trim()),
)

const taskSummary = computed(() => {
  if (!traceMode.value || !rows.value.length) return null
  let ok = 0
  let fail = 0
  let pending = 0
  for (const r of rows.value) {
    if (r.request_status === 'in_progress') pending++
    else if (r.request_status === 'success' || r.success) ok++
    else fail++
  }
  return { total: rows.value.length, ok, fail, pending }
})

/** 点击脉络：优先按会话聚合（同一会话含多步请求）；无会话时按任务 ID */
function filterByTrace(row: RequestLogRow) {
  if (row.gw_session_id) {
    gwSessionFilter.value = row.gw_session_id
    gwTaskFilter.value = ''
  } else if (row.gw_task_id) {
    gwTaskFilter.value = row.gw_task_id
    gwSessionFilter.value = ''
  } else {
    return
  }
  // 脉络视图拉宽时间窗与页大小，避免同脉络记录落在默认 24h/50 条外
  if (hours.value < 168) hours.value = 168
  if (pageSize.value < 200) pageSize.value = 200
  resetPageAndLoad()
}

function filterByTask(taskId: string | null | undefined) {
  if (!taskId) return
  gwTaskFilter.value = taskId
  gwSessionFilter.value = ''
  if (hours.value < 168) hours.value = 168
  if (pageSize.value < 200) pageSize.value = 200
  resetPageAndLoad()
}

function filterBySession(sessionId: string | null | undefined) {
  if (!sessionId) return
  gwSessionFilter.value = sessionId
  gwTaskFilter.value = ''
  if (hours.value < 168) hours.value = 168
  if (pageSize.value < 200) pageSize.value = 200
  resetPageAndLoad()
}

function clearTraceFilter() {
  gwTaskFilter.value = ''
  gwSessionFilter.value = ''
  summaryError.value = null
  summaryResult.value = null
  memoraError.value = null
  memoraResult.value = null
  resetPageAndLoad()
}

const canSummarizeSession = computed(() => gwSessionFilter.value.trim().length > 0)

async function generateSessionSummary() {
  const sid = gwSessionFilter.value.trim()
  if (!sid) return
  summaryLoading.value = true
  summaryError.value = null
  summaryResult.value = null
  try {
    summaryResult.value = await getSessionSummary(sid)
  } catch (e: unknown) {
    summaryError.value = e instanceof Error ? e.message : String(e)
  } finally {
    summaryLoading.value = false
  }
}

function summaryExportContent(data: SessionSummaryResponse): string {
  const lines: string[] = []
  lines.push(t('requests.list.summary.title'))
  lines.push('')
  lines.push(`- Session ID: ${data.meta.session_id}`)
  lines.push(t('requests.list.summary.range', { from: fmtTs(data.meta.data_from), to: fmtTs(data.meta.data_to) }))
  lines.push(t('requests.list.summary.logCount', { n: data.meta.log_count }))
  lines.push(t('requests.list.summary.generatedAt', { ts: fmtTs(data.meta.generated_at) }))
  lines.push('')
  lines.push(t('requests.list.summary.summaryHeading'))
  lines.push(data.summary)
  if (data.key_points && data.key_points.length) {
    lines.push('')
    lines.push(t('requests.list.summary.keyPointsHeading'))
    for (const p of data.key_points) lines.push(`- ${p}`)
  }
  return lines.join('\n')
}

function exportSessionSummary(format: 'md' | 'txt' = 'md') {
  if (!summaryResult.value) return
  const content = summaryExportContent(summaryResult.value)
  const blob = new Blob([content], { type: 'text/plain;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  const day = new Date().toISOString().slice(0, 10)
  a.href = url
  a.download = `session-summary-${summaryResult.value.meta.session_id}-${day}.${format}`
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}

async function writeSummaryToMemora() {
  const sid = gwSessionFilter.value.trim()
  if (!sid) return
  memoraLoading.value = true
  memoraError.value = null
  memoraResult.value = null
  try {
    const resp = await sessionSummaryToMemora(sid)
    summaryResult.value = { summary: resp.summary, key_points: resp.key_points, meta: resp.meta }
    memoraResult.value = resp.memora
  } catch (e: unknown) {
    memoraError.value = e instanceof Error ? e.message : String(e)
  } finally {
    memoraLoading.value = false
  }
}

function routeProviderLine(r: RequestLogRow): string {
  const parts: string[] = []
  if (r.provider_name) parts.push(r.provider_name)
  else if (r.provider_code) parts.push(r.provider_code)
  if (r.credential_label) parts.push(r.credential_label)
  if (parts.length) return parts.join(' · ')
  if (r.error_kind === 'missing_key' || r.error_kind === 'invalid_key') return '—'
  return '—'
}

function routeModelLine(r: RequestLogRow): string {
  const requestModel = r.canonical_name || r.client_model || '—'
  const providerModel = (r.provider_model || r.outbound_model || '').trim()
  if (!providerModel || providerModel.toLowerCase() === requestModel.toLowerCase()) {
    return requestModel
  }
  return `${requestModel} → ${providerModel}`
}

function routeModelTitle(r: RequestLogRow): string {
  const requestModel = r.canonical_name || r.client_model || '—'
  const providerModel = (r.provider_model || r.outbound_model || '').trim()
  if (!providerModel || providerModel.toLowerCase() === requestModel.toLowerCase()) {
    return `${t('requests.detail_extra.requestedModelPrefix')}${requestModel}`
  }
  return t('requests.detail_extra.requestedToProviderModelPrefix', { a: requestModel, b: providerModel })
}

function outboundModelDisplay(r: Pick<RequestLogRow, 'provider_model' | 'outbound_model'> | null | undefined): string {
  if (!r) return '—'
  const v = (r.provider_model || r.outbound_model || '').trim()
  return v || '—'
}

function outboundModelTitle(r: Pick<RequestLogRow, 'provider_model' | 'outbound_model'> | null | undefined): string {
  if (!r) return ''
  const shown = outboundModelDisplay(r)
  const recorded = (r.outbound_model || '').trim()
  if (r.provider_model && recorded && r.provider_model !== recorded) {
    return t('requests.detail_extra.outboundModelRecordedPrefix', { shown, recorded })
  }
  return `${t('requests.detail_extra.outboundModelPrefix')}${shown}`
}

function ellipsize(value: string | null | undefined, max = 28): string {
  const s = (value ?? '').trim()
  if (!s) return '—'
  if (s.length <= max) return s
  return s.slice(0, Math.max(1, max - 1)) + '…'
}

function callerUserLine(r: RequestLogRow): string {
  if (r.api_key_owner_user) return r.api_key_owner_user
  if (r.end_user_id) return r.end_user_id
  if (r.application_code) return r.application_code
  return '—'
}

function callerUserTitle(r: RequestLogRow): string {
  const parts: string[] = []
  if (r.api_key_owner_user) parts.push(`${t('requests.detail_extra.userPrefix')}${r.api_key_owner_user}`)
  if (r.end_user_id) parts.push(`${t('requests.detail_extra.endUserPrefix')}${r.end_user_id}`)
  if (r.application_code) parts.push(`${t('requests.detail_extra.applicationPrefix')}${r.application_code}`)
  return parts.join(' · ') || '—'
}

function callerKeyLine(r: RequestLogRow): string {
  const key = r.api_key_prefix ?? (r.api_key_id != null ? `key#${r.api_key_id}` : t('requests.detail_extra.noKeyPrefix'))
  if (r.application_code && r.api_key_owner_user) return `${key} · ${r.application_code}`
  if (r.application_code) return `${key} · ${r.application_code}`
  return key
}

function callerKeyTitle(r: RequestLogRow): string {
  const parts: string[] = []
  if (r.api_key_prefix) parts.push(`${t('requests.detail_extra.apiKeyPrefix')}: ${r.api_key_prefix}`)
  else if (r.api_key_id != null) parts.push(`${t('requests.detail_extra.apiKeyPrefix')} ID: ${r.api_key_id}`)
  else parts.push(t('requests.detail_extra.noKeyDetail'))
  if (r.application_code) parts.push(`${t('requests.detail_extra.applicationPrefix')}${r.application_code}`)
  return parts.join(' · ')
}

function traceSessionTitle(id: string) {
  return `${t('requests.detail_extra.sessionIdTitle')}\n${id}`
}

function traceTaskTitle(id: string) {
  return `${t('requests.detail_extra.taskIdTitle')}\n${id}`
}

async function load() {
  loading.value = true
  error.value = null
  try {
    const range = timeRange()
    const resp: RequestLogsResponse = await getRequestLogs({
      api_key_id: apiKeyId.value === '' ? undefined : Number(apiKeyId.value),
      from: range.from,
      to: range.to,
      q: keyword.value.trim() || undefined,
      request_status: successFilter.value === '' ? undefined : successFilter.value,
      error_kind: errorKindFilter.value.trim() || undefined,
      model: modelFilter.value || undefined,
      usage_source: usageSourceFilter.value === '' ? undefined : usageSourceFilter.value,
      gw_session_id: gwSessionFilter.value.trim() || undefined,
      gw_task_id: gwTaskFilter.value.trim() || undefined,
      chrono: traceMode.value || undefined,
      page: page.value,
      page_size: pageSize.value,
    })
    rows.value = resp.items
    total.value = resp.count
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : String(e)
  } finally {
    loading.value = false
  }
}

function changePage(delta: number) {
  const max = Math.max(1, Math.ceil(total.value / pageSize.value))
  const next = page.value + delta
  if (next < 1 || next > max) return
  page.value = next
  load()
}

function resetPageAndLoad() {
  page.value = 1
  load()
}

function fmtTs(ts: string) {
  return fmtDateTime(ts)
}

function fmtDate(ts: string) {
  // Local short MM/DD; useFormat.fmtDate returns locale-aware short date.
  return new Date(ts).toLocaleDateString(localeRef.value, { month: '2-digit', day: '2-digit' })
}

function fmtTime(ts: string) {
  return new Date(ts).toLocaleTimeString(localeRef.value, { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' })
}

function token(v: number | null | undefined, usageSource?: 'llm' | 'estimated' | null) {
  if (v == null) return '—'
  const formatted = v.toLocaleString()
  // Mark estimated values with a tilde prefix + tooltip to distinguish from
  // upstream-reported counts. Estimated values come from local text heuristics
  // when the provider (e.g. minimax) does not return a usage block.
  if (usageSource === 'estimated') {
    return `~${formatted}`
  }
  return formatted
}

function tokenTitle(usageSource?: 'llm' | 'estimated' | null): string {
  if (usageSource === 'estimated') return t('requests.detail_extra.estimatedNote')
  if (usageSource === 'llm') return t('requests.detail_extra.llmReported')
  return ''
}

function costDisplay(v: number | string | null | undefined, currency: string | null | undefined) {
  if (v == null) return currency ? t('requests.detail_extra.pendingPricing', { currency }) : t('requests.detail_extra.pendingPricingNoCurrency')
  const amount = Number(v).toFixed(6)
  return currency ? `${amount} ${currency}` : amount
}

function creditsDisplay(v: number | null | undefined): string {
  if (v == null || v <= 0) return '—'
  return v.toLocaleString()
}

function shortHash(v: string | null | undefined) {
  return v ? `${v.slice(0, 12)}…` : '—'
}

async function showDetail(requestId: string) {
  detailVisible.value = true
  detailLoading.value = true
  detail.value = null
  detailTab.value = 'request'
  attachments.value = []
  try {
    detail.value = await getRequestLogDetail(requestId)
    // Load attachments if present
    if (detail.value.has_attachments) {
      loadAttachments(requestId)
    }
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : String(e)
  } finally {
    detailLoading.value = false
  }
}

async function loadAttachments(requestId: string) {
  attachmentsLoading.value = true
  try {
    // 2026-07-02: defensive coercion. The backend's ListByRequestID
    // returns nil when no rows are found, and Go's encoding/json
    // serialises a nil []*Attachment as JSON `null` (not `[]`). Without
    // this fallback, the `attachments.length === 0` check in the
    // template throws "Cannot read properties of null (reading 'length')"
    // and Vue aborts rendering the whole detail panel → white page.
    const result = await getAttachments(requestId)
    attachments.value = Array.isArray(result) ? result : []
  } catch (e: unknown) {
    console.error('Failed to load attachments:', e)
  } finally {
    attachmentsLoading.value = false
  }
}

function closeDetail() {
  detailVisible.value = false
  detail.value = null
  attachments.value = []
  closeImagePreview()
}

function formatJson(obj: any): string {
  if (obj == null) return t('requests.common.noData')
  try {
    return JSON.stringify(obj, null, 2)
  } catch {
    return String(obj)
  }
}

function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

function extractMessagesFromBody(body: any): any[] {
  if (body == null) return []
  if (Array.isArray(body)) return body
  if (typeof body === 'string') {
    try { body = JSON.parse(body) } catch { return [] }
  }
  if (body.messages && Array.isArray(body.messages)) return body.messages
  if (body.choices && Array.isArray(body.choices)) {
    const msgs: any[] = []
    for (const c of body.choices) {
      if (c.message) msgs.push(c.message)
    }
    return msgs
  }
  return [body]
}

// v3 (2026-06-19) session-level outbound body helpers.
// Returns true when the row has an outbound_body that differs from the
// client request_body (i.e. v3 ran for this request).
function hasOutboundBody(row: any): boolean {
  if (!row?.outbound_body) return false
  // Count messages via outbound_msg_count column (cheaper than parsing body).
  if (typeof row.outbound_msg_count === 'number') return row.outbound_msg_count > 0
  const msgs = extractMessagesFromBody(row.outbound_body)
  return msgs.length > 0
}

// Cheap equality check: outbound body stringified bytes match request body bytes.
function outboundEqualsRequest(row: any): boolean {
  if (!row?.outbound_body) return false
  const reqStr = JSON.stringify(row.request_body ?? '')
  const outStr = JSON.stringify(row.outbound_body ?? '')
  return reqStr === outStr
}

// Returns outbound_msg_count - request message count (rough delta indicator).
function outboundMsgDelta(row: any): string {
  const out = typeof row?.outbound_msg_count === 'number' ? row.outbound_msg_count : null
  if (out == null) return ''
  const reqMsgs = extractMessagesFromBody(row?.request_body)
  const reqCount = reqMsgs.length
  const diff = out - reqCount
  if (diff === 0) return '0'
  return diff > 0 ? `+${diff}` : `${diff}`
}

// Returns the smm_v1 summary marker (if present in compression_meta).
function outboundSummaryMarker(row: any): string {
  const meta = row?.compression_meta
  if (!meta || typeof meta !== 'object') return ''
  return typeof meta.summary_marker === 'string' ? meta.summary_marker : ''
}

// True if the given message looks like a gateway-injected compaction summary
// (content starts with the smm_v1 marker prefix).
function isSummaryMarkerMessage(msg: any): boolean {
  const content = msg?.content
  if (typeof content === 'string') return content.startsWith('[smm_v1:')
  if (Array.isArray(content)) {
    for (const p of content) {
      if (typeof p?.text === 'string' && p.text.startsWith('[smm_v1:')) return true
    }
  }
  return false
}

function truncate(s: string, n: number): string {
  if (!s) return ''
  return s.length > n ? s.slice(0, n) + '…' : s
}

// v3 savings helpers (2026-06-20). Compute human-readable byte/token
// savings between request_body and outbound_body.
function bodyBytes(obj: any): number {
  if (!obj) return 0
  if (typeof obj === 'string') return new Blob([obj]).size
  return new Blob([JSON.stringify(obj)]).size
}

function calcSavingDetail(row: any): { savingStr: string; tokenSavingStr: string; msgReductionStr: string; hasSaving: boolean } {
  const hasOutbound = !!row.outbound_body
  if (!hasOutbound) return { savingStr: '', tokenSavingStr: '', msgReductionStr: '', hasSaving: false }
  const reqBytes = bodyBytes(row.request_body)
  const outBytes = bodyBytes(row.outbound_body)
  const savingBytes = reqBytes - outBytes
  const savingPct = reqBytes > 0 ? Math.round((savingBytes / reqBytes) * 100) : 0

  // Token saving: estimate from request vs outbound
  const reqTok = row.outbound_token_est ? Math.round(row.outbound_token_est * (reqBytes / (outBytes || 1))) : 0
  const outTok = row.outbound_token_est || 0
  const tokDiff = reqTok - outTok
  const tokPct = reqTok > 0 ? Math.round((tokDiff / reqTok) * 100) : 0

  // Message reduction: count messages from request vs outbound
  const reqMsgs = extractMessagesFromBody(row.request_body).length
  const outMsgs = row.outbound_msg_count ?? extractMessagesFromBody(row.outbound_body).length
  const msgDiff = reqMsgs - outMsgs
  const msgPct = reqMsgs > 0 ? Math.round((msgDiff / reqMsgs) * 100) : 0

  const fmtBytes = (b: number) => b > 1024 ? `${(b / 1024).toFixed(1)}KB` : `${b}B`
  const savingStr = reqBytes > outBytes ? `-${fmtBytes(savingBytes)} (${savingPct}%)` : '≈0'
  const tokenSavingStr = tokDiff > 0 ? `-${tokDiff} (${tokPct}%)` : '≈0'
  const msgReductionStr = msgDiff > 0 ? `-${msgDiff} (${msgPct}%)` : `${msgDiff >= 0 ? '0' : '+' + Math.abs(msgDiff)}`

  return { savingStr, tokenSavingStr, msgReductionStr, hasSaving: true }
}

// Returns a human-readable explanation sentence for the compression strategy.
function compressExplainText(row: any): string {
  const strat = row.compression_strategy
  if (!strat) return ''
  const reason = row.compression_reason || ''
  const meta = row.compression_meta as Record<string, any> | null
  switch (strat) {
    case 'delta_append':
      return t('requests.list.session.same_session_no_retransmit')
    case 'sliding_window_token':
    case 'sliding_window_count':
    case 'sliding_window_idle': {
      const strategyName = strat === 'sliding_window_token'
        ? t('requests.list.session.strategy_token')
        : strat === 'sliding_window_idle'
          ? t('requests.list.session.strategy_idle')
          : t('requests.list.session.strategy_count')
      const suffix = meta?.summary_marker
        ? t('requests.list.session.with_llm_summary')
        : t('requests.list.session.with_sliding_compress')
      return t('requests.list.session.too_many_messages', { strategy: strategyName }) + suffix
    }
    case 'mechanical_trim':
      if (reason === 'mode_2_on_4xx') return t('requests.list.session.mechanical_4xx')
      return t('requests.list.session.mechanical_fallback')
    case 'memora_l1_inject':
      return t('requests.list.session.memora_inject')
    case 'llm_summary':
      return t('requests.list.session.llm_summary_done')
    case 'noop':
      return t('requests.list.session.skipped')
    default:
      return strat ? t('requests.list.session.strategyLabel', { strat }) : ''
  }
}

function roleColor(role: string): string {
  switch (role) {
    case 'user': return 'var(--info, #3b82f6)'
    case 'assistant': return 'var(--success, #22c55e)'
    case 'system': return 'var(--warning, #f59e0b)'
    case 'tool': return 'var(--muted, #94a3b8)'
    default: return 'inherit'
  }
}

const route = useRoute()

onMounted(async () => {
  const q = route.query
  if (q.success === 'success' || q.success === 'failure' || q.success === 'in_progress') {
    successFilter.value = q.success
  }
  if (typeof q.error_kind === 'string' && q.error_kind.trim()) {
    errorKindFilter.value = q.error_kind.trim()
  }
  if (typeof q.hours === 'string' && /^\d+$/.test(q.hours)) {
    hours.value = Number(q.hours)
  }
  // 2026-07-02: register global ESC handler for the image-preview
  // lightbox. We attach to window (not the modal root) so it fires
  // regardless of which element currently has focus.
  window.addEventListener('keydown', handleKeydown)
  await loadKeys()
  await load()
})
</script>

<template>
  <div>
    <div class="page-header" style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px">
      <h2 style="margin:0">{{ t('requests.list.title') }}</h2>
      <div style="display:flex;gap:8px;align-items:center">
        <span class="tenant-badge" :class="{ 'tenant-badge--admin': isSuperAdmin(), 'tenant-badge--default': isDefaultTenant() }">
          {{ tenantLabel }}
        </span>
        <label style="display:flex;align-items:center;gap:4px;font-size:12px;cursor:pointer;user-select:none">
          <input type="checkbox" v-model="autoRefresh" style="cursor:pointer" />
          <span>{{ t('requests.list.autoRefresh') }}</span>
        </label>
        <button class="btn btn-primary btn-sm" :disabled="loading" @click="load">{{ t('requests.list.refresh') }}</button>
      </div>
    </div>

    <div v-if="!isDefaultTenant()" class="tenant-notice" style="margin-bottom:12px;padding:8px 12px;background:rgba(59,130,246,0.1);border:1px solid rgba(59,130,246,0.3);border-radius:6px;font-size:12px;color:#3b82f6">
      {{ t('requests.list.tenantNonDefaultHint') }}
    </div>

    <!-- v3 压缩说明卡片 (2026-06-20) -->
    <div class="compression-guide-card" style="margin-bottom:12px;border:1px solid var(--border,#333);border-radius:8px;overflow:hidden;font-size:12px">
      <div
        style="display:flex;justify-content:space-between;align-items:center;padding:8px 12px;cursor:pointer;background:var(--surface-secondary,#1a1a2e)"
        @click="showCompressionGuide = !showCompressionGuide"
      >
        <span style="font-weight:600;display:flex;align-items:center;gap:6px">
          <span>{{ t('requests.list.compress.guideTitle') }}</span>
          <span v-if="compressionStats.totalCompressed > 0" class="badge" style="font-size:10px;padding:2px 6px">
            {{ t('requests.list.compress.summaryTemplate', { total: compressionStats.totalCompressed }) }}
            <template v-if="compressionStats.deltaCount">{{ t('requests.list.compress.deltaSuffix', { n: compressionStats.deltaCount }) }}</template>
            <template v-if="compressionStats.slidingCount">{{ t('requests.list.compress.slidingSuffix', { n: compressionStats.slidingCount }) }}</template>
          </span>
        </span>
        <span style="color:var(--text-secondary,#6b7280);font-size:11px">{{ showCompressionGuide ? t('requests.common.collapse') : t('requests.common.expand') }}</span>
      </div>
      <div v-if="showCompressionGuide" style="padding:8px 12px 12px;border-top:1px solid var(--border,#333);line-height:1.7">
        <p style="margin:0 0 6px"><strong>{{ t('requests.list.compress.cacheTitle') }}</strong>：{{ t('requests.list.compress.cacheBody') }}</p>
        <p style="margin:0 0 6px"><strong>{{ t('requests.list.compress.strategyTitle') }}</strong>：</p>
        <table style="width:100%;border-collapse:collapse;font-size:11px">
          <tr>
            <th class="compress-table-head compress-table-head--nowrap">{{ t('requests.list.compress.tableHeaderStrategy') }}</th>
            <th class="compress-table-head">{{ t('requests.list.compress.tableHeaderTrigger') }}</th>
            <th class="compress-table-head">{{ t('requests.list.compress.tableHeaderEffect') }}</th>
          </tr>
          <tr>
            <td style="padding:3px 6px;border:1px solid var(--border,#444);white-space:nowrap;color:var(--success,#22c55e)">{{ t('requests.list.compress.strategies.delta_append') }}</td>
            <td style="padding:3px 6px;border:1px solid var(--border,#444)">{{ t('requests.list.compress.strategies.delta_trigger') }}</td>
            <td style="padding:3px 6px;border:1px solid var(--border,#444)">{{ t('requests.list.compress.strategies.delta_effect') }}</td>
          </tr>
          <tr>
            <td style="padding:3px 6px;border:1px solid var(--border,#444);white-space:nowrap;color:var(--warning,#f59e0b)">{{ t('requests.list.compress.strategies.sliding_window') }}</td>
            <td style="padding:3px 6px;border:1px solid var(--border,#444)">{{ t('requests.list.compress.strategies.sliding_trigger') }}</td>
            <td style="padding:3px 6px;border:1px solid var(--border,#444)">{{ t('requests.list.compress.strategies.sliding_effect') }}</td>
          </tr>
          <tr>
            <td style="padding:3px 6px;border:1px solid var(--border,#444);white-space:nowrap;color:#b45309">{{ t('requests.list.compress.strategies.mechanical_trim') }}</td>
            <td style="padding:3px 6px;border:1px solid var(--border,#444)">{{ t('requests.list.compress.strategies.mechanical_trigger') }}</td>
            <td style="padding:3px 6px;border:1px solid var(--border,#444)">{{ t('requests.list.compress.strategies.mechanical_effect') }}</td>
          </tr>
          <tr>
            <td style="padding:3px 6px;border:1px solid var(--border,#444);white-space:nowrap;color:#6d28d9">{{ t('requests.list.compress.strategies.memora_l1_inject') }}</td>
            <td style="padding:3px 6px;border:1px solid var(--border,#444)">{{ t('requests.list.compress.strategies.memora_trigger') }}</td>
            <td style="padding:3px 6px;border:1px solid var(--border,#444)">{{ t('requests.list.compress.strategies.memora_effect') }}</td>
          </tr>
        </table>
      </div>
    </div>

    <div class="compact-filter-bar compact-filter-bar--stacked">
      <div class="cf-row">
        <select v-model="apiKeyId" class="cf-select cf-cred" :title="'API Key'">
          <option value="">{{ t('requests.list.filter.keyAll') }}</option>
          <option v-for="k in keys" :key="k.id" :value="k.id">{{ k.key_prefix }} ({{ k.application_code }})</option>
        </select>
        <select v-model="hours" class="cf-select cf-hours" :title="t('requests.list.filter.timeTitle')" @change="validateHours">
          <option :value="1">{{ t('requests.list.filter.timeOptions.h1') }}</option>
          <option :value="6">{{ t('requests.list.filter.timeOptions.h6') }}</option>
          <option :value="24">{{ t('requests.list.filter.timeOptions.h24') }}</option>
          <option :value="72">{{ t('requests.list.filter.timeOptions.d3') }}</option>
          <option :value="168" :disabled="!isDefaultTenant()">{{ t('requests.list.filter.timeOptions.d7') }}</option>
        </select>
        <select v-model="successFilter" class="cf-select cf-status" :title="t('requests.list.filter.resultTitle')">
          <option value="">{{ t('requests.list.filter.resultAll') }}</option>
          <option value="in_progress">{{ t('requests.list.filter.resultInProgress') }}</option>
          <option value="success">{{ t('requests.list.filter.resultSuccess') }}</option>
          <option value="failure">{{ t('requests.list.filter.resultFailure') }}</option>
        </select>
        <select v-model="errorKindFilter" class="cf-select cf-error" :title="t('requests.list.filter.errorTitle')">
          <option value="">{{ t('requests.list.filter.errorAll') }}</option>
          <option v-for="kind in Object.keys(ERROR_KIND_LABELS)" :key="kind" :value="kind">{{ ERROR_KIND_LABELS[kind] }}</option>
        </select>
        <select
          v-model="usageSourceFilter"
          class="cf-select cf-source"
          :title="t('requests.list.filter.tokenSourceTitle')"
        >
          <option value="">{{ t('requests.list.filter.tokenSourceAll') }}</option>
          <option value="llm">{{ t('requests.list.filter.tokenSourceLlm') }}</option>
          <option value="estimated">{{ t('requests.list.filter.tokenSourceEstimated') }}</option>
        </select>
        <span class="cf-meta">{{ t('requests.list.filter.totalMeta', { n: total }) }}</span>
      </div>
      <div class="cf-row cf-row--secondary">
        <div class="cf-field cf-field--model">
          <span class="cf-label">{{ t('requests.list.filter.modelLabel') }}</span>
          <ModelPicker
            v-model="modelFilter"
            :placeholder="t('requests.list.filter.modelPlaceholder')"
            :title="t('requests.list.filter.modelTitle')"
            @update:model-value="onModelFilterChange"
          />
        </div>
        <div class="cf-field cf-field--grow">
          <span class="cf-label">{{ t('requests.list.filter.messageLabel') }}</span>
          <input
            v-model="keyword"
            type="text"
            class="cf-input"
            :placeholder="t('requests.list.filter.messagePlaceholder')"
            @keyup.enter="resetPageAndLoad"
          />
        </div>
        <div class="cf-field cf-field--grow">
          <span class="cf-label">{{ t('requests.list.filter.sessionLabel') }}</span>
          <input
            v-model="gwSessionFilter"
            type="text"
            class="cf-input"
            :placeholder="t('requests.list.filter.sessionPlaceholder')"
            @keyup.enter="resetPageAndLoad"
          />
        </div>
        <div class="cf-field cf-field--grow">
          <span class="cf-label">{{ t('requests.list.filter.taskLabel') }}</span>
          <input
            v-model="gwTaskFilter"
            type="text"
            class="cf-input"
            :placeholder="t('requests.list.filter.taskPlaceholder')"
            @keyup.enter="resetPageAndLoad"
          />
        </div>
        <button class="btn btn-primary btn-sm" @click="resetPageAndLoad">{{ t('requests.list.query') }}</button>
      </div>
    </div>

    <p v-if="error" style="color:var(--danger);margin-bottom:12px">{{ error }}</p>

    <div
      v-if="traceMode && taskSummary"
      class="card trace-summary"
      style="margin-bottom:12px;padding:10px 14px;font-size:12px;display:flex;gap:16px;align-items:center;flex-wrap:wrap"
    >
      <span style="font-weight:600">{{ t('requests.list.trace.title') }}</span>
      <span>{{ t('requests.list.trace.summaryTemplate', { total: total, n: taskSummary.total }) }}</span>
      <span style="color:var(--success)">{{ t('requests.list.trace.successLabel', { n: taskSummary.ok }) }}</span>
      <span style="color:var(--danger)">{{ t('requests.list.trace.failLabel', { n: taskSummary.fail }) }}</span>
      <span v-if="taskSummary.pending" style="color:var(--warning, #f59e0b)">{{ t('requests.list.trace.pendingLabel', { n: taskSummary.pending }) }}</span>
      <span v-if="gwTaskFilter" style="color:var(--muted)">{{ t('requests.list.trace.taskFilter', { id: gwTaskFilter }) }}</span>
      <span v-if="gwSessionFilter" style="color:var(--muted)">{{ t('requests.list.trace.sessionFilter', { id: shortHash(gwSessionFilter) }) }}</span>
      <button class="btn btn-ghost btn-sm trace-clear-btn" @click="clearTraceFilter">{{ t('requests.list.trace.clear') }}</button>
    </div>

    <div v-if="canSummarizeSession" class="card" style="margin-bottom:12px;padding:12px">
      <div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap">
        <strong>{{ t('requests.list.trace.sessionSummary') }}</strong>
        <span style="color:var(--muted);font-size:12px">{{ t('requests.list.trace.sessionSummaryHint') }}</span>
        <button class="btn btn-primary btn-sm" :disabled="summaryLoading" @click="generateSessionSummary">
          {{ summaryLoading ? t('requests.list.trace.generating') : t('requests.list.trace.generate') }}
        </button>
        <button
          v-if="summaryResult"
          class="btn btn-ghost btn-sm"
          @click="exportSessionSummary('md')"
        >{{ t('requests.list.trace.exportMd') }}</button>
        <button
          v-if="summaryResult"
          class="btn btn-ghost btn-sm"
          @click="exportSessionSummary('txt')"
        >{{ t('requests.list.trace.exportTxt') }}</button>
        <button
          class="btn btn-ghost btn-sm"
          :disabled="memoraLoading"
          @click="writeSummaryToMemora"
        >{{ memoraLoading ? t('requests.list.trace.writingMemora') : t('requests.list.trace.writeMemora') }}</button>
      </div>
      <p v-if="summaryError" style="margin:8px 0 0;color:var(--danger)">{{ summaryError }}</p>
      <p v-if="memoraError" style="margin:8px 0 0;color:var(--danger)">Memora: {{ memoraError }}</p>
      <p v-if="memoraResult" style="margin:8px 0 0;color:var(--success, #22c55e)">
        {{ t('requests.list.trace.memoraWritten', { n: memoraResult.written, status: memoraResult.status }) }}
      </p>
      <div v-if="summaryResult" style="margin-top:10px;font-size:12px">
        <div style="color:var(--muted);margin-bottom:6px">
          {{ t('requests.list.trace.summaryRange', { from: fmtTs(summaryResult.meta.data_from), to: fmtTs(summaryResult.meta.data_to), n: summaryResult.meta.log_count }) }}
        </div>
        <div style="white-space:pre-wrap;line-height:1.6">{{ summaryResult.summary }}</div>
        <ul v-if="summaryResult.key_points?.length" class="summary-key-points">
          <li v-for="(p, i) in summaryResult.key_points" :key="i">{{ p }}</li>
        </ul>
      </div>
    </div>

    <div v-if="!loading && total > 0" class="pagination-bar">
      <div class="pagination-info">
        <span>{{ t('requests.list.pagination.total', { n: total }) }}</span>
        <span v-if="total > 0">{{ t('requests.list.pagination.pageInfo', { page, totalPages: Math.max(1, Math.ceil(total / pageSize)) }) }}</span>
        <span class="pagination-divider">·</span>
        <span class="page-size-label">{{ t('requests.list.pagination.pageSize') }}</span>
        <select v-model.number="pageSize" @change="resetPageAndLoad" class="page-size-select">
          <option :value="50">50</option>
          <option :value="100">100</option>
          <option :value="200">200</option>
          <option :value="500">500</option>
        </select>
      </div>
      <div class="pagination-controls">
        <button class="btn btn-ghost btn-sm" :disabled="page <= 1" @click="changePage(-1)">{{ t('requests.list.pagination.previous') }}</button>
        <button class="btn btn-ghost btn-sm" :disabled="page >= Math.ceil(total / pageSize)" @click="changePage(1)">{{ t('requests.list.pagination.next') }}</button>
      </div>
    </div>

    <div class="card" style="overflow-x:auto">
      <table class="data-table request-log-table" style="width:100%;font-size:12px">
        <thead>
          <tr>
            <th v-if="traceMode" class="col-seq">#</th>
            <th class="col-time">{{ t('requests.list.table.colTime') }}</th>
            <th class="col-trace">{{ t('requests.list.table.colTrace') }}</th>
            <th class="col-caller">{{ t('requests.list.table.colCaller') }}</th>
            <th class="col-route">{{ t('requests.list.table.colRoute') }}</th>
            <th class="col-tokens">Token</th>
            <th v-if="!isDefaultTenant()" class="col-credits">{{ t('requests.list.table.colCredits') }}</th>
            <th class="col-lat">{{ t('requests.list.table.colLat') }}</th>
            <th class="col-compress">{{ t('requests.list.table.colCompress') }}</th>
            <th class="col-status">{{ t('requests.list.table.colStatus') }}</th>
            <th class="col-attachments" :title="t('requests.list.table.attachmentsTitle')">📎</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="loading"><td :colspan="traceMode ? (isDefaultTenant() ? 10 : 11) : (isDefaultTenant() ? 9 : 10)">{{ t('requests.common.loading') }}</td></tr>
          <tr v-else-if="!rows.length"><td :colspan="traceMode ? (isDefaultTenant() ? 10 : 11) : (isDefaultTenant() ? 9 : 10)">{{ t('requests.common.noRecord') }}</td></tr>
          <tr
            v-for="r in rows"
            :key="r.request_id + r.ts"
            class="request-log-row"
            :class="{ 'row-failure': r.request_status === 'failure' || (!r.success && r.request_status !== 'in_progress') }"
            @click="showDetail(r.request_id)"
          >
            <td v-if="traceMode" class="col-seq">
              <span class="cell-line1">{{ r.trace_seq ?? '—' }}</span>
            </td>
            <td class="col-time" :title="`${r.request_id} · ${fmtTs(r.ts)}`">
              <div class="cell-line1">{{ fmtDate(r.ts) }}</div>
              <div class="cell-line2">{{ fmtTime(r.ts) }}</div>
            </td>
            <td class="col-trace" @click.stop="filterByTrace(r)">
              <div
                v-if="r.gw_session_id"
                class="trace-link trace-full"
                :title="traceSessionTitle(r.gw_session_id)"
              >{{ t('requests.list.table.sessionPrefix') }} {{ ellipsize(r.gw_session_id, 36) }}</div>
              <div
                v-if="r.gw_task_id"
                class="trace-sub trace-full"
                :title="traceTaskTitle(r.gw_task_id)"
                @click.stop="filterByTask(r.gw_task_id)"
              >{{ t('requests.list.table.taskPrefix') }} {{ ellipsize(r.gw_task_id, 36) }}</div>
              <span v-if="!r.gw_task_id && !r.gw_session_id" class="cell-line2" style="color:var(--muted)">—</span>
            </td>
            <td class="col-caller">
              <div class="cell-line1 cell-clip" :title="callerUserTitle(r)">{{ ellipsize(callerUserLine(r), 18) }}</div>
              <div class="cell-line2 cell-clip" :title="callerKeyTitle(r)">{{ ellipsize(callerKeyLine(r), 22) }}</div>
            </td>
            <td class="col-route">
              <div class="cell-line1 cell-clip" :title="routeProviderLine(r)">{{ ellipsize(routeProviderLine(r), 24) }}</div>
              <div class="cell-line2 cell-clip" :title="routeModelTitle(r)">{{ ellipsize(routeModelLine(r), 32) }}</div>
            </td>
            <td class="col-tokens" :title="tokenTitle(r.usage_source)">
              <div class="cell-line1">
                {{ t('requests.list.table.tokenTooltip', { in: token(r.prompt_tokens, r.usage_source), out: token(r.completion_tokens, r.usage_source) }) }}
              </div>
              <div class="cell-line2">
                {{ t('requests.list.table.cacheTokenTooltip', { in: token(r.cache_read_tokens, r.usage_source), out: token(r.cache_write_tokens, r.usage_source) }) }}
              </div>
            </td>
            <td v-if="!isDefaultTenant()" class="col-credits" :title="t('requests.list.table.creditsTitle')">
              <div class="cell-line1">{{ creditsDisplay(r.credits_charged) }}</div>
            </td>
            <td class="col-lat">
              <div class="cell-line1">{{ r.latency_ms != null ? r.latency_ms + 'ms' : '—' }}</div>
              <div v-if="r.request_mode" class="cell-line2">{{ r.request_mode }}</div>
            </td>
            <td class="col-compress">
              <template v-if="compressionLabel(r)">
                <span
                  class="compression-badge"
                  :class="['strategy-' + (r.compression_strategy || 'noop')]"
                  :title="compressionLabel(r)!.tip"
                >
                  <span class="badge-reason">{{ compressionLabel(r)!.reason }}</span>
                  <span class="badge-sep">·</span>
                  <span class="badge-strategy">{{ compressionLabel(r)!.strategy }}</span>
                </span>
                <div v-if="calcSavingDetail(r).hasSaving" class="cell-line2 saving-text">
                  {{ calcSavingDetail(r).savingStr }}
                  <span v-if="calcSavingDetail(r).tokenSavingStr" class="saving-token"> · {{ calcSavingDetail(r).tokenSavingStr }}</span>
                </div>
                <div
                  v-if="r.parent_request_id"
                  class="cell-line2 parent-id parent-id-clickable"
                  :title="t('requests.list.table.parentJumpTitle', { id: r.parent_request_id })"
                  @click="jumpToParent(r)"
                >
                  ← {{ r.parent_request_id.slice(0, 8) }}
                </div>
              </template>
              <template v-else>
                <span class="cell-line1 muted">—</span>
              </template>
            </td>
            <td class="col-status" :style="{ color: statusColor(r) }" :title="statusTitle(r)">
              <div class="cell-line1">{{ statusLabel(r) }}</div>
              <div v-if="r.error_kind && r.request_status === 'failure'" class="cell-line2">{{ r.error_kind }}</div>
            </td>
            <td class="col-attachments" style="text-align:center">
              <span
                v-if="r.has_attachments && r.attachment_count && r.attachment_count > 0"
                class="attachment-badge"
                :title="t('requests.list.table.attachmentCountTitle', { n: r.attachment_count })"
              >
                📎 {{ r.attachment_count }}
              </span>
              <span v-else style="color:var(--muted)">—</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div v-if="!loading && total > 0" class="pagination-bar">
      <div class="pagination-info">
        <span>{{ t('requests.list.pagination.total', { n: total }) }}</span>
        <span>{{ t('requests.list.pagination.pageInfo', { page, totalPages: Math.max(1, Math.ceil(total / pageSize)) }) }}</span>
        <span class="pagination-divider">·</span>
        <span class="page-size-label">{{ t('requests.list.pagination.pageSize') }}</span>
        <select v-model.number="pageSize" @change="resetPageAndLoad" class="page-size-select">
          <option :value="50">50</option>
          <option :value="100">100</option>
          <option :value="200">200</option>
          <option :value="500">500</option>
        </select>
      </div>
      <div class="pagination-controls">
        <button class="btn btn-ghost btn-sm" :disabled="page <= 1" @click="changePage(-1)">{{ t('requests.list.pagination.previous') }}</button>
        <button class="btn btn-ghost btn-sm" :disabled="page >= Math.ceil(total / pageSize)" @click="changePage(1)">{{ t('requests.list.pagination.next') }}</button>
      </div>
    </div>

    <!-- Detail Modal -->
    <div v-if="detailVisible" class="drawer-backdrop" @click="closeDetail">
      <div class="drawer-panel card drawer-panel-wide" @click.stop>
        <div class="drawer-header">
          <h3 style="margin:0">{{ t('requests.detail.inlineDrawerTitle') }}</h3>
          <button class="btn btn-sm" @click="closeDetail">{{ t('requests.common.close') }}</button>
        </div>

        <div v-if="detailLoading" style="text-align:center;padding:40px">{{ t('requests.common.loading') }}</div>

        <template v-else-if="detail">
          <div class="drawer-section">
            <div style="display:flex;gap:16px;flex-wrap:wrap;margin-bottom:12px;font-size:12px">
              <span><strong>{{ t('requests.detail_extra.requestId') }}:</strong> {{ detail.request_id }}</span>
              <span><strong>{{ t('requests.detail_extra.session') }}:</strong> {{ detail.gw_session_id ?? '—' }}</span>
              <span><strong>{{ t('requests.detail_extra.task') }}:</strong> {{ detail.gw_task_id ?? '—' }}</span>
              <span><strong>{{ t('requests.detail_extra.apiKeyPrefix') }}:</strong> {{ detail.api_key_prefix ?? (detail.api_key_id != null ? t('requests.detail_extra.apiKeyIdPrefix') + detail.api_key_id : t('requests.detail_extra.noKey')) }}</span>
              <span v-if="detail.api_key_owner_user"><strong>{{ t('requests.detail_extra.keyUser') }}:</strong> {{ detail.api_key_owner_user }}</span>
              <span v-if="detail.application_code"><strong>{{ t('requests.detail_extra.application') }}:</strong> {{ detail.application_code }}</span>
              <span><strong>{{ t('requests.detail_extra.time') }}:</strong> {{ fmtTs(detail.ts) }}</span>
              <span><strong>{{ t('requests.detail_extra.clientModel') }}:</strong> {{ detail.client_model ?? '—' }}</span>
              <span :title="outboundModelTitle(detail)"><strong>{{ t('requests.detail_extra.outboundModel') }}:</strong> {{ outboundModelDisplay(detail) }}</span>
              <span><strong>{{ t('requests.detail_extra.provider') }}:</strong> {{ detail.provider_name ?? '—' }}</span>
              <span><strong>{{ t('requests.detail_extra.status') }}:</strong> <span :style="{ color: detail.success ? 'var(--success)' : 'var(--danger)' }">{{ detail.success ? t('requests.detail_extra.success') : statusLabel(detail) }}</span></span>
              <span v-if="detail.failure_stage"><strong>{{ t('requests.detail_extra.failureStage') }}:</strong> {{ detail.failure_stage }}</span>
              <span v-if="detail.failure_detail_code">
                <strong>{{ t('requests.detail_extra.failureDetail') }}:</strong>
                {{ FAILURE_DETAIL_LABELS[detail.failure_detail_code] ?? detail.failure_detail_code }}
              </span>
              <!-- 2026-06-19 T-NEW-7: surface the upstream finish_reason
                   separately from failure_detail_code so a successful
                   `tool_calls` response stops looking like a failure. -->
              <span v-if="detail.upstream_finish_reason" :title="t('requests.detail_extra.finishReasonTitle')">
                <strong>{{ t('requests.detail_extra.finishReason') }}:</strong>
                {{ upstreamFinishReasonLabel(detail.upstream_finish_reason) }}
              </span>
              <span><strong>{{ t('requests.detail_extra.latency') }}:</strong> {{ detail.latency_ms ?? '—' }}ms</span>
              <span><strong>Token:</strong> {{ token(detail.prompt_tokens) }} / {{ token(detail.completion_tokens) }}</span>
              <span v-if="!isDefaultTenant()"><strong>{{ t('requests.detail_extra.creditsUsed') }}:</strong> {{ creditsDisplay(detail.credits_charged) }}</span>
              <!-- v3 (2026-06-19) session-level outbound metadata.
                   Displayed when v3 ran for this request (compression_strategy
                   in {delta_append, sliding_window_*, mechanical_trim}). -->
              <template v-if="hasOutboundBody(detail)">
                <div style="display:flex;flex-wrap:wrap;gap:8px;padding:6px 10px;background:var(--surface-primary,#16213e);border-radius:6px;margin-top:4px;font-size:12px">
                  <span><strong>{{ t('requests.detail_extra.outboundMsgCount') }}:</strong> {{ detail.outbound_msg_count ?? '—' }}</span>
                  <span><strong>{{ t('requests.detail_extra.outboundTokenEst') }}:</strong> {{ detail.outbound_token_est ?? '—' }}</span>
                  <span v-if="calcSavingDetail(detail).hasSaving" style="color:var(--success,#22c55e);font-weight:600">
                    {{ t('requests.detail_extra.saving') }}: {{ calcSavingDetail(detail).savingStr }}
                  </span>
                  <span v-if="calcSavingDetail(detail).hasSaving" style="color:var(--warning,#f59e0b)">
                    Token: {{ calcSavingDetail(detail).tokenSavingStr }}
                  </span>
                  <span v-if="calcSavingDetail(detail).hasSaving" style="color:var(--text-secondary,#6b7280)">
                    {{ t('requests.detail_extra.msgReduction') }}: {{ calcSavingDetail(detail).msgReductionStr }}
                  </span>
                  <span v-if="outboundSummaryMarker(detail)">
                    <span class="summary-marker-badge" :title="outboundSummaryMarker(detail)">{{ t('requests.detail_extra.containsLlmSummary') }}</span>
                  </span>
                </div>
                <div v-if="detail.compression_strategy" style="margin-top:4px;font-size:11px;color:var(--text-secondary,#6b7280)">
                  {{ compressExplainText(detail) }}
                </div>
              </template>
            </div>
          </div>

          <div class="drawer-section">
            <div style="display:flex;gap:8px;margin-bottom:12px">
              <button class="btn btn-sm" :class="{ 'btn-primary': detailTab === 'request' }" @click="detailTab = 'request'">{{ t('requests.detail_extra.requestMsgsTab') }}</button>
              <!-- v3 outbound tab: only shown when the row has an outbound body. -->
              <button v-if="hasOutboundBody(detail)" class="btn btn-sm" :class="{ 'btn-primary': detailTab === 'outbound' }" @click="detailTab = 'outbound'">
                {{ t('requests.detail_extra.outboundMsgsTab') }}
                <span class="outbound-diff-badge" :class="{ unchanged: outboundEqualsRequest(detail) }">
                  {{ outboundEqualsRequest(detail) ? t('requests.detail_extra.equalsRequest') : `${t('requests.detail_extra.deltaPrefix')}${outboundMsgDelta(detail)}` }}
                </span>
              </button>
              <button class="btn btn-sm" :class="{ 'btn-primary': detailTab === 'response' }" @click="detailTab = 'response'">{{ t('requests.detail_extra.responseTab') }}</button>
              <button
                v-if="detail.has_attachments && detail.attachment_count && detail.attachment_count > 0"
                class="btn btn-sm"
                :class="{ 'btn-primary': detailTab === 'attachments' }"
                @click="detailTab = 'attachments'"
              >
                {{ t('requests.detail_extra.attachmentsTab') }} ({{ detail.attachment_count }})
              </button>
            </div>
          </div>

          <div class="drawer-section" style="flex:1;overflow:auto;border:1px solid var(--border, #333);border-radius:6px;padding:12px;background:var(--surface-secondary, #1a1a2e);font-size:12px">
            <template v-if="detailTab === 'request'">
              <template v-if="extractMessagesFromBody(detail.request_body).length">
                <div v-for="(msg, i) in extractMessagesFromBody(detail.request_body)" :key="i" style="margin-bottom:12px">
                  <div style="margin-bottom:4px">
                    <span :style="{ color: roleColor(msg.role || ''), fontWeight: 600 }">[{{ msg.role || 'unknown' }}]</span>
                  </div>
                  <pre style="margin:0;white-space:pre-wrap;word-break:break-all;max-height:300px;overflow:auto;font-size:11px;line-height:1.5">{{ formatJson(msg.content ?? msg) }}</pre>
                  <div v-if="msg.tool_calls" style="margin-top:6px">
                    <div style="color:var(--muted);font-size:11px;margin-bottom:4px">{{ t('requests.detail.toolCalls') }}</div>
                    <pre v-for="(tc, j) in msg.tool_calls" :key="j" style="margin:0 0 4px;white-space:pre-wrap;word-break:break-all;font-size:11px;padding:4px;background:var(--surface-primary, #16213e);border-radius:4px">{{ formatJson(tc) }}</pre>
                  </div>
                </div>
              </template>
              <div v-else style="color:var(--muted)">{{ t('requests.detail.noRequest') }}</div>
            </template>

            <template v-else-if="detailTab === 'outbound'">
              <!-- v3 outbound body: shows what was actually forwarded to the
                   upstream LLM after delta-append / sliding-window summary. -->
              <div v-if="detail.outbound_body" style="margin-bottom:8px;padding:6px 10px;background:var(--surface-primary, #16213e);border-radius:4px;color:var(--text-secondary);font-size:11px">
                <strong>v3 {{ t('requests.detail_extra.outboundMsgsTab') }}</strong> · {{ t('requests.detail_extra.outboundMsgCount') }} {{ detail.outbound_msg_count }} · {{ t('requests.detail_extra.outboundTokenEstLabel', { n: detail.outbound_token_est }) }}
                <span v-if="outboundSummaryMarker(detail)" class="outbound-marker-gap">
                  <span class="summary-marker-badge">{{ truncate(outboundSummaryMarker(detail), 24) }}</span>
                  <span style="color:var(--muted);font-size:10px">{{ t('requests.detail_extra.containsSummaryMarker') }}</span>
                </span>
              </div>
              <template v-if="hasOutboundBody(detail)">
                <div v-for="(msg, i) in extractMessagesFromBody(detail.outbound_body)" :key="i" style="margin-bottom:12px">
                  <div style="margin-bottom:4px">
                    <span :style="{ color: roleColor(msg.role || ''), fontWeight: 600 }">[{{ msg.role || 'unknown' }}]</span>
                    <span v-if="isSummaryMarkerMessage(msg)" class="summary-marker-label">{{ t('requests.detail_extra.summaryMarkerBadge') }}</span>
                  </div>
                  <pre style="margin:0;white-space:pre-wrap;word-break:break-all;max-height:300px;overflow:auto;font-size:11px;line-height:1.5">{{ formatJson(msg.content ?? msg) }}</pre>
                  <div v-if="msg.tool_calls" style="margin-top:6px">
                    <div style="color:var(--muted);font-size:11px;margin-bottom:4px">{{ t('requests.detail.toolCalls') }}</div>
                    <pre v-for="(tc, j) in msg.tool_calls" :key="j" style="margin:0 0 4px;white-space:pre-wrap;word-break:break-all;font-size:11px;padding:4px;background:var(--surface-primary, #16213e);border-radius:4px">{{ formatJson(tc) }}</pre>
                  </div>
                </div>
              </template>
              <div v-else style="color:var(--muted)">{{ t('requests.detail_extra.noOutbound') }}</div>
            </template>

            <template v-else-if="detailTab === 'attachments'">
              <div v-if="attachmentsLoading" style="text-align:center;padding:20px;color:var(--muted)">{{ t('requests.detail_extra.attachmentsLoading') }}</div>
              <div v-else-if="attachments.length === 0" style="text-align:center;padding:20px;color:var(--muted)">{{ t('requests.detail_extra.noAttachments') }}</div>
              <div v-else style="display:flex;flex-direction:column;gap:12px">
                <div
                  v-for="attachment in attachments"
                  :key="attachment.id"
                  class="attachment-item"
                >
                  <div style="display:flex;align-items:center;gap:12px">
                    <div v-if="attachment.media_type.startsWith('image/')" style="flex-shrink:0">
                      <img
                        :src="attachment.download_url"
                        :alt="attachment.id"
                        :title="t('requests.detail_extra.clickToPreviewTitle')"
                        style="width:80px;height:80px;object-fit:cover;border-radius:4px;border:1px solid var(--border,#333);cursor:zoom-in;transition:transform .15s ease"
                        @click="openImagePreview(attachment)"
                        @mouseover="(e) => ((e.currentTarget as HTMLImageElement).style.transform = 'scale(1.03)')"
                        @mouseleave="(e) => ((e.currentTarget as HTMLImageElement).style.transform = 'scale(1)')"
                        @error="(e) => ((e.currentTarget as HTMLImageElement).style.display = 'none')"
                      />
                    </div>
                    <div style="flex:1;min-width:0">
                      <div style="font-weight:600;margin-bottom:4px;word-break:break-all">{{ attachment.id }}</div>
                      <div style="font-size:11px;color:var(--muted);display:flex;gap:12px;flex-wrap:wrap">
                        <span>{{ t('requests.common.typeLabel') }}: {{ attachment.media_type }}</span>
                        <span>{{ t('requests.common.sizeLabel') }}: {{ formatBytes(attachment.file_size) }}</span>
                        <span>{{ t('requests.common.hashLabel') }}: {{ attachment.content_hash.substring(0, 12) }}...</span>
                      </div>
                      <div style="font-size:10px;color:var(--muted);margin-top:2px">
                        {{ t('requests.common.createdAtLabel') }}: {{ fmtTs(attachment.created_at) }}
                      </div>
                    </div>
                    <div style="flex-shrink:0">
                      <a
                        :href="attachment.download_url"
                        target="_blank"
                        class="btn btn-sm"
                        :download="attachment.id"
                      >
                        {{ t('requests.detail_extra.download') }}
                      </a>
                    </div>
                  </div>
                </div>
              </div>
            </template>

            <template v-else>
              <template v-if="detail.response_body">
                <template v-if="detail.response_body.choices">
                  <div v-for="(choice, i) in detail.response_body.choices" :key="i" style="margin-bottom:12px">
                    <div style="margin-bottom:4px">
                      <span style="font-weight:600">Choice {{ i }}</span>
                      <span v-if="choice.finish_reason" class="choice-finish-reason">finish: {{ choice.finish_reason }}</span>
                    </div>
                    <div v-if="choice.message" style="margin-bottom:6px">
                      <span :style="{ color: roleColor(choice.message.role || ''), fontWeight: 600 }">[{{ choice.message.role || 'unknown' }}]</span>
                      <pre v-if="choice.message.content" style="margin:4px 0;white-space:pre-wrap;word-break:break-all;max-height:300px;overflow:auto;font-size:11px;line-height:1.5">{{ choice.message.content }}</pre>
                      <div v-if="choice.message.tool_calls" style="margin-top:6px">
                        <div style="color:var(--muted);font-size:11px;margin-bottom:4px">{{ t('requests.detail.toolCalls') }}</div>
                        <pre v-for="(tc, j) in choice.message.tool_calls" :key="j" style="margin:0 0 4px;white-space:pre-wrap;word-break:break-all;font-size:11px;padding:4px;background:var(--surface-primary, #16213e);border-radius:4px">{{ formatJson(tc) }}</pre>
                      </div>
                    </div>
                  </div>
                  <div v-if="detail.response_body.usage" style="margin-top:8px;padding:8px;background:var(--surface-primary, #16213e);border-radius:4px">
                    <strong>Usage:</strong> prompt={{ detail.response_body.usage.prompt_tokens }} completion={{ detail.response_body.usage.completion_tokens }} total={{ detail.response_body.usage.total_tokens }}
                  </div>
                </template>
                <pre v-else style="white-space:pre-wrap;word-break:break-all;font-size:11px;line-height:1.5">{{ formatJson(detail.response_body) }}</pre>
              </template>
              <div v-else style="color:var(--muted)">{{ t('requests.detail.noStreamContent') }}</div>
            </template>
          </div>
        </template>
      </div>
    </div>

    <!-- 2026-07-02: image preview lightbox. Rendered as a sibling of the
         detail drawer so it can overlay the entire viewport regardless
         of where the originating click came from. ESC and backdrop
         click both close it. -->
    <Teleport to="body">
      <div
        v-if="previewAttachment"
        class="image-preview-backdrop"
        @click="closeImagePreview"
        style="position:fixed;inset:0;background:rgba(0,0,0,0.85);display:flex;align-items:center;justify-content:center;z-index:9999;backdrop-filter:blur(4px)"
      >
        <div
          class="image-preview-modal"
          @click.stop
          style="position:relative;max-width:92vw;max-height:92vh;display:flex;flex-direction:column;align-items:center;gap:12px;background:var(--card,#1e1e1e);padding:16px;border-radius:8px;box-shadow:0 8px 32px rgba(0,0,0,0.6)"
        >
          <img
            :src="previewAttachment.download_url"
            :alt="previewAttachment.id"
            :style="{
              maxWidth: '90vw',
              maxHeight: '80vh',
              objectFit: 'contain',
              borderRadius: '4px',
              background: '#000',
            }"
          />
          <div style="display:flex;align-items:center;gap:16px;color:var(--muted,#aaa);font-size:12px;flex-wrap:wrap;justify-content:center">
            <span style="color:var(--fg,#eee);font-weight:600;word-break:break-all">{{ previewAttachment.id }}</span>
            <span>{{ t('requests.common.typeLabel') }}: {{ previewAttachment.media_type }}</span>
            <span>{{ t('requests.common.sizeLabel') }}: {{ formatBytes(previewAttachment.file_size) }}</span>
            <span>{{ t('requests.common.hashLabel') }}: {{ previewAttachment.content_hash.substring(0, 16) }}...</span>
            <a
              :href="previewAttachment.download_url"
              target="_blank"
              class="btn btn-sm"
              :download="previewAttachment.id"
            >{{ t('requests.detail_extra.downloadOriginal') }}</a>
            <button class="btn btn-sm" @click="closeImagePreview">{{ t('requests.detail_extra.closePreview') }}</button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.request-log-row {
  cursor: pointer;
}
.request-log-row:hover td {
  background: color-mix(in srgb, var(--accent, #3b82f6) 8%, transparent);
}
.request-log-row.row-failure td {
  background: color-mix(in srgb, var(--danger, #ef4444) 4%, transparent);
}
.request-log-table th,
.request-log-table td {
  padding: 5px 7px;
  vertical-align: top;
}
.col-seq {
  width: 2.2rem;
  color: var(--muted);
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.col-time {
  width: 4.8rem;
  white-space: nowrap;
}
.col-trace {
  min-width: 9rem;
  max-width: 14rem;
  cursor: pointer;
}
.col-caller {
  min-width: 7rem;
  max-width: 11rem;
}
.col-route {
  min-width: 9rem;
  max-width: 16rem;
}
.col-tokens {
  min-width: 8.5rem;
  white-space: nowrap;
  font-variant-numeric: tabular-nums;
}
.col-credits {
  min-width: 4.5rem;
  white-space: nowrap;
  font-variant-numeric: tabular-nums;
}
.col-lat {
  width: 4.5rem;
  white-space: nowrap;
}
.col-status {
  min-width: 4.5rem;
  max-width: 7rem;
}
.col-attachments {
  width: 3.5rem;
  text-align: center;
  white-space: nowrap;
}
.attachment-badge {
  font-size: 11px;
  color: var(--accent, #3b82f6);
  cursor: pointer;
  display: inline-block;
  padding: 2px 4px;
  border-radius: 3px;
  background: rgba(59, 130, 246, 0.1);
}
.attachment-badge:hover {
  background: rgba(59, 130, 246, 0.2);
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
}
.cell-clip {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 100%;
}
.trace-link {
  color: var(--accent, #3b82f6);
  cursor: pointer;
  font-size: 11px;
}
.trace-link:hover {
  text-decoration: underline;
}
.trace-sub {
  color: var(--muted);
  margin-top: 2px;
  font-size: 10px;
  cursor: pointer;
}
.trace-sub:hover {
  color: var(--accent, #3b82f6);
  text-decoration: underline;
}
.trace-full {
  white-space: normal;
  word-break: break-all;
  overflow-wrap: anywhere;
}
.trace-summary {
  border-inline-start: 3px solid var(--accent, #3b82f6);
}

.compress-table-head {
  text-align: start;
  padding: 3px 6px;
  border: 1px solid var(--border, #444);
  background: var(--surface-primary, #16213e);
}
.compress-table-head--nowrap {
  white-space: nowrap;
}

.trace-clear-btn {
  margin-inline-start: auto;
}

.summary-key-points {
  margin: 8px 0 0;
  padding-inline-start: 18px;
}

.outbound-marker-gap {
  margin-inline-start: 8px;
}

.summary-marker-label {
  margin-inline-start: 6px;
  font-size: 10px;
  color: #1d4ed8;
}

.choice-finish-reason {
  color: var(--muted);
  margin-inline-start: 8px;
}
.tenant-badge {
  display: inline-flex;
  align-items: center;
  padding: 4px 10px;
  border-radius: 12px;
  font-size: 12px;
  font-weight: 500;
  background: var(--surface-secondary, #f3f4f6);
  color: var(--text-secondary, #6b7280);
}
.tenant-badge--admin {
  background: rgba(59, 130, 246, 0.1);
  color: #3b82f6;
}
.tenant-badge--default {
  background: rgba(34, 197, 94, 0.1);
  color: #22c55e;
}

/* Round 47 compression v7: parent-child chain badge. */
.compression-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 3px 8px;
  border-radius: 10px;
  font-size: 11px;
  font-weight: 500;
  white-space: nowrap;
  background: var(--surface-secondary, #f3f4f6);
  color: var(--text-primary, #111827);
}
.compression-badge .badge-sep {
  color: var(--text-secondary, #9ca3af);
}
.compression-badge.strategy-mechanical_trim {
  background: rgba(245, 158, 11, 0.1);
  color: #b45309;
}
.compression-badge.strategy-memora_l1_inject {
  background: rgba(139, 92, 246, 0.1);
  color: #6d28d9;
}
.compression-badge.strategy-llm_summary {
  background: rgba(59, 130, 246, 0.1);
  color: #1d4ed8;
}
.compression-badge.strategy-noop {
  background: rgba(107, 114, 128, 0.1);
  color: #4b5563;
}
/* v3 (2026-06-19) session-level compression strategies.
   Different color palette from v7 to make them visually distinguishable
   in the logs table. */
.compression-badge.strategy-delta_append {
  background: rgba(20, [SERVER], 166, 0.12);
  color: #0f766e;
  border: 1px solid rgba(20, [SERVER], 166, 0.3);
}
.compression-badge.strategy-sliding_window_token,
.compression-badge.strategy-sliding_window_count,
.compression-badge.strategy-sliding_window_idle {
  background: rgba(168, 85, 247, 0.12);
  color: #7e22ce;
  border: 1px solid rgba(168, 85, 247, 0.3);
}
.col-compress {
  max-width: 180px;
  min-width: 120px;
}
/* v3 Outbound tab — highlight when outbound differs from request. */
.outbound-diff-badge {
  display: inline-block;
  padding: 1px 6px;
  border-radius: 6px;
  font-size: 10px;
  font-weight: 500;
  margin-inline-start: 6px;
  background: rgba(20, [SERVER], 166, 0.1);
  color: #0f766e;
}
.outbound-diff-badge.unchanged {
  background: rgba(107, 114, 128, 0.08);
  color: #6b7280;
}
.summary-marker-badge {
  display: inline-block;
  padding: 1px 6px;
  border-radius: 6px;
  font-size: 10px;
  font-weight: 500;
  margin-inline-start: 6px;
  background: rgba(59, 130, 246, 0.1);
  color: #1d4ed8;
  font-family: var(--mono-font, ui-monospace, monospace);
}
.parent-id {
  color: var(--text-secondary, #6b7280);
  font-size: 10px;
  margin-top: 2px;
  font-family: var(--mono-font, ui-monospace, monospace);
}
.parent-id-clickable {
  cursor: pointer;
  color: var(--accent, #3b82f6);
}
.parent-id-clickable:hover {
  text-decoration: underline;
}
.cell-line1.muted {
  color: var(--text-secondary, #9ca3af);
}
.pagination-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-top: 12px;
  padding: 8px 12px;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  flex-wrap: nowrap;
}
.pagination-info {
  display: flex;
  align-items: center;
  gap: 10px;
  color: var(--muted);
  font-size: 12px;
  flex-wrap: nowrap;
  white-space: nowrap;
  flex-shrink: 0;
  min-width: 0;
}
.pagination-controls {
  display: flex;
  gap: 8px;
  flex-wrap: nowrap;
  flex-shrink: 0;
}
.page-size-select {
  width: auto;
  min-width: 0;
  max-width: 96px;
  padding: 2px 6px;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 4px;
  color: var(--text);
  font-size: 12px;
}
.page-size-label {
  color: var(--muted);
  font-size: 12px;
}
.pagination-divider {
  color: var(--muted);
  opacity: 0.6;
}
@media (max-width: 720px) {
  .pagination-bar {
    flex-wrap: wrap;
  }
  .pagination-info,
  .pagination-controls {
    width: 100%;
    justify-content: space-between;
  }
}

/* v3 compression savings text in the table compression column */
.cell-line2.saving-text {
  font-size: 10px;
  color: var(--success, #22c55e);
  margin-top: 2px;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.cell-line2.saving-text .saving-token {
  color: var(--warning, #f59e0b);
}

/* Compression guide card in-page styling */
.compression-guide-card code {
  font-size: 10px;
  padding: 1px 4px;
  border-radius: 3px;
  background: var(--surface-primary, #16213e);
}

/* Attachment styles */
.attachment-item {
  padding: 12px;
  border: 1px solid var(--border, #333);
  border-radius: 6px;
  background: var(--surface-primary, #16213e);
}
.attachment-item:hover {
  background: var(--surface-secondary, #1a1a2e);
}
</style>

