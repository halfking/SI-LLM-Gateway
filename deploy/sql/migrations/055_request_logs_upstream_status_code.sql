-- 2026-06-30: persist upstream HTTP status code on every request_logs row.
-- Phase 2 (P1) of the minimax-m3 transient-error fix. Operators were seeing
-- error_kind='transient' rows with NULL response_body and had no way to tell
-- whether the failure was 502 (upstream gateway down) vs 429 (rate limit)
-- vs a network timeout. This column gives SQL-level visibility for the
-- "minimax-m3 chat check" diagnostic workflow in the admin UI.
--
-- request_logs is a partitioned table (RANGE on ts) but ADD COLUMN in
-- PostgreSQL 11+ propagates the column to all partitions automatically
-- without rewriting data, so this is online-safe even on large tables.

ALTER TABLE request_logs ADD COLUMN IF NOT EXISTS upstream_status_code int;

-- Backfill from candidate_failure_logs (best-effort, pick latest attempt's
-- status code per request_id). Only fills rows that we know failed; leaves
-- successful rows NULL.
UPDATE request_logs r
SET upstream_status_code = cfl.upstream_status_code
FROM (
    SELECT DISTINCT ON (request_id) request_id, upstream_status_code
    FROM candidate_failure_logs
    WHERE upstream_status_code IS NOT NULL
    ORDER BY request_id, attempt_index DESC
) cfl
WHERE r.request_id = cfl.request_id
  AND r.success = false
  AND r.upstream_status_code IS NULL;

CREATE INDEX IF NOT EXISTS idx_request_logs_upstream_status
    ON request_logs (upstream_status_code, ts DESC)
    WHERE upstream_status_code IS NOT NULL;

COMMENT ON COLUMN request_logs.upstream_status_code IS
    'HTTP status code returned by upstream (NULL = network-level error, success, or unknown). Populated from the last attempt in executor.go and persisted via telemetry/client.go INSERT/UPDATE.';