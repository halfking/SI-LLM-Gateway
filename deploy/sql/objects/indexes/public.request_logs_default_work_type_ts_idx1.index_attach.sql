-- ===========================================================================
-- Object:   request_logs_default_work_type_ts_idx1
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default_work_type_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_work_type ATTACH PARTITION public.request_logs_default_work_type_ts_idx1;


--
