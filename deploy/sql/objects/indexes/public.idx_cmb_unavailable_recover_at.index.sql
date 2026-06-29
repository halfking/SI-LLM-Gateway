-- ===========================================================================
-- Object:   idx_cmb_unavailable_recover_at
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_cmb_unavailable_recover_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cmb_unavailable_recover_at ON public.credential_model_bindings USING btree (unavailable_recover_at) WHERE (available = false);


--
