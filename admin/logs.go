package admin

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type requestLogRow struct {
	Ts                 time.Time      `json:"ts"`
	RequestID          string         `json:"request_id"`
	APIKeyID           *int           `json:"api_key_id"`
	EndUserID          *string        `json:"end_user_id"`
	ClientModel        *string        `json:"client_model"`
	OutboundModel      *string        `json:"outbound_model"`
	CredentialID       *int           `json:"credential_id"`
	CredentialLabel    *string        `json:"credential_label"`
	ProviderID         *int           `json:"provider_id"`
	ProviderName       *string        `json:"provider_name"`
	ProviderCode       *string        `json:"provider_code"`
	ClientProfile      *string        `json:"client_profile"`
	RequestMode        *string        `json:"request_mode"`
	PromptTokens       *int           `json:"prompt_tokens"`
	CompletionTokens   *int           `json:"completion_tokens"`
	CacheReadTokens    *int           `json:"cache_read_tokens"`
	CacheWriteTokens   *int           `json:"cache_write_tokens"`
	TotalTokens        *int           `json:"total_tokens"`
	CostUSD            *float64       `json:"cost_usd"`
	CostDisplay        *float64       `json:"cost_display"`
	CostCurrency       *string        `json:"cost_currency"`
	LatencyMs          *int           `json:"latency_ms"`
	Success            bool           `json:"success"`
	RequestStatus      string         `json:"request_status"`
	ErrorKind          *string        `json:"error_kind"`
	SearchText         *string        `json:"search_text"`
	IdentityHash       *string        `json:"identity_hash"`
	VirtualClientID    *string        `json:"virtual_client_id"`
	VirtualIP          *string        `json:"virtual_ip"`
	VirtualMAC         *string        `json:"virtual_mac"`
	AffinityHit        *bool          `json:"affinity_hit"`
	RequestChecksum    *string        `json:"request_checksum"`
	ResponseChecksum   *string        `json:"response_checksum"`
	TransformRuleID    *string `json:"transform_rule_id"`
	EgressProtocol     *string `json:"egress_protocol"`
	FailureStage       *string `json:"failure_stage"`
	FailureDetailCode  *string `json:"failure_detail_code"`
	// 2026-06-19 T-NEW-7: the SOLE home for the upstream finish_reason
	// (stop, tool_calls, length, end_turn, function_call, max_tokens, …).
	// Distinct from FailureDetailCode which is now reserved for actual
	// failure / interruption codes.  Populated for BOTH success and
	// failure rows.  See db/migrations/018_upstream_finish_reason.sql.
	UpstreamFinishReason *string `json:"upstream_finish_reason,omitempty"`
	RequestPreview     *string `json:"request_preview"`
	TransformSummary   *string        `json:"transform_summary"`
	ResponsePreview    *string        `json:"response_preview"`
	StreamFirstChunkMs *int           `json:"stream_first_chunk_ms"`
	StreamChunkCount   *int           `json:"stream_chunk_count"`
	StreamDoneReceived *bool          `json:"stream_done_received"`
	StreamInterrupted  *bool          `json:"stream_interrupted"`
	StreamDoneSent     *bool          `json:"stream_done_sent"`
	UsageSource        *string        `json:"usage_source"`
	GwSessionID        *string        `json:"gw_session_id"`
	GwTaskID           *string        `json:"gw_task_id"`
	APIKeyPrefix       *string        `json:"api_key_prefix"`
	APIKeyOwnerUser    *string        `json:"api_key_owner_user"`
	ApplicationCode    *string        `json:"application_code"`
	CanonicalName      *string        `json:"canonical_name"`
	ProviderModel      *string        `json:"provider_model"`
	TraceSeq           *int           `json:"trace_seq,omitempty"`
	CreditsCharged     *int64         `json:"credits_charged"`
	// v3 (2026-06-19) session-level outbound body fields.
	OutboundBody            json.RawMessage `json:"outbound_body,omitempty"`
	OutboundMsgCount        *int            `json:"outbound_msg_count,omitempty"`
	OutboundTokenEst        *int            `json:"outbound_token_est,omitempty"`
	OutboundMsgHashes       json.RawMessage `json:"outbound_msg_hashes,omitempty"`
	CompressionStrategy     *string         `json:"compression_strategy,omitempty"`
	CompressionReason       *string         `json:"compression_reason,omitempty"`
	CompressionMeta         json.RawMessage `json:"compression_meta,omitempty"`
	ParentRequestID         *string         `json:"parent_request_id,omitempty"`
	// 2026-07-01: attachment tracking. has_attachments lets the list UI
	// badge rows that carried images without pulling the heavy
	// request_body. attachment_count is the number archived.
	HasAttachments  *bool `json:"has_attachments,omitempty"`
	AttachmentCount *int  `json:"attachment_count,omitempty"`
}

