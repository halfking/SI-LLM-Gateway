-- ===========================================================================
-- Object:   model_fingerprints model_fingerprints_credential_id_canonical_id_key
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: model_fingerprints model_fingerprints_credential_id_canonical_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_fingerprints
    ADD CONSTRAINT model_fingerprints_credential_id_canonical_id_key UNIQUE (credential_id, canonical_id);


--
