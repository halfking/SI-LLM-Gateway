-- ============================================
-- View: v_candidate_failure_logs_diagnosis
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE VIEW public.v_candidate_failure_logs_diagnosis AS
 SELECT cfl.id,
    cfl.ts,
    cfl.tenant_id,
    cfl.credential_id,
    cfl.provider_id,
    cfl.raw_model_name,
    cfl.attempt_index,
    cfl.error_kind AS legacy_kind,
    COALESCE(cfl.upstream_status_code,
        CASE
            WHEN (cfl.error_message ~ 'upstream [0-9]+:'::text) THEN ("substring"(cfl.error_message, 'upstream ([0-9]+):'::text))::integer
            ELSE NULL::integer
        END) AS extracted_upstream_status_code,
    public.diagnose_failure_kind(COALESCE(cfl.upstream_status_code,
        CASE
            WHEN (cfl.error_message ~ 'upstream [0-9]+:'::text) THEN ("substring"(cfl.error_message, 'upstream ([0-9]+):'::text))::integer
            ELSE NULL::integer
        END), COALESCE(NULLIF(cfl.upstream_response_body, ''::text), cfl.error_message, ''::text)) AS diagnosed_error_kind,
    cfl.upstream_status_code AS live_upstream_status_code,
    cfl.latency_ms,
    cfl.per_attempt_latency_ms,
    cfl.retryable,
    cfl.error_message,
    (cfl.error_kind IS DISTINCT FROM public.diagnose_failure_kind(COALESCE(cfl.upstream_status_code,
        CASE
            WHEN (cfl.error_message ~ 'upstream [0-9]+:'::text) THEN ("substring"(cfl.error_message, 'upstream ([0-9]+):'::text))::integer
            ELSE NULL::integer
        END), COALESCE(NULLIF(cfl.upstream_response_body, ''::text), cfl.error_message, ''::text))) AS classification_disagrees
   FROM public.candidate_failure_logs cfl;
