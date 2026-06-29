-- ===========================================================================
-- Object:   credential_quotas credential_quotas_credential_id_quota_name_key
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credential_quotas credential_quotas_credential_id_quota_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_quotas
    ADD CONSTRAINT credential_quotas_credential_id_quota_name_key UNIQUE (credential_id, quota_name);


--
