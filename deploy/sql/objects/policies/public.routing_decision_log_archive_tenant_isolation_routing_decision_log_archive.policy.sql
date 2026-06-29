-- ===========================================================================
-- Object:   routing_decision_log_archive tenant_isolation_routing_decision_log_archive
-- Type:     POLICY
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: routing_decision_log_archive tenant_isolation_routing_decision_log_archive; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_routing_decision_log_archive ON public.routing_decision_log_archive USING ((tenant_id = public.get_current_tenant()));


--
