-- ============================================
-- Indexes for table: provider_models
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_provider_models_canonical_id ON public.provider_models USING btree (canonical_id);
CREATE INDEX idx_provider_models_lower_raw_model_name ON public.provider_models USING btree (lower(raw_model_name));
CREATE INDEX idx_provider_models_lower_standardized_name ON public.provider_models USING btree (lower(standardized_name));
