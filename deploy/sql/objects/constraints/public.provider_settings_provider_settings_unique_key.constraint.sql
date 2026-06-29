-- ===========================================================================
-- Object:   provider_settings provider_settings_unique_key
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: provider_settings provider_settings_unique_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_settings
    ADD CONSTRAINT provider_settings_unique_key UNIQUE (provider_id, setting_key);


--
