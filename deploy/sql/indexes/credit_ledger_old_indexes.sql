-- ============================================
-- Indexes for table: credit_ledger_old
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_credit_ledger_tenant_ts ON public.credit_ledger_old USING btree (tenant_id, created_at DESC);
