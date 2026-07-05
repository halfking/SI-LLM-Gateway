-- ============================================
-- Indexes for table: tenant_model_policies_audit
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_tmp_audit_tenant_ts ON public.tenant_model_policies_audit USING btree (tenant_id, ts DESC);
CREATE INDEX idx_tmp_audit_ts ON public.tenant_model_policies_audit USING btree (ts DESC);
