-- ===========================================================================
-- Object:   agents tenant_isolation_agents
-- Type:     POLICY
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: agents tenant_isolation_agents; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_agents ON public.agents USING ((tenant_id = public.get_current_tenant()));


--
