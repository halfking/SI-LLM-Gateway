-- ===========================================================================
-- Object:   local_models local_models_runtime_id_raw_name_key
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: local_models local_models_runtime_id_raw_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.local_models
    ADD CONSTRAINT local_models_runtime_id_raw_name_key UNIQUE (runtime_id, raw_name);


--
