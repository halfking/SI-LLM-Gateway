-- ===========================================================================
-- Object:   credit_ledger_2026_07_pkey
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credit_ledger_2026_07_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.credit_ledger_partitioned_pkey ATTACH PARTITION public.credit_ledger_2026_07_pkey;


--