type requestLogDetail struct {
	requestLogRow
	RequestBody  any `json:"request_body"`
	ResponseBody any `json:"response_body"`
}

// requestLogStatusExpr was the COALESCE fallback expression the read
// path used to compute request_status from rl.success / rl.error_kind
// at query time. After migration 058 (request_status backfill in
// db/db.go + 058_request_logs_status_materialize.sql), every row has
// rl.request_status populated with the canonical label, so the read
// path can read rl.request_status directly.
//
// The constant is kept for backwards compatibility with the existing
// admin/session_title_test.go:TestRequestLogStatusExprRequiresRLAlias
// test, which pins the alias-by-rl convention. The constant is no
// longer referenced in any SQL string in this file.
//
// 2026-06-30: materialized via migration 058.
const requestLogStatusExpr = `rl.request_status`

// requestLogsSelectCols is the FULL projection used by the detail handler
// (getLog). It includes the three large JSONB columns
// (outbound_body, outbound_msg_hashes, compression_meta) which are only
// rendered inside the request-detail dialog.
//
// DO NOT use this projection from the LIST handler — see
// requestLogsListCols and the migration 056 commentary for why.
//
// 2026-06-30: split out requestLogsListCols to keep list responses cheap.
// The original listLogs used this projection directly, but pulled all
// three JSONB blobs over the wire for every page even though the list
// view only displays scalar metadata + the compression_* / parent_*
// pointers. See migration 056 for the EXPLAIN-backed rationale.
const requestLogsSelectCols = `
	rl.ts, rl.request_id, rl.api_key_id, rl.end_user_id,
	rl.client_model, rl.outbound_model,
	rl.credential_id, c.label AS credential_label,
	rl.provider_id, p.display_name AS provider_name,
	p.catalog_code AS provider_code,
	rl.client_profile, rl.request_mode,
	rl.prompt_tokens, rl.completion_tokens,
	rl.cache_read_tokens, rl.cache_write_tokens, rl.total_tokens,
	rl.cost_usd::float8, rl.cost_display::float8, rl.cost_currency, rl.latency_ms, rl.success,
	` + requestLogStatusExpr + ` AS request_status,
	rl.error_kind, rl.search_text,
	rl.identity_hash, rl.virtual_client_id, rl.virtual_ip, rl.virtual_mac,
	rl.affinity_hit, rl.request_checksum, rl.response_checksum,
	rl.transform_rule_id, rl.egress_protocol, rl.failure_stage, rl.failure_detail_code,
	-- 2026-06-19 T-NEW-7: split the semantic overload of failure_detail_code.
	-- New column is the SOLE home for the upstream finish_reason.
	rl.upstream_finish_reason,
	rl.request_preview, rl.transform_summary, rl.response_preview,
	rl.stream_first_chunk_ms, rl.stream_chunk_count,
	rl.stream_done_received, rl.stream_interrupted, rl.stream_done_sent,
	rl.usage_source,
	rl.gw_session_id, rl.gw_task_id,
	COALESCE(NULLIF(TRIM(rl.api_key_prefix), ''), NULLIF(TRIM(ak.key_prefix), '')) AS api_key_prefix,
	COALESCE(NULLIF(TRIM(rl.api_key_owner_user), ''), ak.owner_user) AS api_key_owner_user,
	COALESCE(NULLIF(TRIM(rl.application_code), ''), app.code) AS application_code,
	mc.canonical_name,
	-- 2026-06-30 (migration 057): provider_model is denormalized
	-- onto request_logs and written at INSERT time by
	-- telemetry.ResolveProviderModel. The pre-057 LATERAL has been
	-- removed from requestLogsJoins. NULLIF maps the helper's
	-- empty-string sentinel (no model_offers row matched) to NULL so
	-- the JSON response stays consistent with the old LATERAL path.
	NULLIF(rl.provider_model, '') AS provider_model,
	rl.credits_charged,
	-- v3 (2026-06-19) session-level outbound body fields.
	rl.outbound_body,
	rl.outbound_msg_count,
	rl.outbound_token_est,
	rl.outbound_msg_hashes,
	rl.compression_strategy,
	rl.compression_reason,
	rl.compression_meta,
	rl.parent_request_id,
	rl.has_attachments,
	rl.attachment_count
`

