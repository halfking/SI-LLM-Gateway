-- Migration 058: materialize request_logs.request_status (2026-06-30)
--
-- Phase 2 (P2) of /request-logs slow-query fix. Migration 056 added
-- indexes; 057 denormalized provider_model. This migration makes
-- request_logs.request_status a queryable column instead of a
-- COALESCE expression, so that WHERE request_status = $1 can finally
-- use the existing idx_request_logs_status_ts partial index.
--
-- Today (pre-058):
--   request_status column exists on request_logs but is not always
--   populated:
--     - happy INSERT path populates it via normalizeRequestStatus()
--     - the early-batch initial INSERT (recordInitialRequestLog) was
--       added later; rows from older gateway versions may have NULL
--     - the upsertRequestLogFallback binds strPtrValue() which can
--       produce "" for a missing pointer
--   So real rows may have:
--     request_status = 'success' | 'failure' | 'in_progress' | NULL | ''
--
--   The read path (admin/logs.go:requestLogStatusExpr) computes:
--     COALESCE(NULLIF(request_status, ''),
--              CASE WHEN success THEN 'success'
--                   WHEN error_kind IS NOT NULL AND error_kind <> '' THEN 'failure'
--                   ELSE 'in_progress' END)
--
--   This COALESCE defeats any index on request_status, because PG can
--   only use a B-tree on the bare column.
--
-- 058 changes:
--
--   1. Backfill rows where request_status is NULL or '' to the same
--      value the COALESCE expression would have computed. The values
--      are produced from success + error_kind only, which are NOT NULL
--      on the existing schema (success is NOT NULL, error_kind is NULL-
--      able). After the backfill:
--        request_status = 'success'  iff success = true
--        request_status = 'failure'  iff success = false AND error_kind NOT NULL/empty
--        request_status = 'in_progress' otherwise
--
--   2. The column stays text (no enum, no NOT NULL). The empty-string
--      case continues to be representable in case a future regression
--      rebinds "" — the partial predicate on idx_request_logs_status_ts
--      continues to filter it out.
--
--   3. The read path (admin/logs.go, admin/logs_summary.go,
--      admin/session_title.go, admin/no_topic_session.go) is updated
--      separately (commit ca0e53ae-style) to read rl.request_status
--      directly, dropping the COALESCE wrapper.
--
-- This migration deliberately does NOT:
--   - Add a NOT NULL constraint. The fallback path in
--     upsertRequestLogFallback binds strPtrValue(entry.RequestStatus)
--     which yields "" for nil pointers; a NOT NULL constraint would
--     reject these rows. Backfilling alone is enough for the read
--     path to use the index.
--   - Drop the partial predicate on idx_request_logs_status_ts.
--     Keeping the partial index is a defense-in-depth: if a future
--     regression re-introduces NULL/'' rows, the index continues to
--     serve the "happy" rows without bloat.
--   - Add a CHECK constraint. The application layer's
--     normalizeRequestStatus() already enforces the three-value
--     invariant; adding a CHECK would be belt-and-suspenders and
--     might conflict with future enum work.
--
-- Companion:
--   - Backfill helper: same CASE expression as the read path (kept
--     in lock-step; any future change must update both).
--   - Read path change: see follow-up commit replacing
--     requestLogStatusExpr with rl.request_status in 5 sites.

-- ----------------------------------------------------------------------------
-- 1) Backfill rows where request_status IS NULL or = ''.
-- ----------------------------------------------------------------------------
-- Done in one statement. Matches the read-path COALESCE semantics
-- exactly. The expression is the same one in admin/logs.go:requestLogStatusExpr
-- (success beats error_kind; an empty error_kind does NOT promote the
-- row to "failure"; otherwise "in_progress").
--
-- No lock contention concern: UPDATE on a partitioned table takes
-- row-level locks; concurrent SELECTs on other partitions are
-- unaffected. The query is partition-pruning friendly (request_status
-- IS NULL OR = '' matches the partial-index complement).
UPDATE request_logs rl
SET request_status = CASE
    WHEN rl.success THEN 'success'
    WHEN rl.error_kind IS NOT NULL AND rl.error_kind <> '' THEN 'failure'
    ELSE 'in_progress'
END
WHERE rl.request_status IS NULL
   OR rl.request_status = '';

-- ----------------------------------------------------------------------------
-- 2) Sanity checks (informational; not enforced).
-- ----------------------------------------------------------------------------
-- These should all return 0 after the UPDATE above. If any of them
-- return > 0 something is wrong with the WHERE clause above.
DO $$
DECLARE
    bad_null   bigint;
    bad_empty  bigint;
    bad_value  bigint;
BEGIN
    SELECT COUNT(*) INTO bad_null
        FROM request_logs WHERE request_status IS NULL;
    SELECT COUNT(*) INTO bad_empty
        FROM request_logs WHERE request_status = '';
    SELECT COUNT(*) INTO bad_value
        FROM request_logs
        WHERE request_status NOT IN ('success', 'failure', 'in_progress');

    RAISE NOTICE 'request_status backfill: NULL=% empty=% unexpected_value=%',
        bad_null, bad_empty, bad_value;
END $$;

COMMENT ON COLUMN request_logs.request_status IS
'Materialized lifecycle status. Always one of in_progress/success/failure for rows
written after migration 058 (enforced by normalizeRequestStatus in
telemetry/client.go and the explicit literal assignments in relay/handler.go,
relay/request_log_pipeline.go, routing/executor.go). Rows written before 058
are backfilled by migration 058 to the same value the read-path COALESCE
would have computed. NULL/empty values are still permitted to avoid
regressing the upsertRequestLogFallback path that binds strPtrValue().';