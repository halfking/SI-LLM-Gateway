-- ===========================================================================
-- Object:   topup_packages topup_packages_code_key
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: topup_packages topup_packages_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topup_packages
    ADD CONSTRAINT topup_packages_code_key UNIQUE (code);


--
