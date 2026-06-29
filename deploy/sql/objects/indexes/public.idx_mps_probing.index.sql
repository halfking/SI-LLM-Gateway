-- ===========================================================================
-- Object:   idx_mps_probing
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_mps_probing; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mps_probing ON public.model_probe_state USING btree (probing_started_at) WHERE (state = 'probing'::text);


--
