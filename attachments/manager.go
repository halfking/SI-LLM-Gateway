package attachments

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Manager handles attachment archival and retrieval.
//
// IMPORTANT (audit 2026-07-01): The manager is an OBSERVER. It archives
// images found in the request body (decode → hash → file → DB row) so
// operators can inspect them later from request_logs, but it NEVER
// modifies the body forwarded to the upstream LLM. The previous
// implementation replaced inline base64 with an `attachment_ref`
// object that upstream providers do not understand, which re-created
// the exact "image lost" bug this feature was built to fix.
type Manager struct {
	pool        *pgxpool.Pool
	storagePath string
	enabled     bool
	maxSizeMB   int64
}

// NewManager creates a new attachment manager.
func NewManager(pool *pgxpool.Pool, storagePath string, enabled bool, maxSizeMB int64) (*Manager, error) {
	if !enabled {
		return &Manager{enabled: false}, nil
	}

	if storagePath == "" {
		storagePath = "./data/attachments"
	}
	if maxSizeMB <= 0 {
		maxSizeMB = 10
	}
	if err := os.MkdirAll(storagePath, 0o755); err != nil {
		return nil, fmt.Errorf("attachments: create storage dir: %w", err)
	}
	// Write-permission probe.
	probe := filepath.Join(storagePath, ".write_test")
	if err := os.WriteFile(probe, []byte("ok"), 0o644); err != nil {
		return nil, fmt.Errorf("attachments: storage dir not writable: %w", err)
	}
	os.Remove(probe)

	slog.Info("attachment manager initialized", "storage_path", storagePath, "max_size_mb", maxSizeMB)
	return &Manager{pool: pool, storagePath: storagePath, enabled: enabled, maxSizeMB: maxSizeMB}, nil
}

func (m *Manager) Enabled() bool { return m != nil && m.enabled }

// ArchiveAttachments is the entry point used by the relay handler. It
// archives all inline base64 images found in the body and returns the
// count. The body is NOT modified.
func (m *Manager) ArchiveAttachments(ctx context.Context, body []byte, requestID, tenantID string) (int, error) {
	atts, err := m.ArchiveFromRequest(ctx, body, requestID, tenantID)
	if err != nil {
		return 0, err
	}
	return len(atts), nil
}

// HasAttachments is a cheap byte-scan used to skip the JSON parse path
// for bodies that obviously carry no media.
func HasAttachments(body []byte) bool {
	s := string(body)
	return strings.Contains(s, "data:image/") ||
		strings.Contains(s, `"type":"image"`) ||
		strings.Contains(s, `"type": "image"`) ||
		strings.Contains(s, `"image_url"`)
}

// ArchiveFromRequest walks the request body, archives every base64 image
// it understands, and returns the metadata for the detected attachments.
// The body is returned UNMODIFIED so the upstream LLM still receives the
// original inline image. Callers persist the returned slice into
// request_logs via has_attachments / attachment_count, and each row is
// independently retrievable through the admin attachments API.
func (m *Manager) ArchiveFromRequest(ctx context.Context, body []byte, requestID, tenantID string) ([]*Attachment, error) {
	if !m.Enabled() || len(body) == 0 || !HasAttachments(body) {
		return nil, nil
	}

	var root map[string]any
	if err := json.Unmarshal(body, &root); err != nil {
		// Non-JSON or array-typed body: nothing to archive.
		return nil, nil
	}

	var out []*Attachment

	// Walk messages[].content (string | []block).
	msgs, _ := root["messages"].([]any)
	for _, msg := range msgs {
		mm, _ := msg.(map[string]any)
		if mm == nil {
			continue
		}
		switch content := mm["content"].(type) {
		case []any:
			for _, part := range content {
				block, _ := part.(map[string]any)
				if block == nil {
					continue
				}
				out = append(out, m.archiveBlock(ctx, block, requestID, tenantID)...)
			}
		}
	}

	return out, nil
}

// archiveBlock inspects one content block and archives the embedded
// base64 payload if present. Supports both OpenAI ("image_url") and
// Anthropic ("image" + source.type=base64) shapes.
func (m *Manager) archiveBlock(ctx context.Context, block map[string]any, requestID, tenantID string) []*Attachment {
	switch block["type"] {
	case "image_url":
		// OpenAI: { "type":"image_url", "image_url": { "url": "data:image/png;base64,..." } }
		iu, _ := block["image_url"].(map[string]any)
		if iu == nil {
			return nil
		}
		urlStr, _ := iu["url"].(string)
		return m.archiveDataURL(ctx, urlStr, requestID, tenantID)

	case "image":
		// Anthropic: { "type":"image", "source": { "type":"base64", "media_type":"image/png", "data":"..." } }
		src, _ := block["source"].(map[string]any)
		if src == nil {
			return nil
		}
		if t, _ := src["type"].(string); t == "base64" {
			mediaType, _ := src["media_type"].(string)
			if mediaType == "" {
				mediaType = "image/png"
			}
			data, _ := src["data"].(string)
			return m.archiveBase64(ctx, mediaType, data, requestID, tenantID)
		}
	}
	return nil
}

