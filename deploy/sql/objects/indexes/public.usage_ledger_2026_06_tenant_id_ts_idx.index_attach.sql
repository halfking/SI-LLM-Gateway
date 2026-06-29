-- ===========================================================================
-- Object:   usage_ledger_2026_06_tenant_id_ts_idx
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: usage_ledger_2026_06_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_usage_ledger_part_tenant ATTACH PARTITION public.usage_ledger_2026_06_tenant_id_ts_idx;


--
