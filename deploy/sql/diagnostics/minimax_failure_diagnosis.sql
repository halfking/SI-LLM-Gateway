-- ============================================================================
-- minimax_failure_diagnosis.sql
--
-- 2026-06-30: Operations diagnostic queries for the minimax-m3 transient
-- error incident. Reads from v_request_failures_diagnosis (migration 056)
-- and other request_logs / candidate_failure_logs tables.
--
-- All queries are parameterised by a 7-day window by default. Override
-- the timestamps in §0 to focus on a specific incident.
--
-- Run order:
--   1. §1 — overall health snapshot
--   2. §2 — per-provider / per-credential breakdown
--   3. §3 — what the diagnosed_kind view says about the legacy error_kind
--   4. §4 — top "real" transient cases (after P2 classification)
--   5. §5 — provider 18 404 spike investigation (separate issue)
--   6. §6 — pre-P1 baseline that motivates the column additions
--
-- Requires: migrations 055 (upstream_status_code column) + 056
-- (diagnose_failure_kind function + v_request_failures_diagnosis view).
-- Pre-P1 archive data: diagnosed_kind falls back to legacy_kind because
-- response_body and upstream_status_code are NULL on archived rows.
-- ============================================================================

-- §0. Time window (override for incident-specific slicing)
\set window_start 'NOW() - INTERVAL ''7 days'''
\set window_end   'NOW()'

-- ============================================================================
-- §1. Overall health snapshot
-- ============================================================================

\echo
\echo '=== §1.1 — Total failures by kind (last 7d) ==='
SELECT
    diagnosed_kind,
    COUNT(*) AS rows,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM v_request_failures_diagnosis
WHERE ts BETWEEN :window_start AND :window_end
GROUP BY 1
ORDER BY rows DESC;

\echo
\echo '=== §1.2 — Same data, filtered to known false-positive legacy_kind ==='
\echo '    (operators learn to read the table by recognising transient noise)'
SELECT
    legacy_kind,
    diagnosed_kind,
    COUNT(*) AS rows
FROM v_request_failures_diagnosis
WHERE ts BETWEEN :window_start AND :window_end
  AND legacy_kind IN ('transient', 'model_not_found', 'provider_error')
GROUP BY 1, 2
ORDER BY rows DESC
LIMIT 20;

\echo
\echo '=== §1.3 — Is the new code deployed yet? (post-P1 indicator) ==='
\echo '    If upstream_status_code is non-NULL on most failures, the new'
\echo '    code is deployed. If NULL everywhere, the binary is still the'
\echo '    pre-P1 version.'
SELECT
    COUNT(*) AS total_failures,
    COUNT(upstream_status_code) AS with_upstream_status,
    ROUND(100.0 * COUNT(upstream_status_code) / NULLIF(COUNT(*), 0), 1) AS pct_with_status
FROM v_request_failures_diagnosis
WHERE ts BETWEEN :window_start AND :window_end;

-- ============================================================================
-- §2. Per-provider / per-credential breakdown
-- ============================================================================

\echo
\echo '=== §2.1 — Failures by provider (sorted by count) ==='
SELECT
    provider_id,
    COUNT(DISTINCT credential_id) AS credentials,
    COUNT(*) AS failures,
    COUNT(*) FILTER (WHERE legacy_kind = 'transient') AS legacy_transient,
    COUNT(*) FILTER (WHERE diagnosed_kind = 'transient') AS diagnosed_transient,
    COUNT(*) FILTER (WHERE diagnosed_kind = 'tool_call_id_mismatch') AS diagnosed_tool_call_id,
    COUNT(*) FILTER (WHERE diagnosed_kind = 'context_length_exceeded') AS diagnosed_ctx
FROM v_request_failures_diagnosis
WHERE ts BETWEEN :window_start AND :window_end
GROUP BY 1
ORDER BY failures DESC
LIMIT 15;

