-- ===========================================================================
-- Object:   idx_request_logs_parent_ts
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_request_logs_parent_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_parent_ts ON ONLY public.request_logs USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);


--
