import { req } from './_core'

// tuning.ts — v6.0 audit T12 (2026-06-22)
// Auto-route analytics + admin tuning surfaces. The auto-router
// evaluates different routing strategies (Phase 5) and A/B-tests them
// against a baseline; the endpoints here surface the verdict, per-
// strategy correlation breakdowns, and admin overrides (pin/ban
// a model for a given task_type × profile combo).
//
// Data Lifecycle endpoints (hot/warm/cold/expired data + cleanup
// preview) live at the bottom of this file because they share the
// "admin observability" theme.

export interface StrategySummaryRow {
  strategy: string
  total: number
  avg_quality: number
  avg_success: number
  avg_latency: number
  avg_cost: number
  drift_rate: number
}

export interface StrategyBreakdownRow {
  strategy: string
  task_type: string
  total: number
  avg_quality: number
  avg_success: number
}

export interface StrategyResponse {
  window_days: number
  summary: StrategySummaryRow[]
  breakdown: StrategyBreakdownRow[]
  ab_verdict: 'pattern_layered_wins' | 'baseline_heuristic_wins' | 'no_significant_difference' | 'insufficient_samples' | 'ab_test_disabled'
  ab_enabled: boolean
  ab_baseline_pct: number
  generated_at: string
}

export function getTuningStrategies(days = 7) {
  return req<StrategyResponse>('GET',
    `/api/admin/auto-route/tuning/strategies?days=${days}`)
}

export interface CorrelationRow {
  label: string
  samples: number
  success_rate: number
  avg_latency_ms: number
  avg_cost_usd: number
  avg_quality?: number
}

export interface CorrelationRowMT {
  model: string
  task_type: string
  samples: number
  success_rate: number
  avg_latency_ms: number
  avg_cost_usd: number
}

export interface CorrelationVerdict {
  task_type: string
  model: string
  success_rate: number
  avg_latency_ms: number
  rank: number
}

export interface AutoRouteCorrelationsResponse {
  window_days: number
  by_model: CorrelationRow[]
  by_strategy: CorrelationRow[]
  by_task_type: CorrelationRow[]
  by_model_task: CorrelationRowMT[]
  verdict: CorrelationVerdict[]
  generated_at: string
}

export function getAutoRouteCorrelations(params: {
  days?: number
  min_samples?: number
} = {}) {
  const q = new URLSearchParams()
  if (params.days) q.set('days', String(params.days))
  if (params.min_samples) q.set('min_samples', String(params.min_samples))
  const path = '/api/admin/auto-route/correlations' + (q.toString() ? '?' + q : '')
  return req<AutoRouteCorrelationsResponse>('GET', path)
}

export interface RoutingOverride {
  id: number
  task_type: string
  profile: string
  mode: 'pin' | 'ban'
  model_chosen?: string
  reason: string
  created_by?: string
  expires_at?: string
  created_at: string
  updated_at: string
}

export interface RoutingOverridesResponse {
  overrides: RoutingOverride[]
  count: number
  filter: { task_type: string; profile: string; active: string }
}

export interface RoutingOverrideCreate {
  task_type: string
  profile?: string
  mode: 'pin' | 'ban'
  model_chosen?: string
  reason: string
  expires_at?: string
}

export function getRoutingOverrides(params: {
  active?: boolean
  task_type?: string
  profile?: string
} = {}) {
  const q = new URLSearchParams()
  if (params.active) q.set('active', 'true')
  if (params.task_type) q.set('task_type', params.task_type)
  if (params.profile) q.set('profile', params.profile)
  const path = '/api/admin/routing/overrides' + (q.toString() ? '?' + q : '')
  return req<RoutingOverridesResponse>('GET', path)
}

export function createRoutingOverride(body: RoutingOverrideCreate) {
  return req<{ id: number; status: string; message: string }>('POST',
    '/api/admin/routing/overrides', body)
}

export function deleteRoutingOverride(id: number) {
  return req<{ id: number; status: string; note: string }>('DELETE',
    `/api/admin/routing/overrides/${id}`)
}

export function extendRoutingOverride(id: number, expires_at: string | null) {
  return req<{ id: number; status: string }>('PATCH',
    `/api/admin/routing/overrides/${id}/extend`, { expires_at })
}