\echo
\echo '=== §2.2 — Top failing credentials (use this to check the original'
\echo '    2026-06-30 minimax-m3 / credential 6 case) ==='
SELECT
    provider_id,
    credential_id,
    COUNT(*) AS failures,
    COUNT(*) FILTER (WHERE diagnosed_kind = 'transient') AS transient,
    COUNT(*) FILTER (WHERE diagnosed_kind = 'tool_call_id_mismatch') AS tool_call_id,
    COUNT(*) FILTER (WHERE diagnosed_kind = 'context_length_exceeded') AS ctx_exceeded,
    COUNT(*) FILTER (WHERE diagnosed_kind = 'auth') AS auth,
    ROUND(AVG(latency_ms)) AS avg_latency_ms,
    MAX(latency_ms) AS max_latency_ms
FROM v_request_failures_diagnosis
WHERE ts BETWEEN :window_start AND :window_end
GROUP BY 1, 2
ORDER BY failures DESC
LIMIT 20;

-- ============================================================================
-- §3. Legacy vs diagnosed — the P2 fix in numbers
-- ============================================================================

\echo
\echo '=== §3.1 — Disagreement between legacy error_kind and diagnosed_kind ==='
\echo '    Shows how many rows had their classification CHANGED by the P2'
\echo '    fix. The fix only affects post-deployment data; for archive data'
\echo '    (pre-P1) both columns are equal because no body was captured.'
SELECT
    legacy_kind,
    diagnosed_kind,
    COUNT(*) AS rows
FROM v_request_failures_diagnosis
WHERE ts BETWEEN :window_start AND :window_end
  AND legacy_kind IS DISTINCT FROM diagnosed_kind
GROUP BY 1, 2
ORDER BY rows DESC
LIMIT 30;

\echo
\echo '=== §3.2 — Was the P1 column actually populated on these rows? ==='
\echo '    P1 (upstream_status_code column) was added in migration 055.'
\echo '    If this query returns 0, the production binary is still the'
\echo '    pre-P1 version and the new code needs to be deployed.'
SELECT
    upstream_status_code,
    COUNT(*) AS rows
FROM v_request_failures_diagnosis
WHERE ts BETWEEN :window_start AND :window_end
  AND upstream_status_code IS NOT NULL
GROUP BY 1
ORDER BY rows DESC
LIMIT 20;

-- ============================================================================
-- §4. Real transient candidates (after P2)
-- ============================================================================
-- A "transient" classification post-P2 is reserved for upstream errors
-- that don't match any of the precise known categories. These are the
-- cases that DO warrant investigation: they could be real network
-- failures, upstream bugs we haven't seen before, or new vendor error
-- formats.

\echo
\echo '=== §4.1 — diagnosed_kind = ''transient'' (the remaining unknown) ==='
\echo '    These are the cases where the body did not match any of the'
\echo '    known patterns. Inspect the response_body to see what the'
\echo '    upstream is actually saying.'
SELECT
    provider_id,
    credential_id,
    client_model,
    outbound_model,
    COUNT(*) AS rows,
    -- Top failure_stage for this group
    MODE() WITHIN GROUP (ORDER BY failure_stage) AS typical_stage,
    -- First non-NULL response_body snippet (320 chars max)
    SUBSTRING(MIN(response_body_text) FILTER (WHERE response_body_text IS NOT NULL), 1, 320) AS example_body
FROM v_request_failures_diagnosis
WHERE ts BETWEEN :window_start AND :window_end
  AND diagnosed_kind = 'transient'
GROUP BY 1, 2, 3, 4
ORDER BY rows DESC
LIMIT 15;

\echo
\echo '=== §4.2 — Real transient latency distribution ==='
\echo '    Network-layer transient (i/o timeout) usually shows up as'
\echo '    >= 5s. Application-layer transient usually < 2s.'
SELECT
    CASE
        WHEN latency_ms < 1000  THEN '<1s'
        WHEN latency_ms < 5000  THEN '1-5s'
        WHEN latency_ms < 30000 THEN '5-30s'
        ELSE '>30s'
    END AS latency_bucket,
    COUNT(*) AS rows
