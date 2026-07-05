-- ============================================
-- Indexes for table: usage_ledger_2026_07
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX usage_ledger_2026_07_request_id_idx ON public.usage_ledger_2026_07 USING btree (request_id);
CREATE INDEX usage_ledger_2026_07_tenant_id_ts_idx ON public.usage_ledger_2026_07 USING btree (tenant_id, ts);
CREATE INDEX usage_ledger_2026_07_ts_idx ON public.usage_ledger_2026_07 USING btree (ts);
