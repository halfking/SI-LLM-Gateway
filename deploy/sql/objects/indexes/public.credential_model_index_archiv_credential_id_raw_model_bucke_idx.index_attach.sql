-- ===========================================================================
-- Object:   credential_model_index_archiv_credential_id_raw_model_bucke_idx
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credential_model_index_archiv_credential_id_raw_model_bucke_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_cmi_archive_cred_model ATTACH PARTITION public.credential_model_index_archiv_credential_id_raw_model_bucke_idx;


--
