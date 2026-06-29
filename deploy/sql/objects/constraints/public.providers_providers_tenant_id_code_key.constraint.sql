-- ===========================================================================
-- Object:   providers providers_tenant_id_code_key
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: providers providers_tenant_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.providers
    ADD CONSTRAINT providers_tenant_id_code_key UNIQUE (tenant_id, code);


--
