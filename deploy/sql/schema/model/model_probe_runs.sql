-- ============================================
-- Table: model_probe_runs
-- Category: model
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.model_probe_runs (
    id bigint,
    tenant_id text,
    credential_id bigint,
    raw_model_name text,
    status text,
    http_status integer,
    error_code text,
    error_message text,
    latency_ms integer,
    state_change text,
    state_applied boolean,
    triggered_by text,
    created_at timestamp with time zone
);
