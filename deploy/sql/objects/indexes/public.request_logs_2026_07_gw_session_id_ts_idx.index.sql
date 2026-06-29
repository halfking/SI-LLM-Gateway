-- ===========================================================================
-- Object:   request_logs_2026_07_gw_session_id_ts_idx
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_2026_07_gw_session_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_gw_session_id_ts_idx ON public.request_logs_2026_07 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));


--
