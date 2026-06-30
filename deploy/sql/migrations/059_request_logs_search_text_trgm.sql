-- Migration 059: GIN trgm index on request_logs.search_text (2026-07-01)
--
-- Phase 2 (P2) of /request-logs slow-query fix. The /api/logs ?q=
-- filter was previously:
--
--   rl.search_text ILIKE '%' || $1 || '%'
--
-- search_text has no B-tree or GIN index, so this WHERE clause
-- forced a sequential scan of the 24h partition. For a query the
-- UI fires from the search box on every keystroke (debounced),
-- this is the dominant cost after the LATERAL removal in 9a20359b.
--
-- This migration adds a GIN trgm index on request_logs.search_text.
-- The index lets PG plan:
--   Bitmap Heap Scan -> Bitmap Index Scan on idx_request_logs_search_text_trgm
-- instead of the previous Seq Scan.
--
-- Schema reference (already created by 056 + earlier migrations):
--
--   - idx_request_logs_client_model_trgm: same pattern, GIN trgm on
--     client_model. Used by the ?model= filter via
--     admin/logs.go:457-474. Not changed by this migration; already
--     serving the model= filter correctly.
--
-- Why GIN trgm specifically (not B-tree text_pattern_ops):
--
--   - search_text contains tokens like error_kind labels, failure
--     detail codes, error snippets, model names, request_id prefixes
--     and identity_hash. The q= filter matches ANY substring of any
--     of those. A prefix-only B-tree would miss "rate limit" inside
--     a longer token.
--   - trgm GIN handles %foo% natively via the gin_trgm_ops opclass.
--   - The cost is ~3x larger index than a B-tree and slower writes
--     (GIN builds a pending list). For a write-heavy table this is
--     the main trade-off; we accept it because the read path is the
--     bottleneck (the request-logs page is opened many times per
--     minute by ops, writes are batched through the telemetry queue).
--
-- Why parent-only (no per-partition attach files):
--
--   request_logs is PARTITION BY RANGE(ts). On PG 11+, an index
--   declared on the parent table is automatically propagated to all
--   existing AND future partitions. The existing GIN indexes
--   (idx_request_logs_quality_flags, idx_request_logs_tool_calls,
--   idx_request_logs_client_model_trgm) follow this pattern. The
--   per-partition _attach files under deploy/sql/objects/indexes/
--   are pg_dump snapshots for documentation/replay; they are NOT
--   required at runtime and are NOT touched by this migration.
--
-- Online-safety:
--
--   CREATE INDEX without CONCURRENTLY takes a SHARE lock on the
--   parent table that blocks writes for the duration of the build.
--   On a 100M-row table that can take 10-30 minutes. Operators
--   who need to keep the gateway live should run the index build
--   in two phases (see down.sql for the rollback recipe + a
--   CONCURRENTLY-style note).
--
-- Companion:
--   - db/db.go: ensureRequestLogSchema mirrors the CREATE INDEX
--     statement so a fresh deployment gets the index without
--     needing to run this migration manually.

-- ----------------------------------------------------------------------------
-- 1) The index itself.
-- ----------------------------------------------------------------------------
-- pg_trgm is a contrib extension that should already be enabled on
-- production (the existing client_model_trgm index uses it). If
-- CREATE INDEX fails with 'extension "pg_trgm" is not available',
-- run: CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_request_logs_search_text_trgm
    ON public.request_logs
    USING gin (search_text public.gin_trgm_ops);

COMMENT ON INDEX public.idx_request_logs_search_text_trgm IS
'GIN trigram index on request_logs.search_text. Speeds up the ?q=
substring filter in /api/logs (admin/logs.go:420) from Seq Scan to
Bitmap Heap Scan. Read-heavy table; index cost (~3x plain B-tree)
is justified. Created by migration 059.';