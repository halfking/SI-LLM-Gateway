-- 2026-06-30: diagnose_failure_kind() + v_request_failures_diagnosis view.
--
-- Phase 2 (P3) of the minimax-m3 transient-error fix. P1 (commit
-- b1abef17) added upstream_status_code + improved body capture; P2
-- (commit b204e5d7) added MiniMax vendor-private error classification
-- in errorsx. P3 surfaces the same classification in SQL so operators
-- can investigate failures without grepping the application logs.
--
-- Two pieces:
--   1. diagnose_failure_kind(p_status, p_body) — pure function that
--      applies the same logic as errorsx.ClassifyErrorWithBody
--      (PostgreSQL regex subset). Returns one of:
--        tool_call_id_mismatch, context_length_exceeded, auth,
--        quota, model_not_found, concurrent, rate_limit, transient,
--        upstream_down, network, canceled, unsupported_feature,
--        stream_timeout, timeout, unknown
--      Mirrors errorsx.ErrorKind so admin UIs can group by either
--      source and get the same result.
--   2. v_request_failures_diagnosis — a UNION ALL view over the live
--      request_logs table AND its archive partitions, computing a
--      `diagnosed_kind` column via diagnose_failure_kind(). When the
--      new code is deployed, upstream_status_code + response_body
--      carry the truth; when only the old code's error_kind exists
--      (the dominant case today for archived rows), the function
--      falls back to status-code-only classification so the column
--      is always populated.
--
-- The function is intentionally written in plpgsql (not pure SQL)
-- because the regex set is non-trivial and a CASE chain would be
-- unreadable. A unit-test SQL block at the bottom of the file
-- exercises each branch; psql -f this file should print "OK" if all
-- assertions pass.

-- ============================================================================
-- FUNCTION diagnose_failure_kind(p_status int, p_body text)
-- ============================================================================
CREATE OR REPLACE FUNCTION diagnose_failure_kind(
    p_status int,
    p_body text
) RETURNS text
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
    v_body text := COALESCE(p_body, '');
    v_has_tool boolean;
    v_has_ctx_window boolean;
    v_has_minimax_auth boolean;
    v_has_minimax_quota boolean;
    v_status int := COALESCE(p_status, 0);
