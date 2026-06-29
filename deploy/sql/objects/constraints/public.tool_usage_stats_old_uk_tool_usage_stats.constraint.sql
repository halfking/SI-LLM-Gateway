-- ===========================================================================
-- Object:   tool_usage_stats_old uk_tool_usage_stats
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tool_usage_stats_old uk_tool_usage_stats; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_usage_stats_old
    ADD CONSTRAINT uk_tool_usage_stats UNIQUE (tool_id, tenant_id, usage_date);


--
