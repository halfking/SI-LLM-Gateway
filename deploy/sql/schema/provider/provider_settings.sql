-- ============================================
-- Table: provider_settings
-- Category: provider
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.provider_settings (
    id bigint NOT NULL,
    provider_id bigint NOT NULL,
    setting_key text NOT NULL,
    setting_value jsonb NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_by text DEFAULT 'system'::text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
