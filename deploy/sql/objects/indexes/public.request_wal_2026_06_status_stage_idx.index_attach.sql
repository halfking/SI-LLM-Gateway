-- ===========================================================================
-- Object:   request_wal_2026_06_status_stage_idx
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_wal_2026_06_status_stage_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_wal_status_stage ATTACH PARTITION public.request_wal_2026_06_status_stage_idx;


--
