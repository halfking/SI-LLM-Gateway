-- ============================================
-- Table: provider_events
-- Category: provider
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.provider_events (
    id bigint,
    credential_id bigint,
    event_kind text,
    payload_json jsonb,
    ts timestamp with time zone
);
