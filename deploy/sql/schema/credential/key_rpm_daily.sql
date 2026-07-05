-- ============================================
-- Table: key_rpm_daily
-- Category: credential
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.key_rpm_daily (
    api_key_id bigint NOT NULL,
    day_bucket date NOT NULL,
    peak_rpm numeric(10,3) DEFAULT 0 NOT NULL,
    avg_rpm numeric(10,3) DEFAULT 0 NOT NULL,
    request_count bigint DEFAULT 0 NOT NULL
);
