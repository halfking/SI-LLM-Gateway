-- ===========================================================================
-- Object:   tool_usage_stats_2026_07_pkey
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tool_usage_stats_2026_07_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.tool_usage_stats_partitioned_pkey ATTACH PARTITION public.tool_usage_stats_2026_07_pkey;


--
