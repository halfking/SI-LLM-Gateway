-- ===========================================================================
-- Object:   prompt_injection_policies prompt_injection_policies_tenant
-- Type:     POLICY
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: prompt_injection_policies prompt_injection_policies_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY prompt_injection_policies_tenant ON public.prompt_injection_policies USING (((tenant_id)::text = current_setting('app.current_tenant'::text, true)));


--
