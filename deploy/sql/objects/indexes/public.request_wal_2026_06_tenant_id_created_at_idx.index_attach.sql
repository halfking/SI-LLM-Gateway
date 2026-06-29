-- ===========================================================================
-- Object:   request_wal_2026_06_tenant_id_created_at_idx
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_wal_2026_06_tenant_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_wal_tenant_created ATTACH PARTITION public.request_wal_2026_06_tenant_id_created_at_idx;


--
