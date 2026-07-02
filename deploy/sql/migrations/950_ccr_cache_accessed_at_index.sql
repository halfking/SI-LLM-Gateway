-- Migration: 950_ccr_cache_accessed_at_index
-- Purpose: Add index on accessed_at for CCR cache eviction queries
-- Date: 2026-07-02
--
-- The CCR (Columnar Content Repository) L3 storage uses accessed_at to
-- implement LRU eviction when the cache grows too large. Without an index,
-- the eviction query (ORDER BY accessed_at LIMIT N) requires a full table
-- scan, which becomes expensive as the cache grows.
--
-- This index supports:
-- 1. SELECT ... ORDER BY accessed_at ASC LIMIT N (find oldest entries)
-- 2. DELETE FROM ccr_cache WHERE hash IN (...oldest...)
--
-- Performance impact: negligible write overhead (~1-2%), significant read
-- speedup for eviction queries (O(N log N) → O(N)).

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ccr_cache_accessed_at 
    ON ccr_cache (accessed_at);

COMMENT ON INDEX idx_ccr_cache_accessed_at IS 
    'Supports LRU eviction queries (ORDER BY accessed_at ASC LIMIT N) for CCR L3 cache management';
