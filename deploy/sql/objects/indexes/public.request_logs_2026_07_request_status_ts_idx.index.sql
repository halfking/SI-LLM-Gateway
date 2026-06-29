-- ===========================================================================
-- Object:   request_logs_2026_07_request_status_ts_idx
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_2026_07_request_status_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_request_status_ts_idx ON public.request_logs_2026_07 USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));


--
