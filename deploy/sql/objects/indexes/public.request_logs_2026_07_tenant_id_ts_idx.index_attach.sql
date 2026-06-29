-- ===========================================================================
-- Object:   request_logs_2026_07_tenant_id_ts_idx
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_2026_07_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_outbound_msg_count ATTACH PARTITION public.request_logs_2026_07_tenant_id_ts_idx;


--
