-- ============================================
-- Table: model_reconcile_log
-- Category: model
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.model_reconcile_log (
    id bigint NOT NULL,
    provider_id bigint NOT NULL,
    credential_id bigint,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    added integer DEFAULT 0 NOT NULL,
    removed integer DEFAULT 0 NOT NULL,
    changed integer DEFAULT 0 NOT NULL,
    diff_json jsonb
);
