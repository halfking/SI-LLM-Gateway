package db

import (
	"context"
	"log/slog"
)

// ensureAttachmentsSchema creates the attachments table and indexes if they don't exist
func (d *DB) ensureAttachmentsSchema(ctx context.Context) error {
	if d == nil || d.pool == nil {
		return nil
	}

	_, err := d.pool.Exec(ctx, `
		-- Attachments table for storing image/file metadata
		-- Files are stored on filesystem, this table stores metadata
		CREATE TABLE IF NOT EXISTS attachments (
			id TEXT PRIMARY KEY,
			tenant_id TEXT NOT NULL,
			request_id TEXT NOT NULL,
			attachment_type TEXT NOT NULL,     -- 'image', 'file', 'audio', 'video'
			media_type TEXT NOT NULL,          -- MIME type: 'image/png', 'image/jpeg'
			file_size BIGINT NOT NULL,         -- file size in bytes
			file_path TEXT NOT NULL,           -- relative path from storage root
			original_data_type TEXT NOT NULL,  -- 'base64', 'url'
			original_url TEXT,                 -- if type='url', store original URL
			content_hash TEXT NOT NULL,        -- SHA256 hash for deduplication
			created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
			metadata JSONB                     -- extensible metadata (width, height, etc)
		);

		-- Index for finding attachments by request
		CREATE INDEX IF NOT EXISTS idx_attachments_request
			ON attachments (request_id);

		-- Index for tenant + time queries
		CREATE INDEX IF NOT EXISTS idx_attachments_tenant_created
			ON attachments (tenant_id, created_at DESC);

		-- Index for deduplication by content hash
		CREATE INDEX IF NOT EXISTS idx_attachments_hash
			ON attachments (content_hash, tenant_id);

		-- RLS policy for tenant isolation
		ALTER TABLE attachments ENABLE ROW LEVEL SECURITY;
		DROP POLICY IF EXISTS tenant_isolation_attachments ON attachments;
		CREATE POLICY tenant_isolation_attachments ON attachments
			USING ((tenant_id)::text = (public.get_current_tenant())::text);

		-- Add attachment tracking columns to request_logs
		DO $$ 
		BEGIN
			IF NOT EXISTS (
				SELECT 1 FROM information_schema.columns 
				WHERE table_name = 'request_logs' AND column_name = 'has_attachments'
			) THEN
				ALTER TABLE request_logs ADD COLUMN has_attachments BOOLEAN DEFAULT FALSE;
			END IF;

			IF NOT EXISTS (
				SELECT 1 FROM information_schema.columns 
				WHERE table_name = 'request_logs' AND column_name = 'attachment_count'
			) THEN
				ALTER TABLE request_logs ADD COLUMN attachment_count INTEGER DEFAULT 0;
			END IF;
		END $$;

		-- Index for filtering requests with attachments
		CREATE INDEX IF NOT EXISTS idx_request_logs_has_attachments
			ON request_logs (has_attachments, ts DESC)
			WHERE has_attachments = TRUE;
	`)

	if err != nil {
		return err
	}

	slog.Info("attachments schema ensured (table + indexes + RLS)")
	return nil
}
