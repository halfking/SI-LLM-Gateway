-- ============================================
-- Indexes for table: usage_ledger_2026_06
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX usage_ledger_2026_06_col_request_id_idx ON public.usage_ledger_2026_06 USING btree (request_id);
CREATE INDEX usage_ledger_2026_06_col_tenant_id_ts_idx ON public.usage_ledger_2026_06 USING btree (tenant_id, ts);
CREATE INDEX usage_ledger_2026_06_col_ts_idx ON public.usage_ledger_2026_06 USING btree (ts);
