-- ===========================================================================
-- Object:   subscription_plans subscription_plans_code_key
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: subscription_plans subscription_plans_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_plans
    ADD CONSTRAINT subscription_plans_code_key UNIQUE (code);


--
