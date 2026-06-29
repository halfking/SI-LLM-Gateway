-- ===========================================================================
-- Object:   users tenant_isolation_users
-- Type:     POLICY
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: users tenant_isolation_users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_users ON public.users USING (((tenant_id)::text = public.get_current_tenant()));


--