// requestLogsListCols is the projection used by the LIST handler
// (listLogs). It is identical to requestLogsSelectCols EXCEPT that it
// drops the three large JSONB columns — outbound_body,
// outbound_msg_hashes, compression_meta — which the list view never
// renders. Detail dialog fetches them through getLog instead.
//
// Scan order MUST stay in lock-step with scanRequestLogListRowWithTotal
// below.
const requestLogsListCols = `
	rl.ts, rl.request_id, rl.api_key_id, rl.end_user_id,
	rl.client_model, rl.outbound_model,
	rl.credential_id, c.label AS credential_label,
	rl.provider_id, p.display_name AS provider_name,
	p.catalog_code AS provider_code,
	rl.client_profile, rl.request_mode,
	rl.prompt_tokens, rl.completion_tokens,
	rl.cache_read_tokens, rl.cache_write_tokens, rl.total_tokens,
	rl.cost_usd::float8, rl.cost_display::float8, rl.cost_currency, rl.latency_ms, rl.success,
	` + requestLogStatusExpr + ` AS request_status,
	rl.error_kind, rl.search_text,
	rl.identity_hash, rl.virtual_client_id, rl.virtual_ip, rl.virtual_mac,
	rl.affinity_hit, rl.request_checksum, rl.response_checksum,
	rl.transform_rule_id, rl.egress_protocol, rl.failure_stage, rl.failure_detail_code,
	rl.upstream_finish_reason,
	rl.request_preview, rl.transform_summary, rl.response_preview,
	rl.stream_first_chunk_ms, rl.stream_chunk_count,
	rl.stream_done_received, rl.stream_interrupted, rl.stream_done_sent,
	rl.usage_source,
	rl.gw_session_id, rl.gw_task_id,
	COALESCE(NULLIF(TRIM(rl.api_key_prefix), ''), NULLIF(TRIM(ak.key_prefix), '')) AS api_key_prefix,
	COALESCE(NULLIF(TRIM(rl.api_key_owner_user), ''), ak.owner_user) AS api_key_owner_user,
	COALESCE(NULLIF(TRIM(rl.application_code), ''), app.code) AS application_code,
	mc.canonical_name,
	-- 2026-06-30 (migration 057): see requestLogsSelectCols above —
	-- the LATERAL has been removed; we read rl.provider_model
	-- directly. NULLIF maps the helper's empty-string sentinel to NULL.
	NULLIF(rl.provider_model, '') AS provider_model,
	rl.credits_charged,
	-- v3 session-level outbound body fields — SCALAR ones only.
	-- The JSONB blobs (outbound_body / outbound_msg_hashes /
	-- compression_meta) are intentionally dropped; list UI never
	-- renders them and they are fetched by getLog when the user opens
	-- a row's detail panel.
	rl.outbound_msg_count,
	rl.outbound_token_est,
	rl.compression_strategy,
	rl.compression_reason,
	rl.parent_request_id,
	rl.has_attachments,
	rl.attachment_count
`

// requestLogsJoins is the join set used by listLogs + getLog.
//
// 2026-06-30 (migration 057): the LEFT JOIN LATERAL on model_offers
// has been REMOVED. The list handler previously evaluated that LATERAL
// for every row (4-CASE ORDER BY + LIMIT 1) on every page render, and
// was the dominant cost in the EXPLAIN of /api/logs on the default 24h
// window. provider_model is now denormalized onto request_logs
// (column added by 057 + written at INSERT time by
// telemetry.ResolveProviderModel / telemetry.PersistProviderModel).
//
// The four remaining LEFT JOINs are required for SELECT projections
// (provider_name, provider_code, credential_label, api_key_*,
// application_code, canonical_name) and for tenant filtering on
// ak.tenant_id; they are cheap because each is keyed by a single bigint
// (p.id, c.id, ak.id, app.id, mc.id) on a small lookup table.
const requestLogsJoins = `
	LEFT JOIN providers p ON p.id = rl.provider_id
	LEFT JOIN credentials c ON c.id = rl.credential_id
	LEFT JOIN api_keys ak ON ak.id = rl.api_key_id
	LEFT JOIN applications app ON app.id = ak.application_id
	LEFT JOIN models_canonical mc ON mc.id = rl.canonical_id
`

