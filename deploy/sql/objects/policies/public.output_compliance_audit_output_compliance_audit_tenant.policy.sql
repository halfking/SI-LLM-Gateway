-- ===========================================================================
-- Object:   output_compliance_audit output_compliance_audit_tenant
-- Type:     POLICY
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: output_compliance_audit output_compliance_audit_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY output_compliance_audit_tenant ON public.output_compliance_audit USING (((tenant_id)::text = current_setting('app.current_tenant'::text, true)));


--
