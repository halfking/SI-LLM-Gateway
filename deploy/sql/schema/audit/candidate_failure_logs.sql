-- ============================================
-- Table: candidate_failure_logs
-- Category: audit
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.candidate_failure_logs (
    id bigint,
    request_id text,
    ts timestamp with time zone,
    tenant_id text,
    credential_id integer,
    provider_id integer,
    raw_model_name text,
    attempt_index integer,
    error_kind text,
    error_message text,
    upstream_status_code integer,
    upstream_response_body text,
    upstream_response_preview text,
    latency_ms integer,
    retryable boolean,
    context jsonb,
    per_attempt_latency_ms integer,
    extracted_upstream_status_code integer,
    diagnosed_error_kind text
);
