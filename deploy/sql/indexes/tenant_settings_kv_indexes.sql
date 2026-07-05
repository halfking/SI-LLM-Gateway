-- ============================================
-- Indexes for table: tenant_settings_kv
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_tenant_settings_kv_category ON public.tenant_settings_kv USING btree (category);
CREATE INDEX idx_tenant_settings_kv_tenant ON public.tenant_settings_kv USING btree (tenant_id);
