-- ===========================================================================
-- Object:   request_logs_2026_08_request_status_ts_idx
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_2026_08_request_status_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_status_ts ATTACH PARTITION public.request_logs_2026_08_request_status_ts_idx;


--