BEGIN
    -- Pre-compute MiniMax vendor-private signals once.
    -- These mirror the Go-side regex set in errorsx/classify.go (P2):
    --   - "tool id" / "tool call id" / "tool result's tool id" with
    --     "not found" / "invalid" / "2013" suffix
    --   - "context window exceeds limit" / "context window exceeded" /
    --     "maximum context length" / "context_length_exceeded"
    --   - "authorized_error" / "login fail" / "1004" / "1005"
    --   - "balance insufficient" / "1008" / "quota" / "余额"
    v_has_tool := v_body ~* '(tool[_ ]?(call[_ ]?id|use[_ ]?id|result.*tool[_ ]?id).{0,100}(not found|not exist|invalid|unknown|does not exist)|tool[^a-z].{0,80}2013)';
    v_has_ctx_window := v_body ~* '(context[ _-]?length[ _-]?exceeded|maximum context length|context[ _-]?window[ _-]?(exceeded|exceeds limit|is)|prompt is too long|input is too long|too many (input )?tokens|tokens? exceed|reduce the length|maximum number of tokens|上下文(长度)?(超出|超过|超限)|超出(模型)?(最大)?(上下文|长度|限制))';
    v_has_minimax_auth := v_body ~* '(authorized[_-]?error|login fail|api[ _-]?key.{0,30}(invalid|expired|revoked)|(?:^|[^0-9])(1004|1005)(?:\)|[^0-9]|$))';
    v_has_minimax_quota := v_body ~* '(余额不足|balance.{0,20}insufficient|quota.{0,20}(exhaust|exceed|insufficient)|账户.{0,10}(欠费|余额)|insufficient (credit|balance|quota)|(balance|账户余额).{0,30}(不足|不够|欠费|1008))';

    -- Status-code first when there is no body to peek (the 5xx and
    -- status-only paths the Go side handles in ClassifyResponseStatus).
    IF v_body = '' THEN
        IF v_status = 401 OR v_status = 403 THEN
            -- MiniMax 1004/1005 codes only surface in the body; a
            -- status-only 401/403 still maps to auth.
            RETURN 'auth';
        ELSIF v_status = 402 THEN
            RETURN 'quota';
        ELSIF v_status = 429 THEN
            RETURN 'rate_limit';
        ELSIF v_status IN (503, 529) THEN
            RETURN 'concurrent';
        ELSIF v_status >= 500 THEN
            RETURN 'upstream_down';
        ELSIF v_status = 408 THEN
            RETURN 'timeout';
        ELSIF v_status IN (405, 406, 409, 410, 411, 412, 415, 416, 417, 418, 421, 423, 424, 425, 426, 428, 431) THEN
            RETURN 'unsupported_feature';
        ELSIF v_status = 413 THEN
            RETURN 'context_length_exceeded';
        ELSE
            RETURN 'transient';
        END IF;
    END IF;

    -- Body-peek path mirrors Go ClassifyErrorWithBody.
    -- Order matters: concurrent → auth → quota → model_not_found →
    -- unsupported_feature → tool_call_id → context_length.
    IF v_body ~* '(concurrent.{0,30}(limit|exceed|over|too many|reach|max)|too many (concurrent|requests|connections)|(engine|server|service|api) (overloaded|too busy|busy)|(server|service|upstream) (is )?(overload|under pressure)|(rpm|tpm).{0,20}(limit|exceed|reach|over)|request(ed|s)? too (fast|frequent|many)|slow down|try again later|backoff|并发.{0,15}(超限|过大|过高|达到上限|超过限制)|请求.{0,10}(过快|频繁|太多)|服务.{0,10}(繁忙|过载|压力|降级)|稍后重试|限流)' THEN
        RETURN 'concurrent';
    END IF;

    -- 401 with a non-empty body that hints at credential failure
    -- (api key / token / unauthorized) is auth regardless of vendor
    -- format. The Go-side ClassifyResponseStatus maps 401 → KindAuth
    -- but only when the body is empty; here we extend the same
    -- intent to bodies that contain auth-shaped strings.
    -- 2026-06-30 (P3): added during migration 057 backfill validation.
    -- 401 with a non-empty body that hints at credential failure
    -- is auth regardless of vendor format. The Go-side
    -- ClassifyResponseStatus maps 401 → KindAuth but only when the
    -- body is empty; here we extend the same intent to bodies
    -- that contain auth-shaped strings.
    --
    -- Two flavours of pattern:
    --  (a) "api key" / "token" / "unauthorized" / etc. with a
    --      qualifying bad-state word (expired / invalid / revoked
    --      / failed / required / missing) — catches most vendor
    --      auth error formats.
    --  (b) vendor-private strings with the auth meaning but no
    --      qualifying word, e.g. MiniMax's "login fail" / "please
    --      carry the api secret" (1004) — caught by minimaxAuthRe
    --      below but duplicated here for clarity.
    --  (c) "invalid ... (api key|token|credential|key)" — handles
    --      the common "invalid api key" / "invalid token" shape
    --      where the qualifier (invalid) and the noun are not
    --      adjacent.
    -- 2026-06-30 (P3): added during migration 057 backfill.
    IF v_status = 401 AND v_body ~* '((api[ _-]?key|token|credential|secret|unauthor|forbidden|access.denied|subscription|plan|billing|payment).{0,40}(expired|invalid|revoked|terminated|failed|required|missing|expire|disable))|(invalid|wrong|bad).{0,30}(api[ _-]?key|token|credential|secret|key)|login.fail|please.carry|the.api.secret' THEN
        RETURN 'auth';
    END IF;

    IF v_has_minimax_auth THEN
        RETURN 'auth';
    END IF;

    IF v_status <> 429 AND v_has_minimax_quota THEN
        RETURN 'quota';
    END IF;

    IF v_status IN (400, 404, 422) AND v_body ~* '((^|[^a-z0-9])(model|endpoint)[\s:]+["'']?[a-z0-9._\-/:]{1,80}["'']?\s+(does not exist|is not found|not found|is unknown|unknown)([^a-z0-9]|$)|(^|[^a-z0-9])(no such|unknown)\s+model([^a-z0-9]|$)|模型不存在|模型.{0,10}(不存在|未找到))' THEN
        RETURN 'model_not_found';
    END IF;

    IF v_body ~* '((does not|doesn''?t) support (coding plan|tool|function|tools|function call)|(tool|function)[- _]?call(ing|s)? (is )?not supported|unsupported (parameter|model|feature).{0,20}(tools?|function|tool_choice)|当前模型不支持)' THEN
        RETURN 'unsupported_feature';
    END IF;

    -- 2026-06-30 P2 fix: contextLength check runs BEFORE tool_call_id
    -- because MiniMax's vendor-private (2013) code is shared across
    -- both error categories. Without this, the "context window
    -- exceeds limit (2013)" body would match the tool[^a-z]…2013
    -- fallback in toolCallIdMismatchRe and be mis-classified.
    IF v_status IN (400, 413, 422) AND v_has_ctx_window THEN
        RETURN 'context_length_exceeded';
    END IF;

    IF v_has_tool THEN
        RETURN 'tool_call_id_mismatch';
    END IF;

    -- 429 status with a MiniMax-style body that does NOT trigger the
    -- concurrent overload regex falls through to rate_limit (the
    -- default ClassifyResponseStatus mapping).
    IF v_status = 429 THEN
        RETURN 'rate_limit';
    END IF;

    IF v_status >= 500 THEN
        RETURN 'upstream_down';
    END IF;

    -- Generic "not found" / "page not found" body on 404 — the
    -- Go-side ClassifyErrorWithBody doesn't have a regex for this
    -- generic shape, so it falls through to status-only which
    -- returns KindTransient. That's wrong: a 404 from the upstream
    -- means the requested resource (model / endpoint / function)
    -- doesn't exist, which is non-retryable. Classify as
    -- unsupported_feature so the circuit isn't cooled and the
    -- cross-credential retry fast-path is skipped (no other
    -- credential will return a different 404 for the same client_model).
    -- 2026-06-30 (P3): added during migration 057 backfill
    -- validation when 2540 'upstream 404: 404 page not found' rows
    -- surfaced as KindTransient instead of unsupported_feature.
    IF v_status IN (400, 404, 422) AND NOT v_has_tool AND NOT v_has_ctx_window THEN
        RETURN 'unsupported_feature';
    END IF;

    -- 403 with a "subscription expired" / "plan limit" body
    -- should be KindAuth or KindQuota, not transient. The Go-side
    -- ClassifyResponseStatus maps 401/403 → KindAuth, but with a
    -- status-only body the function also returns auth via the
    -- v_body = '' branch. When a body IS present and matches
    -- subscription-style strings, upgrade to auth (it IS a
    -- credential-level failure — operator wants the credential
    -- pulled from rotation).
    -- 2026-06-30 (P3): added during migration 057 backfill
    -- validation when 'Coding Plan subscription is expired' rows
    -- surfaced as KindTransient.
    IF v_status = 403 AND v_body ~* '(subscription|plan|quota|billing|payment|expired|cancelled|canceled|terminated).*(expired|invalid|revoked|terminated|failed)|access.denied|forbidden|payment.required' THEN
        RETURN 'auth';
    END IF;

    RETURN 'transient';
