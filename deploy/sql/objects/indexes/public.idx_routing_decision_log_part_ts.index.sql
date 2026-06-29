-- ===========================================================================
-- Object:   idx_routing_decision_log_part_ts
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_routing_decision_log_part_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_decision_log_part_ts ON ONLY public.routing_decision_log USING btree (ts DESC);


--
