-- ===========================================================================
-- Object:   intent_aggregates intent_aggregates_pkey
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: intent_aggregates intent_aggregates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.intent_aggregates
    ADD CONSTRAINT intent_aggregates_pkey PRIMARY KEY (tenant_id, intent_kind);


--