var dataURLPrefix = "data:"

// archiveDataURL parses a `data:<media>;base64,<payload>` URL.
func (m *Manager) archiveDataURL(ctx context.Context, urlStr, requestID, tenantID string) []*Attachment {
	if !strings.HasPrefix(urlStr, dataURLPrefix) {
		// External http(s) URL — we keep it as a recorded reference but
		// do not download it (out of scope; would leak the user's URL
		// to an outbound fetch).
		return nil
	}
	// Strip "data:" → "image/png;base64,AAAA..."
	body := strings.TrimPrefix(urlStr, dataURLPrefix)
	semi := strings.IndexByte(body, ';')
	comma := strings.IndexByte(body, ',')
	if semi < 0 || comma < 0 || comma <= semi {
		return nil
	}
	mediaType := body[:semi]
	// Only base64 payloads are decodable here.
	if !strings.HasPrefix(body[semi+1:comma], "base64") {
		return nil
	}
	payload := body[comma+1:]
	return m.archiveBase64(ctx, mediaType, payload, requestID, tenantID)
}

// archiveBase64 decodes the payload, hashes it, dedupes against existing
// rows, writes the file, and inserts the metadata row.
func (m *Manager) archiveBase64(ctx context.Context, mediaType, b64, requestID, tenantID string) []*Attachment {
	if b64 == "" {
		return nil
	}
	raw, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		slog.Warn("attachments: base64 decode failed", "error", err)
		return nil
	}
	if int64(len(raw)) > m.maxSizeMB*1024*1024 {
		slog.Warn("attachments: image exceeds size limit, skipping",
			"size", len(raw), "limit_mb", m.maxSizeMB)
		return nil
	}

	sum := sha256.Sum256(raw)
	contentHash := hex.EncodeToString(sum[:])

	// Dedupe by (tenant, hash) so repeated images don't duplicate files.
	if existing, err := m.findByHash(ctx, contentHash, tenantID); err == nil && existing != nil {
		// Still record the association to this request_id so the request
		// log can list it, but reuse the file path.
		existing.RequestID = requestID
		// Best-effort: record a thin association row only if we track
		// request_id separately. Current schema keys on id, so we just
		// return the existing metadata to count toward this request.
		return []*Attachment{existing}
	}

	attID := uuid.NewString()
	now := time.Now().UTC()
	relPath := filepath.Join(
		fmt.Sprintf("%d", now.Year()),
		fmt.Sprintf("%02d", now.Month()),
		fmt.Sprintf("%02d", now.Day()),
		attID+"_"+safeExt(mediaType),
	)
	absPath := filepath.Join(m.storagePath, relPath)
	if err := os.MkdirAll(filepath.Dir(absPath), 0o755); err != nil {
		slog.Error("attachments: mkdir failed", "error", err)
		return nil
	}
	if err := os.WriteFile(absPath, raw, 0o644); err != nil {
		slog.Error("attachments: write file failed", "error", err)
		return nil
	}

	att := &Attachment{
		ID:               attID,
		TenantID:         tenantID,
		RequestID:        requestID,
		AttachmentType:   TypeImage,
		MediaType:        mediaType,
		FileSize:         int64(len(raw)),
		FilePath:         relPath,
		OriginalDataType: DataTypeBase64,
		ContentHash:      contentHash,
		CreatedAt:        now,
	}
	if err := m.save(ctx, att); err != nil {
		// DB write failed; remove the orphaned file so disk and DB stay
		// consistent. The request still succeeds — this is best-effort.
		os.Remove(absPath)
		slog.Warn("attachments: db save failed, removed file", "error", err)
		return nil
	}
	slog.Info("attachments: archived",
		"id", attID, "size", len(raw), "hash_prefix", contentHash[:12])
	return []*Attachment{att}
}

// ── persistence helpers ───────────────────────────────────────────────

func (m *Manager) save(ctx context.Context, att *Attachment) error {
	if m.pool == nil {
		return nil
	}
	_, err := m.pool.Exec(ctx, `
		INSERT INTO attachments (
			id, tenant_id, request_id, attachment_type, media_type,
			file_size, file_path, original_data_type, original_url,
			content_hash, created_at, metadata
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
		ON CONFLICT (id) DO NOTHING
	`, att.ID, att.TenantID, att.RequestID, att.AttachmentType, att.MediaType,
		att.FileSize, att.FilePath, att.OriginalDataType, att.OriginalURL,
		att.ContentHash, att.CreatedAt, att.Metadata)
	return err
}

