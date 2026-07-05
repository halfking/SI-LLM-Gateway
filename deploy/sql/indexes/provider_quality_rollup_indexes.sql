-- ============================================
-- Indexes for table: provider_quality_rollup
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_provider_quality_rollup_bucket ON public.provider_quality_rollup USING btree (bucket_start DESC);
