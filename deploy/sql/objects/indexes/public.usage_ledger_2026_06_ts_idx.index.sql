-- ===========================================================================
-- Object:   usage_ledger_2026_06_ts_idx
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: usage_ledger_2026_06_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX usage_ledger_2026_06_ts_idx ON public.usage_ledger_2026_06 USING btree (ts);


--
