package admin

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"github.com/kaixuan/llm-gateway-go/attachments"
)

// AttachmentsHandler serves attachment downloads and metadata for the
// admin UI. All endpoints require admin authentication (applied by the
// wrapAdmin middleware at registration time) and are tenant-scoped: the
// tenant id is read from the admin session context so a user in tenant A
// can never fetch an attachment owned by tenant B.
type AttachmentsHandler struct {
	manager *attachments.Manager
}

func NewAttachmentsHandler(manager *attachments.Manager) *AttachmentsHandler {
	return &AttachmentsHandler{manager: manager}
}

// ServeHTTP routes:
//   GET /api/admin/attachments/{id}              → raw file download
//   GET /api/admin/attachments/{id}/info         → JSON metadata
//   GET /api/admin/attachments?request_id={rid}  → JSON array for a request
func (h *AttachmentsHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if h.manager == nil || !h.manager.Enabled() {
		http.Error(w, "attachment management not enabled", http.StatusNotImplemented)
		return
	}
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Tenant scope: tenant_admin sees only their tenant; super_admin sees all.
	tenantID := EffectiveTenantID(r)

	// List-by-request: /api/admin/attachments?request_id=...
	if reqID := r.URL.Query().Get("request_id"); reqID != "" {
		atts, err := h.manager.ListByRequestID(r.Context(), reqID, tenantID)
		if err != nil {
			slog.Error("attachment list failed", "request_id", reqID, "error", err)
			http.Error(w, "failed to list attachments", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(atts)
		return
	}

	// Path: /api/admin/attachments/{id}[/info]
	path := strings.TrimPrefix(r.URL.Path, "/api/admin/attachments/")
	path = strings.Trim(path, "/")
	if path == "" {
		http.Error(w, "missing attachment id", http.StatusBadRequest)
		return
	}
	parts := strings.SplitN(path, "/", 2)
	attachmentID := parts[0]
	isInfo := len(parts) == 2 && parts[1] == "info"

	att, err := h.manager.GetByID(r.Context(), attachmentID, tenantID)
	if err != nil {
		slog.Warn("attachment lookup failed",
			"id", attachmentID, "tenant", tenantID, "error", err)
		http.NotFound(w, r)
		return
	}

	if isInfo {
		h.serveInfo(w, r, att)
		return
	}
	h.serveFile(w, r, att)
}

func (h *AttachmentsHandler) serveInfo(w http.ResponseWriter, r *http.Request, att *attachments.Attachment) {
	w.Header().Set("Content-Type", "application/json")
	// Never leak the on-disk absolute path; FilePath is relative to the
	// storage root and only useful server-side.
	_ = json.NewEncoder(w).Encode(att)
}

func (h *AttachmentsHandler) serveFile(w http.ResponseWriter, r *http.Request, att *attachments.Attachment) {
	file, err := h.manager.OpenFile(att)
	if err != nil {
		slog.Error("attachment file open failed", "id", att.ID, "error", err)
		http.Error(w, "failed to read attachment", http.StatusInternalServerError)
		return
	}
	defer file.Close()

	w.Header().Set("Content-Type", att.MediaType)
	w.Header().Set("Content-Length", strconv.FormatInt(att.FileSize, 10))
	w.Header().Set("Cache-Control", "private, max-age=31536000, immutable")
	// Images render inline so the admin UI can preview them; other types
	// trigger a download.
	if strings.HasPrefix(att.MediaType, "image/") {
		w.Header().Set("Content-Disposition", "inline")
	} else {
		w.Header().Set("Content-Disposition", "attachment")
	}

	if _, err := io.Copy(w, file); err != nil {
		slog.Error("attachment send failed", "id", att.ID, "error", err)
	}
}
