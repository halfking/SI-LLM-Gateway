-- ============================================
-- Indexes for table: usage_ledger_default
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX usage_ledger_default_request_id_idx ON public.usage_ledger_default USING btree (request_id);
CREATE INDEX usage_ledger_default_tenant_id_ts_idx ON public.usage_ledger_default USING btree (tenant_id, ts);
CREATE INDEX usage_ledger_default_ts_idx ON public.usage_ledger_default USING btree (ts);
