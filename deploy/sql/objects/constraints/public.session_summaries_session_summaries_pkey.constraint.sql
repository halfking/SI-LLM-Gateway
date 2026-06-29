-- ===========================================================================
-- Object:   session_summaries session_summaries_pkey
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: session_summaries session_summaries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_summaries
    ADD CONSTRAINT session_summaries_pkey PRIMARY KEY (session_key);


--