func (h *Handler) handleLogs(w http.ResponseWriter, r *http.Request) {
	if h.db == nil {
		writeError(w, http.StatusServiceUnavailable, "database not configured")
		return
	}
	remaining := r.URL.Path[len("/api/logs/"):]
	if remaining == "" {
		h.listLogs(w, r)
		return
	}
	if remaining == "top-models" {
		h.listTopModels(w, r)
		return
	}
	if remaining == "session-summary" {
		h.handleSessionSummary(w, r)
		return
	}
	if remaining == "session-summary-to-memora" {
		h.handleSessionSummaryToMemora(w, r)
		return
	}
	h.getLog(w, r)
}

func (h *Handler) handleLogsRoot(w http.ResponseWriter, r *http.Request) {
	h.listLogs(w, r)
}

func scanRequestLogRow(rows interface {
	Scan(dest ...any) error
}, withTraceSeq bool) (requestLogRow, error) {
	var l requestLogRow
	dest := []any{
		&l.Ts, &l.RequestID, &l.APIKeyID, &l.EndUserID,
		&l.ClientModel, &l.OutboundModel,
		&l.CredentialID, &l.CredentialLabel,
		&l.ProviderID, &l.ProviderName, &l.ProviderCode,
		&l.ClientProfile, &l.RequestMode,
		&l.PromptTokens, &l.CompletionTokens,
		&l.CacheReadTokens, &l.CacheWriteTokens, &l.TotalTokens,
		&l.CostUSD, &l.CostDisplay, &l.CostCurrency, &l.LatencyMs, &l.Success, &l.RequestStatus, &l.ErrorKind, &l.SearchText,
		&l.IdentityHash, &l.VirtualClientID, &l.VirtualIP, &l.VirtualMAC,
		&l.AffinityHit, &l.RequestChecksum, &l.ResponseChecksum,
		&l.TransformRuleID, &l.EgressProtocol, &l.FailureStage, &l.FailureDetailCode,
		&l.UpstreamFinishReason,
		&l.RequestPreview, &l.TransformSummary, &l.ResponsePreview,
		&l.StreamFirstChunkMs, &l.StreamChunkCount,
		&l.StreamDoneReceived, &l.StreamInterrupted, &l.StreamDoneSent,
		&l.UsageSource,
		&l.GwSessionID, &l.GwTaskID,
		&l.APIKeyPrefix, &l.APIKeyOwnerUser, &l.ApplicationCode,
		&l.CanonicalName, &l.ProviderModel, &l.CreditsCharged,
		// v3 session-level outbound body fields.
		&l.OutboundBody, &l.OutboundMsgCount, &l.OutboundTokenEst, &l.OutboundMsgHashes,
		&l.CompressionStrategy, &l.CompressionReason, &l.CompressionMeta, &l.ParentRequestID,
		// 2026-07-01: attachment tracking.
		&l.HasAttachments, &l.AttachmentCount,
	}
	if withTraceSeq {
		dest = append(dest, &l.TraceSeq)
	}
	err := rows.Scan(dest...)
	return l, err
}

