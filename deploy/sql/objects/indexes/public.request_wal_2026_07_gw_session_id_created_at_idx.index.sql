-- ===========================================================================
-- Object:   request_wal_2026_07_gw_session_id_created_at_idx
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_wal_2026_07_gw_session_id_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_wal_2026_07_gw_session_id_created_at_idx ON public.request_wal_2026_07 USING btree (gw_session_id, created_at);


--
