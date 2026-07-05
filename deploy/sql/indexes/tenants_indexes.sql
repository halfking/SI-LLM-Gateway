-- ============================================
-- Indexes for table: tenants
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_tenants_name ON public.tenants USING btree (name);
CREATE INDEX idx_tenants_status ON public.tenants USING btree (status);
