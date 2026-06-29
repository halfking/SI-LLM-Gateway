-- ===========================================================================
-- Object:   idx_request_logs_gw_session_ts
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_request_logs_gw_session_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_gw_session_ts ON ONLY public.request_logs USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));


--
