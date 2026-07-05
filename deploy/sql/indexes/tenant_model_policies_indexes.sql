-- ============================================
-- Indexes for table: tenant_model_policies
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_tmp_canonical ON public.tenant_model_policies USING btree (canonical_name);
CREATE INDEX idx_tmp_tenant_active ON public.tenant_model_policies USING btree (tenant_id) WHERE (deleted_at IS NULL);
