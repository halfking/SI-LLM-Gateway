-- ===========================================================================
-- Object:   request_logs_2026_06_client_model_idx3
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_2026_06_client_model_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model_trgm ATTACH PARTITION public.request_logs_2026_06_client_model_idx3;


--
