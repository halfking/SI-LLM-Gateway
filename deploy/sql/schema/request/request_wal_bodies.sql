-- ============================================
-- Table: request_wal_bodies
-- Category: request
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.request_wal_bodies (
    request_id character varying(64) NOT NULL,
    outbound_body text,
    compression_meta jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