FROM v_request_failures_diagnosis
WHERE ts BETWEEN :window_start AND :window_end
  AND diagnosed_kind = 'transient'
GROUP BY 1
ORDER BY 1;

-- ============================================================================
-- §5. Provider 18 404 spike (independent issue, surfaced during the
-- minimax-m3 investigation)
-- ============================================================================

\echo
\echo '=== §5.1 — Provider 18 detail (where the 796 HTTP 404s come from) ==='
SELECT
    credential_id,
    COUNT(*) AS failures_404,
    ROUND(AVG(latency_ms)) AS avg_latency_ms,
    MIN(ts) AS first_seen,
    MAX(ts) AS last_seen,
    -- error_kind on archived rows that were 404:
    -- most are legacy_kind='' (empty) because the 404 came from a
    -- client-side match that never reached the executor
    COUNT(DISTINCT legacy_kind) AS distinct_legacy_kinds
FROM v_request_failures_diagnosis
WHERE ts BETWEEN :window_start AND :window_end
  AND provider_id = 18
GROUP BY 1
ORDER BY failures_404 DESC;

\echo
\echo '=== §5.2 — Provider 18 404 root-cause hint: what client_model was'
\echo '    being requested? ==='
SELECT
    client_model,
    outbound_model,
    COUNT(*) AS rows,
    SUBSTRING(MIN(search_text), 1, 120) AS example_search
FROM v_request_failures_diagnosis
WHERE ts BETWEEN :window_start AND :window_end
  AND provider_id = 18
GROUP BY 1, 2
ORDER BY rows DESC
LIMIT 10;

-- ============================================================================
-- §6. Pre-P1 baseline (justifies the upstream_status_code column add)
-- ============================================================================
-- This shows what was missing before the fix. With NULL upstream_status_code
-- everywhere, the operator could not distinguish 502 upstream gateway
-- failures from 429 rate limits. Run this once on archive data so the
-- historical baseline is documented in runbooks.

\echo
\echo '=== §6.1 — Diagnostic gap: pre-P1 NULL rate ==='
\echo '    of all failures in the window, how many have NO upstream_status_code?'
SELECT
    COUNT(*) AS total_failures,
    COUNT(upstream_status_code) AS with_status,
    COUNT(*) - COUNT(upstream_status_code) AS without_status,
    ROUND(100.0 * (COUNT(*) - COUNT(upstream_status_code)) / NULLIF(COUNT(*), 0), 1)
        AS pct_without_status
FROM v_request_failures_diagnosis
WHERE ts BETWEEN :window_start AND :window_end;

\echo
\echo '=== §6.2 — Ground truth from candidate_failure_logs (June 2026 incident) ==='
\echo '    The 2026-06-23..25 incident window is fully archived in'
\echo '    candidate_failure_logs (3038 rows tagged as "transient"). The'
\echo '    error_message column preserves the upstream status code that'
\echo '    the Go code lost to fmt.Errorf("upstream %d: %s", ...). This'
\echo '    query extracts the real status code with a regex and shows'
\echo '    what would have been visible to operators if P1 had been'
\echo '    deployed at the time.'
SELECT
    SUBSTRING(error_message FROM 'upstream ([0-9]+):') AS extracted_upstream_status,
    error_kind AS legacy_kind,
    provider_id,
    credential_id,
    COUNT(*) AS rows
FROM candidate_failure_logs
WHERE ts BETWEEN '2026-06-23'::timestamptz AND '2026-06-25'::timestamptz
  AND error_message ~ 'upstream [0-9]+:'
GROUP BY 1, 2, 3, 4
ORDER BY rows DESC
LIMIT 25;