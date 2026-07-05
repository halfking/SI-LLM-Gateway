-- ============================================
-- Indexes for table: model_aliases
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_model_aliases_lower_raw_name_status ON public.model_aliases USING btree (lower(raw_name), status) WHERE (status = 'active'::text);
