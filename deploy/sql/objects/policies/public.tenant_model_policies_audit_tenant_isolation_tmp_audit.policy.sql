-- ===========================================================================
-- Object:   tenant_model_policies_audit tenant_isolation_tmp_audit
-- Type:     POLICY
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tenant_model_policies_audit tenant_isolation_tmp_audit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_tmp_audit ON public.tenant_model_policies_audit USING (((tenant_id = public.get_current_tenant()) OR (tenant_id IS NULL)));


--
