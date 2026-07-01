package admin

import (
	"log/slog"
	"net/http"
	"strings"

	"github.com/kaixuan/llm-gateway-go/attachmentanalysis"
	"github.com/kaixuan/llm-gateway-go/attachments"
)

// AttachmentAnalysisHandler exposes admin endpoints for the content-
// identification subsystem: manual re-analyze, pending-recovery trigger,
// and queue stats. All endpoints require admin auth (applied at
// registration) and are tenant-scoped.
//
// Routes (mounted under /api/admin/attachments/analysis):
//
//	POST /reanalyze/{id}     → re-run analysis for one attachment
//	POST /reanalyze-pending  → scan + re-enqueue all pending (recovery)
//	GET  /stats              → queue counters + recent errors
type AttachmentAnalysisHandler struct {
	sink     *attachmentanalysis.Sink
	analyzer *attachmentanalysis.Analyzer
	attMgr   *attachments.Manager
}

// NewAttachmentAnalysisHandler builds the handler. sink/analyzer may be
// nil if the subsystem is disabled — in that case all endpoints return 503.
func NewAttachmentAnalysisHandler(sink *attachmentanalysis.Sink, analyzer *attachmentanalysis.Analyzer, attMgr *attachments.Manager) *AttachmentAnalysisHandler {
	return &AttachmentAnalysisHandler{sink: sink, analyzer: analyzer, attMgr: attMgr}
}

// Enabled reports whether the analysis subsystem is wired.
func (h *AttachmentAnalysisHandler) Enabled() bool {
	return h != nil && h.sink != nil && h.analyzer != nil && h.attMgr != nil
}

// ServeHTTP dispatches the analysis admin endpoints.
func (h *AttachmentAnalysisHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if !h.Enabled() {
		http.Error(w, "attachment analysis not enabled", http.StatusNotImplemented)
		return
	}
	path := strings.TrimPrefix(r.URL.Path, "/api/admin/attachments/analysis")
	path = strings.Trim(path, "/")
	parts := strings.SplitN(path, "/", 2)

	switch {
	case len(parts) == 2 && parts[0] == "reanalyze" && r.Method == http.MethodPost:
		h.handleReanalyze(w, r, parts[1])
	case len(parts) == 1 && parts[0] == "reanalyze-pending" && r.Method == http.MethodPost:
		h.handleReanalyzePending(w, r)
	case len(parts) == 1 && parts[0] == "stats" && r.Method == http.MethodGet:
		h.handleStats(w, r)
	default:
		http.NotFound(w, r)
	}
}

// handleReanalyze re-runs the full analysis pipeline for a single
// attachment. It does NOT consult the hash cache — it forces a fresh
// pass (useful after a source is newly enabled or a model is changed).
func (h *AttachmentAnalysisHandler) handleReanalyze(w http.ResponseWriter, r *http.Request, attachmentID string) {
	tenantID := EffectiveTenantID(r)
	att, err := h.attMgr.GetByID(r.Context(), attachmentID, tenantID)
	if err != nil {
		slog.Warn("reanalyze: attachment lookup failed",
			"id", attachmentID, "error", err)
		http.NotFound(w, r)
		return
	}

	// Reset the status to pending so the analyzer runs a fresh pass
	// (the hash-cache check only reuses *done* siblings).
	if err := h.analyzer.ForceReanalyze(r.Context(), attachmentanalysis.AnalysisOp{
		AttachmentID: att.ID,
		ContentHash:  att.ContentHash,
		MediaType:    att.MediaType,
		FilePath:     att.FilePath,
		TenantID:     tenantID,
		RequestID:    att.RequestID,
	}); err != nil {
		slog.Error("reanalyze: force reanalyze failed",
			"id", attachmentID, "error", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{
			"error": "reanalyze failed: " + err.Error(),
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"status":        "reanalyzed",
		"attachment_id": attachmentID,
	})
}

// handleReanalyzePending scans for attachments whose analysis is pending
// (or never started) and re-enqueues them. This is the manual trigger for
// the same recovery the bg sweeper does automatically.
func (h *AttachmentAnalysisHandler) handleReanalyzePending(w http.ResponseWriter, r *http.Request) {
	tenantID := EffectiveTenantID(r)
	limit := 200
	ops, err := h.analyzer.ScanPending(r.Context(), tenantID, limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{
			"error": "scan failed: " + err.Error(),
		})
		return
	}
	enqueued := 0
	for _, op := range ops {
		h.sink.Enqueue(op)
		enqueued++
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"scanned":   len(ops),
		"enqueued":  enqueued,
		"queue_len": len(ops),
	})
}

// handleStats returns the sink counters for observability.
func (h *AttachmentAnalysisHandler) handleStats(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, h.sink.Stats())
}