// scanRequestLogListRowWithTotal scans the merged list+count projection
// used by listLogs (see migration 056). It returns the row, the total
// count of WHERE-matching rows, and any scan error.
//
// The merged projection order is:
//
//	requestLogsListCols [, ROW_NUMBER() OVER (ORDER BY rl.ts ASC) AS trace_seq] , COUNT(*) OVER () AS total_count
//
// `total_count` is constant across every row in the result set (it is
// computed BEFORE LIMIT/OFFSET), so the caller reads it from the first
// row only. `trace_seq` only appears when the caller asked for chrono
// mode (gw_session_id/gw_task_id filter or explicit ?chrono=1).
//
// Total_count is returned as `int` rather than `*int` because the window
// function always produces a non-NULL integer.
func scanRequestLogListRowWithTotal(rows interface {
	Scan(dest ...any) error
}, withTraceSeq bool) (requestLogRow, int, error) {
	var l requestLogRow
	var total int
	dest := []any{
		&l.Ts, &l.RequestID, &l.APIKeyID, &l.EndUserID,
		&l.ClientModel, &l.OutboundModel,
		&l.CredentialID, &l.CredentialLabel,
		&l.ProviderID, &l.ProviderName, &l.ProviderCode,
		&l.ClientProfile, &l.RequestMode,
		&l.PromptTokens, &l.CompletionTokens,
		&l.CacheReadTokens, &l.CacheWriteTokens, &l.TotalTokens,
		&l.CostUSD, &l.CostDisplay, &l.CostCurrency, &l.LatencyMs, &l.Success, &l.RequestStatus, &l.ErrorKind, &l.SearchText,
		&l.IdentityHash, &l.VirtualClientID, &l.VirtualIP, &l.VirtualMAC,
		&l.AffinityHit, &l.RequestChecksum, &l.ResponseChecksum,
		&l.TransformRuleID, &l.EgressProtocol, &l.FailureStage, &l.FailureDetailCode,
		&l.UpstreamFinishReason,
		&l.RequestPreview, &l.TransformSummary, &l.ResponsePreview,
		&l.StreamFirstChunkMs, &l.StreamChunkCount,
		&l.StreamDoneReceived, &l.StreamInterrupted, &l.StreamDoneSent,
		&l.UsageSource,
		&l.GwSessionID, &l.GwTaskID,
		&l.APIKeyPrefix, &l.APIKeyOwnerUser, &l.ApplicationCode,
		&l.CanonicalName, &l.ProviderModel, &l.CreditsCharged,
		// v3 session-level outbound body fields — SCALAR only;
		// the JSONB blobs are NOT scanned because they are not in the
		// list projection (see requestLogsListCols).
		&l.OutboundMsgCount, &l.OutboundTokenEst,
		&l.CompressionStrategy, &l.CompressionReason, &l.ParentRequestID,
		// 2026-07-01: attachment tracking.
		&l.HasAttachments, &l.AttachmentCount,
	}
	if withTraceSeq {
		dest = append(dest, &l.TraceSeq)
	}
	// total_count is ALWAYS the last column in the merged list query
	// (see listLogs). Append it last so the scan order stays in sync
	// even when withTraceSeq adds the intermediate trace_seq column.
	dest = append(dest, &total)
	err := rows.Scan(dest...)
	return l, total, err
}