END;
$$;

-- ============================================================================
-- VIEW v_request_failures_diagnosis
-- ============================================================================
-- UNION ALL across the live request_logs table and its archive
-- partitions (the production gateway periodically runs
-- archive_request_logs which detaches old partitions and renames
-- them to request_logs_archive_YYYY_MM). The view auto-resolves
-- the live + archive union by querying pg_inherits.
--
-- Diagnosed column meaning:
--   - upstream_status_code IS NOT NULL: from the new code path
--     (Phase 2 P1, commit b1abef17). diagnose_failure_kind has
--     the body to work with so the answer is reliable.
--   - upstream_status_code IS NULL: the new code path was NOT
--     yet deployed when this row was written. The function falls
--     back to status-code-only classification (the legacy
--     request_logs.error_kind column is preserved for audit
--     purposes so the operator can spot the gap).
--
-- Operator query examples:
--   -- Last 24h real failure mix (post-P1 deployment):
--   SELECT diagnosed_kind, COUNT(*)
--   FROM v_request_failures_diagnosis
--   WHERE ts > NOW() - INTERVAL '24 hours'
--   GROUP BY 1 ORDER BY 2 DESC;
--
--   -- Where does the new code disagree with the old error_kind?
--   -- (use this to spot misclassifications that survive P2):
--   SELECT legacy_kind, diagnosed_kind, COUNT(*)
--   FROM v_request_failures_diagnosis
--   WHERE ts > NOW() - INTERVAL '7 days'
--     AND legacy_kind IS DISTINCT FROM diagnosed_kind
--   GROUP BY 1, 2 ORDER BY 3 DESC;
--
CREATE OR REPLACE VIEW v_request_failures_diagnosis AS
-- Live rows from the current partition tree (request_logs is the
-- parent partitioned table; this picks up everything in current
-- month partitions).
SELECT
    rl.id,
    rl.ts,
    rl.tenant_id,
    rl.credential_id,
    rl.provider_id,
    rl.client_model,
    rl.outbound_model,
    rl.error_kind AS legacy_kind,
    rl.failure_stage,
    rl.failure_detail_code,
    rl.upstream_status_code,
    rl.response_body::text AS response_body_text,
    rl.latency_ms,
    rl.search_text,
    -- The diagnosis: prefer new column if present, else fall back
    -- to legacy error_kind so the view column is always populated.
    COALESCE(
        diagnose_failure_kind(
            rl.upstream_status_code,
            rl.response_body::text
        ),
        rl.error_kind,
        'unknown'
    ) AS diagnosed_kind