export interface QualityCorrelationRow {
  bucket: string
  samples: number
  success_rate: number
  avg_latency_ms: number
  avg_quality: number
  avg_cost_usd: number
}

export interface QualityCorrelationInsight {
  predictor: 'prompt_length' | 'tools' | 'images' | 'code_block'
  buckets: number
  samples: number
  correlation: number
  abs_r: number
  interpretation: string
}

export interface QualityCorrelationResponse {
  window_days: number
  by: string
  breakdown: QualityCorrelationRow[]
  insights: QualityCorrelationInsight[]
  generated_at: string
}

export function getQualityCorrelations(params: {
  days?: number
  by?: 'prompt_length' | 'tools' | 'images' | 'code_block'
} = {}) {
  const q = new URLSearchParams()
  if (params.days) q.set('days', String(params.days))
  if (params.by) q.set('by', params.by)
  const path = '/api/admin/auto-route/quality-correlations' + (q.toString() ? '?' + q : '')
  return req<QualityCorrelationResponse>('GET', path)
}

export interface RoutingAuditEntry {
  id: number
  ts: string
  action: 'insert' | 'update' | 'delete'
  override_id?: number
  task_type?: string
  profile?: string
  mode?: string
  model_chosen?: string
  reason?: string
  expires_at?: string
  old_expires_at?: string
  actor?: string
}

export interface RoutingAuditResponse {
  entries: RoutingAuditEntry[]
  count: number
  filter: { action: string; actor: string; override_id: string; days: string }
}

export function getRoutingAudit(params: {
  action?: 'insert' | 'update' | 'delete' | ''
  actor?: string
  override_id?: number
  days?: number
  limit?: number
} = {}) {
  const q = new URLSearchParams()
  if (params.action) q.set('action', params.action)
  if (params.actor) q.set('actor', params.actor)
  if (params.override_id) q.set('override_id', String(params.override_id))
  if (params.days) q.set('days', String(params.days))
  if (params.limit) q.set('limit', String(params.limit))
  const path = '/api/admin/routing/overrides/audit' + (q.toString() ? '?' + q : '')
  return req<RoutingAuditResponse>('GET', path)
}

// ── Data Lifecycle Management API ─────────────────────────────────────────

export interface DataSegment {
  rows: number
  size_bytes: number
  size_human: string
  days: number
  percent_of_total: number
}

export interface TenantDataStats {
  tenant_id: string
  rows: number
  size_bytes: number
  size_human: string
}

export interface DailyGrowth {
  date: string
  requests: number
  compressed: number
  compression_rate: number
}

export interface DataLifecycleStatsResponse {
  total_rows: number
  total_size_bytes: number
  total_size_human: string
  hot_data: DataSegment | null
  warm_data: DataSegment | null
  cold_data: DataSegment | null
  expired_data: DataSegment | null
  by_tenant: TenantDataStats[]
  growth_trend: DailyGrowth[]
}

export function dataLifecycleStats() {
  return req<DataLifecycleStatsResponse>('GET', '/api/admin/data-lifecycle/stats')
}

export interface CleanupPreviewResponse {
  affected_rows: number
  estimated_freed_bytes: number
  estimated_freed_human: string
  warning_message?: string
}

export function dataLifecycleCleanupPreview(
  action: string,
  from: string,
  to: string
) {
  return req<CleanupPreviewResponse>('POST', '/api/admin/data-lifecycle/cleanup/preview', {
    action,
    from,
    to
  })
}

export interface DataLifecycleMetricsResponse {
  total_rows: number
  total_size_bytes: number
  hot_data_rows: number
  hot_data_size_bytes: number
  warm_data_rows: number
  warm_data_size_bytes: number
  cold_data_rows: number
  cold_data_size_bytes: number
  expired_data_rows: number
  expired_data_size_bytes: number
  last_cleanup_at?: string
  last_archive_at?: string
}

export function dataLifecycleMetrics() {
  return req<DataLifecycleMetricsResponse>('GET', '/api/admin/data-lifecycle/metrics')
}

