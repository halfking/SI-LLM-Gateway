-- ============================================
-- Table: model_fingerprints
-- Category: model
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.model_fingerprints (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    canonical_id bigint NOT NULL,
    fingerprint_hash text NOT NULL,
    sampled_features_json jsonb,
    last_verified_at timestamp with time zone,
    drift_detected boolean DEFAULT false NOT NULL
);
