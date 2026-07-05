-- ============================================
-- Table: credential_model_bindings
-- Category: credential
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.credential_model_bindings (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    provider_model_id bigint NOT NULL,
    routing_tier smallint DEFAULT 2,
    weight smallint DEFAULT 100,
    manual_priority smallint DEFAULT 99,
    success_rate numeric,
    p95_latency_ms integer,
    active_sessions integer DEFAULT 0,
    consecutive_failures integer DEFAULT 0,
    unit_price_in_per_1m numeric,
    unit_price_out_per_1m numeric,
    cache_read_price_per_1m numeric,
    cache_write_price_per_1m numeric,
    currency text DEFAULT 'USD'::text,
    billing_mode text DEFAULT 'per_token'::text,
    pricing_source text,
    pricing_updated_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    available boolean DEFAULT true NOT NULL,
    unavailable_reason text,
    unavailable_at timestamp with time zone,
    plan_meta jsonb DEFAULT '{}'::jsonb NOT NULL,
    admin_protected boolean DEFAULT false NOT NULL,
    unavailable_recover_at timestamp with time zone,
    transient_failure_count integer DEFAULT 0,
    pending_verification boolean DEFAULT false,
    plan_type_origin text DEFAULT 'auto'::text,
    CONSTRAINT credential_model_bindings_plan_type_origin_check CHECK ((plan_type_origin = ANY (ARRAY['auto'::text, 'manual'::text, 'backfill'::text])))
);
