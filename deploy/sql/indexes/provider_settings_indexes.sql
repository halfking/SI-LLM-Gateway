-- ============================================
-- Indexes for table: provider_settings
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_provider_settings_key ON public.provider_settings USING btree (setting_key) WHERE (enabled = true);
CREATE INDEX idx_provider_settings_provider ON public.provider_settings USING btree (provider_id) WHERE (enabled = true);
