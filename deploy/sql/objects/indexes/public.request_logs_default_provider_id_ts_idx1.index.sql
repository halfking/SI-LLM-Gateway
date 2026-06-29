-- ===========================================================================
-- Object:   request_logs_default_provider_id_ts_idx1
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default_provider_id_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_provider_id_ts_idx1 ON public.request_logs_default USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));


--
