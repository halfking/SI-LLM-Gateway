-- ===========================================================================
-- Object:   tenant_model_policies tenant_isolation_tmp
-- Type:     POLICY
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tenant_model_policies tenant_isolation_tmp; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_tmp ON public.tenant_model_policies USING (((tenant_id)::text = public.get_current_tenant()));


--
