-- ===========================================================================
-- Object:   request_logs_2026_07_request_id_ts_idx
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_2026_07_request_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_request_id_ts_unique ATTACH PARTITION public.request_logs_2026_07_request_id_ts_idx;


--
