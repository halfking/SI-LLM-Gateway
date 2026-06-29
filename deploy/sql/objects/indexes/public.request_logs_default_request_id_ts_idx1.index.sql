-- ===========================================================================
-- Object:   request_logs_default_request_id_ts_idx1
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default_request_id_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX request_logs_default_request_id_ts_idx1 ON public.request_logs_default USING btree (request_id, ts);


--
