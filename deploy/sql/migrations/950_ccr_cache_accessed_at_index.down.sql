-- Rollback: 950_ccr_cache_accessed_at_index
-- Purpose: Remove accessed_at index from ccr_cache

DROP INDEX CONCURRENTLY IF EXISTS idx_ccr_cache_accessed_at;
