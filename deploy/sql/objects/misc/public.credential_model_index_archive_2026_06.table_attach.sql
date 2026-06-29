-- ===========================================================================
-- Object:   credential_model_index_archive_2026_06
-- Type:     TABLE ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credential_model_index_archive_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_model_index_archive ATTACH PARTITION public.credential_model_index_archive_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


--
