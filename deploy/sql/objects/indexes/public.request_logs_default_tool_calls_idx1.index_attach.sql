-- ===========================================================================
-- Object:   request_logs_default_tool_calls_idx1
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default_tool_calls_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_tool_calls ATTACH PARTITION public.request_logs_default_tool_calls_idx1;


--
