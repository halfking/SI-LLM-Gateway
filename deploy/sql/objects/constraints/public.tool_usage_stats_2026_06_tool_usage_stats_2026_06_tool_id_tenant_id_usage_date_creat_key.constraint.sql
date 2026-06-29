-- ===========================================================================
-- Object:   tool_usage_stats_2026_06 tool_usage_stats_2026_06_tool_id_tenant_id_usage_date_creat_key
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tool_usage_stats_2026_06 tool_usage_stats_2026_06_tool_id_tenant_id_usage_date_creat_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_usage_stats_2026_06
    ADD CONSTRAINT tool_usage_stats_2026_06_tool_id_tenant_id_usage_date_creat_key UNIQUE (tool_id, tenant_id, usage_date, created_at);


--
