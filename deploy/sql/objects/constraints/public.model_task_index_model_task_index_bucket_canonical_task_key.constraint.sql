-- ===========================================================================
-- Object:   model_task_index model_task_index_bucket_canonical_task_key
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: model_task_index model_task_index_bucket_canonical_task_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_task_index
    ADD CONSTRAINT model_task_index_bucket_canonical_task_key UNIQUE (bucket, canonical_id, task_type);


--
