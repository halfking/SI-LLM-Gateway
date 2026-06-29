-- ===========================================================================
-- Object:   provider_header_profiles provider_header_profiles_profile_code_key
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: provider_header_profiles provider_header_profiles_profile_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_header_profiles
    ADD CONSTRAINT provider_header_profiles_profile_code_key UNIQUE (profile_code);


--
