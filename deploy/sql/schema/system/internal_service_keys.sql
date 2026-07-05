-- ============================================
-- Table: internal_service_keys
-- Category: system
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.internal_service_keys (
    service_id text NOT NULL,
    secret_hash text NOT NULL,
    description text,
    enabled boolean DEFAULT true NOT NULL,
    last_used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    rotated_at timestamp with time zone,
    rotation_notes text
);
