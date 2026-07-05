-- ============================================
-- Indexes for table: applications
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_applications_tenant_code ON public.applications USING btree (tenant_id, code) WHERE (enabled = true);
