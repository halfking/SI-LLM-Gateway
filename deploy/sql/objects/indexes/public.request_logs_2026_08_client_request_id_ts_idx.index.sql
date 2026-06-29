-- ===========================================================================
-- Object:   request_logs_2026_08_client_request_id_ts_idx
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_2026_08_client_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_client_request_id_ts_idx ON public.request_logs_2026_08 USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);


--
