-- ===========================================================================
-- Object:   applications applications_tenant_id_code_key
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: applications applications_tenant_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.applications
    ADD CONSTRAINT applications_tenant_id_code_key UNIQUE (tenant_id, code);


--
