-- ===========================================================================
-- Object:   routing_decision_log_2026_07_request_id_idx
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: routing_decision_log_2026_07_request_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_07_request_id_idx ON public.routing_decision_log_2026_07 USING btree (request_id);


--
