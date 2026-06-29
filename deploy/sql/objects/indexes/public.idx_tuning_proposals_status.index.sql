-- ===========================================================================
-- Object:   idx_tuning_proposals_status
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_tuning_proposals_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tuning_proposals_status ON public.tuning_proposals USING btree (status, ts DESC);


--
