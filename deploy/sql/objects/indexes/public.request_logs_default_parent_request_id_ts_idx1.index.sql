-- ===========================================================================
-- Object:   request_logs_default_parent_request_id_ts_idx1
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default_parent_request_id_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_parent_request_id_ts_idx1 ON public.request_logs_default USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);


--
