-- ===========================================================================
-- Object:   request_logs_2026_07_request_id_ts_idx
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_2026_07_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX request_logs_2026_07_request_id_ts_idx ON public.request_logs_2026_07 USING btree (request_id, ts);


--
