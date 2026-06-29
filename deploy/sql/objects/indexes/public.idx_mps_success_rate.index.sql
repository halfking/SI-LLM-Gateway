-- ===========================================================================
-- Object:   idx_mps_success_rate
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_mps_success_rate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mps_success_rate ON public.model_probe_state USING btree (success_rate_7d);


--