// ── Storage management (2026-07-02 V2.3.3) ─────────────────────────────
//
// Endpoints mounted by admin/storage_stats.go + admin/attachments_cleanup.go
// + admin/logs_cleanup.go:
//
//   GET  /api/admin/data-lifecycle/storage-stats       — disk + DB + attachments + logs
//   POST /api/admin/data-lifecycle/cleanup-attachments — {dry_run,older_than_days,orphaned_only}
//   POST /api/admin/data-lifecycle/cleanup-logs        — {dry_run,older_than_days,compressed_only}
//   POST /api/admin/data-lifecycle/config              — LifecycleConfig JSON
//   POST /api/admin/data-lifecycle/log-config          — {max_size_mb,max_backups,max_age_days,compress}

export interface DiskStats {
  total_bytes: number
  used_bytes: number
  available_bytes: number
  usage_percent: number
  mount_path: string
  filesystem: string
}

export interface TableSizeInfo {
  table_name: string
  size_bytes: number
  size_human: string
  row_count?: number
}

export interface DatabaseStats {
  total_size_bytes: number
  total_size_human: string
  request_logs_bytes: number
  request_logs_human: string
  attachments_meta_bytes: number
  attachments_meta_human: string
  other_tables_bytes: number
  other_tables_human: string
  table_sizes?: TableSizeInfo[]
}

export interface MediaTypeStats {
  media_type: string
  count: number
  size_bytes: number
  size_human: string
}

export interface AttachmentStorageStats {
  storage_path: string
  total_files: number
  total_size_bytes: number
  total_size_human: string
  by_media_type: MediaTypeStats[]
  orphaned_files?: number
}

export interface LogFileInfo {
  name: string
  path: string
  size_bytes: number
  size_human: string
  modified_at: string
  is_compressed: boolean
  is_active: boolean
}

export interface LogConfig {
  file: string
  max_size_mb: number
  max_backups: number
  max_age_days: number
  compress: boolean
}

export interface LogFilesStorageStats {
  log_directory: string
  total_files: number
  total_size_bytes: number
  total_size_human: string
  active_log_file?: LogFileInfo
  rotated_files: LogFileInfo[]
  config: LogConfig
}

export interface LifecycleConfig {
  retention_days: number
  auto_cleanup_enabled: boolean
  cleanup_schedule: string
  last_cleanup_at?: string
  attachment_storage_path: string
  max_attachment_size_mb: number
}

export interface StorageStatsResponse {
  disk: DiskStats | null
  database: DatabaseStats | null
  attachments_storage: AttachmentStorageStats | null
  log_files_storage: LogFilesStorageStats | null
  lifecycle_config: LifecycleConfig | null
}

export function getStorageStats() {
  return req<StorageStatsResponse>('GET', '/api/admin/data-lifecycle/storage-stats')
}

export interface CleanupAttachmentsRequest {
  dry_run: boolean
  older_than_days: number
  orphaned_only: boolean
}

export interface CleanupAttachmentsResponse {
  affected_files: number
  affected_db_rows: number
  estimated_freed_bytes: number
  estimated_freed_human: string
  orphaned_files: number
  orphaned_size_bytes: number
  warning_message?: string
  executed_at?: string
}

export function cleanupAttachments(req: CleanupAttachmentsRequest) {
  return req<CleanupAttachmentsResponse>(
    'POST',
    '/api/admin/data-lifecycle/cleanup-attachments',
    req
  )
}

export interface CleanupLogsRequest {
  dry_run: boolean
  older_than_days: number
  compressed_only: boolean
}

export interface CleanupLogsResponse {
  affected_files: number
  estimated_freed_bytes: number
  estimated_freed_human: string
  warning_message?: string
  executed_at?: string
}

export function cleanupLogs(req: CleanupLogsRequest) {
  return req<CleanupLogsResponse>(
    'POST',
    '/api/admin/data-lifecycle/cleanup-logs',
    req
  )
}

export function updateLifecycleConfig(cfg: LifecycleConfig) {
  return req<{ success: boolean; message: string; config: LifecycleConfig }>(
    'POST',
    '/api/admin/data-lifecycle/config',
    cfg
  )
}

