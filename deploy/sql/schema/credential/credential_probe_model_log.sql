-- ============================================
-- Table: credential_probe_model_log
-- Category: credential
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.credential_probe_model_log (
    id bigint,
    tenant_id text,
    credential_id bigint,
    source text,
    old_model text,
    new_model text,
    actor text,
    reason text,
    created_at timestamp with time zone
);
