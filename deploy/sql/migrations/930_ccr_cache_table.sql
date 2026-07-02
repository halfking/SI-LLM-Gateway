-- Migration: 930_ccr_cache_table
-- Purpose: Create CCR (Columnar Content Repository) L3 storage table
-- Date: 2026-07-02
--
-- CCR is the L3 storage layer for Headroom compression. It stores compressed
-- JSON array data with session-scoped access control. This enables:
--
-- 1. Lossless compression: Large arrays are stored here, replaced with markers
-- 2. Session isolation: Each hash is bound to a session_id for security
-- 3. Retrieval: LLM can call headroom_retrieve tool to fetch original data
-- 4. Eviction: LRU eviction based on accessed_at for cache management
--
-- L1 (sync.Map) → L2 (Redis) → L3 (PostgreSQL)
-- Only L3 can enforce session isolation (L1/L2 are content-only caches).

CREATE TABLE IF NOT EXISTS ccr_cache (
    hash VARCHAR(24) PRIMARY KEY,           -- 24-char hex hash (96 bits)
    data BYTEA NOT NULL,                    -- Compressed JSON array
    session_id VARCHAR(64),                 -- Gateway session ID (for isolation)
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    accessed_at TIMESTAMP NOT NULL DEFAULT NOW(),
    access_count INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Index for session-scoped lookups (security-critical)
CREATE INDEX IF NOT EXISTS idx_ccr_session ON ccr_cache(session_id);

-- Index for eviction queries (find oldest entries)
CREATE INDEX IF NOT EXISTS idx_ccr_created ON ccr_cache(created_at);

-- Index for LRU eviction (added in migration 950)
-- CREATE INDEX IF NOT EXISTS idx_ccr_accessed ON ccr_cache(accessed_at);

COMMENT ON TABLE ccr_cache IS 
    'CCR L3 storage for Headroom-compressed JSON arrays. Session-scoped for security.';
COMMENT ON COLUMN ccr_cache.hash IS 
    '24-char hex hash (96 bits) of compressed data';
COMMENT ON COLUMN ccr_cache.session_id IS 
    'Gateway session ID for cross-session access prevention (SECURITY)';
COMMENT ON COLUMN ccr_cache.accessed_at IS 
    'Last access timestamp for LRU eviction';
