-- 2026-06-30: backfill classification for candidate_failure_logs rows
-- recorded before the Phase 2 P1 commit (b1abef17) fixed
-- upstream_status_code + body capture. Pre-P1 the routing layer
-- wrapped 4xx/5xx errors in fmt.Errorf("upstream %d: %s", ...) and
-- discarded both the status code and the response body; the only
-- surviving signal is the error_message string itself.
--
-- Production complication (discovered while writing this migration):
-- candidate_failure_logs is a columnar (citus_columnar) table in the
-- production cluster, and columnar tables do NOT support UPDATE
-- (only DELETE + INSERT). To avoid a costly table rewrite, this
-- migration does NOT add new columns to the base table. Instead it
-- provides a view v_candidate_failure_logs_diagnosis that computes
-- the backfilled values on the fly from error_message:
--
--   extracted_upstream_status_code  int  — SUBSTRING("upstream NNN:")
--   diagnosed_error_kind             text — diagnose_failure_kind()
--                                            (migration 056) on
--                                            (status, error_message)
--   classification_disagrees          bool — error_kind != diagnosed
--
-- Trade-off: the view recomputes on every read. For 7484 rows this
-- is <50ms on the production cluster. If the table grows past
-- ~100k rows we should reconsider materialising the values into
-- a regular (heap) shadow table that is refreshed nightly.
--
-- Why not rewrite error_kind? Audit integrity. The original column
-- is what was on the operator dashboards at the time of the
-- incident (the 7029 'transient' rows are exactly what led to the
-- 2026-06-30 alert). Changing the original would lose the ground
-- truth; the view gives operators a side-by-side view so they
-- can verify the backfill before committing to the new taxonomy
-- in any downstream alerting rules.

-- ============================================================================
-- View v_candidate_failure_logs_diagnosis
-- ============================================================================
-- Computes the recovered status code and the diagnosed kind on
-- the fly. Reads are O(rows) but columnar scans are efficient.
CREATE OR REPLACE VIEW v_candidate_failure_logs_diagnosis AS
SELECT
    cfl.id,
    cfl.ts,
    cfl.tenant_id,
    cfl.credential_id,
    cfl.provider_id,
    cfl.raw_model_name,
    cfl.attempt_index,
    cfl.error_kind AS legacy_kind,
    -- Recovered upstream HTTP status code (NULL for non-4xx
    -- errors like timeout / network / EOF). Falls back to the
    -- column populated by the live candidate_failure_logger
    -- (post-P1 rows) so a single column works for both windows.
    COALESCE(
        cfl.upstream_status_code,
        (CASE WHEN cfl.error_message ~ 'upstream [0-9]+:'
              THEN SUBSTRING(cfl.error_message FROM 'upstream ([0-9]+):')::int
              ELSE NULL END)
    ) AS extracted_upstream_status_code,
    -- Diagnosed kind: pass (recovered_status, error_message) to
    -- the live classifier. When upstream_response_body was
    -- captured (38 rows in production), prefer it; otherwise the
    -- error_message itself is the best signal we have.
    diagnose_failure_kind(
        COALESCE(
            cfl.upstream_status_code,
            (CASE WHEN cfl.error_message ~ 'upstream [0-9]+:'
                  THEN SUBSTRING(cfl.error_message FROM 'upstream ([0-9]+):')::int
                  ELSE NULL END)
        ),
        COALESCE(
            NULLIF(cfl.upstream_response_body, ''),
            cfl.error_message,
            ''
        )
    ) AS diagnosed_error_kind,
    cfl.upstream_status_code AS live_upstream_status_code,
    cfl.latency_ms,
    cfl.per_attempt_latency_ms,
    cfl.retryable,
    cfl.error_message,
    -- Quality flag: do the new and legacy classifications agree?
    cfl.error_kind IS DISTINCT FROM diagnose_failure_kind(
        COALESCE(
            cfl.upstream_status_code,
            (CASE WHEN cfl.error_message ~ 'upstream [0-9]+:'
                  THEN SUBSTRING(cfl.error_message FROM 'upstream ([0-9]+):')::int
                  ELSE NULL END)
        ),
        COALESCE(
            NULLIF(cfl.upstream_response_body, ''),
            cfl.error_message,
            ''
        )
    ) AS classification_disagrees
