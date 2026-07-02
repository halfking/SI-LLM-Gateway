-- Rollback: 930_ccr_cache_table
-- Purpose: Drop CCR L3 storage table and indexes

DROP INDEX IF EXISTS idx_ccr_session;
DROP INDEX IF EXISTS idx_ccr_created;
DROP TABLE IF EXISTS ccr_cache;
