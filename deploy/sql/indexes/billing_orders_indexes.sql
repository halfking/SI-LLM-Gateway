-- ============================================
-- Indexes for table: billing_orders
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_billing_orders_status ON public.billing_orders USING btree (status, created_at DESC);
CREATE INDEX idx_billing_orders_tenant ON public.billing_orders USING btree (tenant_id, created_at DESC);
