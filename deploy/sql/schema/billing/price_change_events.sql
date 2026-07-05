-- ============================================
-- Table: price_change_events
-- Category: billing
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.price_change_events (
    id bigint,
    old_plan_id bigint,
    new_plan_id bigint,
    delta_json jsonb,
    detected_at timestamp with time zone,
    notify_channel text,
    applied boolean
);
