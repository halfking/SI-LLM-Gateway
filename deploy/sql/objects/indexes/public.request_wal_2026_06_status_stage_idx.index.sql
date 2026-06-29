-- ===========================================================================
-- Object:   request_wal_2026_06_status_stage_idx
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_wal_2026_06_status_stage_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_wal_2026_06_status_stage_idx ON public.request_wal_2026_06 USING btree (status, stage);


--
