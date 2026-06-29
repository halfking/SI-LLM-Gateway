-- ===========================================================================
-- Object:   model_offers_legacy model_offers_credential_id_raw_model_name_key
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: model_offers_legacy model_offers_credential_id_raw_model_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_offers_legacy
    ADD CONSTRAINT model_offers_credential_id_raw_model_name_key UNIQUE (credential_id, raw_model_name);


--