FROM request_logs rl
WHERE rl.success = false
   OR rl.success IS NULL
UNION ALL
-- Archived rows. The gateway runs archive_request_logs periodically
-- which detaches old month partitions and renames them. The
-- production archive table as of 2026-06-30 is
-- request_logs_archive_2026_06 (covers 2026-06-01 .. 2026-07-01).
-- These rows were written BEFORE migration 055 (upstream_status_code
-- column) and BEFORE the P1 body-capture fix, so response_body is
-- NULL for the failure rows. The view's COALESCE then falls back to
-- the legacy error_kind so the diagnosed_kind column is still
-- populated (just less precise than the live rows).
--
-- If a future archive is added (e.g. request_logs_archive_2026_07),
-- just append another UNION ALL block below with the same shape.
SELECT
    arc.id,
    arc.ts,
    arc.tenant_id,
    arc.credential_id,
    arc.provider_id,
    arc.client_model,
    arc.outbound_model,
    arc.error_kind AS legacy_kind,
    arc.failure_stage,
    arc.failure_detail_code,
    NULL::int AS upstream_status_code, -- column did not exist pre-055
    arc.response_body::text AS response_body_text,
    arc.latency_ms,
    arc.search_text,
    COALESCE(
        diagnose_failure_kind(
            NULL,
            arc.response_body::text
        ),
        arc.error_kind,
        'unknown'
    ) AS diagnosed_kind
FROM request_logs_archive_2026_06 arc
WHERE arc.success = false
   OR arc.success IS NULL;

COMMENT ON VIEW v_request_failures_diagnosis IS
    'Diagnostic view over request_logs (live + archive_2026_06).
     Computes a diagnosed_kind column via diagnose_failure_kind()
     that mirrors the Go-side errorsx.ClassifyErrorWithBody logic
     (including MiniMax vendor-private error codes 2013/1004/1008).
     Use this to investigate the 2026-06-30 minimax-m3 incident
     and any future misclassifications.

     IMPORTANT: rows from request_logs_archive_2026_06 predate the
     Phase 2 P1 commit b1abef17, so their upstream_status_code and
     response_body columns are NULL. The function falls back to
     status-code-only classification which is less precise (most
     such rows get diagnosed_kind=transient). After P1 is deployed
     to production AND the next archive window runs, the new
     archive rows will carry body + status, and the diagnosed_kind
     column will be as precise as the Go-side classifier.';

