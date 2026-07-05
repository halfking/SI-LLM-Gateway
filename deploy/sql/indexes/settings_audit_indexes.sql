-- ============================================
-- Indexes for table: settings_audit
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_settings_audit_created ON public.settings_audit USING btree (created_at);
CREATE INDEX idx_settings_audit_key_time ON public.settings_audit USING btree (setting_key, created_at DESC);
CREATE INDEX idx_settings_audit_operator ON public.settings_audit USING btree (operator_user, created_at DESC);
CREATE INDEX idx_settings_audit_tenant_time ON public.settings_audit USING btree (tenant_id, created_at DESC);
