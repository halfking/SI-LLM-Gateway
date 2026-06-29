-- ===========================================================================
-- Object:   request_logs_default_gw_session_id_ts_idx3
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default_gw_session_id_ts_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_gw_session_id_ts_idx3 ON public.request_logs_default USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));


--
