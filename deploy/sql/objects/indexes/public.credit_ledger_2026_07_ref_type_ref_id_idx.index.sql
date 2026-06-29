-- ===========================================================================
-- Object:   credit_ledger_2026_07_ref_type_ref_id_idx
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credit_ledger_2026_07_ref_type_ref_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX credit_ledger_2026_07_ref_type_ref_id_idx ON public.credit_ledger_2026_07 USING btree (ref_type, ref_id);


--
