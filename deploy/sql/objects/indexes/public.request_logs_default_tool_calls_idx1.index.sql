-- ===========================================================================
-- Object:   request_logs_default_tool_calls_idx1
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default_tool_calls_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_tool_calls_idx1 ON public.request_logs_default USING gin (tool_calls) WHERE ((tool_calls IS NOT NULL) AND (tool_calls <> '[]'::jsonb));


--
