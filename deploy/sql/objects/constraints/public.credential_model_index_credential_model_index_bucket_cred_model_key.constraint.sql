-- ===========================================================================
-- Object:   credential_model_index credential_model_index_bucket_cred_model_key
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credential_model_index credential_model_index_bucket_cred_model_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_model_index
    ADD CONSTRAINT credential_model_index_bucket_cred_model_key UNIQUE (bucket, credential_id, raw_model);


--