func (h *Handler) listLogs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	now := time.Now().UTC()
	start := parseQueryTime(r, "from", now.Add(-24*time.Hour))
	end := parseQueryTime(r, "to", now)

	page := queryInt(r, "page", 1)
	if page < 1 {
		page = 1
	}
	pageSize := queryInt(r, "page_size", 100)
	if pageSize < 1 {
		pageSize = 100
	}
	if pageSize > 500 {
		pageSize = 500
	}

	clauses := []string{"rl.ts >= $1", "rl.ts <= $2"}
	args := []any{start, end}
	argIdx := 3

	addFilter := func(clause string, val any) {
		clauses = append(clauses, fmt.Sprintf(clause, argIdx))
		args = append(args, val)
		argIdx++
	}

	// tenant_admin callers may only see request logs for their own tenant's
	// api_keys. The join `ak` (LEFT JOIN api_keys ak ON ak.id = rl.api_key_id)
	// is already present in requestLogsJoins, so we can filter on ak.tenant_id.
	if IsTenantAdmin(r) {
		addFilter("ak.tenant_id = $%d", GetTenantID(r))
		addFilter("rl.tenant_id = $%d", GetTenantID(r))
	}
	if v := queryIntPtr(r, "api_key_id"); v != nil {
		addFilter("rl.api_key_id = $%d", *v)
	}
	if v := strings.TrimSpace(queryString(r, "request_id")); v != "" {
		addFilter("rl.request_id = $%d", v)
	}
	if v := queryIntPtr(r, "provider_id"); v != nil {
		addFilter("rl.provider_id = $%d", *v)
	}
	if v := queryIntPtr(r, "credential_id"); v != nil {
		addFilter("rl.credential_id = $%d", *v)
	}
	if v := strings.TrimSpace(queryString(r, "identity_hash")); v != "" {
		addFilter("rl.identity_hash = $%d", v)
	}
	if v := strings.TrimSpace(queryString(r, "q")); v != "" {
		addFilter("rl.search_text ILIKE $%d", "%"+v+"%")
	}
	if v := strings.TrimSpace(queryString(r, "error_kind")); v != "" {
		addFilter("rl.error_kind = $%d", v)
	}
	if v := strings.TrimSpace(queryString(r, "request_status")); v != "" {
		switch v {
		case "in_progress", "success", "failure":
			// 2026-06-30 (migration 058): rl.request_status is now
			// materialized; reading the bare column lets the planner
			// use idx_request_logs_status_ts. We still exclude ''
			// defensively in case a future regression re-introduces
			// empty-string rows (the partial index already filters
			// them out, but the explicit predicate keeps the EXPLAIN
			// plan obvious).
			clauses = append(clauses, fmt.Sprintf("rl.request_status = $%d AND rl.request_status <> ''", argIdx))
			args = append(args, v)
			argIdx++
		default:
			writeError(w, http.StatusBadRequest, "request_status must be 'in_progress', 'success', or 'failure'")
			return
		}
	} else if v := queryOptionalBool(r, "success"); v != nil {
		status := "failure"
		if *v {
			status = "success"
		}
		// 2026-06-30 (migration 058): bare column on rl.request_status.
		clauses = append(clauses, fmt.Sprintf("rl.request_status = $%d AND rl.request_status <> ''", argIdx))
		args = append(args, status)
		argIdx++
	}
	if v := queryIntPtr(r, "canonical_id"); v != nil {
		addFilter("rl.canonical_id = $%d", *v)
	}
	if v := strings.TrimSpace(queryString(r, "model")); v != "" {
		pattern := "%" + v + "%"
		clauses = append(clauses, fmt.Sprintf(`(
			EXISTS (
				SELECT 1 FROM models_canonical mc
				WHERE mc.id = rl.canonical_id
				  AND mc.canonical_name ILIKE $%d
			)
			OR EXISTS (
				SELECT 1
				FROM model_aliases ma
				JOIN models_canonical mc ON mc.id = ma.canonical_id
				WHERE lower(ma.raw_name) = lower(rl.client_model)
				  AND ma.status = 'active'
				  AND mc.canonical_name ILIKE $%d
			)
			OR rl.client_model ILIKE $%d
		)`, argIdx, argIdx+1, argIdx+2))
		args = append(args, pattern, pattern, pattern)
		argIdx += 3
	}
	if v := strings.TrimSpace(queryString(r, "gw_session_id")); v != "" {
		addFilter("rl.gw_session_id = $%d", v)
	}
	if v := strings.TrimSpace(queryString(r, "gw_task_id")); v != "" {
		addFilter("rl.gw_task_id = $%d", v)
	}
	if v := strings.TrimSpace(queryString(r, "usage_source")); v != "" {
		if v != "llm" && v != "estimated" {
			writeError(w, http.StatusBadRequest, "usage_source must be 'llm' or 'estimated'")
			return
		}
		addFilter("rl.usage_source = $%d", v)
	}

	hasTaskFilter := strings.TrimSpace(queryString(r, "gw_task_id")) != ""
	hasSessionFilter := strings.TrimSpace(queryString(r, "gw_session_id")) != ""
	chrono := queryString(r, "chrono") == "1" || hasTaskFilter || hasSessionFilter
	orderBy := "rl.ts DESC"
	traceSeqCol := ""
	if chrono {
		orderBy = "rl.ts ASC"
		traceSeqCol = ", ROW_NUMBER() OVER (ORDER BY rl.ts ASC) AS trace_seq"
	}

	where := strings.Join(clauses, " AND ")

	// 2026-06-30 (migration 056): previously the list handler issued TWO
	// round-trips — a separate `SELECT COUNT(*)` and a `SELECT ... LIMIT N
	// OFFSET M`. The COUNT branch additionally LEFT JOINed api_keys just to
	// reuse `ak.tenant_id` even though the WHERE clause already filters on
	// `rl.tenant_id`. Each branch had to walk the same partitions and
	// re-evaluate the same WHERE; the COUNT round-trip alone added ~1s on
	// the production 24h window.
	//
	// We now merge them into a single SELECT that projects the page rows
	// AND a `COUNT(*) OVER ()` window so every emitted row carries the
	// total count of WHERE-matching rows (computed BEFORE LIMIT/OFFSET,
	// identical semantics to the previous standalone COUNT). This halves
	// the round-trip count and removes the api_keys join from the COUNT
	// path entirely.
	offset := (page - 1) * pageSize
	listArgs := append(append([]any{}, args...), pageSize, offset)
	limitIdx := argIdx
	offsetIdx := argIdx + 1

	rows, err := h.db.Query(ctx, fmt.Sprintf(`
		SELECT %s%s, COUNT(*) OVER () AS total_count
		FROM request_logs rl
		%s
		WHERE %s
		ORDER BY %s
		LIMIT $%d OFFSET $%d
	`, requestLogsListCols, traceSeqCol, requestLogsJoins, where, orderBy, limitIdx, offsetIdx), listArgs...)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "query failed")
		return
	}
	defer rows.Close()

	items := make([]requestLogRow, 0)
	count := 0
	// total_count is the same on every row in this result set (it's a
	// window over the WHERE-clause rows before LIMIT/OFFSET). Capture it
	// from the first row; if there are zero rows we fall back to 0
	// which matches the previous standalone COUNT(*)=0 path.
	for rows.Next() {
		l, c, err := scanRequestLogListRowWithTotal(rows, chrono)
		if err != nil {
			continue
		}
		if count == 0 {
			count = c
		}
		items = append(items, l)
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"items": items,
		"count": count,
	})
}

