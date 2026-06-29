-- ===========================================================================
-- Object:   request_logs_default_upstream_finish_reason_ts_idx1
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default_upstream_finish_reason_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_upstream_finish_reason ATTACH PARTITION public.request_logs_default_upstream_finish_reason_ts_idx1;


--
