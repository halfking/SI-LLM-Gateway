-- ============================================
-- Table: routing_audit_log
-- Category: routing
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.routing_audit_log (
    id bigint NOT NULL,
    ts timestamp with time zone DEFAULT now(),
    actor text NOT NULL,
    action text NOT NULL,
    target_type text,
    target_id bigint,
    before_json jsonb,
    after_json jsonb
);
