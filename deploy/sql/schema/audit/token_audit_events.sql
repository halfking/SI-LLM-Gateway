-- ============================================
-- Table: token_audit_events
-- Category: audit
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.token_audit_events (
    id bigint NOT NULL,
    request_id text NOT NULL,
    credential_id bigint NOT NULL,
    claimed_tokens integer,
    estimated_tokens integer,
    delta_pct numeric(6,3),
    ts timestamp with time zone DEFAULT now() NOT NULL
);
