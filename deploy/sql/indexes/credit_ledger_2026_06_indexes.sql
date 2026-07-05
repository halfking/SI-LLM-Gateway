-- ============================================
-- Indexes for table: credit_ledger_2026_06
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX credit_ledger_2026_06_created_at_idx ON public.credit_ledger_2026_06 USING btree (created_at);
CREATE INDEX credit_ledger_2026_06_ref_type_ref_id_idx ON public.credit_ledger_2026_06 USING btree (ref_type, ref_id);
CREATE INDEX credit_ledger_2026_06_tenant_id_created_at_idx ON public.credit_ledger_2026_06 USING btree (tenant_id, created_at);
