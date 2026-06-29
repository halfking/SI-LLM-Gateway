-- ===========================================================================
-- Object:   passive_probe_state passive_probe_state_pkey
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: passive_probe_state passive_probe_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.passive_probe_state
    ADD CONSTRAINT passive_probe_state_pkey PRIMARY KEY (credential_id, raw_model_name, error_kind);


--
