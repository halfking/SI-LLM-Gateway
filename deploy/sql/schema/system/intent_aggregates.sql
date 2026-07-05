-- ============================================
-- Table: intent_aggregates
-- Category: system
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.intent_aggregates (
    tenant_id text NOT NULL,
    intent_kind text NOT NULL,
    count bigint DEFAULT 0 NOT NULL,
    last_updated timestamp with time zone DEFAULT now() NOT NULL
);
