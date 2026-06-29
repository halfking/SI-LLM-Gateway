-- ===========================================================================
-- Object:   idx_routing_decision_log_part_credential
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_routing_decision_log_part_credential; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_decision_log_part_credential ON ONLY public.routing_decision_log USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);


--
