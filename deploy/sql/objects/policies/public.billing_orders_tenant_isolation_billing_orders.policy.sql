-- ===========================================================================
-- Object:   billing_orders tenant_isolation_billing_orders
-- Type:     POLICY
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: billing_orders tenant_isolation_billing_orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_billing_orders ON public.billing_orders USING (((tenant_id)::text = public.get_current_tenant()));


--
