-- ===========================================================================
-- Object:   tool_usage_stats_2026_06_tool_id_tenant_id_usage_date_creat_key
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tool_usage_stats_2026_06_tool_id_tenant_id_usage_date_creat_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.tool_usage_stats_partitioned_tool_id_tenant_id_usage_date_c_key ATTACH PARTITION public.tool_usage_stats_2026_06_tool_id_tenant_id_usage_date_creat_key;


--
