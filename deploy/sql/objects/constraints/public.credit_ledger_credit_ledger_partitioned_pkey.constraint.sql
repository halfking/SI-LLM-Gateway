-- ===========================================================================
-- Object:   credit_ledger credit_ledger_partitioned_pkey
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credit_ledger credit_ledger_partitioned_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_ledger
    ADD CONSTRAINT credit_ledger_partitioned_pkey PRIMARY KEY (id, created_at);


--
