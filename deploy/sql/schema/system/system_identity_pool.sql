-- ============================================
-- Table: system_identity_pool
-- Category: system
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.system_identity_pool (
    id integer DEFAULT 1 NOT NULL,
    max_identities integer DEFAULT 10000 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by text,
    CONSTRAINT system_identity_pool_id_check CHECK ((id = 1))
);
