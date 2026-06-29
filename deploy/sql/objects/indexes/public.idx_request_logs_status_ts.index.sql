-- ===========================================================================
-- Object:   idx_request_logs_status_ts
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_request_logs_status_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_status_ts ON ONLY public.request_logs USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));


--
