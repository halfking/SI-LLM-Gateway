-- ===========================================================================
-- Object:   credential_capabilities credential_capabilities_credential_id_capability_key
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credential_capabilities credential_capabilities_credential_id_capability_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_capabilities
    ADD CONSTRAINT credential_capabilities_credential_id_capability_key UNIQUE (credential_id, capability);


--
