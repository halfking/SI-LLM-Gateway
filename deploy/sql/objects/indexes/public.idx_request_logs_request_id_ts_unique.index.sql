-- ===========================================================================
-- Object:   idx_request_logs_request_id_ts_unique
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_request_logs_request_id_ts_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_request_logs_request_id_ts_unique ON ONLY public.request_logs USING btree (request_id, ts);


--
