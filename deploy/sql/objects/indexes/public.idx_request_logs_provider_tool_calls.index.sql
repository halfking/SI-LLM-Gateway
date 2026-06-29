-- ===========================================================================
-- Object:   idx_request_logs_provider_tool_calls
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_request_logs_provider_tool_calls; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_provider_tool_calls ON ONLY public.request_logs USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));


--
