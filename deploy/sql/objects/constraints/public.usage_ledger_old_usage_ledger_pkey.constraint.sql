-- ===========================================================================
-- Object:   usage_ledger_old usage_ledger_pkey
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: usage_ledger_old usage_ledger_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_ledger_old
    ADD CONSTRAINT usage_ledger_pkey PRIMARY KEY (request_id);


--
