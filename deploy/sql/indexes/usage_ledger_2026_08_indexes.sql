-- ============================================
-- Indexes for table: usage_ledger_2026_08
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX usage_ledger_2026_08_heap_request_id_idx ON public.usage_ledger_2026_08 USING btree (request_id);
CREATE INDEX usage_ledger_2026_08_heap_tenant_id_ts_idx ON public.usage_ledger_2026_08 USING btree (tenant_id, ts);
CREATE INDEX usage_ledger_2026_08_heap_ts_idx ON public.usage_ledger_2026_08 USING btree (ts);
