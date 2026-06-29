-- ===========================================================================
-- Object:   usage_ledger_2026_06_request_id_ts_key
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: usage_ledger_2026_06_request_id_ts_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.usage_ledger_partitioned_request_id_ts_key ATTACH PARTITION public.usage_ledger_2026_06_request_id_ts_key;


--
