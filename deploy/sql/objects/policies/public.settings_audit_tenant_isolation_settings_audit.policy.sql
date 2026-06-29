-- ===========================================================================
-- Object:   settings_audit tenant_isolation_settings_audit
-- Type:     POLICY
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: settings_audit tenant_isolation_settings_audit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_settings_audit ON public.settings_audit USING ((((tenant_id)::text = public.get_current_tenant()) OR (tenant_id IS NULL)));


--
