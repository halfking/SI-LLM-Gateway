-- ============================================
-- Indexes for table: credentials
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_credentials_auto_limit ON public.credentials USING btree (concurrency_limit_auto) WHERE (concurrency_limit_auto IS NOT NULL);
