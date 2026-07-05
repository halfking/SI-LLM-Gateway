-- ============================================
-- Indexes for table: tenant_subscriptions
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_tenant_subscriptions_tenant ON public.tenant_subscriptions USING btree (tenant_id, status);
