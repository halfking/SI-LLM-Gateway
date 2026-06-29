-- ===========================================================================
-- Object:   idx_wal_session
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_wal_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wal_session ON ONLY public.request_wal USING btree (gw_session_id, created_at);


--
