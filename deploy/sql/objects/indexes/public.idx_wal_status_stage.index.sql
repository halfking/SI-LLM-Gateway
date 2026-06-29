-- ===========================================================================
-- Object:   idx_wal_status_stage
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_wal_status_stage; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wal_status_stage ON ONLY public.request_wal USING btree (status, stage);


--
