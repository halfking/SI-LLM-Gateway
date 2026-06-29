-- ===========================================================================
-- Object:   tenant_settings_kv tenant_isolation_tenant_settings_kv
-- Type:     POLICY
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tenant_settings_kv tenant_isolation_tenant_settings_kv; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_tenant_settings_kv ON public.tenant_settings_kv USING (((tenant_id)::text = public.get_current_tenant()));


--
