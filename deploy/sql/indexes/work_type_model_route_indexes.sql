-- ============================================
-- Indexes for table: work_type_model_route
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_wtmr_tier ON public.work_type_model_route USING btree (work_type_key, tier, weight DESC);
CREATE INDEX idx_wtmr_work_type ON public.work_type_model_route USING btree (work_type_key);
