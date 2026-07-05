-- ============================================
-- Table: model_offer_events
-- Category: model
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.model_offer_events (
    id bigint,
    ts timestamp with time zone,
    source text,
    action text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    raw_model_name text,
    reason_code text,
    reason_detail text,
    request_id text,
    run_id bigint,
    metadata_json jsonb
);
