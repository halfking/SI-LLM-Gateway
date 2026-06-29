-- ===========================================================================
-- Object:   credential_model_index_archive_2026_06_bucket_idx
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credential_model_index_archive_2026_06_bucket_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_cmi_archive_bucket ATTACH PARTITION public.credential_model_index_archive_2026_06_bucket_idx;


--
