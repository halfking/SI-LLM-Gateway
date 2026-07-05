-- ============================================
-- Table: credential_model_peak_1m
-- Category: credential
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.credential_model_peak_1m (
    bucket timestamp with time zone NOT NULL,
    credential_id bigint NOT NULL,
    raw_model text DEFAULT ''::text NOT NULL,
    peak_concurrent integer DEFAULT 0 NOT NULL,
    avg_concurrent numeric(8,2) DEFAULT 0 NOT NULL,
    sample_count integer DEFAULT 0 NOT NULL
);
