-- ===========================================================================
-- Object:   idx_usage_ledger_part_ts
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_usage_ledger_part_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_usage_ledger_part_ts ON ONLY public.usage_ledger USING btree (ts);


--
