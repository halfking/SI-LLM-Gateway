-- ===========================================================================
-- Object:   credit_ledger_2026_06_created_at_idx
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credit_ledger_2026_06_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX credit_ledger_2026_06_created_at_idx ON public.credit_ledger_2026_06 USING btree (created_at);


--
