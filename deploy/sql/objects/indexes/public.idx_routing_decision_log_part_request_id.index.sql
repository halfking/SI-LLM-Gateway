-- ===========================================================================
-- Object:   idx_routing_decision_log_part_request_id
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_routing_decision_log_part_request_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_decision_log_part_request_id ON ONLY public.routing_decision_log USING btree (request_id);


--
