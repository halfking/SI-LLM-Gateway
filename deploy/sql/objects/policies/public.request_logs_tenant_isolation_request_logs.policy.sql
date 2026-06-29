-- ===========================================================================
-- Object:   request_logs tenant_isolation_request_logs
-- Type:     POLICY
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs tenant_isolation_request_logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_request_logs ON public.request_logs USING ((tenant_id = public.get_current_tenant()));


--
