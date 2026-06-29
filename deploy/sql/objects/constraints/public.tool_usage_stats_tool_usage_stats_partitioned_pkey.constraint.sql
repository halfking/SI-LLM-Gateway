-- ===========================================================================
-- Object:   tool_usage_stats tool_usage_stats_partitioned_pkey
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tool_usage_stats tool_usage_stats_partitioned_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_usage_stats
    ADD CONSTRAINT tool_usage_stats_partitioned_pkey PRIMARY KEY (id, created_at);


--
