-- ===========================================================================
-- Object:   armor_judgments tenant_isolation_armor_judgments
-- Type:     POLICY
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: armor_judgments tenant_isolation_armor_judgments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_armor_judgments ON public.armor_judgments USING ((tenant_id = public.get_current_tenant()));


--