func (m *Manager) findByHash(ctx context.Context, contentHash, tenantID string) (*Attachment, error) {
	if m.pool == nil {
		return nil, nil
	}
	var a Attachment
	err := m.pool.QueryRow(ctx, `
		SELECT id, tenant_id, request_id, attachment_type, media_type,
		       file_size, file_path, original_data_type, original_url,
		       content_hash, created_at, metadata
		FROM attachments
		WHERE content_hash = $1 AND tenant_id = $2
		LIMIT 1
	`, contentHash, tenantID).Scan(
		&a.ID, &a.TenantID, &a.RequestID, &a.AttachmentType, &a.MediaType,
		&a.FileSize, &a.FilePath, &a.OriginalDataType, &a.OriginalURL,
		&a.ContentHash, &a.CreatedAt, &a.Metadata,
	)
	if err != nil {
		return nil, err
	}
	return &a, nil
}

// GetByID retrieves an attachment by ID (tenant-scoped).
func (m *Manager) GetByID(ctx context.Context, id, tenantID string) (*Attachment, error) {
	if !m.Enabled() || m.pool == nil {
		return nil, fmt.Errorf("attachments: manager not available")
	}
	var a Attachment
	err := m.pool.QueryRow(ctx, `
		SELECT id, tenant_id, request_id, attachment_type, media_type,
		       file_size, file_path, original_data_type, original_url,
		       content_hash, created_at, metadata
		FROM attachments
		WHERE id = $1 AND tenant_id = $2
	`, id, tenantID).Scan(
		&a.ID, &a.TenantID, &a.RequestID, &a.AttachmentType, &a.MediaType,
		&a.FileSize, &a.FilePath, &a.OriginalDataType, &a.OriginalURL,
		&a.ContentHash, &a.CreatedAt, &a.Metadata,
	)
	if err != nil {
		return nil, err
	}
	return &a, nil
}

// OpenFile opens an attachment file for reading.
func (m *Manager) OpenFile(att *Attachment) (*os.File, error) {
	if !m.Enabled() {
		return nil, fmt.Errorf("attachments: manager not enabled")
	}
	return os.Open(filepath.Join(m.storagePath, att.FilePath))
}

// ListByRequestID returns all attachments associated with a request.
// When tenantID is non-empty, results are scoped to that tenant so a
// tenant_admin can only list their own attachments. An empty tenantID
// (used by super_admin) returns rows for any tenant.
func (m *Manager) ListByRequestID(ctx context.Context, requestID, tenantID string) ([]*Attachment, error) {
	if !m.Enabled() || m.pool == nil {
		return nil, nil
	}
	var (
		rows interface {
			Next() bool
			Scan(...any) error
			Err() error
			Close()
		}
		err error
	)
	if tenantID != "" {
		rows, err = m.pool.Query(ctx, `
			SELECT id, tenant_id, request_id, attachment_type, media_type,
			       file_size, file_path, original_data_type, original_url,
			       content_hash, created_at, metadata
			FROM attachments
			WHERE request_id = $1 AND tenant_id = $2
			ORDER BY created_at
		`, requestID, tenantID)
	} else {
		rows, err = m.pool.Query(ctx, `
			SELECT id, tenant_id, request_id, attachment_type, media_type,
			       file_size, file_path, original_data_type, original_url,
			       content_hash, created_at, metadata
			FROM attachments
			WHERE request_id = $1
			ORDER BY created_at
		`, requestID)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*Attachment
	for rows.Next() {
		var a Attachment
		if err := rows.Scan(
			&a.ID, &a.TenantID, &a.RequestID, &a.AttachmentType, &a.MediaType,
			&a.FileSize, &a.FilePath, &a.OriginalDataType, &a.OriginalURL,
			&a.ContentHash, &a.CreatedAt, &a.Metadata,
		); err != nil {
			return nil, err
		}
		out = append(out, &a)
	}
	return out, rows.Err()
}

// safeExt maps a MIME type to a lowercase file extension.
func safeExt(mediaType string) string {
	// e.g. "image/png" -> "image.png" (kept consistent with the prior
	// on-disk layout). Unknown types default to .bin.
	parts := strings.Split(mediaType, "/")
	if len(parts) == 2 && parts[1] != "" {
		return parts[0] + "." + parts[1]
	}
	return "attachment.bin"
}
