-- ============================================
-- Indexes for table: settings_kv
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_settings_kv_category ON public.settings_kv USING btree (category);
CREATE INDEX idx_settings_kv_scope ON public.settings_kv USING btree (scope);
CREATE INDEX idx_settings_kv_updated ON public.settings_kv USING btree (updated_at DESC);
