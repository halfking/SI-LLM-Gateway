-- ===========================================================================
-- Object:   response_format_anomalies response_format_anomalies_tenant_isolation
-- Type:     POLICY
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: response_format_anomalies response_format_anomalies_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY response_format_anomalies_tenant_isolation ON public.response_format_anomalies USING (((tenant_id IS NULL) OR (tenant_id = public.get_current_tenant())));


--
