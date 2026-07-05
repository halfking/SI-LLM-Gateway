-- ============================================
-- Table: provider_scores
-- Category: provider
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.provider_scores (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    canonical_id bigint,
    score numeric(6,4) NOT NULL,
    factors_json jsonb,
    computed_at timestamp with time zone DEFAULT now() NOT NULL
);