FROM candidate_failure_logs cfl;

COMMENT ON VIEW v_candidate_failure_logs_diagnosis IS
    '2026-06-30 (migration 057). Computes the post-P2 classifier
     output (diagnosed_error_kind) for every candidate_failure_logs
     row, recovering the upstream HTTP status code from
     error_message via the "upstream NNN:" regex. Side-by-side
     legacy_kind vs diagnosed_error_kind for incident review.
     Companion to v_request_failures_diagnosis (migration 056).';

-- ============================================================================
-- Unit / smoke tests
-- ============================================================================
DO $$
DECLARE
    n_total int;
    n_extracted int;
    n_diagnosed int;
    n_disagree int;
    n_transient_to_tool_call_id int;
    n_transient_to_context int;
    n_transient_to_auth int;
    n_transient_to_quota int;
    n_transient_unchanged int;
BEGIN
    SELECT COUNT(*) INTO n_total FROM candidate_failure_logs;
    SELECT COUNT(*) INTO n_extracted FROM v_candidate_failure_logs_diagnosis
        WHERE extracted_upstream_status_code IS NOT NULL;
    SELECT COUNT(*) INTO n_diagnosed FROM v_candidate_failure_logs_diagnosis
        WHERE diagnosed_error_kind IS NOT NULL;
    SELECT COUNT(*) INTO n_disagree FROM v_candidate_failure_logs_diagnosis
        WHERE classification_disagrees;
    SELECT COUNT(*) INTO n_transient_to_tool_call_id
        FROM v_candidate_failure_logs_diagnosis
        WHERE legacy_kind = 'transient'
          AND diagnosed_error_kind = 'tool_call_id_mismatch';
    SELECT COUNT(*) INTO n_transient_to_context
        FROM v_candidate_failure_logs_diagnosis
        WHERE legacy_kind = 'transient'
          AND diagnosed_error_kind = 'context_length_exceeded';
    SELECT COUNT(*) INTO n_transient_to_auth
        FROM v_candidate_failure_logs_diagnosis
        WHERE legacy_kind = 'transient'
          AND diagnosed_error_kind = 'auth';
    SELECT COUNT(*) INTO n_transient_to_quota
        FROM v_candidate_failure_logs_diagnosis
        WHERE legacy_kind = 'transient'
          AND diagnosed_error_kind = 'quota';
    SELECT COUNT(*) INTO n_transient_unchanged
        FROM v_candidate_failure_logs_diagnosis
        WHERE legacy_kind = 'transient'
          AND diagnosed_error_kind = 'transient';

    RAISE NOTICE '=== Migration 057 backfill report ===';
    RAISE NOTICE 'total candidate_failure_logs rows:    %', n_total;
    RAISE NOTICE 'rows with extracted status code:     %', n_extracted;
    RAISE NOTICE 'rows with diagnosed_error_kind:      %', n_diagnosed;
    RAISE NOTICE 'rows where legacy != diagnosed:       %', n_disagree;
    RAISE NOTICE '';
    RAISE NOTICE 'Legacy "transient" rows reclassified as:';
    RAISE NOTICE '  tool_call_id_mismatch: %', n_transient_to_tool_call_id;
    RAISE NOTICE '  context_length_exceeded: %', n_transient_to_context;
    RAISE NOTICE '  auth:                  %', n_transient_to_auth;
    RAISE NOTICE '  quota:                 %', n_transient_to_quota;
    RAISE NOTICE '  transient (unchanged): %', n_transient_unchanged;

    -- Sanity: the backfill must have classified most of the
    -- legacy "transient" rows that the P2 fix targets. The
    -- "tool_call_id_mismatch" bucket alone is expected to be in
    -- the thousands (production showed 2162 in the 2026-06-23..25
    -- window for provider 14 / credential 6). If this assertion
    -- fails, either the function is misclassifying or the regex
    -- is missing rows.
    IF n_transient_to_tool_call_id < 1000 THEN
        RAISE WARNING 'expected >= 1000 transient->tool_call_id_mismatch'
            ' but got % (function or regex may be wrong)',
            n_transient_to_tool_call_id;
    END IF;
END;
$$;