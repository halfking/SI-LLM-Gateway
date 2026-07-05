-- ============================================
-- Table: schema_migrations
-- Category: system
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.schema_migrations (
    version text NOT NULL,
    description text,
    applied_at timestamp with time zone DEFAULT now()
);
