-- ===========================================================================
-- Object:   tenant_tool_policies uk_tenant_tool_policy
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tenant_tool_policies uk_tenant_tool_policy; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_tool_policies
    ADD CONSTRAINT uk_tenant_tool_policy UNIQUE (tenant_id, tool_pattern);


--
