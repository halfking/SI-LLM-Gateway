-- ============================================
-- Table: test_columnar_new
-- Category: system
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.test_columnar_new (
    id integer NOT NULL,
    tenant_id text,
    model text,
    prompt_tokens integer,
    completion_tokens integer,
    created_at timestamp with time zone DEFAULT now()
);
