-- Rollback: Remove stream_chunks_sent column from request_logs
-- Date: 2026-07-04
-- Purpose: Rollback migration 960_add_stream_chunks_sent.sql
-- WARNING: This will drop the stream_chunks_sent column and all its data

-- Drop index first
DROP INDEX IF EXISTS idx_request_logs_stream_chunks_sent_zero;

-- Drop column
ALTER TABLE request_logs
DROP COLUMN IF EXISTS stream_chunks_sent;

-- Verify rollback
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'request_logs' 
        AND column_name = 'stream_chunks_sent'
    ) THEN
        RAISE EXCEPTION 'Rollback failed: stream_chunks_sent column still exists';
    END IF;
    
    RAISE NOTICE 'Rollback 960_add_stream_chunks_sent completed successfully';
END $$;
