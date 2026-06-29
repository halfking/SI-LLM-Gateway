-- ===========================================================================
-- Object:   request_logs_default_request_status_ts_idx1
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default_request_status_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_request_status_ts_idx1 ON public.request_logs_default USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));


--
