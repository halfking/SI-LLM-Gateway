-- ============================================
-- Table: sticky_sessions
-- Category: routing
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.sticky_sessions (
    sticky_key text NOT NULL,
    credential_id bigint NOT NULL,
    set_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    canonical_id bigint,
    last_request_id text
);