export function updateLogConfig(cfg: {
  max_size_mb: number
  max_backups: number
  max_age_days: number
  compress: boolean
}) {
  return req<{ success: boolean; message: string; config: unknown }>(
    'POST',
    '/api/admin/data-lifecycle/log-config',
    cfg
  )
}

// ── Tuning proposals + accuracy (Phase 5) ──────────────────────────────
//
// Three endpoints are mounted by admin/auto_route_tuning.go:
//
//   GET  /api/admin/auto-route/tuning/proposals?status=&category=&limit=
//   POST /api/admin/auto-route/tuning/proposals/:id/approve
//   POST /api/admin/auto-route/tuning/proposals/:id/reject  (body: {reason}?)
//   GET  /api/admin/auto-route/tuning/accuracy?days=
//
// `triggerTuningAnalyze` is currently a frontend-only call: there is no
// matching backend endpoint yet (auto_route_tuning.go mounts 4 routes,
// none of which trigger an ad-hoc analyzer run). The function below
// posts to /tuning/analyze; the existing try/catch in TuningView.vue
// surfaces the 404 as a user-facing alert. When the backend adds the
// trigger endpoint the call will start succeeding.

export type TuningProposalCategory = 'keyword_add' | 'weight_adjust' | 'threshold_change'
export type TuningProposalStatus = 'pending' | 'approved' | 'rejected' | 'applied'

export interface TuningProposal {
  id: number
  ts: string
  category: TuningProposalCategory
  task_type: string | null
  proposal: Record<string, unknown>
  evidence: ProposalEvidence
  status: TuningProposalStatus
  reviewed_by: string | null
  reviewed_at: string | null
  applied_at: string | null
  review_note: string | null
}

// The analyzer writes a different evidence shape per category
// (see bg/feedback_analyzer.go lines 244-249 and 319-324). The
// frontend only renders a few fields in evidenceSummary so we keep
// the optional+typed model: present fields per category, others
// undefined.
export interface ProposalEvidence {
  sample_count?: number
  window_days?: number
  quality_threshold?: number
  actual_success?: number
  predicted_match?: number
  avg_quality?: number
  rationale?: string
  confidence?: number
}

export interface TuningProposalsResponse {
  proposals: TuningProposal[]
  count: number
  filter: { status: string; category: string }
}

export function getTuningProposals(params: {
  status?: TuningProposalStatus | ''
  category?: TuningProposalCategory | ''
  limit?: number
} = {}) {
  const q = new URLSearchParams()
  if (params.status) q.set('status', params.status)
  if (params.category) q.set('category', params.category)
  if (params.limit != null) q.set('limit', String(params.limit))
  const s = q.toString()
  return req<TuningProposalsResponse>('GET', `/api/admin/auto-route/tuning/proposals${s ? '?' + s : ''}`)
}

export function approveTuningProposal(id: number) {
  return req<{ id: number; status: string; message: string }>(
    'POST', `/api/admin/auto-route/tuning/proposals/${id}/approve`
  )
}

export function rejectTuningProposal(id: number, reason?: string) {
  return req<{ id: number; status: string; message: string }>(
    'POST', `/api/admin/auto-route/tuning/proposals/${id}/reject`,
    { reason: reason ?? null }
  )
}

export interface AccuracyBreakdownRow {
  task_type: string
  classifier: string
  total: number
  avg_quality: number
  avg_success: number
  avg_latency: number
  avg_cost: number
  drift_rate: number
}

export interface TuningAccuracyResponse {
  window_days: number
  breakdown: AccuracyBreakdownRow[]
  generated_at: string
}

export function getTuningAccuracy(days = 7) {
  return req<TuningAccuracyResponse>('GET', `/api/admin/auto-route/tuning/accuracy?days=${days}`)
}

export interface TriggerTuningAnalyzeResponse {
  completed_at: string
  triggered_by: string
}

export function triggerTuningAnalyze() {
  // TODO(backend): no matching endpoint in admin/auto_route_tuning.go
  // yet. Post path is a placeholder — when the trigger endpoint lands,
  // update this path to match. Until then the call will 404 and the
  // TuningView.vue catch handler will show the error to the user.
  return req<TriggerTuningAnalyzeResponse>('POST', '/api/admin/auto-route/tuning/analyze')
}