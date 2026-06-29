-- ===========================================================================
-- Object:   request_logs_2026_08_gw_session_id_ts_idx1
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_2026_08_gw_session_id_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_gw_session_id_ts_idx1 ON public.request_logs_2026_08 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));


--
