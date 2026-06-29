-- ===========================================================================
-- Object:   response_format_anomalies response_format_anomalies_super_admin
-- Type:     POLICY
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: response_format_anomalies response_format_anomalies_super_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY response_format_anomalies_super_admin ON public.response_format_anomalies USING ((current_setting('app.bypass_rls'::text, true) = 'true'::text));


--
