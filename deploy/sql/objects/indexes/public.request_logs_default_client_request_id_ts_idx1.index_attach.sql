-- ===========================================================================
-- Object:   request_logs_default_client_request_id_ts_idx1
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default_client_request_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_request_id ATTACH PARTITION public.request_logs_default_client_request_id_ts_idx1;


--
