-- ===========================================================================
-- Object:   models_canonical models_canonical_canonical_name_key
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: models_canonical models_canonical_canonical_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.models_canonical
    ADD CONSTRAINT models_canonical_canonical_name_key UNIQUE (canonical_name);


--
