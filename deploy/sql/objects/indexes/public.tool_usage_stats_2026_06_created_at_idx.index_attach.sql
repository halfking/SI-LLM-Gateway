-- ===========================================================================
-- Object:   tool_usage_stats_2026_06_created_at_idx
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tool_usage_stats_2026_06_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_tool_stats_part_created ATTACH PARTITION public.tool_usage_stats_2026_06_created_at_idx;


--
