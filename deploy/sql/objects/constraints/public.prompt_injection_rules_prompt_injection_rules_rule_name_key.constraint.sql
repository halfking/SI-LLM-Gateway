-- ===========================================================================
-- Object:   prompt_injection_rules prompt_injection_rules_rule_name_key
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: prompt_injection_rules prompt_injection_rules_rule_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_injection_rules
    ADD CONSTRAINT prompt_injection_rules_rule_name_key UNIQUE (rule_name);


--