func (h *Handler) getLog(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}

	requestID, err := url.PathUnescape(strings.Trim(r.URL.Path[len("/api/logs/"):], "/"))
	if err != nil || requestID == "" {
		writeError(w, http.StatusBadRequest, "invalid request id")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	var detail requestLogDetail
	var requestBodyRaw []byte
	var responseBodyRaw []byte

	err = h.db.QueryRow(ctx, fmt.Sprintf(`
		SELECT %s, rl.request_body::text, rl.response_body::text
		  FROM request_logs rl
		%s
		 WHERE rl.request_id = $1
		   AND ($2 OR ak.tenant_id = $3)
		 ORDER BY rl.ts DESC
		 LIMIT 1
	`, requestLogsSelectCols, requestLogsJoins), requestID, !IsTenantAdmin(r), GetTenantID(r)).Scan(
		&detail.Ts,
		&detail.RequestID,
		&detail.APIKeyID,
		&detail.EndUserID,
		&detail.ClientModel,
		&detail.OutboundModel,
		&detail.CredentialID,
		&detail.CredentialLabel,
		&detail.ProviderID,
		&detail.ProviderName,
		&detail.ProviderCode,
		&detail.ClientProfile,
		&detail.RequestMode,
		&detail.PromptTokens,
		&detail.CompletionTokens,
		&detail.CacheReadTokens,
		&detail.CacheWriteTokens,
		&detail.TotalTokens,
		&detail.CostUSD,
		&detail.CostDisplay,
		&detail.CostCurrency,
		&detail.LatencyMs,
		&detail.Success,
		&detail.RequestStatus,
		&detail.ErrorKind,
		&detail.SearchText,
		&detail.IdentityHash,
		&detail.VirtualClientID,
		&detail.VirtualIP,
		&detail.VirtualMAC,
		&detail.AffinityHit,
		&detail.RequestChecksum,
		&detail.ResponseChecksum,
		&detail.TransformRuleID,
		&detail.EgressProtocol,
		&detail.FailureStage,
		&detail.FailureDetailCode,
		&detail.UpstreamFinishReason,
		&detail.RequestPreview,
		&detail.TransformSummary,
		&detail.ResponsePreview,
		&detail.StreamFirstChunkMs,
		&detail.StreamChunkCount,
		&detail.StreamDoneReceived,
		&detail.StreamInterrupted,
		&detail.StreamDoneSent,
		&detail.UsageSource,
		&detail.GwSessionID,
		&detail.GwTaskID,
		&detail.APIKeyPrefix,
		&detail.APIKeyOwnerUser,
		&detail.ApplicationCode,
		&detail.CanonicalName,
		&detail.ProviderModel,
		&detail.CreditsCharged,
		// v3 session-level outbound body fields.
		&detail.OutboundBody,
		&detail.OutboundMsgCount,
		&detail.OutboundTokenEst,
		&detail.OutboundMsgHashes,
		&detail.CompressionStrategy,
		&detail.CompressionReason,
		&detail.CompressionMeta,
		&detail.ParentRequestID,
		// 2026-07-01: attachment tracking.
		&detail.HasAttachments,
		&detail.AttachmentCount,
		&requestBodyRaw,
		&responseBodyRaw,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, "request log not found")
			return
		}
		slog.Warn("admin getLog scan failed", "request_id", requestID, "error", err.Error())
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"error": map[string]any{
				"detail":    "query failed",
				"db_error":  err.Error(),
				"request_id": requestID,
			},
		})
		return
	}

	detail.RequestBody = decodeJSONText(requestBodyRaw)
	detail.ResponseBody = decodeJSONText(responseBodyRaw)
	// Outbound body: it's already a JSON RawMessage from JSONB scan; convert to
	// a structured payload so the UI can render it as a message list.
	if len(detail.OutboundBody) > 0 {
		detail.OutboundBody = normalizeJSONForAPI(detail.OutboundBody)
	}
	if len(detail.OutboundMsgHashes) > 0 {
		detail.OutboundMsgHashes = normalizeJSONForAPI(detail.OutboundMsgHashes)
	}
	if len(detail.CompressionMeta) > 0 {
		detail.CompressionMeta = normalizeJSONForAPI(detail.CompressionMeta)
	}
	writeJSON(w, http.StatusOK, detail)
}

