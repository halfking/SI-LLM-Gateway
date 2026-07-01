package admin

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/kaixuan/llm-gateway-go/attachments"
)

// AttachmentsHandler serves attachment downloads and metadata for the
// admin UI.
//
// Auth model: the list endpoint (?request_id=…) and the metadata endpoint
// (/{id}/info) always require an authenticated admin session. The raw-file
// endpoint (/{id}) additionally accepts a short-lived HMAC signature in the
// query string (?exp=&tenant=&sig=) so the admin UI's browser-native
// <img src> and <a download> elements — which cannot attach an
// Authorization header — can fetch images directly. See AttachmentsWithAuth
// for how the signed bypass is wired in before the normal AdminMiddleware.
//
// All endpoints are tenant-scoped: tenant_admin sees only their tenant;
// super_admin sees all. For signed downloads the tenant id is bound into
// the signature and re-applied to the lookup, so a link minted for tenant A
// can never retrieve tenant B's attachment.
type AttachmentsHandler struct {
	manager   *attachments.Manager
	secretKey string
}

func NewAttachmentsHandler(manager *attachments.Manager, secretKey string) *AttachmentsHandler {
	return &AttachmentsHandler{manager: manager, secretKey: secretKey}
}

// AttachmentsWithAuth wraps AttachmentsHandler.ServeHTTP so that a request
// carrying a valid signature (?sig=…) is served without requiring a Bearer
// token, while every other request still goes through AdminMiddleware. This
// is necessary because browser <img>/<a> elements cannot send Authorization
// headers, yet the list/info endpoints must remain token-gated.
func AttachmentsWithAuth(h *AttachmentsHandler, pool *pgxpool.Pool, secretKey string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// A signed download request carries ?sig= on a /{id} path. Serve it
		// without a Bearer token. Only the raw-file path is eligible; list
		// (?request_id=) and /info still require a token.
		if q := r.URL.Query(); q.Get("sig") != "" && !strings.Contains(r.URL.Path, "/info") {
			h.ServeHTTP(w, r)
			return
		}
		AdminMiddleware(h.ServeHTTP, pool, secretKey)(w, r)
	}
}

// ServeHTTP routes:
//   GET /api/admin/attachments/{id}              → raw file download (supports signed bypass)
//   GET /api/admin/attachments/{id}/info         → JSON metadata (token required)
//   GET /api/admin/attachments?request_id={rid}  → JSON array for a request (token required)
func (h *AttachmentsHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if h.manager == nil || !h.manager.Enabled() {
		http.Error(w, "attachment management not enabled", http.StatusNotImplemented)
		return
	}
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Signed-download bypass: if a ?sig= is present, verify it and resolve
	// the tenant from the signature itself (AdminMiddleware did not run).
	if sigQuery := r.URL.Query(); sigQuery.Get("sig") != "" {
		path := strings.TrimPrefix(r.URL.Path, "/api/admin/attachments/")
		attachmentID := strings.Trim(path, "/")
		tenantID, ok := VerifyAttachmentURL(attachmentID, h.secretKey, sigQuery)
		if !ok {
			http.Error(w, "invalid or expired attachment link", http.StatusUnauthorized)
			return
		}
		att, err := h.manager.GetByID(r.Context(), attachmentID, tenantID)
		if err != nil {
			slog.Warn("attachment signed lookup failed",
				"id", attachmentID, "tenant", tenantID, "error", err)
			http.NotFound(w, r)
			return
		}
		h.serveFile(w, r, att)
		return
	}

	// Authenticated path: tenant scope comes from the admin session context.
	tenantID := EffectiveTenantID(r)

	// List-by-request: /api/admin/attachments?request_id=...
	if reqID := r.URL.Query().Get("request_id"); reqID != "" {
		atts, err := h.manager.ListByRequestID(r.Context(), reqID, tenantID)
		if err != nil {
			slog.Error("attachment list failed", "request_id", reqID, "error", err)
			http.Error(w, "failed to list attachments", http.StatusInternalServerError)
			return
		}
		// Stamp each row with a short-lived signed download URL so the
		// browser can fetch images without an Authorization header.
		for _, a := range atts {
			a.DownloadURL = "/api/admin/attachments/" + a.ID +
				"?" + SignAttachmentURL(a.ID, a.TenantID, h.secretKey)
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
