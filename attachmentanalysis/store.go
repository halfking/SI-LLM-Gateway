package attachmentanalysis

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// store wraps the DB operations the analyzer needs. It deliberately keeps
// to the existing attachments table (no new tables) and writes results
// into the metadata JSONB column via the `||` merge operator so partial
// updates from different sources compose without clobbering each other.
type store struct {
	pool *pgxpool.Pool
}

func newStore(pool *pgxpool.Pool) *store {
	return &store{pool: pool}
}

// MergeMetadata deep-merges a patch (JSON object) into the attachment's
// metadata column: `metadata = COALESCE(metadata,'{}') || $2`. Top-level
// keys in the patch overwrite existing ones; this is what we want for
// analysis_status/analyzed_at/content_identification.
func (s *store) MergeMetadata(ctx context.Context, attachmentID string, patch map[string]any) error {
	if s.pool == nil {
		return fmt.Errorf("attachmentanalysis: store has no DB pool")
	}
	patchJSON, err := json.Marshal(patch)
	if err != nil {
		return fmt.Errorf("attachmentanalysis: marshal patch: %w", err)
	}
	_, err = s.pool.Exec(ctx,
		`UPDATE attachments SET metadata = COALESCE(metadata, '{}'::jsonb) || $2::jsonb WHERE id = $1`,
		attachmentID, patchJSON,
	)
	return err
}

// SetStatus writes metadata.analysis_status (a convenience wrapper around
// MergeMetadata since it's the most frequent single-field update during
// the analyze lifecycle).
func (s *store) SetStatus(ctx context.Context, attachmentID, status string) error {
	return s.MergeMetadata(ctx, attachmentID, map[string]any{
		"analysis_status": status,
	})
}

// MarkDone writes the final status, timestamp, and the content
// identification payload in one merge.
func (s *store) MarkDone(ctx context.Context, attachmentID string, ci ContentIdentification) error {
	patch := map[string]any{
		"analysis_status":        statusDone,
		"analyzed_at":            time.Now().UTC().Format(time.RFC3339),
		"content_identification": ci,
	}
	return s.MergeMetadata(ctx, attachmentID, patch)
}

// FindByHashDone looks for an attachment with the same content_hash whose
// analysis already completed, returning its content_identification payload.
// This is the hash-cache lookup (source B): a repeated image can skip
// re-analysis entirely and reuse the cached result.
func (s *store) FindByHashDone(ctx context.Context, contentHash, tenantID string) (ContentIdentification, bool, error) {
	if s.pool == nil {
		return ContentIdentification{}, false, nil
	}
	var metadataJSON []byte
	err := s.pool.QueryRow(ctx, `
		SELECT metadata
		FROM attachments
		WHERE content_hash = $1
		  AND tenant_id = $2
		  AND metadata->>'analysis_status' = 'done'
		ORDER BY created_at DESC
		LIMIT 1
	`, contentHash, tenantID).Scan(&metadataJSON)
	if err != nil {
		// ErrNoRows just means no cached result yet — not an error.
		return ContentIdentification{}, false, nil
	}
	var meta struct {
		ContentIdentification ContentIdentification `json:"content_identification"`
	}
	if err := json.Unmarshal(metadataJSON, &meta); err != nil {
		return ContentIdentification{}, false, nil
	}
	return meta.ContentIdentification, true, nil
}

// ScanPending returns up to limit attachment IDs whose analysis is pending
// (or never started), oldest first, scoped to a tenant. Used by the bg
// recovery sweeper. Returns full AnalysisOp records so the caller can
// enqueue them directly without a second lookup.
func (s *store) ScanPending(ctx context.Context, tenantID string, limit int) ([]AnalysisOp, error) {
	if s.pool == nil {
		return nil, nil
	}
	rows, err := s.pool.Query(ctx, `
		SELECT id, content_hash, media_type, file_path, tenant_id, request_id
		FROM attachments
		WHERE ($1 = '' OR tenant_id = $1)
		  AND (metadata IS NULL
		       OR metadata->>'analysis_status' IS NULL
		       OR metadata->>'analysis_status' = 'pending')
		ORDER BY created_at ASC
		LIMIT $2
	`, tenantID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ops []AnalysisOp
	for rows.Next() {
		var op AnalysisOp
		if err := rows.Scan(&op.AttachmentID, &op.ContentHash, &op.MediaType, &op.FilePath, &op.TenantID, &op.RequestID); err != nil {
			return nil, err
		}
		ops = append(ops, op)
	}
	return ops, rows.Err()
}