// normalizeJSONForAPI is a no-op pass-through kept as a hook for future
// transformations (e.g. stripping sensitive fields before sending to the UI).
func normalizeJSONForAPI(raw json.RawMessage) json.RawMessage {
	return raw
}

func (h *Handler) listTopModels(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	now := time.Now().UTC()
	start := parseQueryTime(r, "from", now.Add(-24*time.Hour))
	end := parseQueryTime(r, "to", now)
	limit := queryInt(r, "limit", 20)
	if limit < 1 {
		limit = 1
	}
	if limit > 50 {
		limit = 50
	}

	rows, err := h.db.Query(ctx, `
		SELECT
			COALESCE(mc.id, mc2.id) AS canonical_id,
			COALESCE(mc.canonical_name, mc2.canonical_name, rl.client_model) AS canonical_name,
			COALESCE(mc.display_name, mc2.display_name, mc.canonical_name, mc2.canonical_name, rl.client_model) AS display_name,
			COUNT(*) AS request_count
		FROM request_logs rl
		LEFT JOIN models_canonical mc ON mc.id = rl.canonical_id
		LEFT JOIN LATERAL (
			SELECT canonical_id
			FROM model_aliases
			WHERE lower(raw_name) = lower(rl.client_model)
			  AND status = 'active'
			LIMIT 1
		) ma ON TRUE
		LEFT JOIN models_canonical mc2 ON mc2.id = ma.canonical_id
		WHERE rl.ts >= $1 AND rl.ts <= $2
		  AND rl.client_model IS NOT NULL AND rl.client_model != ''
		GROUP BY canonical_id, canonical_name, display_name
		ORDER BY request_count DESC
		LIMIT $3
	`, start, end, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "query failed")
		return
	}
	defer rows.Close()

	type topModel struct {
		CanonicalID   *int   `json:"canonical_id"`
		CanonicalName string `json:"canonical_name"`
		DisplayName   string `json:"display_name"`
		RequestCount  int    `json:"request_count"`
	}
	items := make([]topModel, 0)
	for rows.Next() {
		var item topModel
		if err := rows.Scan(&item.CanonicalID, &item.CanonicalName, &item.DisplayName, &item.RequestCount); err != nil {
			continue
		}
		items = append(items, item)
	}
	if items == nil {
		items = []topModel{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func parseQueryTime(r *http.Request, key string, def time.Time) time.Time {
	raw := strings.TrimSpace(r.URL.Query().Get(key))
	if raw == "" {
		return def.UTC()
	}
	for _, layout := range []string{time.RFC3339, time.RFC3339Nano, "2006-01-02T15:04:05", "2006-01-02 15:04:05"} {
		if ts, err := time.Parse(layout, raw); err == nil {
			return ts.UTC()
		}
	}
	return def.UTC()
}

func decodeJSONText(raw []byte) any {
	if len(raw) == 0 {
		return nil
	}

	var decoded any
	if err := json.Unmarshal(raw, &decoded); err == nil {
		return decoded
	}
	return string(raw)
}
