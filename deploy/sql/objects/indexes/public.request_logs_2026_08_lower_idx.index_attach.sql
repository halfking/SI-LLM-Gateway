-- ===========================================================================
-- Object:   request_logs_2026_08_lower_idx
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_2026_08_lower_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model_lower ATTACH PARTITION public.request_logs_2026_08_lower_idx;


--
