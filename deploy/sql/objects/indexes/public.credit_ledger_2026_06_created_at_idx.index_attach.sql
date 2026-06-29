-- ===========================================================================
-- Object:   credit_ledger_2026_06_created_at_idx
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credit_ledger_2026_06_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_credit_ledger_part_created ATTACH PARTITION public.credit_ledger_2026_06_created_at_idx;


--