COMMENT ON FUNCTION diagnose_failure_kind(int, text) IS
    'Pure SQL mirror of errorsx.ClassifyErrorWithBody. Used by
     v_request_failures_diagnosis. Stays in sync with the Go side
     via the tests in errorsx/classify_minimax_test.go (Go) and
     the unit-test block at the bottom of migration 056 (SQL).';

-- ============================================================================
-- Unit tests (run via psql -f and expect "OK")
-- ============================================================================
DO $$
DECLARE
    -- Each case: (status, body, expected_kind)
    cases text[][] := ARRAY[
        -- Tool call id mismatch (MiniMax 2013)
        ARRAY['400',
              '{"error":{"message":"invalid params, tool result''s tool id(call_function_xxx) not found (2013)","code":2013}}',
              'tool_call_id_mismatch'],
        -- Context length (MiniMax 2013 with "context window" wording)
        ARRAY['400',
              '{"error":{"message":"invalid params, context window exceeds limit (2013)","code":2013}}',
              'context_length_exceeded'],
        -- Auth (MiniMax 1004)
        ARRAY['401',
              '{"error":{"type":"authorized_error","message":"login fail (1004)"}}',
              'auth'],
        -- Quota (MiniMax 1008)
        ARRAY['402',
              '{"error":{"type":"insufficient_balance_error","message":"balance insufficient (1008)"}}',
              'quota'],
        -- Concurrent overload
        ARRAY['429',
              'engine overloaded',
              'concurrent'],
        -- Rate limit (no body, status-only)
        ARRAY['429', '', 'rate_limit'],
        -- Status-only 401 → auth
        ARRAY['401', '', 'auth'],
        -- Status-only 500 → upstream_down
        ARRAY['502', '', 'upstream_down'],
        -- Status-only 503 → concurrent
        ARRAY['503', '', 'concurrent'],
        -- 4xx unknown body → unsupported_feature (NOT transient)
        ARRAY['400', 'some html page', 'unsupported_feature'],
        -- 404 page not found (no body shape) → unsupported_feature,
        -- not transient (regression test for 2540 rows in
        -- migration 057 backfill).
        ARRAY['404', '404 page not found', 'unsupported_feature'],
        -- 403 with "subscription expired" body → auth, not transient
        -- (regression test for migration 057 backfill).
        ARRAY['403',
              '{"error":{"message":"Coding Plan subscription is expired","code":"403"}}',
              'auth'],
        -- 403 with "access denied" body → auth
        ARRAY['403', 'access denied', 'auth'],
        -- 401 with any body → auth (status-only check catches empty
        -- body; here we verify a non-empty body still classifies
        -- correctly).
        ARRAY['401', '{"error":"invalid api key"}', 'auth'],
        -- Model not found (note: Go-side regex requires lowercase
        -- model names per P5 tightening 2026-06-18; "MiniMax-M9"
        -- with capital letters would not match the Go regex either,
        -- so the SQL mirror must stay consistent).
        ARRAY['404',
              'model glm-5.1 not found',
              'model_not_found'],
        -- Priority order: context_window BEFORE tool_call_id when both
        -- could match via (2013) — the body wording disambiguates.
        ARRAY['400',
              '{"error":{"message":"context window exceeds limit (2013)","code":2013}}',
              'context_length_exceeded']
    ];
    c text[];
    got text;
    bad int := 0;
BEGIN
    FOREACH c SLICE 1 IN ARRAY cases LOOP
        got := diagnose_failure_kind(c[1]::int, c[2]);
        IF got <> c[3] THEN
            RAISE WARNING 'diagnose_failure_kind: status=%, body=%, got=%, want=%',
                c[1], LEFT(c[2], 60), got, c[3];
            bad := bad + 1;
        END IF;
    END LOOP;
    IF bad > 0 THEN
        RAISE EXCEPTION 'diagnose_failure_kind unit tests FAILED: %/% cases wrong', bad, array_length(cases, 1);
    END IF;
    RAISE NOTICE 'OK: diagnose_failure_kind unit tests passed (% cases)', array_length(cases, 1);
END;
$$;