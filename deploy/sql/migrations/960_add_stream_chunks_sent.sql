-- Migration: Add stream_chunks_sent column to request_logs
-- Date: 2026-07-04
-- Purpose: Track chunks actually sent to client vs chunks received from upstream
-- Related: docs/2026-07-04-stream-chunks-sent-tracking-fix.md

-- Add column to track chunks successfully sent to client
ALTER TABLE request_logs
ADD COLUMN IF NOT EXISTS stream_chunks_sent INTEGER DEFAULT NULL;

COMMENT ON COLUMN request_logs.stream_chunks_sent IS 
'Number of chunks successfully sent to client (vs stream_chunk_count = chunks received from upstream). 
NULL means the request was non-streaming or predates this feature (before 2026-07-04). 
0 when streaming but all writes failed (client disconnected before first chunk).
Discrepancy between stream_chunk_count and stream_chunks_sent indicates client disconnected mid-stream.';

-- Index for diagnostic queries (find requests where client disconnected mid-stream)
CREATE INDEX IF NOT EXISTS idx_request_logs_stream_chunks_sent_zero 
ON request_logs (created_at DESC, stream_chunk_count, stream_chunks_sent)
WHERE stream_chunk_count > 0 AND (stream_chunks_sent = 0 OR stream_chunks_sent IS NULL);

COMMENT ON INDEX idx_request_logs_stream_chunks_sent_zero IS
'Diagnostic index for finding streaming requests where chunks were received from upstream 
but failed to send to client (client_write_failed scenarios). Used for monitoring and alerting.';

-- Verify migration
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'request_logs' 
        AND column_name = 'stream_chunks_sent'
    ) THEN
        RAISE EXCEPTION 'Migration failed: stream_chunks_sent column not created';
    END IF;
    
    RAISE NOTICE 'Migration 960_add_stream_chunks_sent completed successfully';
END $$;
