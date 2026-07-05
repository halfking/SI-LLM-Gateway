-- ============================================
-- Indexes for table: models_canonical
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_models_canonical_released ON public.models_canonical USING btree (released_at DESC NULLS LAST);
CREATE INDEX idx_models_canonical_strengths ON public.models_canonical USING gin (strengths);
CREATE INDEX idx_models_canonical_version_rank ON public.models_canonical USING btree (version_rank);
